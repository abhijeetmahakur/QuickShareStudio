// End-to-end tests of the internet path (PeerJS Cloud signaling + WebRTC), compiled as a web
// app and run in real Chrome by tool/e2e/run_internet_e2e.mjs:
//
//   flutter build web --wasm -t tool/e2e/internet_e2e.dart -o build/e2e_web
//   node tool/e2e/run_internet_e2e.mjs
//
// URL parameters:
//   ?scenarios=all|name,name   which single-page scenarios to run
//   &bigMb=500                 size of the large-file scenario
//   &turn=turn:host:port&turnUser=u&turnPass=p   enables the forced-relay scenario
//   &role=receiver             two-instance mode: show a code, receive one transfer
//   &role=sender&code=123456   two-instance mode: connect to that code and send
//
// Every scenario prints "E2E PASS <name> ..." or "E2E FAIL <name>: <reason>", then
// "E2E DONE <json>".
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:quickshare/data/models/pairing_session.dart';
import 'package:quickshare/transfer/app_config.dart';
import 'package:quickshare/transfer/connect_flow.dart';
import 'package:quickshare/transfer/file_source.dart';
import 'package:quickshare/transfer/internet/webrtc_link.dart';
import 'package:quickshare/transfer/protocol/frames.dart';
import 'package:quickshare/transfer/protocol/handshake.dart';
import 'package:quickshare/transfer/protocol/streaming_sha256.dart';
import 'package:quickshare/transfer/protocol/transfer_protocol.dart';
import 'package:quickshare/transfer/sinks.dart';

const _receiverMe = LocalIdentity(id: 'recv-1', name: 'Receiver PC', platform: 'Windows');
const _senderMe = LocalIdentity(id: 'send-1', name: 'Sender Phone', platform: 'Android');

final _status = ValueNotifier<String>('starting');

void _log(String line) {
  // ignore: avoid_print
  print(line);
  _status.value = line;
}

class _CheckFailed implements Exception {
  _CheckFailed(this.what);
  final String what;
  @override
  String toString() => 'check failed: $what';
}

void check(bool condition, String what) {
  if (!condition) throw _CheckFailed(what);
}

final _results = <Map<String, Object?>>[];

Future<void> scenario(String name, Future<String?> Function() body, {Duration timeout = const Duration(minutes: 3)}) async {
  _log('E2E START $name');
  final sw = Stopwatch()..start();
  try {
    final note = await body().timeout(timeout);
    _results.add({'name': name, 'ok': true, 'ms': sw.elapsedMilliseconds, 'note': note});
    _log('E2E PASS $name (${sw.elapsedMilliseconds} ms) ${note ?? ''}');
  } catch (e) {
    _results.add({'name': name, 'ok': false, 'ms': sw.elapsedMilliseconds, 'error': '$e'});
    _log('E2E FAIL $name: $e');
  }
}

/// A receiving device: shows a code, hosts it on PeerJS, accepts authenticated senders.
class _Receiver {
  _Receiver(this.config, {this.decide}) {
    session = PairingSession.create(hostDeviceName: 'Receiver PC', hostIp: '0.0.0.0', hostPort: 0);
  }

  final AppConfig config;
  final Future<bool> Function(IncomingOffer offer)? decide;
  late PairingSession session;
  InternetHost? host;
  final connections = <InternetConnection>[];
  final sessions = <PeerSession>[];
  final failures = <HandshakeException>[];
  final updates = StreamController<TransferSnapshot>.broadcast();
  final connected = StreamController<InternetConnection>.broadcast();
  int codeRegenerations = 0;
  IncomingFileSink Function(IncomingOffer offer, int index)? sinkFor;

  String verify(String mode, String proof, String nonce, String binding) {
    final s = session;
    final secret = switch (mode) {
      'code' => utf8.encode(s.numericCode),
      'qr' => utf8.encode('${s.numericCode}|${s.nonce}'),
      _ => throw HandshakeException('Unsupported mode.', countsAsFailedAttempt: true),
    };
    if (s.isExpired || !constantTimeEquals(proof, computeProof(secret, nonce, binding))) {
      throw HandshakeException('Wrong code.', countsAsFailedAttempt: true);
    }
    return randomToken();
  }

