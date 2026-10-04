import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Incremental SHA-256: feed chunks as they arrive, read the hex digest at the end.
/// (WebCrypto's digest() is one-shot, so large files would need to sit in memory.)
class StreamingSha256 {
  StreamingSha256() {
    _input = sha256.startChunkedConversion(_output);
  }

  final _DigestSink _output = _DigestSink();
  late final ByteConversionSink _input;
  int _length = 0;
  bool _closed = false;

  int get length => _length;

  void add(List<int> data) {
    if (_closed) throw StateError('digest already finished');
    _input.add(data);
    _length += data.length;
  }

  /// Lowercase hex digest of everything added.
  String finish() {
    if (!_closed) {
      _input.close();
      _closed = true;
    }
    return _output.value.toString();
  }
}

class _DigestSink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
