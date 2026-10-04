import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:printing/printing.dart';

@JS('window.quickshareShareFile')
external JSPromise<JSString> _jsShareFile(JSUint8Array bytes, String fileName, String mimeType);

String _mimeFor(String fileName) {
  final ext = fileName.contains('.') ? fileName.split('.').last.toLowerCase() : '';
  const types = {
    'pdf': 'application/pdf',
    'png': 'image/png',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'webp': 'image/webp',
    'gif': 'image/gif',
    'txt': 'text/plain',
    'zip': 'application/zip',
  };
  return types[ext] ?? 'application/octet-stream';
}

/// Asks the launcher server to write the file. Returns its path, or null when the
/// server is unavailable (e.g. the app was opened by a plain static file server).
Future<String?> _serverSave(Uint8List bytes, String fileName, {bool preview = false, String? directory}) async {
  try {
    final uri = Uri.base.resolve('/api/save-file').replace(queryParameters: {
      'name': fileName,
      if (preview) 'preview': '1',
      if (directory != null && _isAbsolutePath(directory)) 'dir': directory,
    });
    final res = await http.post(uri, headers: {'Content-Type': 'application/octet-stream'}, body: bytes);
    if (res.statusCode == 200) return jsonDecode(res.body)['path'] as String;
  } catch (_) {}
  return null;
}

/// The web default ("Downloads/QuickShare") is relative and means "server default";
/// only an absolute folder picked in Settings is passed on.
bool _isAbsolutePath(String path) =>
    RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(path) || path.startsWith('/') || path.startsWith(r'\\');

Future<void> _serverAction(String action, String path) async {
  final uri = Uri.base.resolve('/api/$action').replace(queryParameters: {'path': path});
  final res = await http.post(uri);
  if (res.statusCode != 200) {
    throw Exception('Server could not $action: ${res.body}');
  }
}

Future<String> saveFile(Uint8List bytes, String fileName, String? directory) async {
  final path = await _serverSave(bytes, fileName, directory: directory);
  if (path != null) return 'Saved to $path';
  // No launcher server: let the browser download it instead.
  await FilePicker.saveFile(fileName: fileName, bytes: bytes, mimeType: _mimeFor(fileName));
  return 'Downloaded "$fileName" to your browser\'s Downloads folder';
}

Future<String> openFile(Uint8List bytes, String fileName) async {
  final path = await _serverSave(bytes, fileName, preview: true);
  if (path != null) {
    await _serverAction('open-file', path);
    return 'Opened "$fileName"';
  }
  if (_mimeFor(fileName) == 'application/pdf') {
    await Printing.layoutPdf(onLayout: (_) async => bytes, name: fileName);
    return 'Opened print dialog for "$fileName"';
  }
  return saveFile(bytes, fileName, null);
}

Future<String> shareFile(Uint8List bytes, String fileName, String? directory) async {
  final result = (await _jsShareFile(bytes.toJS, fileName, _mimeFor(fileName)).toDart).toDart;
  if (result == 'shared') return 'Shared "$fileName"';
  if (result == 'cancelled') return 'Share cancelled';

  // Share sheet unavailable: save it and show it in File Explorer so it can be attached anywhere.
  final path = await _serverSave(bytes, fileName, directory: directory);
  if (path == null) return saveFile(bytes, fileName, directory);
  await _serverAction('reveal-file', path);
  return 'Saved to $path and opened its folder for sharing';
}

Future<String> openSavedFile(String path) async {
  await _serverAction('open-file', path);
  return 'Opened "${path.split(RegExp(r'[\\/]')).last}"';
}
