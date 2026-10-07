import 'dart:io';

import 'package:dbus/dbus.dart';
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

bool get canReveal => Platform.isWindows || Platform.isLinux;

Future<Uint8List> readSavedFile(String path) => File(path).readAsBytes();

Future<String> revealInFolder(String path) async {
  final file = File(path);
  if (!file.existsSync()) throw Exception('The file is no longer at $path');
  final name = path.split(Platform.pathSeparator).last;
  if (Platform.isWindows) {
    // Explorer returns 1 even when it worked, so the exit code is not checked.
    await Process.start('explorer.exe', ['/select,', path], mode: ProcessStartMode.detached);
    return 'Showing $name in File Explorer';
  }
  if (Platform.isLinux) {
    // Nautilus, Dolphin, Nemo, Caja and others select the file through this D-Bus call.
    final bus = DBusClient.session();
    try {
      await bus.callMethod(
        destination: 'org.freedesktop.FileManager1',
        path: DBusObjectPath('/org/freedesktop/FileManager1'),
        interface: 'org.freedesktop.FileManager1',
        name: 'ShowItems',
        values: [DBusArray.string([file.absolute.uri.toString()]), const DBusString('')],
        replySignature: DBusSignature(''),
      );
      return 'Showing $name in the file manager';
    } catch (_) {
      // No file manager implements it: open the folder instead.
      if (!await launchUrl(file.parent.absolute.uri)) throw Exception('Could not open ${file.parent.path}');
      return 'Opened the folder containing $name';
    } finally {
      await bus.close();
    }
  }
  throw UnsupportedError('Showing files in a folder is not available on this device.');
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
