import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:async/async.dart';
import 'package:cryptography/cryptography.dart';

import 'channel.dart';

/// Application-layer end-to-end encryption for transports without their own (LAN WebSocket,
/// Wi-Fi Direct socket). WebRTC already has DTLS and does not use this.
///
/// Handshake (2 frames): each side sends an ephemeral X25519 public key with an HMAC over it
/// keyed by a pre-shared secret (the LAN pairing token, or the key agreed over Bluetooth), so
/// a man in the middle without that secret cannot complete it. Keys come from
/// HKDF-SHA256(ECDH shared secret, salt = PSK) with one AES-256-GCM key per direction.
/// Every frame carries a 64-bit counter used as the GCM nonce; counters must strictly
/// increase, so frames cannot be replayed, reordered or dropped unnoticed.
class SecureFrameChannel implements FrameChannel {
  SecureFrameChannel._(this._raw, this._sendKey, this._receiveKey, this.verificationCode, Stream<Uint8List> rawFrames) {
    _frames = rawFrames.asyncMap(_decrypt).handleError((Object e) {
      _raw.close();
      throw e;
    }, test: (e) => e is SecureChannelException);
  }

  static const int _keyFrame = 0xE0;
  static const int _dataFrame = 0xE1;
  static final _aes = AesGcm.with256bits();
  static final _x25519 = X25519();

  final FrameChannel _raw;
  final SecretKey _sendKey;
  final SecretKey _receiveKey;

  /// Four digits both users can compare to rule out an interceptor.
  final String verificationCode;

  late final Stream<Uint8List> _frames;
  int _sendCounter = 0;
  int _receiveCounter = 0;
  Future<void> _sendChain = Future<void>.value();

  /// Frames encrypted so far (lets tests prove encryption is really in use).
  int encryptedFrames = 0;

