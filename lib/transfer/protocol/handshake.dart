import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:async/async.dart';
import 'package:crypto/crypto.dart';

import '../channel.dart';
import 'frames.dart';

const int protocolVersion = 2;

/// Who this device is, as told to the other side.
class LocalIdentity {
  const LocalIdentity({required this.id, required this.name, required this.platform});
  final String id;
  final String name;
  final String platform;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'platform': platform, 'v': protocolVersion};
}

class RemoteIdentity {
  const RemoteIdentity({required this.id, required this.name, required this.platform, this.mode = '', this.resumeId});
  final String id;
  final String name;
  final String platform;

  /// How the initiator proved itself ('code', 'qr', 'resume', 'paired').
  final String mode;

  /// Secret the receiver hands out so an interrupted sender can reconnect later.
  final String? resumeId;

  static RemoteIdentity fromJson(Map<String, dynamic> json, {String mode = '', String? resumeId}) => RemoteIdentity(
        id: _clip(json['id'], 64, 'unknown'),
        name: _clip(json['name'], 60, 'Device'),
        platform: _clip(json['platform'], 24, 'Device'),
        mode: mode,
        resumeId: resumeId,
      );

  static String _clip(Object? value, int max, String fallback) {
    final s = (value?.toString() ?? '').replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '').trim();
    if (s.isEmpty) return fallback;
    return s.length > max ? s.substring(0, max) : s;
  }
}

class HandshakeException implements Exception {
  HandshakeException(this.message, {this.countsAsFailedAttempt = false});
  final String message;

  /// True when the other side presented a wrong proof (attempt limits apply).
  final bool countsAsFailedAttempt;

  @override
  String toString() => message;
}

/// HMAC-SHA256 proof that the initiator knows [secret], bound to this exact session
/// ([nonce] from the receiver and [binding], e.g. both DTLS fingerprints).
String computeProof(List<int> secret, String nonce, String binding) {
  final mac = Hmac(sha256, secret).convert(utf8.encode('quickshare-proof-v2|$nonce|$binding'));
  return base64Url.encode(mac.bytes);
}

bool constantTimeEquals(String a, String b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return diff == 0;
}

String randomToken([int bytes = 16]) {
  final rnd = Random.secure();
  return base64Url.encode(List<int>.generate(bytes, (_) => rnd.nextInt(256))).replaceAll('=', '');
}

/// Receiver (acceptor) side: challenge the initiator and check its proof with [verify].
/// [verify] returns the resume id to hand out, or throws [HandshakeException].
Future<RemoteIdentity> acceptHandshake(
  FrameChannel channel,
  StreamQueue<Uint8List> frames,
  LocalIdentity me, {
  required String Function(String mode, String proof, String nonce) verify,
  Duration timeout = const Duration(seconds: 15),
}) async {
  final nonce = randomToken();
  await channel.send(Frame.encodeControl(FrameType.challenge, {...me.toJson(), 'nonce': nonce}));
  final Frame hello;
  try {
    hello = Frame.decode(await frames.next.timeout(timeout));
  } on TimeoutException {
    throw HandshakeException('The other device did not answer in time.');
  } on StateError {
    throw HandshakeException('The other device disconnected during the handshake.');
  }
  if (hello.type != FrameType.hello) {
    throw HandshakeException('Unexpected ${hello.type.name} during handshake.', countsAsFailedAttempt: true);
  }
  final mode = hello.json['mode']?.toString() ?? '';
  final proof = hello.json['proof']?.toString() ?? '';
  final String resumeId;
  try {
    resumeId = verify(mode, proof, nonce);
  } on HandshakeException catch (e) {
    await _sendReject(channel, e.message);
    rethrow;
  }
  await channel.send(Frame.encodeControl(FrameType.welcome, {'resumeId': resumeId}));
  return RemoteIdentity.fromJson(hello.json, mode: mode, resumeId: resumeId);
}

/// Sender (initiator) side: answer the receiver's challenge with [prove].
Future<RemoteIdentity> initiateHandshake(
  FrameChannel channel,
  StreamQueue<Uint8List> frames,
  LocalIdentity me, {
  required String mode,
  required String Function(String nonce) prove,
  Duration timeout = const Duration(seconds: 15),
}) async {
  Future<Frame> next() async {
    try {
      return Frame.decode(await frames.next.timeout(timeout));
    } on TimeoutException {
      throw HandshakeException('The other device did not answer in time.');
    } on StateError {
      throw HandshakeException('The other device closed the connection.');
    }
  }

  final challenge = await next();
  if (challenge.type != FrameType.challenge) throw HandshakeException('Unexpected ${challenge.type.name} during handshake.');
  final nonce = challenge.json['nonce']?.toString() ?? '';
  if (nonce.length < 16) throw HandshakeException('The other device sent an invalid challenge.');
  await channel.send(Frame.encodeControl(FrameType.hello, {...me.toJson(), 'mode': mode, 'proof': prove(nonce)}));
  final answer = await next();
  if (answer.type == FrameType.reject) {
    throw HandshakeException(answer.json['reason']?.toString() ?? 'The other device rejected the connection.');
  }
  if (answer.type != FrameType.welcome) throw HandshakeException('Unexpected ${answer.type.name} during handshake.');
  return RemoteIdentity.fromJson(challenge.json, mode: mode, resumeId: answer.json['resumeId']?.toString());
}

Future<void> _sendReject(FrameChannel channel, String reason) async {
  try {
    await channel.send(Frame.encodeControl(FrameType.reject, {'reason': reason}));
  } catch (_) {}
}
