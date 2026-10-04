import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:intl/intl.dart';

class FileUtils {
  /// Returns a platform-appropriate default download directory path
  static String getDefaultDownloadDirectory() {
    if (kIsWeb) {
      return 'Downloads/QuickShare';
    }
    try {
      if (Platform.isWindows) {
        final profile = Platform.environment['USERPROFILE'];
        return profile != null ? '$profile\\Downloads\\QuickShare' : r'C:\Downloads\QuickShare';
      }
      if (Platform.isMacOS || Platform.isLinux) {
        final home = Platform.environment['HOME'];
        return home != null ? '$home/Downloads/QuickShare' : '/tmp/QuickShare';
      }
      if (Platform.isAndroid) {
        return '/storage/emulated/0/Download/QuickShare';
      }
    } catch (_) {}
    return 'Downloads/QuickShare';
  }
  /// Sanitizes invalid filename characters for all operating systems (Windows, macOS, Linux, Android, iOS)
  static String sanitizeFilename(String filename, {String fallback = 'document'}) {
    var clean = filename.trim();
    // Replace forbidden characters: \ / : * ? " < > |
    clean = clean.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    // Remove control characters (0-31)
    clean = clean.replaceAll(RegExp(r'[\x00-\x1F]'), '');
    // Remove trailing periods and spaces (problematic on Windows)
    clean = clean.replaceAll(RegExp(r'[. ]+$'), '');

    if (clean.isEmpty) {
      clean = fallback;
    }
    return clean;
  }

  /// Formats and sanitizes a custom PDF filename for export.
  /// Automatically strips forbidden filesystem characters, trims whitespace,
  /// handles empty input with a sensible fallback, and ensures .pdf extension.
  static String formatPdfFilename(String input, {String fallback = 'QuickShare_Document.pdf'}) {
    var clean = input.trim();
    // Replace forbidden characters: \ / : * ? " < > |
    clean = clean.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    // Remove control characters (0-31)
    clean = clean.replaceAll(RegExp(r'[\x00-\x1F]'), '');
    // Remove trailing periods and spaces
    clean = clean.replaceAll(RegExp(r'[. ]+$'), '');

    if (clean.isEmpty) {
      clean = fallback;
    }
    if (!clean.toLowerCase().endsWith('.pdf')) {
      clean = '$clean.pdf';
    }
    return clean;
  }

  /// Generates a smart default PDF filename based on a session name or date
  static String generateSmartPdfName(String sessionName) {
    final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    if (sessionName.trim().isEmpty) {
      return 'Lab_Screenshots_$dateStr.pdf';
    }
    final cleanSession = sanitizeFilename(sessionName).replaceAll(' ', '_');
    return '${cleanSession}_$dateStr.pdf';
  }

  /// Suggests a non-conflicting numbered filename if an existing set of names contains it
  static String getNumberedFilename(String baseName, Set<String> existingNames) {
    if (!existingNames.contains(baseName)) return baseName;

    final dotIndex = baseName.lastIndexOf('.');
    final nameWithoutExt = dotIndex != -1 ? baseName.substring(0, dotIndex) : baseName;
    final ext = dotIndex != -1 ? baseName.substring(dotIndex) : '';

    var counter = 1;
    while (true) {
      final candidate = '$nameWithoutExt ($counter)$ext';
      if (!existingNames.contains(candidate)) {
        return candidate;
      }
      counter++;
    }
  }

  /// Detects whether a filename represents an image
  static bool isImageFilename(String filename) {
    final lower = filename.toLowerCase();
    return lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.bmp') ||
        lower.endsWith('.gif');
  }

  /// Detects whether a filename represents a PDF
  static bool isPdfFilename(String filename) {
    return filename.toLowerCase().endsWith('.pdf');
  }

  /// Combines a directory path and a filename using the appropriate separator
  /// (handles both Windows backslashes and POSIX forward slashes for Linux/macOS/Android)
  static String joinPath(String directory, String fileName) {
    if (directory.isEmpty) return fileName;
    if (directory.endsWith('/') || directory.endsWith(r'\')) {
      return '$directory$fileName';
    }
    final separator = directory.contains(r'\') ? r'\' : '/';
    return '$directory$separator$fileName';
  }
}
