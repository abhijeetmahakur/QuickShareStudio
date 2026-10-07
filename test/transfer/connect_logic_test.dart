import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:quickshare/data/models/pairing_session.dart';
import 'package:quickshare/transfer/attempt_limiter.dart';
import 'package:quickshare/transfer/app_config.dart';
import 'package:quickshare/transfer/connect_flow.dart';
import 'package:quickshare/transfer/file_names.dart';

void main() {
  group('Code generation', () {
    test('codes are 6 digits, never repeat within a run, and carry a one-time nonce', () {
      final seen = <String>{};
      final nonces = <String>{};
      for (var i = 0; i < 2000; i++) {
        final s = PairingSession.create(
          hostDeviceName: 'PC',
          hostIp: '10.0.0.2',
          hostPort: 8088,
        );
        expect(s.numericCode, matches(RegExp(r'^[1-9]\d{5}$')));
        expect(
          seen.add(s.numericCode),
          isTrue,
          reason: 'code ${s.numericCode} was reused',
        );
        expect(s.nonce.length, greaterThanOrEqualTo(21)); // 16 random bytes
        nonces.add(s.nonce);
        expect(s.peerId, s.numericCode);
      }
      expect(nonces.length, 2000);
    });

    test('the QR payload carries code and nonce; the nonce is not in the typed code', () {
      final s = PairingSession.create(
        hostDeviceName: 'Lab PC',
        hostIp: '192.168.1.5',
        hostPort: 8088,
      );
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
      final s = PairingSession.create(
        hostDeviceName: 'PC',
        hostIp: 'x',
        hostPort: 1,
        now: t0,
      );
      expect(s.ttl, const Duration(minutes: 5));
      expect(
        s.hasTimedOut(t0.add(const Duration(minutes: 4, seconds: 59))),
        isFalse,
      );
      expect(
        s.remaining(t0.add(const Duration(minutes: 4))),
        const Duration(minutes: 1),
      );
      expect(s.hasTimedOut(t0.add(const Duration(minutes: 5))), isTrue);
      expect(s.remaining(t0.add(const Duration(minutes: 9))), Duration.zero);
    });

    test('invalidate ends a code immediately', () {
      final s = PairingSession.create(
        hostDeviceName: 'PC',
        hostIp: 'x',
        hostPort: 1,
      );
      expect(s.isExpired, isFalse);
      s.invalidate();
      expect(s.isExpired, isTrue);
    });
  });

  group('Attempt limits', () {
    test('receiver: the 5th failed handshake invalidates the code', () {
      final s = PairingSession.create(
        hostDeviceName: 'PC',
        hostIp: 'x',
        hostPort: 1,
      );
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
      final limiter = AttemptLimiter(
        maxAttempts: 5,
        lockout: const Duration(minutes: 1),
        clock: () => now,
      );
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
      expect(
        limiter.lockRemaining,
        const Duration(minutes: 2),
        reason: 'second lockout doubles',
      );

      now = now.add(const Duration(minutes: 3));
      limiter.recordSuccess();
      expect(limiter.remainingAttempts, 5);
    });
  });

  group('Fallback state machine', () {
    test('default ICE configuration includes multiple STUN servers and credentialed TURN', () {
      final stunUrls = AppConfig.defaultStunServers.expand(
        (server) => server.urls,
      );
      expect(stunUrls, contains('stun:stun.l.google.com:19302'));
      expect(stunUrls.length, greaterThan(1));
      final configuredStunUrls = AppConfig.fromEnvironment().stunServers.expand(
        (server) => server.urls,
      );
      expect(configuredStunUrls, contains('stun:stun.l.google.com:19302'));
      expect(configuredStunUrls.length, greaterThan(1));

      final turn = AppConfig.defaultTurnServers.firstWhere(
        (server) => server.isTurn,
      );
      expect(turn.username, isNotEmpty);
      expect(turn.credential, isNotEmpty);
      expect(
        AppConfig().iceServers(turnOnly: true).every((server) => server.isTurn),
        isTrue,
      );
      final allIceUrls = AppConfig().iceServers().expand((server) => server.urls);
      expect(allIceUrls, contains('turn:openrelay.metered.ca:443?transport=tcp'));
      expect(allIceUrls, contains('turns:openrelay.metered.ca:443'));
    });

    test('LAN success connects without touching internet and sets Connected via Wi-Fi', () async {
      var internetCalls = 0;
      final flow = ConnectFlow<String>(
        lan: (_) async => 'lan-device',
        internetStun: (_) async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          internetCalls++;
          return 'stun-device';
        },
        internetRelay: (_) async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          internetCalls++;
          return 'relay-device';
        },
        isOnline: () async => true,
      );
      expect(await flow.run(), 'lan-device');
      expect(flow.state.value.phase, ConnectPhase.connected);
      expect(flow.state.value.statusText, 'Connected via Wi-Fi');
      expect(internetCalls, 0);
    });

    test('parallel racing: LAN silence races with STUN, STUN wins and cancels others', () async {
      var lanCleaned = false;
      final flow = ConnectFlow<String>(
        lan: (token) {
          token.onCancel(() => lanCleaned = true);
          return Completer<String>().future; // nobody answers
        },
        internetStun: (_) async => 'stun-device',
        internetRelay: (_) => Completer<String>().future,
        isOnline: () async => true,
      );
      expect(await flow.run(), 'stun-device');
      expect(flow.state.value.phase, ConnectPhase.connected);
      expect(flow.state.value.statusText, 'Connected via Direct');
      expect(lanCleaned, isTrue);
    });

    test('a false connectivity probe does not suppress Internet pairing', () async {
      var internetStarted = false;
      final flow = ConnectFlow<String>(
        lan: (_) => Completer<String>().future,
        internetStun: (_) async {
          internetStarted = true;
          return 'internet-device';
        },
        internetRelay: (_) => Completer<String>().future,
        isOnline: () async => false,
      );

      expect(await flow.run(), 'internet-device');
      expect(internetStarted, isTrue);
      expect(flow.state.value.statusText, 'Connected via Direct');
    });

    test('selected ICE relay route is shown as Relay, not Direct', () async {
      final flow = ConnectFlow<bool>(
        lan: (_) => Completer<bool>().future,
        internetStun: (_) async => true,
        internetRelay: (_) => Completer<bool>().future,
        isOnline: () async => true,
        connectionLabel: (isRelayed, attempted) => isRelayed ? 'Relay' : attempted,
      );

      expect(await flow.run(), isTrue);
      expect(flow.state.value.statusText, 'Connected via Relay');
    });

    test(
      'timed-out LAN attempt is cancelled before automatic Bluetooth fallback',
      () async {
        var lanCleaned = false;
        var bluetoothCalled = false;
        final flow = ConnectFlow<String>(
          lan: (token) {
            token.onCancel(() => lanCleaned = true);
            return Completer<String>().future;
          },
          internetStun: (_) async =>
              throw ConnectException(ConnectFailure.noRoute, 'no STUN route'),
          internetRelay: (_) async =>
              throw ConnectException(ConnectFailure.noRoute, 'no TURN route'),
          bluetooth: (_) async {
            bluetoothCalled = true;
            return 'bluetooth-device';
          },
          isOnline: () async => true,
          lanTimeout: const Duration(milliseconds: 20),
        );

        expect(await flow.run(), 'bluetooth-device');
        expect(lanCleaned, isTrue);
        expect(bluetoothCalled, isTrue);
        expect(flow.state.value.statusText, 'Connected via Bluetooth');
      },
    );

    test('auto-fallback: LAN and STUN fail, WebRTC TURN Relay wins', () async {
      final flow = ConnectFlow<String>(
        lan: (_) async =>
            throw ConnectException(ConnectFailure.notFoundOnLan, 'no lan'),
        internetStun: (_) async =>
            throw ConnectException(ConnectFailure.noRoute, 'stun blocked'),
        internetRelay: (_) async => 'relay-device',
        isOnline: () async => true,
      );
      expect(await flow.run(), 'relay-device');
      expect(flow.state.value.phase, ConnectPhase.connected);
      expect(flow.state.value.statusText, 'Connected via Relay');
    });

    test(
      'auto-fallback: 1-3 fail, Bluetooth fallback succeeds silently',
      () async {
        final flow = ConnectFlow<String>(
          lan: (_) async =>
              throw ConnectException(ConnectFailure.notFoundOnLan, 'no lan'),
          internetStun: (_) async =>
              throw ConnectException(ConnectFailure.noRoute, 'no stun'),
          internetRelay: (_) async =>
              throw ConnectException(ConnectFailure.noRoute, 'no relay'),
          bluetooth: (_) async => 'bt-device',
          isOnline: () async => true,
        );
        expect(await flow.run(), 'bt-device');
        expect(flow.state.value.phase, ConnectPhase.connected);
        expect(flow.state.value.statusText, 'Connected via Bluetooth');
      },
    );

    test('all methods fail: shows single failed status with NO manual choice options', () async {
      final flow = ConnectFlow<String>(
        lan: (_) async =>
            throw ConnectException(ConnectFailure.notFoundOnLan, 'no lan'),
        internetStun: (_) async =>
            throw ConnectException(ConnectFailure.signalingUnavailable, 'PeerJS WebSocket refused the connection.'),
        internetRelay: (_) async =>
            throw ConnectException(ConnectFailure.noRoute, 'no relay'),
        bluetooth: (_) async =>
            throw ConnectException(ConnectFailure.other, 'no bt'),
        isOnline: () async => true,
      );
      expect(await flow.run(), isNull);
      final s = flow.state.value;
      expect(s.phase, ConnectPhase.failed);
      expect(s.detail, 'PeerJS WebSocket refused the connection.');
      expect(s.statusText, contains('PeerJS WebSocket refused'));
      expect(s.showsOptions, isFalse); // Never show manual choice screen!
    });

    test(
      'wrong code is fatal: stops immediately with wrongCode failure',
      () async {
        final flow = ConnectFlow<String>(
          lan: (_) async =>
              throw ConnectException(ConnectFailure.wrongCode, 'Wrong code.'),
          internetStun: (_) async =>
              throw ConnectException(ConnectFailure.wrongCode, 'Wrong code.'),
          isOnline: () async => true,
        );
        expect(await flow.run(), isNull);
        expect(flow.state.value.failure, ConnectFailure.wrongCode);
        expect(flow.state.value.detail, 'Wrong code.');
        expect(flow.state.value.showsOptions, isFalse);
      },
    );

    test(
      'cancel during search releases resources and cancels all running tasks',
      () async {
        var lanCleaned = false, stunCleaned = false;
        final flow = ConnectFlow<String>(
          lan: (token) {
            token.onCancel(() => lanCleaned = true);
            return Completer<String>().future;
          },
          internetStun: (token) {
            token.onCancel(() => stunCleaned = true);
            return Completer<String>().future;
          },
          isOnline: () async => true,
        );
        final running = flow.run();
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await flow.cancel();
        expect(await running, isNull);
        expect(lanCleaned, isTrue);
        expect(stunCleaned, isTrue);
        expect(flow.state.value.phase, ConnectPhase.cancelled);
      },
    );
  });

  group('File name sanitization', () {
    test('path traversal and absolute paths are reduced to a bare name', () {
      expect(sanitizeIncomingFileName('../../etc/passwd'), 'passwd');
      expect(
        sanitizeIncomingFileName(r'..\..\Windows\System32\drivers\etc\hosts'),
        'hosts',
      );
      expect(sanitizeIncomingFileName('/abs/path/report.pdf'), 'report.pdf');
      expect(sanitizeIncomingFileName('..'), 'file');
      expect(sanitizeIncomingFileName('...'), 'file');
      expect(sanitizeIncomingFileName(''), 'file');
    });

    test('control characters, NUL and bidi overrides are removed', () {
      expect(sanitizeIncomingFileName('evil\u0000.txt'), 'evil.txt');
      expect(sanitizeIncomingFileName('line\nbreak.txt'), 'linebreak.txt');
      // A right-to-left override makes "invoicefdp.exe" display as "invoiceexe.pdf".
      expect(
        sanitizeIncomingFileName('invoice\u202Efdp.exe'),
        'invoicefdp.exe',
      );
    });

    test('Windows-reserved names and characters are neutralized', () {
      expect(sanitizeIncomingFileName('CON'), '_CON');
      expect(sanitizeIncomingFileName('lpt1.txt'), '_lpt1.txt');
      expect(
        sanitizeIncomingFileName('a<b>c:d"e|f?g*h.txt'),
        'a_b_c_d_e_f_g_h.txt',
      );
      expect(sanitizeIncomingFileName('trailing. . '), 'trailing');
      expect(sanitizeIncomingFileName('.hidden'), 'hidden');
    });

    test('very long names are cut but keep their extension', () {
      final name = sanitizeIncomingFileName('${'a' * 500}.pdf');
      expect(name.length, maxFileNameLength);
      expect(name.endsWith('.pdf'), isTrue);
    });

    test('unicode names are kept', () {
      expect(
        sanitizeIncomingFileName('प्रयोग रिपोर्ट.pdf'),
        'प्रयोग रिपोर्ट.pdf',
      );
      expect(sanitizeIncomingFileName('写真 2026.jpg'), '写真 2026.jpg');
    });

    test('duplicates get numbered', () {
      final taken = {'a.txt', 'a (2).txt'};
      expect(uniqueFileName('a.txt', taken.contains), 'a (3).txt');
      expect(uniqueFileName('b.txt', taken.contains), 'b.txt');
    });
  });
}
