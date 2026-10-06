import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';

import 'file_names.dart';
import 'protocol/transfer_protocol.dart';
import 'sink_factory.dart';

const _androidSystemChannel = MethodChannel('quickshare/system');

/// Streams a verified inbound file into Android's public Downloads collection.
class AndroidDownloadsSink implements IncomingFileSink {
  AndroidDownloadsSink._(this._uri, this._name, this._size, this._keepBytes);

  final String _uri;
  final String _name;
  final int _size;
  final BytesBuilder? _keepBytes;
  bool _closed = false;

  static Future<AndroidDownloadsSink> open(String name, int size) async {
    final result = await _androidSystemChannel.invokeMapMethod<String, String>(
      'beginDownload',
      {'name': name},
    );
    final uri = result?['uri'];
    final savedName = result?['name'];
    if (uri == null || uri.isEmpty || savedName == null || savedName.isEmpty) {
      throw FileSystemException('Android did not create a Downloads file.', name);
    }
    return AndroidDownloadsSink._(
      uri,
      savedName,
      size,
      size <= keepInMemoryLimit ? BytesBuilder(copy: true) : null,
    );
  }

  @override
  Future<void> add(Uint8List data) async {
    if (_closed) throw StateError('Cannot write to a closed Downloads file.');
    await _androidSystemChannel.invokeMethod<void>(
      'writeDownloadChunk',
      {'uri': _uri, 'data': data},
    );
    _keepBytes?.add(data);
  }

  @override
  Future<ReceivedFile> commit(String sha256) async {
    if (_closed) throw StateError('Cannot commit a closed Downloads file.');
    final savedUri = await _androidSystemChannel.invokeMethod<String>(
      'finishDownload',
      {'uri': _uri},
    );
    if (savedUri == null || savedUri.isEmpty) {
      throw FileSystemException('Android could not finish saving to Downloads.', _name);
    }
    _closed = true;
    return ReceivedFile(
      name: _name,
      size: _size,
      sha256: sha256,
      path: savedUri,
      bytes: _keepBytes?.takeBytes(),
    );
  }

  @override
  Future<void> discard() async {
    if (_closed) return;
    _closed = true;
    await _androidSystemChannel.invokeMethod<void>(
      'discardDownload',
      {'uri': _uri},
    );
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
    final sdkInt = await _androidSystemChannel.invokeMethod<int>('sdkInt');
    if ((sdkInt ?? 0) >= 29) {
      return AndroidDownloadsSink.open(fileName, size);
    }

    final permission = await Permission.storage.request();
    if (!permission.isGranted) {
      throw FileSystemException(
        'Storage permission is required to save received files to Downloads.',
        directory,
      );
    }
  }

  try {
    return await FileSystemSink.open(Directory(directory), fileName, size);
  } on FileSystemException {
    if (Platform.isAndroid) rethrow;
    final base = await getApplicationDocumentsDirectory();
    final fallback = Directory('${base.path}${Platform.pathSeparator}QuickShare');
    return FileSystemSink.open(fallback, fileName, size);
  }
}
