import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'file_names.dart';
import 'protocol/transfer_protocol.dart';
import 'sink_factory.dart';

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
  try {
    return await FileSystemSink.open(Directory(directory), fileName, size);
  } on FileSystemException {
    // e.g. Android 9 and older without storage permission: use the app's own folder.
    final base = Platform.isAndroid ? await getExternalStorageDirectory() : await getApplicationDocumentsDirectory();
    final fallback = Directory('${(base ?? await getApplicationDocumentsDirectory()).path}${Platform.pathSeparator}QuickShare');
    return FileSystemSink.open(fallback, fileName, size);
  }
}
