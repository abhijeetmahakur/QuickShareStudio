import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:async/async.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickshare/transfer/app_config.dart';
import 'package:quickshare/transfer/channel.dart';
import 'package:quickshare/transfer/file_source.dart';
import 'package:quickshare/transfer/protocol/handshake.dart';
import 'package:quickshare/transfer/protocol/transfer_protocol.dart';
import 'package:quickshare/transfer/secure_channel.dart';
import 'package:quickshare/transfer/sinks.dart';

final _psk = utf8.encode('0123456789abcdef0123456789abcdef');

Future<(SecureFrameChannel, SecureFrameChannel, MemoryFrameChannel, MemoryFrameChannel)> _connect({
  List<int>? initiatorPsk,
  List<int>? responderPsk,
}) async {
  final (a, b) = MemoryFrameChannel.pair();
  final results = await (
    SecureFrameChannel.establish(a, StreamQueue(a.frames), initiator: true, psk: initiatorPsk ?? _psk),
    SecureFrameChannel.establish(b, StreamQueue(b.frames), initiator: false, psk: responderPsk ?? _psk),
  ).wait;
  return (results.$1, results.$2, a, b);
}

bool _contains(List<int> haystack, List<int> needle) {
  outer:
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) continue outer;
    }
    return true;
  }
  return false;
}

void main() {
  test('both sides derive the same verification code and exchange frames', () async {
    final (alice, bob, _, _) = await _connect();
    expect(alice.verificationCode, matches(RegExp(r'^\d{4}$')));
    expect(alice.verificationCode, bob.verificationCode);

    final bobFrames = StreamQueue(bob.frames);
    final aliceFrames = StreamQueue(alice.frames);
    await alice.send(Uint8List.fromList(utf8.encode('hello bob')));
    await bob.send(Uint8List.fromList(utf8.encode('hello alice')));
    expect(utf8.decode(await bobFrames.next), 'hello bob');
    expect(utf8.decode(await aliceFrames.next), 'hello alice');
  });

  test('nothing readable crosses the wire', () async {
    final (alice, bob, wireA, _) = await _connect();
    final wire = <int>[];
    wireA.tamper = (frame) {
      wire.addAll(frame);
      return frame;
    };
    final secret = utf8.encode('TOP-SECRET-LAB-RESULTS');
    final frames = StreamQueue(bob.frames);
    await alice.send(Uint8List.fromList([...secret, ...secret]));
    expect(_contains(await frames.next, secret), isTrue);
    expect(_contains(wire, secret), isFalse);
    expect(alice.encryptedFrames, 1);
  });

  test('a device without the pairing secret cannot connect', () async {
    final (a, b) = MemoryFrameChannel.pair();
    final initiator = SecureFrameChannel.establish(a, StreamQueue(a.frames), initiator: true, psk: utf8.encode('ffffffffffffffffffffffffffffffff'));
    final responder = SecureFrameChannel.establish(b, StreamQueue(b.frames), initiator: false, psk: _psk);
    await expectLater(responder, throwsA(isA<SecureChannelException>().having((e) => e.authentication, 'authentication', isTrue)));
    await expectLater(initiator, throwsA(isA<SecureChannelException>()));
    expect(a.isOpen || b.isOpen, isFalse);
  });

  test('a tampered frame is rejected and the connection closes', () async {
    final (alice, bob, wireA, _) = await _connect();
    wireA.tamper = (frame) => Uint8List.fromList(frame)..[20] ^= 1;
    final received = bob.frames.toList();
    await alice.send(Uint8List.fromList(List.filled(100, 7)));
    await expectLater(received, throwsA(isA<SecureChannelException>()));
    await bob.closed;
  });

  test('a replayed frame is rejected', () async {
    final (alice, bob, wireA, _) = await _connect();
    Uint8List? first;
    wireA.tamper = (frame) {
      first ??= frame;
      return frame;
    };
    final frames = StreamQueue(bob.frames);
    await alice.send(Uint8List.fromList([1, 2, 3]));
    expect(await frames.next, [1, 2, 3]);
    wireA.tamper = (_) => first; // the attacker re-sends the captured frame
    await alice.send(Uint8List.fromList([4, 5, 6]));
    await expectLater(frames.next, throwsA(isA<SecureChannelException>()));
  });

  test('a full transfer over the encrypted channel verifies and leaks no plaintext', () async {
    final (alice, bob, wireA, _) = await _connect();
    final marker = utf8.encode('PLAINTEXT-MARKER-0123456789');
    final content = Uint8List.fromList([for (var i = 0; i < 4000; i++) ...marker]);
    var leaked = false;
    wireA.tamper = (frame) {
      if (_contains(frame, marker)) leaked = true;
      return frame;
    };
    const config = AppConfig();
    final sender = PeerSession(
      channel: alice,
      frames: StreamQueue(alice.frames),
      remote: const RemoteIdentity(id: 'b', name: 'Bob', platform: 'Windows'),
      config: config,
      onOffer: (_) async => false,
      openSink: (o, i) async => MemoryFileSink('x'),
    )..start();
    final got = Completer<ReceivedFile>();
    final receiver = PeerSession(
      channel: bob,
      frames: StreamQueue(bob.frames),
      remote: const RemoteIdentity(id: 'a', name: 'Alice', platform: 'Android'),
      config: config,
      onOffer: (_) async => true,
      openSink: (o, i) async => MemoryFileSink(o.files[i].name),
    )..start();
    receiver.incomingUpdates.listen((s) {
      if (s.phase == TransferPhase.completed && !got.isCompleted) got.complete(s.received.single);
    });
    final result = await OutgoingTransfer(files: [BytesFileSource('notes.txt', content)], config: config, peerName: 'Bob')
        .run(sender);
    expect(result.phase, TransferPhase.completed, reason: result.error);
    final file = await got.future;
    expect(file.bytes, content);
    expect(file.sha256, sha256.convert(content).toString());
    expect(leaked, isFalse);
    expect(alice.encryptedFrames, greaterThan(content.length ~/ config.chunkSize));
  });
}
