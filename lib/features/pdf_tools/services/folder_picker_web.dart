import 'dart:js_interop';
import 'folder_picker.dart';

extension type _JsPickedFile(JSObject _) implements JSObject {
  external String get path;
  external JSUint8Array? get bytes;
}

@JS('window.quicksharePickFolder')
external JSPromise<JSArray<_JsPickedFile>> _jsPickFolder(int maxBytes);

Future<PickedFolder?> pickFolder(int maxFileBytes) async {
  final List<_JsPickedFile> picked;
  try {
    picked = (await _jsPickFolder(maxFileBytes).toDart).toDart;
  } catch (_) {
    return null;
  }
  if (picked.isEmpty) return null;
  // webkitRelativePath is "<folder>/<sub>/<file>": the first segment is the picked folder.
  final folderName = picked.first.path.split('/').first;
  final files = <PickedFolderFile>[];
  final skipped = <String>[];
  for (final f in picked) {
    final rel = f.path.contains('/') ? f.path.substring(f.path.indexOf('/') + 1) : f.path;
    if (FolderPicker.isIgnored(rel)) continue;
    final bytes = f.bytes;
    if (bytes == null) {
      skipped.add(rel);
    } else {
      files.add(PickedFolderFile(rel, bytes.toDart));
    }
  }
  files.sort((a, b) => a.relativePath.toLowerCase().compareTo(b.relativePath.toLowerCase()));
  return PickedFolder(folderName, files, skipped);
}
