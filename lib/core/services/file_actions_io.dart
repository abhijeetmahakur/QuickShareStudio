import 'dart:io';

import 'package:flutter/services.dart';
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utils/file_utils.dart';

Future<String> saveFile(
  Uint8List bytes,
  String fileName,
  String? directory,
) async {
  final dir = (directory != null && directory.isNotEmpty)
      ? directory
      : FileUtils.getDefaultDownloadDirectory();
  final file = File(FileUtils.joinPath(dir, fileName));
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes, flush: true);
  return 'Saved to ${file.path}';
}

Future<String> openFile(Uint8List bytes, String fileName) async {
  if (fileName.toLowerCase().endsWith('.pdf')) {
    await Printing.layoutPdf(onLayout: (_) async => bytes, name: fileName);
    return 'Opened print dialog for "$fileName"';
  }
  return saveFile(bytes, fileName, null);
}

Future<String> shareFile(
  Uint8List bytes,
  String fileName,
  String? directory,
) async {
  await Printing.sharePdf(bytes: bytes, filename: fileName);
  return 'Shared "$fileName"';
}

Future<String> openSavedFile(String path) async {
  if (Platform.isAndroid) {
    final opened =
        await const MethodChannel('quickshare/system')
            .invokeMethod<bool>('openFile', {'path': path}) ??
        false;
    if (!opened) {
      throw Exception('No app on this phone can open this kind of file.');
    }
    final name = path.startsWith('content://')
        ? 'received file'
        : path.split(Platform.pathSeparator).last;
    return 'Opened $name';
  }
  if (!File(path).existsSync()) {
    throw Exception('The file is no longer at $path');
  }
  if (!await launchUrl(Uri.file(path))) throw Exception('Could not open $path');
  return 'Opened ${path.split(Platform.pathSeparator).last}';
}
