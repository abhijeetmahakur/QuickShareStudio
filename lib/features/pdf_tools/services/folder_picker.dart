import 'dart:typed_data';
import 'folder_picker_io.dart' if (dart.library.js_interop) 'folder_picker_web.dart' as impl;

class PickedFolderFile {
  /// Path inside the picked folder using '/' separators, e.g. "week1/Lab1.java".
  final String relativePath;
  final Uint8List bytes;
  PickedFolderFile(this.relativePath, this.bytes);

  String get name => relativePath.split('/').last;
}

class PickedFolder {
  final String name;
  final List<PickedFolderFile> files;
  /// Files left out because they exceed the size limit.
  final List<String> skippedTooLarge;
  PickedFolder(this.name, this.files, this.skippedTooLarge);
}

class FolderPicker {
  static const maxFileBytes = 150 * 1024 * 1024;
  static const _ignored = {'.ds_store', 'thumbs.db', 'desktop.ini'};

  static bool isIgnored(String relativePath) {
    final name = relativePath.split('/').last.toLowerCase();
    return _ignored.contains(name) || relativePath.split('/').any((seg) => seg.startsWith('.') && seg.length > 1);
  }

  /// Lets the user choose a folder and reads every file in it (recursively).
  /// Returns null when the picker is cancelled.
  static Future<PickedFolder?> pick() => impl.pickFolder(maxFileBytes);
}
