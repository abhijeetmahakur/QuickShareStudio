import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

/// Where a file ended up in the phone's Downloads folder.
class SavedDownload {
  const SavedDownload({required this.path, required this.name, required this.copied});

  /// A content:// URI on Android 10+, a file path before; [FileActions.openSaved] opens either.
  final String path;

  /// Its name in Downloads/QuickShare (Android renames clashes, e.g. "photo (1).jpg").
  final String name;

  /// False when the file was already in Downloads and nothing was written.
  final bool copied;
}

/// Saving into Downloads failed, with a message that can be shown as is.
class DownloadsException implements Exception {
  const DownloadsException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The phone's public Downloads/QuickShare folder, which the Files app shows. Android 10+ writes
/// through MediaStore and needs no permission; Android 9 and older need storage permission.
/// The Android side (DownloadsBridge.kt) runs these calls off the UI thread.
class AndroidDownloads {
  AndroidDownloads._();

  static const _channel = MethodChannel('quickshare/downloads');
  static const _system = MethodChannel('quickshare/system');

  /// How the folder is named to people.
  static const folder = 'Downloads/QuickShare';

  /// Bytes per write call, so a large file needs few platform-channel round trips.
  static const blockSize = 512 * 1024;

  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Asks for storage permission where Android needs it to write into Downloads (9 and older).
  static Future<bool> ensurePermission() async {
    final sdk = await _system.invokeMethod<int>('sdkInt') ?? 0;
    if (sdk >= 29) return true;
    return (await Permission.storage.request()).isGranted;
  }

  /// Creates an empty file in Downloads/QuickShare that stays hidden until [finish]; returns the
  /// handle the other calls take.
  static Future<String> begin(String fileName) async {
    final handle = await _channel.invokeMethod<String>('begin', {'name': fileName});
    if (handle == null || handle.isEmpty) throw const DownloadsException('Android did not create the file in $folder.');
    return handle;
  }

  static Future<void> write(String handle, Uint8List data) =>
      _channel.invokeMethod<void>('write', {'handle': handle, 'data': data});

  /// Publishes the file; returns its final name. On failure the file is already deleted.
  static Future<String> finish(String handle) async =>
      await _channel.invokeMethod<String>('finish', {'handle': handle}) ??
      (throw const DownloadsException('Android could not finish saving to $folder.'));

  /// Deletes a file that will not be finished.
  static Future<void> discard(String handle) => _channel.invokeMethod<void>('discard', {'handle': handle});

  /// Writes [bytes] as a new file in Downloads/QuickShare.
  static Future<SavedDownload> saveBytes(String fileName, Uint8List bytes) async {
    final handle = await begin(fileName);
    try {
      for (var start = 0; start < bytes.length; start += blockSize) {
        await write(handle, Uint8List.sublistView(bytes, start, min(start + blockSize, bytes.length)));
      }
      return SavedDownload(path: handle, name: await finish(handle), copied: true);
    } catch (_) {
      await discard(handle).catchError((_) {});
      rethrow;
    }
  }

  /// Makes sure a received file is in Downloads/QuickShare: keeps it if it already is there,
  /// copies it in from [path] if it was saved elsewhere (e.g. app storage), or else writes
  /// [bytes]. Returns null when neither the file nor its contents are left.
  static Future<SavedDownload?> saveReceived({
    required String fileName,
    required String path,
    Uint8List? bytes,
  }) async {
    if (!await ensurePermission()) {
      throw const DownloadsException('Allow storage access to save files into $folder.');
    }
    if (path.isNotEmpty) {
      final kept = await _channel.invokeMapMethod<String, Object?>('keep', {'path': path, 'name': fileName});
      if (kept != null) {
        return SavedDownload(
          path: kept['path']! as String,
          name: kept['name']! as String,
          copied: kept['copied'] == true,
        );
      }
    }
    if (bytes == null || bytes.isEmpty) return null;
    return saveBytes(fileName, bytes);
  }
}
