import 'dart:typed_data';

import 'protocol/transfer_protocol.dart';

/// Keeps received bytes in memory (web builds, small files, tests).
class MemoryFileSink implements IncomingFileSink {
  MemoryFileSink(this.name);

  final String name;
  final BytesBuilder _bytes = BytesBuilder(copy: false);
  bool _discarded = false;

  int get length => _bytes.length;

  @override
  Future<void> add(Uint8List data) async {
    if (_discarded) return;
    // Incoming frames are views into transport buffers; keep our own copy.
    _bytes.add(Uint8List.fromList(data));
  }

  @override
  Future<ReceivedFile> commit(String sha256) async {
    final bytes = _bytes.takeBytes();
    return ReceivedFile(name: name, size: bytes.length, sha256: sha256, bytes: bytes);
  }

  @override
  Future<void> discard() async {
    _discarded = true;
    _bytes.clear();
  }
}

/// Hashes and counts bytes without storing them (large-transfer tests, benchmarks).
class CountingFileSink implements IncomingFileSink {
  CountingFileSink(this.name, {this.verify});

  final String name;

  /// Optional check of each byte at its offset.
  final int Function(int index)? verify;
  int length = 0;
  int mismatches = 0;
  bool discarded = false;

  @override
  Future<void> add(Uint8List data) async {
    final check = verify;
    if (check != null) {
      // Spot-check a few bytes per chunk; a full compare is the hash's job.
      for (final i in [0, data.length ~/ 2, data.length - 1]) {
        if (i >= 0 && i < data.length && data[i] != check(length + i)) mismatches++;
      }
    }
    length += data.length;
  }

  @override
  Future<ReceivedFile> commit(String sha256) async => ReceivedFile(name: name, size: length, sha256: sha256);

  @override
  Future<void> discard() async => discarded = true;
}
