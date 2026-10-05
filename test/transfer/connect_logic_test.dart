import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:quickshare/data/models/pairing_session.dart';
import 'package:quickshare/transfer/attempt_limiter.dart';
import 'package:quickshare/transfer/connect_flow.dart';
import 'package:quickshare/transfer/file_names.dart';

void main() {
  group('Code generation', () {
    test('codes are 6 digits, never repeat within a run, and carry a one-time nonce', () {
      final seen = <String>{};
      final nonces = <String>{};
      for (var i = 0; i < 2000; i++) {
        final s = PairingSession.create(hostDeviceName: 'PC', hostIp: '10.0.0.2', hostPort: 8088);
        expect(s.numericCode, matches(RegExp(r'^[1-9]\d{5}$')));
        expect(seen.add(s.numericCode), isTrue, reason: 'code ${s.numericCode} was reused');
        expect(s.nonce.length, greaterThanOrEqualTo(21)); // 16 random bytes
        nonces.add(s.nonce);
        expect(s.peerId, s.numericCode);
      }
      expect(nonces.length, 2000);
    });

    test('the QR payload carries code and nonce; the nonce is not in the typed code', () {
      final s = PairingSession.create(hostDeviceName: 'Lab PC', hostIp: '192.168.1.5', hostPort: 8088);
      final uri = Uri.parse(s.qrPayload);
      expect(uri.queryParameters['code'], s.numericCode);
      expect(uri.queryParameters['peerId'], s.numericCode);
      expect(uri.queryParameters['n'], s.nonce);
      expect(uri.queryParameters['host'], '192.168.1.5');
      expect(s.formattedCode.contains(s.nonce), isFalse);
    });
  });

  group('Code expiry', () {
    test('a code expires after its TTL (5 minutes by default)', () {
      final t0 = DateTime(2026, 1, 1, 12);
      final s = PairingSession.create(hostDeviceName: 'PC', hostIp: 'x', hostPort: 1, now: t0);
      expect(s.ttl, const Duration(minutes: 5));
      expect(s.hasTimedOut(t0.add(const Duration(minutes: 4, seconds: 59))), isFalse);
      expect(s.remaining(t0.add(const Duration(minutes: 4))), const Duration(minutes: 1));
      expect(s.hasTimedOut(t0.add(const Duration(minutes: 5))), isTrue);
      expect(s.remaining(t0.add(const Duration(minutes: 9))), Duration.zero);
    });

    test('invalidate ends a code immediately', () {
      final s = PairingSession.create(hostDeviceName: 'PC', hostIp: 'x', hostPort: 1);
      expect(s.isExpired, isFalse);
      s.invalidate();
      expect(s.isExpired, isTrue);
    });
  });

  group('Attempt limits', () {
    test('receiver: the 5th failed handshake invalidates the code', () {
      final s = PairingSession.create(hostDeviceName: 'PC', hostIp: 'x', hostPort: 1);
      for (var i = 1; i <= 4; i++) {
        expect(s.registerFailedAttempt(), isFalse, reason: 'attempt $i');
        expect(s.isExpired, isFalse);
      }
      expect(s.registerFailedAttempt(), isTrue);
      expect(s.isLockedOut, isTrue);
      expect(s.isExpired, isTrue);
    });

    test('sender: 5 wrong codes lock code entry, with escalating lockouts', () {
      var now = DateTime(2026, 1, 1);
      final limiter = AttemptLimiter(maxAttempts: 5, lockout: const Duration(minutes: 1), clock: () => now);
      for (var i = 0; i < 4; i++) {
        expect(limiter.recordFailure(), isFalse);
      }
      expect(limiter.remainingAttempts, 1);
      expect(limiter.recordFailure(), isTrue);
      expect(limiter.isLocked, isTrue);
      expect(limiter.lockRemaining, const Duration(minutes: 1));

      now = now.add(const Duration(seconds: 61));
      expect(limiter.isLocked, isFalse);
      for (var i = 0; i < 5; i++) {
        limiter.recordFailure();
      }
      expect(limiter.lockRemaining, const Duration(minutes: 2), reason: 'second lockout doubles');

      now = now.add(const Duration(minutes: 3));
      limiter.recordSuccess();
      expect(limiter.remainingAttempts, 5);
    });
  });

  group('Fallback state machine', () {
    test('LAN success connects without touching the internet', () async {
      var internetCalls = 0;
      final flow = ConnectFlow<String>(
        lan: (_) async => 'lan-device',
        internet: (_) async {
          internetCalls++;
          return 'net';
        },
        isOnline: () async => true,
      );
      expect(await flow.run(), 'lan-device');
      expect(flow.state.value.phase, ConnectPhase.connected);
      expect(internetCalls, 0);
    });

    test('LAN silence -> "Trying over internet" within the LAN timeout, then connected', () async {
      final phases = <ConnectPhase>[];
      final internetStarted = Completer<Duration>();
      final sw = Stopwatch()..start();
      final flow = ConnectFlow<String>(
        lan: (_) => Completer<String>().future, // nobody answers
        internet: (_) async {
          internetStarted.complete(sw.elapsed);
          return 'net-device';
        },
        isOnline: () async => true,
        lanTimeout: const Duration(milliseconds: 300),
      );
      flow.state.addListener(() => phases.add(flow.state.value.phase));
      expect(await flow.run(), 'net-device');
      final startedAfter = await internetStarted.future;
      expect(startedAfter, greaterThanOrEqualTo(const Duration(milliseconds: 300)));
      expect(startedAfter, lessThan(const Duration(milliseconds: 1500)));
      expect(phases, containsAllInOrder([ConnectPhase.searchingLan, ConnectPhase.tryingInternet, ConnectPhase.connected]));
    });

    test('offline: no internet attempt; the Bluetooth/internet/retry options are shown', () async {
      var internetCalls = 0;
      final flow = ConnectFlow<String>(
        lan: (_) async => throw ConnectException(ConnectFailure.notFoundOnLan, 'nobody'),
        internet: (_) async {
          internetCalls++;
          return 'x';
        },
        isOnline: () async => false,
      );
      expect(await flow.run(), isNull);
      final s = flow.state.value;
      expect(internetCalls, 0);
      expect(s.phase, ConnectPhase.failed);
      expect(s.failure, ConnectFailure.noInternet);
      expect(s.showsOptions, isTrue);
      expect(s.statusText, ConnectFlowState.lanNotFoundMessage);
    });

    test('internet failure keeps the options and explains why', () async {
      final flow = ConnectFlow<String>(
        lan: (_) async => throw ConnectException(ConnectFailure.notFoundOnLan, 'nobody'),
        internet: (_) async => throw ConnectException(ConnectFailure.wrongCode, 'No device is online with that code.'),
        isOnline: () async => true,
      );
      expect(await flow.run(), isNull);
      expect(flow.state.value.failure, ConnectFailure.wrongCode);
      expect(flow.state.value.detail, 'No device is online with that code.');
      expect(flow.state.value.showsOptions, isTrue);
    });

    test('cancel during the LAN search releases resources and stops everything', () async {
      var lanCleaned = false, internetCalls = 0;
      final flow = ConnectFlow<String>(
        lan: (token) {
          token.onCancel(() => lanCleaned = true);
          return Completer<String>().future;
        },
        internet: (_) async {
          internetCalls++;
          return 'x';
        },
        isOnline: () async => true,
      );
      final running = flow.run();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await flow.cancel();
      expect(await running, isNull);
      expect(lanCleaned, isTrue);
      expect(internetCalls, 0);
      expect(flow.state.value.phase, ConnectPhase.cancelled);
    });

    test('cancel while trying the internet tears down the peer', () async {
      var peerDestroyed = false;
      final flow = ConnectFlow<String>(
        lan: (_) async => throw ConnectException(ConnectFailure.notFoundOnLan, 'x'),
        internet: (token) {
          token.onCancel(() => peerDestroyed = true);
          return Completer<String>().future;
        },
        isOnline: () async => true,
      );
      final running = flow.run();
      while (flow.state.value.phase != ConnectPhase.tryingInternet) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      await flow.cancel();
      expect(await running, isNull);
      expect(peerDestroyed, isTrue);
      expect(flow.state.value.phase, ConnectPhase.cancelled);
    });

    test('a timed-out LAN search is cleaned up even though the flow continues', () async {
      var lanCleaned = false;
      final flow = ConnectFlow<String>(
        lan: (token) {
          token.onCancel(() => lanCleaned = true);
          return Completer<String>().future;
        },
        internet: (_) async => 'net',
        isOnline: () async => true,
        lanTimeout: const Duration(milliseconds: 100),
      );
      expect(await flow.run(), 'net');
      expect(lanCleaned, isTrue);
    });

    test('[Try over internet] skips the LAN search', () async {
      var lanCalls = 0;
      final flow = ConnectFlow<String>(
        lan: (_) async {
          lanCalls++;
          return 'lan';
        },
        internet: (_) async => 'net',
        isOnline: () async => true,
      );
      expect(await flow.tryInternet(), 'net');
      expect(lanCalls, 0);
    });
  });

  group('File name sanitization', () {
    test('path traversal and absolute paths are reduced to a bare name', () {
      expect(sanitizeIncomingFileName('../../etc/passwd'), 'passwd');
      expect(sanitizeIncomingFileName(r'..\..\Windows\System32\drivers\etc\hosts'), 'hosts');
      expect(sanitizeIncomingFileName('/abs/path/report.pdf'), 'report.pdf');
      expect(sanitizeIncomingFileName('..'), 'file');
      expect(sanitizeIncomingFileName('...'), 'file');
      expect(sanitizeIncomingFileName(''), 'file');
    });

    test('control characters, NUL and bidi overrides are removed', () {
      expect(sanitizeIncomingFileName('evil\u0000.txt'), 'evil.txt');
      expect(sanitizeIncomingFileName('line\nbreak.txt'), 'linebreak.txt');
      // A right-to-left override makes "invoicefdp.exe" display as "invoiceexe.pdf".
      expect(sanitizeIncomingFileName('invoice\u202Efdp.exe'), 'invoicefdp.exe');
    });

    test('Windows-reserved names and characters are neutralized', () {
      expect(sanitizeIncomingFileName('CON'), '_CON');
      expect(sanitizeIncomingFileName('lpt1.txt'), '_lpt1.txt');
      expect(sanitizeIncomingFileName('a<b>c:d"e|f?g*h.txt'), 'a_b_c_d_e_f_g_h.txt');
      expect(sanitizeIncomingFileName('trailing. . '), 'trailing');
      expect(sanitizeIncomingFileName('.hidden'), 'hidden');
    });

    test('very long names are cut but keep their extension', () {
      final name = sanitizeIncomingFileName('${'a' * 500}.pdf');
      expect(name.length, maxFileNameLength);
      expect(name.endsWith('.pdf'), isTrue);
    });

    test('unicode names are kept', () {
      expect(sanitizeIncomingFileName('प्रयोग रिपोर्ट.pdf'), 'प्रयोग रिपोर्ट.pdf');
      expect(sanitizeIncomingFileName('写真 2026.jpg'), '写真 2026.jpg');
    });

    test('duplicates get numbered', () {
      final taken = {'a.txt', 'a (2).txt'};
      expect(uniqueFileName('a.txt', taken.contains), 'a (3).txt');
      expect(uniqueFileName('b.txt', taken.contains), 'b.txt');
    });
  });
}
