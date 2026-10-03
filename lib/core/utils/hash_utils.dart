import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

class HashUtils {
  /// Computes SHA-256 hexadecimal string from raw byte array
  static String computeSha256(Uint8List bytes) {
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Computes SHA-256 for a string (e.g. for salted PIN hashing)
  static String hashString(String input, {String salt = 'QuickShare_Salt_2026'}) {
    final bytes = utf8.encode('$salt:$input');
    return sha256.convert(bytes).toString();
  }

  /// Computes short 8-character fingerprint for display
  static String shortFingerprint(String fullHash) {
    if (fullHash.length < 8) return fullHash;
    return fullHash.substring(0, 8).toUpperCase();
  }
}