  Future<void> start() async {
    host = InternetHost(
      config: config,
      peerId: session.peerId,
      me: _receiverMe,
      verify: verify,
      onFailedAttempt: (e) async {
        failures.add(e);
        if (session.registerFailedAttempt()) {
          // 5 failed handshakes: destroy the peer and show a brand-new code.
          await host?.stop();
          codeRegenerations++;
          session = PairingSession.create(hostDeviceName: 'Receiver PC', hostIp: '0.0.0.0', hostPort: 0);
          await start();
        }
      },
      onConnection: (c) {
        connections.add(c);
        final ps = PeerSession(
          channel: c.channel,
          frames: c.frames,
          remote: c.remote,
          config: config,
          onOffer: decide ?? (_) async => true,
          openSink: (offer, i) async => sinkFor?.call(offer, i) ?? MemoryFileSink(offer.files[i].name),
        )..start();
        ps.incomingUpdates.listen(updates.add);
        sessions.add(ps);
        connected.add(c);
      },
    );
    await host!.start();
  }

  Future<void> stop() async {
    await host?.stop();
    for (final s in sessions) {
      await s.close();
    }
  }
}

Future<(InternetConnection, PeerSession)> _connect(AppConfig config, String peerId, {String mode = 'code', required List<int> secret}) async {
  final c = await connectToPeer(config: config, targetPeerId: peerId, me: _senderMe, mode: mode, secret: secret, token: CancelToken());
  final session = PeerSession(
    channel: c.channel,
    frames: c.frames,
    remote: c.remote,
    config: config,
    onOffer: (_) async => false,
    openSink: (o, i) async => MemoryFileSink('unused'),
  )..start();
  return (c, session);
}

