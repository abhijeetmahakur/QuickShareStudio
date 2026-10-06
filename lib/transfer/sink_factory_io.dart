import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../core/services/android_downloads.dart';
import 'file_names.dart';
import 'protocol/transfer_protocol.dart';
import 'sink_factory.dart';

/// Streams a verified inbound file into the phone's public Downloads/QuickShare folder.
class AndroidDownloadsSink implements IncomingFileSink {
  AndroidDownloadsSink._(this._handle, this._size, this._keepBytes);

  final String _handle;
  final int _size;
  final BytesBuilder? _keepBytes;
  // Chunks arrive in 16 KiB pieces; batching them keeps platform-channel calls rare.
  final _pending = BytesBuilder(copy: true);
  bool _closed = false;

  static Future<AndroidDownloadsSink> open(String name, int size) async => AndroidDownloadsSink._(
        await AndroidDownloads.begin(name),
        size,
        size <= keepInMemoryLimit ? BytesBuilder(copy: true) : null,
      );

  @override
  Future<void> add(Uint8List data) async {
    if (_closed) throw StateError('Cannot write to a closed Downloads file.');
    _pending.add(data);
    _keepBytes?.add(data);
    if (_pending.length >= AndroidDownloads.blockSize) await _flush();
  }

  Future<void> _flush() async {
    if (_pending.isNotEmpty) await AndroidDownloads.write(_handle, _pending.takeBytes());
  }

  @override
  Future<ReceivedFile> commit(String sha256) async {
    if (_closed) throw StateError('Cannot commit a closed Downloads file.');
    _closed = true;
    try {
      await _flush();
      final name = await AndroidDownloads.finish(_handle);
      return ReceivedFile(name: name, size: _size, sha256: sha256, path: _handle, bytes: _keepBytes?.takeBytes());
    } catch (_) {
      // The protocol does not discard a sink whose commit failed.
      await AndroidDownloads.discard(_handle).catchError((_) {});
      rethrow;
    }
  }

  @override
  Future<void> discard() async {
    if (_closed) return;
    _closed = true;
    await AndroidDownloads.discard(_handle);
  }
}

/// Writes to `<dir>/.<name>.<random>.part`, renamed to a free final name once verified.
class FileSystemSink implements IncomingFileSink {
  FileSystemSink._(this._dir, this._name, this._part, this._out, this._keepBytes);

  final Directory _dir;
  final String _name;
  final File _part;
  final RandomAccessFile _out;
  final BytesBuilder? _keepBytes;
  bool _closed = false;

  static Future<FileSystemSink> open(Directory dir, String name, int size) async {
    await dir.create(recursive: true);
    final rnd = Random.secure().nextInt(1 << 30).toRadixString(36);
    final part = File('${dir.path}${Platform.pathSeparator}.$name.$rnd.part');
    final out = await part.open(mode: FileMode.writeOnly);
    return FileSystemSink._(dir, name, part, out, size <= keepInMemoryLimit ? BytesBuilder(copy: true) : null);
  }

  @override
  Future<void> add(Uint8List data) async {
    await _out.writeFrom(data);
    _keepBytes?.add(data);
  }

  @override
  Future<ReceivedFile> commit(String sha256) async {
    await _out.flush();
    await _out.close();
    _closed = true;
    final target = uniqueFileName(_name, (n) => File('${_dir.path}${Platform.pathSeparator}$n').existsSync());
    final file = await _part.rename('${_dir.path}${Platform.pathSeparator}$target');
    final size = await file.length();
    return ReceivedFile(name: target, size: size, sha256: sha256, path: file.path, bytes: _keepBytes?.takeBytes());
  }

  @override
  Future<void> discard() async {
    if (!_closed) {
      _closed = true;
      try {
        await _out.close();
      } catch (_) {}
    }
    try {
      await _part.delete();
    } catch (_) {}
  }
}

Future<IncomingFileSink> openSink({required String fileName, required int size, required String directory}) async {
  if (Platform.isAndroid) {
    // Into the public Downloads/QuickShare folder, where the Files app shows it.
    try {
      if (await AndroidDownloads.ensurePermission()) return await AndroidDownloadsSink.open(fileName, size);
    } catch (e) {
      debugPrint('[QuickShare] Could not save "$fileName" into Downloads, using app storage: $e');
    }
    return _openAppStorageSink(fileName, size);
  }
  try {
    return await FileSystemSink.open(Directory(directory), fileName, size);
  } on FileSystemException {
    return _openAppStorageSink(fileName, size);
  }
}

/// The app's own folder: always writable, but on Android only visible inside QuickShare.
Future<IncomingFileSink> _openAppStorageSink(String fileName, int size) async {
  final base = Platform.isAndroid ? await getExternalStorageDirectory() : null;
  final dir = Directory('${(base ?? await getApplicationDocumentsDirectory()).path}${Platform.pathSeparator}QuickShare');
  return FileSystemSink.open(dir, fileName, size);
}
