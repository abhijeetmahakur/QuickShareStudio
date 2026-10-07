import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'file_actions_io.dart' if (dart.library.js_interop) 'file_actions_web.dart' as impl;

/// Save / open / share for files the app produces or receives.
///
/// The installed app is a Flutter web bundle, which cannot write to disk itself, so on web
/// these go through the local launcher server (scripts/server.py). Each method returns a
/// user-facing message describing what happened, and throws if it failed.
class FileActions {
  /// Saves into Downloads/QuickShare ([directory] on native builds).
  static Future<String> save(Uint8List bytes, String fileName, {String? directory}) =>
      impl.saveFile(bytes, fileName, directory);

  /// Opens the file in its default Windows app (for PDFs, a viewer that can print).
  static Future<String> open(Uint8List bytes, String fileName) => impl.openFile(bytes, fileName);

  /// Opens a file that is already saved (large received files are not kept in memory).
  static Future<String> openSaved(String path) => impl.openSavedFile(path);

  /// Reads a file that was saved earlier (received files too large to keep in memory).
  static Future<Uint8List> readSaved(String path) => impl.readSavedFile(path);

  /// Whether [revealInFolder] works here (desktop apps and the browser launcher).
  static bool get canReveal => impl.canReveal;

  /// Opens the file manager at a saved file, with the file selected where supported.
  static Future<String> revealInFolder(String path) => impl.revealInFolder(path);

  /// Opens the OS share sheet; falls back to saving and revealing the file.
  static Future<String> share(Uint8List bytes, String fileName, {String? directory}) =>
      impl.shareFile(bytes, fileName, directory);

  /// Runs one of the actions above and shows its outcome (or error) in a snackbar.
  static Future<void> runWithSnackBar(BuildContext context, Future<String> Function() action) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final message = await action();
      messenger.showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 4)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }
}