Future<void> _runSinglePage(AppConfig config, Set<String> only, int bigMb, IceServer? turn) async {
  bool wanted(String name) => only.contains('all') || only.contains(name);

  if (only.contains('bench')) {
    await scenario('bench', () async {
      const mb = 32;
      final src = GeneratedFileSource('b', mb * 1024 * 1024);
      double rate(Stopwatch sw) => mb / (sw.elapsedMilliseconds / 1000);
      var sw = Stopwatch()..start();
      final chunks = await rechunk(src.openRead(), config.chunkSize).toList();
      final gen = rate(sw);
      sw = Stopwatch()..start();
      final h = StreamingSha256();
      for (final c in chunks) {
        h.add(c);
      }
      h.finish();
      final hash = rate(sw);
      sw = Stopwatch()..start();
      var seq = 0;
      for (final c in chunks) {
        Frame.decode(Frame.encodeChunk(tag: 1, fileIndex: 0, sequence: seq++, data: c));
      }
      final framing = rate(sw);
      return 'generate+rechunk ${gen.toStringAsFixed(0)} MB/s, sha256 ${hash.toStringAsFixed(0)} MB/s, '
          'frame enc+dec ${framing.toStringAsFixed(0)} MB/s';
    });
  }

  if (wanted('small-file')) {
    await scenario('small-file', () async {
      final receiver = _Receiver(config);
      await receiver.start();
      try {
        final sw = Stopwatch()..start();
        final (conn, sender) = await _connect(config, receiver.session.peerId, secret: utf8.encode(receiver.session.numericCode));
        final connectMs = sw.elapsedMilliseconds;
        final recvConn = receiver.connections.isNotEmpty ? receiver.connections.first : await receiver.connected.stream.first;
        check(conn.remote.name == 'Receiver PC', 'sender sees receiver name');
        check(recvConn.remote.name == 'Sender Phone', 'receiver sees sender name');
        check(RegExp(r'^\d{4}$').hasMatch(conn.verificationCode), 'verification code is 4 digits');
        check(conn.verificationCode == recvConn.verificationCode, 'both devices show the same verification code');
        final content = Uint8List.fromList(List.generate(300 * 1024 + 17, (i) => (i * 31 + 7) & 0xFF));
        final done = receiver.updates.stream.firstWhere((s) => s.phase.isFinal);
        final result = await OutgoingTransfer(files: [BytesFileSource('Lab Report.pdf', content)], config: config, peerName: 'Receiver PC')
            .run(sender);
        check(result.phase == TransferPhase.completed, 'sender completed (${result.error})');
        final incoming = await done;
        check(incoming.phase == TransferPhase.completed, 'receiver completed');
        final got = incoming.received.single;
        check(got.name == 'Lab Report.pdf', 'name');
        check(got.bytes!.length == content.length, 'size');
        check(got.sha256 == sha256.convert(content).toString(), 'sha256 verified');
        return 'connect ${connectMs}ms, relayed=${conn.channel.relayed}, code=${conn.verificationCode}';
      } finally {
        await receiver.stop();
      }
    });
  }

  if (wanted('multi-file')) {
    await scenario('multi-file', () async {
      final receiver = _Receiver(config);
      await receiver.start();
      try {
        final (_, sender) = await _connect(config, receiver.session.peerId, secret: utf8.encode(receiver.session.numericCode));
        final files = [
          BytesFileSource('a.txt', Uint8List.fromList(utf8.encode('hello'))),
          BytesFileSource('empty.bin', Uint8List(0)),
          BytesFileSource('photo.jpg', Uint8List.fromList(List.generate(100000, (i) => i % 251))),
        ];
        final done = receiver.updates.stream.firstWhere((s) => s.phase.isFinal);
        final result = await OutgoingTransfer(files: files, config: config, peerName: 'R').run(sender);
        check(result.phase == TransferPhase.completed, 'completed (${result.error})');
        final incoming = await done;
        check(incoming.received.length == 3, '3 files received');
        for (var i = 0; i < 3; i++) {
          check(incoming.received[i].sha256 == sha256.convert(files[i].bytes).toString(), 'hash of file $i');
        }
        return null;
      } finally {
        await receiver.stop();
      }
    });
  }

  if (wanted('wrong-code')) {
    await scenario('wrong-code', () async {
      final sw = Stopwatch()..start();
      try {
        await connectToPeer(
          config: config,
          targetPeerId: 'qs-${100000 + Random.secure().nextInt(900000)}',
          me: _senderMe,
          mode: 'code',
          secret: utf8.encode('000000'),
          token: CancelToken(),
        );
        throw _CheckFailed('connected to a code nobody shows');
      } on ConnectException catch (e) {
        check(e.kind == ConnectFailure.wrongCode, 'kind is wrongCode (got ${e.kind}: ${e.message})');
      }
      check(sw.elapsed < const Duration(seconds: 15), 'detected quickly');
      return 'detected in ${sw.elapsedMilliseconds} ms';
    });
  }

  if (wanted('five-failures')) {
    await scenario('five-failures', () async {
      final receiver = _Receiver(config);
      await receiver.start();
      try {
        final firstCode = receiver.session.numericCode;
        final firstPeer = receiver.session.peerId;
        for (var i = 1; i <= 5; i++) {
          try {
            await _connect(config, firstPeer, mode: 'qr', secret: utf8.encode('$firstCode|stale-nonce-$i'));
            throw _CheckFailed('attempt $i with a stale QR nonce connected');
          } on ConnectException catch (e) {
            check(e.kind == ConnectFailure.rejected, 'attempt $i rejected (got ${e.kind})');
          }
          await Future<void>.delayed(const Duration(milliseconds: 300));
        }
        check(receiver.failures.length == 5, '5 failures counted (${receiver.failures.length})');
        check(receiver.codeRegenerations == 1, 'code regenerated once');
        check(receiver.session.numericCode != firstCode, 'new code differs');
        try {
          await _connect(config, firstPeer, secret: utf8.encode(firstCode));
          throw _CheckFailed('old code still reachable');
        } on ConnectException catch (e) {
          check(e.kind == ConnectFailure.wrongCode, 'old code is gone (got ${e.kind})');
        }
        final (conn, _) = await _connect(config, receiver.session.peerId, secret: utf8.encode(receiver.session.numericCode));
        check(conn.remote.name == 'Receiver PC', 'new code works');
        return 'old $firstCode -> new ${receiver.session.numericCode}';
      } finally {
        await receiver.stop();
      }
    });
  }

  if (wanted('qr-nonce')) {
    await scenario('qr-nonce', () async {
      final receiver = _Receiver(config);
      await receiver.start();
      try {
        final s = receiver.session;
        final (conn, _) = await _connect(config, s.peerId, mode: 'qr', secret: utf8.encode('${s.numericCode}|${s.nonce}'));
        check(conn.remote.name == 'Receiver PC', 'QR (code + nonce) connects');
        return null;
      } finally {
        await receiver.stop();
      }
    });
  }

  if (wanted('decline')) {
    await scenario('decline', () async {
      var sinksOpened = 0;
      final receiver = _Receiver(config, decide: (_) async => false)
        ..sinkFor = (o, i) {
          sinksOpened++;
          return MemoryFileSink('x');
        };
      await receiver.start();
      try {
        final (conn, sender) = await _connect(config, receiver.session.peerId, secret: utf8.encode(receiver.session.numericCode));
        final result = await OutgoingTransfer(
          files: [BytesFileSource('private.zip', Uint8List(2 * 1024 * 1024))],
          config: config,
          peerName: 'Receiver PC',
        ).run(sender);
        check(result.phase == TransferPhase.declined, 'declined (${result.phase})');
        check(sinksOpened == 0, 'no file opened on the receiver');
        return null;
      } finally {
        await receiver.stop();
      }
    });
  }

  if (wanted('kill-mid-transfer')) {
    await scenario('kill-mid-transfer', () async {
      final receiver = _Receiver(config)..sinkFor = (o, i) => CountingFileSink(o.files[i].name);
      await receiver.start();
      try {
        final (conn, sender) = await _connect(config, receiver.session.peerId, secret: utf8.encode(receiver.session.numericCode));
        final out = OutgoingTransfer(files: [GeneratedFileSource('big.bin', 200 * 1024 * 1024)], config: config, peerName: 'Receiver PC');
        final running = out.run(sender);
        await receiver.updates.stream.firstWhere((s) => s.bytesDone > 2 * 1024 * 1024);
        // The receiver's side of the connection dies abruptly.
        await receiver.connections.single.channel.pc.close();
        final result = await running.timeout(const Duration(seconds: 30));
        check(result.phase == TransferPhase.interrupted, 'sender sees interrupted (${result.phase})');
        check(result.resumable, 'offered as resumable');
        await out.cancel();
        await conn.channel.closed.timeout(const Duration(seconds: 15));
        check(!conn.channel.isOpen, 'sender channel closed');
        return 'interrupted after ${result.bytesDone ~/ 1024} KB, then cancelled cleanly';
      } finally {
        await receiver.stop();
      }
    });
  }

  if (wanted('cancel-connect')) {
    await scenario('cancel-connect', () async {
      final receiver = _Receiver(config);
      await receiver.start();
      try {
        final token = CancelToken();
        final attempt = connectToPeer(
          config: config,
          targetPeerId: receiver.session.peerId,
          me: _senderMe,
          mode: 'code',
          secret: utf8.encode(receiver.session.numericCode),
          token: token,
        );
        await Future<void>.delayed(const Duration(milliseconds: 150));
        await token.cancel();
        try {
          await attempt.timeout(const Duration(seconds: 10));
          // Connecting may legitimately win the race; the point is it never hangs or crashes.
          return 'connect finished before the cancel took effect';
        } on CancelledException {
          return 'cancelled cleanly';
        } on ConnectException catch (e) {
          return 'stopped: ${e.message}';
        }
      } finally {
        await receiver.stop();
      }
    });
  }

  if (wanted('large-file')) {
    await scenario('large-file', () async {
      CountingFileSink? sink;
      final source = GeneratedFileSource('dataset.bin', bigMb * 1024 * 1024, seed: 42);
      final receiver = _Receiver(config)..sinkFor = (o, i) => sink = CountingFileSink(o.files[i].name, verify: source.byteAt);
      await receiver.start();
      try {
        final (conn, sender) = await _connect(config, receiver.session.peerId, secret: utf8.encode(receiver.session.numericCode));
        final done = receiver.updates.stream.firstWhere((s) => s.phase.isFinal);
        final sw = Stopwatch()..start();
        var maxBuffered = 0;
        final probe = Timer.periodic(const Duration(milliseconds: 20), (_) {
          maxBuffered = max(maxBuffered, conn.channel.dc.bufferedAmount ?? 0);
        });
        final out = OutgoingTransfer(files: [source], config: config, peerName: 'Receiver PC');
        var lastPct = -1;
        out.updates.listen((s) {
          final pct = (s.progress * 100).floor();
          if (pct ~/ 10 != lastPct ~/ 10) {
            lastPct = pct;
            _log('E2E progress $pct% ${(s.bytesPerSecond / 1048576).toStringAsFixed(1)} MB/s eta ${s.eta?.inSeconds}s');
          }
        });
        final result = await out.run(sender);
        probe.cancel();
        check(result.phase == TransferPhase.completed, 'completed (${result.error})');
        final incoming = await done;
        check(incoming.phase == TransferPhase.completed, 'receiver completed');
        check(sink!.length == source.size, 'all bytes arrived');
        check(sink!.mismatches == 0, 'content spot-checks match');
        check(maxBuffered < conn.channel.highWaterMark + 64 * 1024, 'bufferedAmount bounded ($maxBuffered)');
        final secs = sw.elapsedMilliseconds / 1000;
        return '$bigMb MB in ${secs.toStringAsFixed(1)} s (${(bigMb / secs).toStringAsFixed(1)} MB/s), '
            'max buffered ${(maxBuffered / 1024).round()} KB, sha256 ${incoming.received.single.sha256.substring(0, 16)}';
      } finally {
        await receiver.stop();
      }
    }, timeout: const Duration(minutes: 20));
  }

  if (turn != null && wanted('forced-relay')) {
    await scenario('forced-relay', () async {
      final relayConfig = config.copyWith(forceRelay: true, turnServers: [turn]);
      final receiver = _Receiver(relayConfig);
      await receiver.start();
      try {
        final (conn, sender) = await _connect(relayConfig, receiver.session.peerId, secret: utf8.encode(receiver.session.numericCode));
        check(conn.channel.relayed, 'selected candidate pair is a relay');
        final content = Uint8List.fromList(List.generate(2 * 1024 * 1024, (i) => (i * 7) & 0xFF));
        final done = receiver.updates.stream.firstWhere((s) => s.phase.isFinal);
        final result = await OutgoingTransfer(files: [BytesFileSource('relay.bin', content)], config: relayConfig, peerName: 'R').run(sender);
        check(result.phase == TransferPhase.completed, 'completed over relay (${result.error})');
        check((await done).received.single.sha256 == sha256.convert(content).toString(), 'hash over relay');
        return 'relayed=${conn.channel.relayed} via ${turn.urls.first}';
      } finally {
        await receiver.stop();
      }
    });
  }
}

