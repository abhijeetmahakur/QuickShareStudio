import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:async/async.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickshare/transfer/app_config.dart';
import 'package:quickshare/transfer/channel.dart';
import 'package:quickshare/transfer/file_source.dart';
import 'package:quickshare/transfer/protocol/frames.dart';
import 'package:quickshare/transfer/protocol/handshake.dart';
import 'package:quickshare/transfer/protocol/streaming_sha256.dart';
import 'package:quickshare/transfer/protocol/transfer_protocol.dart';
import 'package:quickshare/transfer/sinks.dart';

const _alice = RemoteIdentity(id: 'alice-id', name: 'Alice Phone', platform: 'Android');
const _bob = RemoteIdentity(id: 'bob-id', name: 'Bob PC', platform: 'Windows');

/// Two sessions over an in-memory channel: [sender] (Alice) and [receiver] (Bob).
class _Pair {
  _Pair({
    AppConfig? config,
    this.decide,
    PartialTransferStore? partials,
    int highWaterMark = 1 << 20,
  }) : config = config ?? const AppConfig() {
    final (a, b) = MemoryFrameChannel.pair(highWaterMark: highWaterMark);
    aliceEnd = a;
    bobEnd = b;
    store = partials ?? PartialTransferStore();
    sender = PeerSession(
      channel: a,
      frames: StreamQueue(a.frames),
      remote: _bob,
      config: this.config,
      onOffer: (_) async => false,
      openSink: (offer, i) async => MemoryFileSink(offer.files[i].name),
    )..start();
    receiver = PeerSession(
      channel: b,
      frames: StreamQueue(b.frames),
      remote: _alice,
      config: this.config,
      partials: store,
      onOffer: (offer) async {
        offers.add(offer);
        return decide == null ? true : await decide!(offer);
      },
      openSink: (offer, i) async {
        final sink = MemoryFileSink(offer.files[i].name);
        sinks.add(sink);
        return sink;
      },
    )..start();
    receiver.incomingUpdates.listen(updates.add);
  }

  final AppConfig config;
  final Future<bool> Function(IncomingOffer offer)? decide;
  late final MemoryFrameChannel aliceEnd;
  late final MemoryFrameChannel bobEnd;
  late final PartialTransferStore store;
  late final PeerSession sender;
  late final PeerSession receiver;
  final offers = <IncomingOffer>[];
  final sinks = <MemoryFileSink>[];
  final updates = <TransferSnapshot>[];

  TransferSnapshot? get lastIncoming => updates.isEmpty ? null : updates.last;
}

Uint8List _bytes(int n, [int seed = 7]) {
  final r = Random(seed);
  return Uint8List.fromList(List<int>.generate(n, (_) => r.nextInt(256)));
}

