import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Pure logic of the Bluetooth handshake (no platform code), so it can be unit tested.
///
/// Over one GATT characteristic the two phones exchange:
///   1. sender -> receiver  {t: hello, pub, name, id, p}
///   2. receiver -> sender  {t: hello, pub, name, id, p}
///      both derive K = HKDF-SHA256(X25519, salt "quickshare-bt-v1", info pubSender|pubReceiver)
///   3. receiver -> sender  {t: wifi, box}  = AES-256-GCM_K({ssid, passphrase, ip, port})
/// The sender joins the Wi-Fi Direct group and opens a TCP socket; K is then the pre-shared
/// key of the SecureFrameChannel on that socket, so a device that skipped the BLE exchange
/// cannot connect even if it sniffed the Wi-Fi credentials.

/// Splits a message into GATT-sized pieces: `[flags][payload]`, flag bit 0 = last piece.
List<Uint8List> chunkMessage(List<int> message, int mtu) {
  final room = (mtu - 3 - 1).clamp(16, 512);
  final out = <Uint8List>[];
  for (var offset = 0; offset < message.length || out.isEmpty; offset += room) {
    final end = (offset + room).clamp(0, message.length);
    final last = end >= message.length;
    out.add(Uint8List.fromList([last ? 1 : 0, ...message.sublist(offset, end)]));
    if (last) break;
  }
  return out;
}

/// Reassembles pieces produced by [chunkMessage].
class MessageAssembler {
  final BytesBuilder _parts = BytesBuilder(copy: true);

  static const int maxMessage = 4096;

  /// Returns the full message when [piece] completes one.
  Uint8List? add(List<int> piece) {
    if (piece.isEmpty) return null;
    _parts.add(piece.sublist(1));
    if (_parts.length > maxMessage) {
      _parts.clear();
      throw const FormatException('handshake message too large');
    }
    if (piece[0] & 1 == 0) return null;
    return _parts.takeBytes();
  }
}

class BleKeyAgreement {
  BleKeyAgreement._(this._keyPair, this.publicKey);

  final SimpleKeyPair _keyPair;
  final List<int> publicKey;

  static final _x25519 = X25519();

  static Future<BleKeyAgreement> create() async {
    final pair = await _x25519.newKeyPair();
    final pub = (await pair.extractPublicKey()).bytes;
    return BleKeyAgreement._(pair, pub);
  }

  /// The shared 32-byte key. [senderPub]/[receiverPub] fix the order on both sides.
  Future<List<int>> derive({required List<int> peerPublicKey, required List<int> senderPub, required List<int> receiverPub}) async {
    final shared = await _x25519.sharedSecretKey(
      keyPair: _keyPair,
      remotePublicKey: SimplePublicKey(peerPublicKey, type: KeyPairType.x25519),
    );
    final key = await Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
      secretKey: shared,
      nonce: utf8.encode('quickshare-bt-v1'),
      info: [...senderPub, ...receiverPub],
    );
    return key.extractBytes();
  }
}

Map<String, dynamic> helloMessage({required List<int> publicKey, required String name, required String id, required String platform}) => {
      't': 'hello',
      'pub': base64.encode(publicKey),
      'name': name.length > 40 ? name.substring(0, 40) : name,
      'id': id.length > 40 ? id.substring(0, 40) : id,
      'p': platform,
    };

/// Wi-Fi Direct credentials, sealed with the BLE key.
class WifiCredentials {
  const WifiCredentials({required this.ssid, required this.passphrase, required this.ip, required this.port});
  final String ssid;
  final String passphrase;
  final String ip;
  final int port;

  static final _aes = AesGcm.with256bits();

  Future<String> seal(List<int> key) async {
    final box = await _aes.encrypt(
      utf8.encode(jsonEncode({'s': ssid, 'k': passphrase, 'i': ip, 'p': port})),
      secretKey: SecretKey(key),
    );
    return base64.encode(box.concatenation());
  }

  static Future<WifiCredentials> open(String sealed, List<int> key) async {
    final box = SecretBox.fromConcatenation(base64.decode(sealed), nonceLength: 12, macLength: 16);
    final clear = await _aes.decrypt(box, secretKey: SecretKey(key));
    final json = jsonDecode(utf8.decode(clear)) as Map<String, dynamic>;
    return WifiCredentials(
      ssid: json['s'] as String,
      passphrase: json['k'] as String,
      ip: json['i'] as String,
      port: (json['p'] as num).toInt(),
    );
  }
}
