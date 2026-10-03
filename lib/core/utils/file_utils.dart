import 'package:intl/intl.dart';

class FileUtils {
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
}
