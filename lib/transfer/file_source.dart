import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

/// A file the sender can read (again) from any offset, so interrupted transfers can resume
/// without keeping everything in memory.
abstract class FileSource {
  String get name;
  int get size;

  /// Bytes from [start] to the end of the file, in arbitrary-sized pieces.
  Stream<Uint8List> openRead([int start = 0]);
}

/// A file already held in memory (small files, web picks, generated PDFs).
class BytesFileSource implements FileSource {
  BytesFileSource(this.name, this.bytes);

  @override
  final String name;
  final Uint8List bytes;

  @override
  int get size => bytes.length;

  @override
  Stream<Uint8List> openRead([int start = 0]) async* {
    const piece = 256 * 1024;
    for (var offset = start; offset < bytes.length; offset += piece) {
      yield Uint8List.sublistView(bytes, offset, min(offset + piece, bytes.length));
      // Let the UI breathe between pieces of a large in-memory file.
      await Future<void>.delayed(Duration.zero);
    }
  }
}

/// Deterministic pseudo-random content of any size without allocating it (tests, benchmarks).
class GeneratedFileSource implements FileSource {
  GeneratedFileSource(this.name, this.size, {this.seed = 1});

  @override
  final String name;
  @override
  final int size;
  final int seed;

  static const int _block = 64 * 1024;

  /// Byte at [index], so receivers can verify content without storing it.
  int byteAt(int index) => _blockBytes(index ~/ _block)[index % _block];

  final Map<int, Uint8List> _cache = {};

  Uint8List _blockBytes(int blockIndex) {
    return _cache.putIfAbsent(blockIndex, () {
      if (_cache.length > 8) _cache.remove(_cache.keys.first);
      // xorshift32 seeded per block: cheap and reproducible.
      var x = (seed * 2654435761 + blockIndex * 40503 + 1) & 0xFFFFFFFF;
      if (x == 0) x = 1;
      final out = Uint8List(_block);
      for (var i = 0; i < _block; i += 4) {
        x ^= (x << 13) & 0xFFFFFFFF;
        x ^= x >> 17;
        x ^= (x << 5) & 0xFFFFFFFF;
        out[i] = x & 0xFF;
        out[i + 1] = (x >> 8) & 0xFF;
        out[i + 2] = (x >> 16) & 0xFF;
        out[i + 3] = (x >> 24) & 0xFF;
      }
      return out;
    });
  }

  @override
  Stream<Uint8List> openRead([int start = 0]) async* {
    var offset = start;
    while (offset < size) {
      final block = offset ~/ _block;
      final within = offset % _block;
      final end = min(_block, within + (size - offset));
      yield Uint8List.sublistView(_blockBytes(block), within, end);
      offset += end - within;
      if (block % 16 == 0) await Future<void>.delayed(Duration.zero);
    }
  }
}

/// Re-slices a byte stream into pieces of exactly [size] bytes (the last may be shorter).
Stream<Uint8List> rechunk(Stream<Uint8List> source, int size) async* {
  final pending = BytesBuilder(copy: false);
  await for (final piece in source) {
    var data = piece;
    if (pending.isNotEmpty) {
      pending.add(data);
      data = pending.takeBytes();
    }
    var offset = 0;
    while (data.length - offset >= size) {
      yield Uint8List.sublistView(data, offset, offset + size);
      offset += size;
    }
    if (offset < data.length) pending.add(Uint8List.sublistView(data, offset));
  }
  if (pending.isNotEmpty) yield pending.takeBytes();
}
