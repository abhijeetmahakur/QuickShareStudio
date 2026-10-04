import 'dart:io';
import 'dart:typed_data';
import 'package:printing/printing.dart';
import '../utils/file_utils.dart';

Future<String> saveFile(Uint8List bytes, String fileName, String? directory) async {
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

Future<String> shareFile(Uint8List bytes, String fileName, String? directory) async {
  await Printing.sharePdf(bytes: bytes, filename: fileName);
  return 'Shared "$fileName"';
}