Future<void> _runReceiver(AppConfig config) async {
  final receiver = _Receiver(config)..sinkFor = (o, i) => CountingFileSink(o.files[i].name);
  await receiver.start();
  _log('E2E CODE ${receiver.session.numericCode}');
  await scenario('two-instance-receive', () async {
    final conn = await receiver.connected.stream.first;
    _log('E2E VERIFY ${conn.verificationCode}');
    final done = await receiver.updates.stream.firstWhere((s) => s.phase.isFinal);
    check(done.phase == TransferPhase.completed, 'received (${done.error})');
    return 'from ${conn.remote.name}: ${done.received.length} file(s), '
        '${done.received.fold<int>(0, (s, f) => s + f.size)} bytes, sha256 ${done.received.first.sha256.substring(0, 16)}';
  }, timeout: const Duration(minutes: 20));
  await receiver.stop();
}

Future<void> _runSender(AppConfig config, String code, int mb) async {
  await scenario('two-instance-send', () async {
    final (conn, sender) = await _connect(config, 'qs-$code', secret: utf8.encode(code));
    _log('E2E VERIFY ${conn.verificationCode}');
    final source = GeneratedFileSource('from-other-instance.bin', mb * 1024 * 1024, seed: 9);
    final sw = Stopwatch()..start();
    final result = await OutgoingTransfer(files: [source], config: config, peerName: conn.remote.name).run(sender);
    check(result.phase == TransferPhase.completed, 'sent (${result.error})');
    return '$mb MB in ${(sw.elapsedMilliseconds / 1000).toStringAsFixed(1)} s, relayed=${conn.channel.relayed}';
  }, timeout: const Duration(minutes: 20));
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(MaterialApp(
    home: Scaffold(body: Center(child: ValueListenableBuilder(valueListenable: _status, builder: (_, s, _) => Text(s)))),
  ));
  final q = Uri.base.queryParameters;
  final turnUrl = q['turn'];
  final turn = turnUrl == null ? null : IceServer([turnUrl], username: q['turnUser'], credential: q['turnPass']);
  // With a TURN server the two-instance roles may relay (as a real app with TURN would).
  final config = turn == null ? AppConfig.current : AppConfig.current.copyWith(turnServers: [turn]);
  final bigMb = int.tryParse(q['bigMb'] ?? '') ?? 500;
  switch (q['role']) {
    case 'receiver':
      await _runReceiver(config);
    case 'sender':
      await _runSender(config, q['code'] ?? '', bigMb);
    default:
      await _runSinglePage(config, (q['scenarios'] ?? 'all').split(',').toSet(), bigMb, turn);
  }
  _log('E2E DONE ${jsonEncode(_results)}');
}