  /// Runs the handshake over [raw]. [rawFrames] must be the only reader of [raw]'s frames.
  static Future<SecureFrameChannel> establish(
    FrameChannel raw,
    StreamQueue<Uint8List> rawFrames, {
    required bool initiator,
    required List<int> psk,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    if (psk.length < 16) throw SecureChannelException('pre-shared key too short');
    final hmac = Hmac.sha256();
    final keyPair = await _x25519.newKeyPair();
    final myPub = (await keyPair.extractPublicKey()).bytes;

    Future<List<int>> mac(String role, List<int> a, [List<int> b = const []]) async =>
        (await hmac.calculateMac([...utf8.encode('qs-secure-v1|$role|'), ...a, ...b], secretKey: SecretKey(psk))).bytes;

    Uint8List keyMessage(List<int> pub, List<int> tag) => Uint8List.fromList([_keyFrame, ...pub, ...tag]);

    Future<List<int>> readPeerKey(String role, List<int> boundTo) async {
      final Uint8List frame;
      try {
        frame = await rawFrames.next.timeout(timeout);
      } on TimeoutException {
        throw SecureChannelException('The other device did not answer the secure handshake.');
      } on StateError {
        throw SecureChannelException('The other device closed the connection during the secure handshake.');
      }
      if (frame.length != 1 + 32 + 32 || frame[0] != _keyFrame) {
        throw SecureChannelException('Invalid secure handshake.');
      }
      final pub = frame.sublist(1, 33);
      final expected = await mac(role, pub, boundTo);
      if (!_equal(expected, frame.sublist(33))) {
        throw SecureChannelException('The other device could not prove it is paired with this one.', authentication: true);
      }
      return pub;
    }

    try {
      final List<int> pubI, pubR;
      if (initiator) {
        pubI = myPub;
        await raw.send(keyMessage(myPub, await mac('I', myPub)));
        pubR = await readPeerKey('R', myPub);
      } else {
        pubI = await readPeerKey('I', const []);
        pubR = myPub;
        await raw.send(keyMessage(myPub, await mac('R', myPub, pubI)));
      }
      final shared = await _x25519.sharedSecretKey(
        keyPair: keyPair,
        remotePublicKey: SimplePublicKey(initiator ? pubR : pubI, type: KeyPairType.x25519),
      );
      final okm = await (await Hkdf(hmac: hmac, outputLength: 68).deriveKey(
        secretKey: shared,
        nonce: psk,
        info: [...utf8.encode('quickshare-secure-v1'), ...pubI, ...pubR],
      ))
          .extractBytes();
      final i2r = SecretKey(okm.sublist(0, 32));
      final r2i = SecretKey(okm.sublist(32, 64));
      final sas = ByteData.sublistView(Uint8List.fromList(okm.sublist(64, 68))).getUint32(0) % 10000;
      return SecureFrameChannel._(
        raw,
        initiator ? i2r : r2i,
        initiator ? r2i : i2r,
        sas.toString().padLeft(4, '0'),
        rawFrames.rest,
      );
    } catch (_) {
      await raw.close();
      rethrow;
    }
  }

  static bool _equal(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  // ByteData's 64-bit accessors are unsupported on JavaScript builds; use two 32-bit halves.
  static void _putCounter(Uint8List target, int offset, int counter) {
    final view = ByteData.sublistView(target);
    view.setUint32(offset, counter ~/ 0x100000000);
    view.setUint32(offset + 4, counter % 0x100000000);
  }

  static int _readCounter(Uint8List source, int offset) {
    final view = ByteData.sublistView(source);
    return view.getUint32(offset) * 0x100000000 + view.getUint32(offset + 4);
  }

  static List<int> _nonce(int counter) {
    final n = Uint8List(12);
    _putCounter(n, 4, counter);
    return n;
  }

  Future<Uint8List> _decrypt(Uint8List frame) async {
    if (frame.length < 1 + 8 + 16 || frame[0] != _dataFrame) throw SecureChannelException('Unencrypted or malformed frame.');
    final counter = _readCounter(frame, 1);
    if (counter != _receiveCounter) throw SecureChannelException('Replayed or missing frame.');
    _receiveCounter++;
    try {
      final clear = await _aes.decrypt(
        SecretBox(
          Uint8List.sublistView(frame, 9, frame.length - 16),
          nonce: _nonce(counter),
          mac: Mac(Uint8List.sublistView(frame, frame.length - 16)),
        ),
        secretKey: _receiveKey,
      );
      return clear is Uint8List ? clear : Uint8List.fromList(clear);
    } on SecretBoxAuthenticationError {
      throw SecureChannelException('A frame failed authentication (tampered or wrong key).');
    }
  }

  @override
  Stream<Uint8List> get frames => _frames;

  @override
  Future<void> send(Uint8List frame) {
    if (!_raw.isOpen) return Future.error(ChannelClosedException());
    final counter = _sendCounter++;
    final sealed = _aes.encrypt(frame, secretKey: _sendKey, nonce: _nonce(counter)).then((box) {
      final out = Uint8List(1 + 8 + box.cipherText.length + 16);
      out[0] = _dataFrame;
      _putCounter(out, 1, counter);
      out.setRange(9, 9 + box.cipherText.length, box.cipherText);
      out.setRange(9 + box.cipherText.length, out.length, box.mac.bytes);
      encryptedFrames++;
      return out;
    });
    // Encryption may finish out of order; sending must not.
    final done = _sendChain.then((_) async => _raw.send(await sealed));
    _sendChain = done.then((_) {}, onError: (_) {});
    return done;
  }

  @override
  Future<void> close() => _raw.close();

  @override
  Future<void> get closed => _raw.closed;

  @override
  bool get isOpen => _raw.isOpen;
}

class SecureChannelException implements Exception {
  SecureChannelException(this.message, {this.authentication = false});
  final String message;

  /// The peer failed to prove knowledge of the shared secret.
  final bool authentication;

  @override
  String toString() => message;
}
