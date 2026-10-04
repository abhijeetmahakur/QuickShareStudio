import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'folder_picker.dart';

Future<PickedFolder?> pickFolder(int maxFileBytes) async {
  final path = await FilePicker.getDirectoryPath(dialogTitle: 'Choose a folder to convert');
  if (path == null) return null;
  final root = Directory(path);
  final rootPath = root.absolute.path.replaceAll('\\', '/');
  final files = <PickedFolderFile>[];
  final skipped = <String>[];
  await for (final entity in root.list(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final rel = entity.absolute.path.replaceAll('\\', '/').substring(rootPath.length).replaceFirst(RegExp(r'^/'), '');
    if (FolderPicker.isIgnored(rel)) continue;
    if (await entity.length() > maxFileBytes) {
      skipped.add(rel);
      continue;
    }
    files.add(PickedFolderFile(rel, await entity.readAsBytes()));
  }
  files.sort((a, b) => a.relativePath.toLowerCase().compareTo(b.relativePath.toLowerCase()));
  return PickedFolder(rootPath.split('/').where((s) => s.isNotEmpty).last, files, skipped);
}