void main() {
  group('Chunking', () {
    test('rechunk produces exact 16 KB pieces and a short tail', () async {
      final data = _bytes(16 * 1024 * 3 + 100);
      final pieces = await rechunk(BytesFileSource('x', data).openRead(), 16 * 1024).toList();
      expect(pieces.map((p) => p.length), [16384, 16384, 16384, 100]);
      expect(pieces.expand((p) => p).toList(), data);
    });

    test('rechunk from an offset resumes at the right byte', () async {
      final data = _bytes(100000);
      final pieces = await rechunk(BytesFileSource('x', data).openRead(32768), 16384).toList();
      expect(pieces.expand((p) => p).toList(), data.sublist(32768));
    });

    test('chunk frames carry tag, file index and sequence number', () {
      final encoded = Frame.encodeChunk(tag: 0xDEADBEEF, fileIndex: 3, sequence: 70000, data: [1, 2, 3]);
      final f = Frame.decode(encoded);
      expect(f.type, FrameType.chunk);
      expect(f.tag, 0xDEADBEEF);
      expect(f.fileIndex, 3);
      expect(f.sequence, 70000);
      expect(f.data, [1, 2, 3]);
    });

    test('malformed frames are rejected', () {
      expect(() => Frame.decode(Uint8List(0)), throwsA(isA<ProtocolException>()));
      expect(() => Frame.decode(Uint8List.fromList([0x99])), throwsA(isA<ProtocolException>()));
      expect(() => Frame.decode(Uint8List.fromList([FrameType.offer.code, 0x7B])), throwsA(isA<ProtocolException>()));
      expect(() => Frame.decode(Uint8List.fromList([FrameType.chunk.code, 1, 2])), throwsA(isA<ProtocolException>()));
    });
  });

  group('Checksum', () {
    test('streaming SHA-256 equals one-shot SHA-256 for any split', () {
      final data = _bytes(1000003);
      final h = StreamingSha256();
      var i = 0;
      final r = Random(1);
      while (i < data.length) {
        final n = min(r.nextInt(70000) + 1, data.length - i);
        h.add(data.sublist(i, i + n));
        i += n;
      }
      expect(h.finish(), sha256.convert(data).toString());
      expect(h.length, data.length);
    });

    test('empty input has the well-known digest', () {
      expect(StreamingSha256().finish(), 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
    });

    test('generated sources are deterministic and verifiable byte by byte', () async {
      final src = GeneratedFileSource('big.bin', 300000, seed: 9);
      final all = (await src.openRead().toList()).expand((p) => p).toList();
      expect(all.length, 300000);
      for (final i in [0, 1, 65535, 65536, 299999]) {
        expect(all[i], src.byteAt(i));
      }
      final again = (await src.openRead(70000).toList()).expand((p) => p).toList();
      expect(again, all.sublist(70000));
    });
  });

  group('Transfer protocol', () {
    test('sends several files; receiver verifies each hash', () async {
      final pair = _Pair();
      final files = [
        BytesFileSource('report.pdf', _bytes(50000, 1)),
        BytesFileSource('empty.txt', Uint8List(0)),
        BytesFileSource('photo.jpg', _bytes(16384 * 4, 2)),
      ];
      final out = OutgoingTransfer(files: files, config: pair.config, peerName: 'Bob PC');
      final result = await out.run(pair.sender);

      expect(result.phase, TransferPhase.completed, reason: result.error);
      expect(result.bytesDone, 50000 + 65536);
      expect(pair.offers.single.files.map((f) => f.name), ['report.pdf', 'empty.txt', 'photo.jpg']);
      await pumpEventQueue();
      final done = pair.lastIncoming!;
      expect(done.phase, TransferPhase.completed);
      expect(done.received.map((r) => r.bytes!.length), [50000, 0, 65536]);
      expect(done.received[0].bytes, files[0].bytes);
      expect(done.received[2].sha256, sha256.convert(files[2].bytes).toString());
    });

    test('the receiver sees name, count and size before any data is sent', () async {
      final seenBeforeAccept = <int>[];
      late _Pair pair;
      pair = _Pair(decide: (offer) async {
        seenBeforeAccept.add(pair.aliceEnd.framesSent);
        expect(offer.sender.name, 'Alice Phone');
        expect(offer.totalBytes, 70000);
        expect(pair.sinks, isEmpty);
        return true;
      });
      final out = OutgoingTransfer(files: [BytesFileSource('a.bin', _bytes(70000))], config: pair.config, peerName: 'Bob');
      final result = await out.run(pair.sender);
      expect(result.phase, TransferPhase.completed);
      expect(seenBeforeAccept, [1], reason: 'only the offer frame was sent before acceptance');
    });

    test('decline: no bytes are received or stored', () async {
      final pair = _Pair(decide: (_) async => false);
      final out = OutgoingTransfer(files: [BytesFileSource('secret.zip', _bytes(200000))], config: pair.config, peerName: 'Bob');
      final result = await out.run(pair.sender);
      expect(result.phase, TransferPhase.declined);
      expect(result.error, contains('declined'));
      expect(pair.sinks, isEmpty);
      expect(pair.aliceEnd.bytesSent, lessThan(1000), reason: 'only the offer went over the wire');
      await pumpEventQueue();
      expect(pair.lastIncoming!.phase, TransferPhase.declined);
    });

    test('a sender that pushes chunks without acceptance is cut off and nothing is written', () async {
      final pair = _Pair(decide: (_) => Completer<bool>().future); // never decides
      final out = OutgoingTransfer(files: [BytesFileSource('x', _bytes(10))], config: pair.config, peerName: 'Bob');
      unawaited(out.run(pair.sender));
      await pumpEventQueue();
      for (var i = 0; i < 100 && pair.aliceEnd.isOpen; i++) {
        await pair.aliceEnd.send(Frame.encodeChunk(tag: out.tag, fileIndex: 0, sequence: i, data: [1, 2, 3]));
        await pumpEventQueue();
      }
      expect(pair.bobEnd.isOpen, isFalse);
      expect(pair.sinks, isEmpty);
    });

    test('offered file names are sanitized and de-duplicated', () async {
      final pair = _Pair();
      final out = OutgoingTransfer(
        files: [
          BytesFileSource('../../etc/passwd', _bytes(5)),
          BytesFileSource(r'C:\Windows\system32\evil.dll', _bytes(5)),
          BytesFileSource('passwd', _bytes(5)),
          BytesFileSource('CON.txt', _bytes(5)),
        ],
        config: pair.config,
        peerName: 'Bob',
      );
      expect((await out.run(pair.sender)).phase, TransferPhase.completed);
      expect(pair.offers.single.files.map((f) => f.name), ['passwd', 'evil.dll', 'passwd (2)', '_CON.txt']);
    });

    test('transfers over the size limit are refused before acceptance', () async {
      final pair = _Pair(config: const AppConfig(maxTransferBytes: 1000));
      final out = OutgoingTransfer(files: [BytesFileSource('big', _bytes(1001))], config: pair.config, peerName: 'Bob');
      final result = await out.run(pair.sender);
      expect(result.phase, TransferPhase.failed);
      expect(result.error, contains('limit'));
      expect(pair.offers, isEmpty);
    });

    test('a corrupted chunk is detected: "file corrupted, retry"', () async {
      final pair = _Pair();
      var flipped = false;
      pair.aliceEnd.tamper = (frame) {
        if (!flipped && frame[0] == FrameType.chunk.code && frame.length > 100) {
          flipped = true;
          final copy = Uint8List.fromList(frame);
          copy[50] ^= 0xFF;
          return copy;
        }
        return frame;
      };
      final out = OutgoingTransfer(files: [BytesFileSource('a.bin', _bytes(40000))], config: pair.config, peerName: 'Bob');
      final result = await out.run(pair.sender);
      expect(result.phase, TransferPhase.failed);
      expect(result.error, contains('corrupted'));
      await pumpEventQueue();
      expect(pair.lastIncoming!.phase, TransferPhase.failed);
      expect(pair.lastIncoming!.error, 'File corrupted, retry.');
      expect(pair.lastIncoming!.received, isEmpty, reason: 'the corrupted file is discarded');
    });

    test('out-of-order chunks close the connection', () async {
      final pair = _Pair();
      pair.aliceEnd.tamper = (frame) {
        if (frame[0] == FrameType.chunk.code) {
          final copy = Uint8List.fromList(frame);
          ByteData.sublistView(copy).setUint32(7, 5); // wrong sequence number
          return copy;
        }
        return frame;
      };
      final out = OutgoingTransfer(files: [BytesFileSource('a.bin', _bytes(40000))], config: pair.config, peerName: 'Bob');
      final result = await out.run(pair.sender);
      expect(result.phase, isNot(TransferPhase.completed));
      expect(pair.bobEnd.isOpen, isFalse);
    });

    test('sender cancel stops the transfer and the receiver discards the partial file', () async {
      final pair = _Pair();
      final out = OutgoingTransfer(files: [GeneratedFileSource('big.bin', 20 * 1024 * 1024)], config: pair.config, peerName: 'Bob');
      final running = out.run(pair.sender);
      await out.updates.firstWhere((s) => s.bytesDone > 1024 * 1024);
      await out.cancel();
      final result = await running;
      expect(result.phase, TransferPhase.cancelled);
      await pumpEventQueue();
      expect(pair.lastIncoming!.phase, TransferPhase.cancelled);
      expect(pair.sinks.single.length, 0, reason: 'partial data discarded');
      expect(pair.aliceEnd.isOpen, isTrue, reason: 'the connection survives a cancel');
    });

    test('receiver cancel stops the sender', () async {
      final pair = _Pair();
      final out = OutgoingTransfer(files: [GeneratedFileSource('big.bin', 20 * 1024 * 1024)], config: pair.config, peerName: 'Bob');
      final running = out.run(pair.sender);
      await pair.receiver.incomingUpdates.firstWhere((s) => s.bytesDone > 1024 * 1024);
      await pair.receiver.cancelIncoming(out.transferId);
      final result = await running;
      expect(result.phase, TransferPhase.cancelled);
      expect(result.error, contains('receiver cancelled'));
    });

    test('flow control: the sender never runs further ahead than the window', () async {
      final pair = _Pair(config: const AppConfig(flowControlWindow: 256 * 1024), highWaterMark: 64 << 20);
      final out = OutgoingTransfer(files: [GeneratedFileSource('f', 8 * 1024 * 1024)], config: pair.config, peerName: 'Bob');
      var maxAhead = 0;
      final sub = Stream.periodic(const Duration(milliseconds: 1)).listen((_) {
        final ahead = pair.aliceEnd.bytesSent - (pair.sinks.isEmpty ? 0 : pair.sinks.single.length);
        maxAhead = max(maxAhead, ahead);
      });
      final result = await out.run(pair.sender);
      await sub.cancel();
      expect(result.phase, TransferPhase.completed);
      // window + one 256 KB ack interval + framing overhead
      expect(maxAhead, lessThan(256 * 1024 + 256 * 1024 + 64 * 1024));
    });

    test('connection loss mid-file, then resume on a new connection from the same offset', () async {
      final store = PartialTransferStore();
      final first = _Pair(partials: store, config: const AppConfig(flowControlWindow: 512 * 1024));
      final source = GeneratedFileSource('movie.mp4', 6 * 1024 * 1024 + 123, seed: 3);
      final out = OutgoingTransfer(
        files: [BytesFileSource('notes.txt', _bytes(1000)), source],
        config: first.config,
        peerName: 'Bob',
      );
      final running = out.run(first.sender);
      await first.receiver.incomingUpdates.firstWhere((s) => s.bytesDone > 2 * 1024 * 1024);
      first.aliceEnd.sever();
      final interrupted = await running;
      expect(interrupted.phase, TransferPhase.interrupted);
      expect(interrupted.resumable, isTrue);
      await pumpEventQueue();
      expect(first.lastIncoming!.phase, TransferPhase.interrupted);
      expect(store.contains(out.transferId), isTrue);
      final sinkBefore = first.sinks.last;
      final bytesBefore = sinkBefore.length;

      // Reconnect: same sender identity, same store on the receiver.
      final second = _Pair(partials: store, config: first.config);
      final resumed = await out.run(second.sender, resume: true);
      expect(resumed.phase, TransferPhase.completed, reason: resumed.error);
      expect(second.offers, isEmpty, reason: 'a resume is not asked again');
      expect(second.aliceEnd.bytesSent, lessThan(source.size - bytesBefore + 200 * 1024),
          reason: 'only the missing part was re-sent');
      await pumpEventQueue();
      final finished = second.lastIncoming!;
      expect(finished.phase, TransferPhase.completed);
      expect(finished.received.length, 2);
      final got = finished.received[1].bytes!;
      expect(got.length, source.size);
      expect(sha256.convert(got).toString(), finished.received[1].sha256);
      for (final i in [0, bytesBefore - 1, bytesBefore, source.size - 1]) {
        expect(got[i], source.byteAt(i));
      }
    });

    test('resume works even before the receiver noticed the old connection died', () async {
      final store = PartialTransferStore();
      final first = _Pair(partials: store, config: const AppConfig(flowControlWindow: 512 * 1024));
      final source = GeneratedFileSource('a.bin', 8 * 1024 * 1024, seed: 5);
      final out = OutgoingTransfer(files: [source], config: first.config, peerName: 'Bob');
      final running = out.run(first.sender);
      await first.receiver.incomingUpdates.firstWhere((s) => s.bytesDone > 1024 * 1024);
      first.aliceEnd.dropLocally();
      expect((await running).phase, TransferPhase.interrupted);
      expect(first.bobEnd.isOpen, isTrue, reason: 'the receiver has not noticed yet');

      final second = _Pair(partials: store, config: first.config);
      final resumed = await out.run(second.sender, resume: true);
      expect(resumed.phase, TransferPhase.completed, reason: resumed.error);
      await pumpEventQueue();
      final got = second.lastIncoming!.received.single;
      expect(got.size, source.size);
      expect(got.sha256, sha256.convert(got.bytes!).toString());
    });

    test('the receiver can cancel an interrupted transfer: partial data is deleted', () async {
      final discarded = <String>[];
      final store = PartialTransferStore(onDiscarded: (id, {required expired}) => discarded.add('$id:$expired'));
      final first = _Pair(partials: store, config: const AppConfig(flowControlWindow: 512 * 1024));
      final out = OutgoingTransfer(files: [GeneratedFileSource('x', 16 * 1024 * 1024)], config: first.config, peerName: 'Bob');
      final running = out.run(first.sender);
      await first.receiver.incomingUpdates.firstWhere((s) => s.bytesDone > 1024 * 1024);
      first.aliceEnd.sever();
      await running;
      await pumpEventQueue();
      expect(store.contains(out.transferId), isTrue);
      expect(first.sinks.single.length, greaterThan(0));

      expect(await store.discard(out.transferId), isTrue);
      expect(store.contains(out.transferId), isFalse);
      expect(first.sinks.single.length, 0, reason: 'partial data deleted');
      expect(discarded, ['${out.transferId}:false']);
      expect(await store.discard(out.transferId), isFalse);

      // And it can no longer be resumed.
      final second = _Pair(partials: store, config: first.config);
      expect((await out.run(second.sender, resume: true)).phase, TransferPhase.failed);
    });

    test('an unresumed partial transfer expires and is deleted', () async {
      final discarded = <String>[];
      final store = PartialTransferStore(onDiscarded: (id, {required expired}) => discarded.add('$id:$expired'));
      final config = const AppConfig(flowControlWindow: 512 * 1024, resumeGracePeriod: Duration(milliseconds: 200));
      final first = _Pair(partials: store, config: config);
      final out = OutgoingTransfer(files: [GeneratedFileSource('x', 16 * 1024 * 1024)], config: config, peerName: 'Bob');
      final running = out.run(first.sender);
      await first.receiver.incomingUpdates.firstWhere((s) => s.bytesDone > 1024 * 1024);
      first.aliceEnd.sever();
      await running;
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(store.contains(out.transferId), isFalse);
      expect(first.sinks.single.length, 0);
      expect(discarded, ['${out.transferId}:true']);
    });

    test('a resume from a different sender identity is refused', () async {
      final store = PartialTransferStore();
      final first = _Pair(partials: store, config: const AppConfig(flowControlWindow: 512 * 1024));
      final out = OutgoingTransfer(files: [GeneratedFileSource('x', 16 * 1024 * 1024)], config: first.config, peerName: 'Bob');
      final running = out.run(first.sender);
      await first.receiver.incomingUpdates.firstWhere((s) => s.bytesDone > 1024 * 1024);
      first.aliceEnd.sever();
      await running;

      final (a, b) = MemoryFrameChannel.pair();
      final mallory = PeerSession(
        channel: a,
        frames: StreamQueue(a.frames),
        remote: _bob,
        config: const AppConfig(),
        onOffer: (_) async => false,
        openSink: (o, i) async => MemoryFileSink('x'),
      )..start();
      PeerSession(
        channel: b,
        frames: StreamQueue(b.frames),
        remote: const RemoteIdentity(id: 'mallory', name: 'Mallory', platform: 'Linux'),
        config: const AppConfig(),
        partials: store,
        onOffer: (_) async => true,
        openSink: (o, i) async => MemoryFileSink('x'),
      ).start();
      final result = await out.run(mallory, resume: true);
      expect(result.phase, TransferPhase.failed, reason: result.error);
      expect(result.error, contains('no longer be resumed'));
      expect(store.contains(out.transferId), isTrue);
    });
  });

  group('Handshake', () {
    test('a correct proof is accepted and a resume id is handed out', () async {
      final (a, b) = MemoryFrameChannel.pair();
      final qa = StreamQueue(a.frames), qb = StreamQueue(b.frames);
      final secret = utf8.encode('123456');
      final receiver = acceptHandshake(b, qb, const LocalIdentity(id: 'r', name: 'Receiver', platform: 'Windows'),
          verify: (mode, proof, nonce) {
        if (!constantTimeEquals(proof, computeProof(secret, nonce, 'fp'))) throw HandshakeException('wrong', countsAsFailedAttempt: true);
        return 'resume-123';
      });
      final sender = initiateHandshake(a, qa, const LocalIdentity(id: 's', name: 'Sender', platform: 'Android'),
          mode: 'code', prove: (nonce) => computeProof(secret, nonce, 'fp'));
      final (r, s) = await (receiver, sender).wait;
      expect(r.name, 'Sender');
      expect(r.mode, 'code');
      expect(s.name, 'Receiver');
      expect(s.resumeId, 'resume-123');
    });

    test('a wrong proof is rejected and counts as a failed attempt', () async {
      final (a, b) = MemoryFrameChannel.pair();
      final qa = StreamQueue(a.frames), qb = StreamQueue(b.frames);
      final receiver = acceptHandshake(b, qb, const LocalIdentity(id: 'r', name: 'R', platform: 'W'), verify: (mode, proof, nonce) {
        if (!constantTimeEquals(proof, computeProof(utf8.encode('123456'), nonce, 'fp'))) {
          throw HandshakeException('Wrong code.', countsAsFailedAttempt: true);
        }
        return 'x';
      });
      final sender = initiateHandshake(a, qa, const LocalIdentity(id: 's', name: 'S', platform: 'A'),
          mode: 'code', prove: (nonce) => computeProof(utf8.encode('654321'), nonce, 'fp'));
      await expectLater(receiver, throwsA(isA<HandshakeException>().having((e) => e.countsAsFailedAttempt, 'counts', isTrue)));
      await expectLater(sender, throwsA(isA<HandshakeException>().having((e) => e.message, 'message', 'Wrong code.')));
    });

    test('proofs are bound to the session binding (e.g. DTLS fingerprints)', () {
      final secret = utf8.encode('123456');
      expect(computeProof(secret, 'n', 'fpA|fpB'), isNot(computeProof(secret, 'n', 'fpA|fpMITM')));
      expect(computeProof(secret, 'n1', 'fp'), isNot(computeProof(secret, 'n2', 'fp')));
    });
  });
}
