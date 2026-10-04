import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'protocol/transfer_protocol.dart';
import 'sink_factory.dart';
import 'sinks.dart';

/// Streams a received file to the launcher server (`/api/stream/*`) in ~1 MB pieces, so the
/// page never holds a large file in memory.
class LauncherStreamSink implements IncomingFileSink {
  LauncherStreamSink._(this._id, this._keep);

  final String _id;
  final BytesBuilder? _keep;
  final BytesBuilder _pending = BytesBuilder(copy: false);
  int _size = 0;

  static const int _batch = 1024 * 1024;

  static Uri _api(String path, Map<String, String> query) => Uri.base.resolve(path).replace(queryParameters: query);

  static bool _isAbsolute(String path) =>
      RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(path) || path.startsWith('/') || path.startsWith(r'\\');

  static Future<LauncherStreamSink?> open(String name, int size, String directory) async {
    try {
      final res = await http.post(_api('/api/stream/open', {
        'name': name,
        if (_isAbsolute(directory)) 'dir': directory,
      }));
      if (res.statusCode != 200) return null;
      final id = (jsonDecode(res.body) as Map<String, dynamic>)['id'] as String;
      return LauncherStreamSink._(id, size <= keepInMemoryLimit ? BytesBuilder(copy: true) : null);
    } catch (_) {
      return null;
    }
  }

  Future<void> _flush() async {
    if (_pending.isEmpty) return;
    final body = _pending.takeBytes();
    final res = await http.post(_api('/api/stream/append', {'id': _id}),
        headers: {'Content-Type': 'application/octet-stream'}, body: body);
    if (res.statusCode != 200) throw StateError('Could not write the received file to disk.');
  }

  @override
  Future<void> add(Uint8List data) async {
    _pending.add(Uint8List.fromList(data));
    _keep?.add(data);
    _size += data.length;
    if (_pending.length >= _batch) await _flush();
  }

  @override
  Future<ReceivedFile> commit(String sha256) async {
    await _flush();
    final res = await http.post(_api('/api/stream/commit', {'id': _id}));
    if (res.statusCode != 200) throw StateError('Could not save the received file.');
    final path = (jsonDecode(res.body) as Map<String, dynamic>)['path'] as String;
    final name = path.split(RegExp(r'[\\/]')).last;
    return ReceivedFile(name: name, size: _size, sha256: sha256, path: path, bytes: _keep?.takeBytes());
  }

  @override
  Future<void> discard() async {
    _pending.clear();
    try {
      await http.post(_api('/api/stream/discard', {'id': _id}));
    } catch (_) {}
  }
}

Future<IncomingFileSink> openSink({required String fileName, required int size, required String directory}) async {
  // Without the launcher server (plain static hosting) keep it in memory.
  return await LauncherStreamSink.open(fileName, size, directory) ?? MemoryFileSink(fileName);
}
