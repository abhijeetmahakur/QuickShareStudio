import 'dart:typed_data';
import 'ocr_service_io.dart' if (dart.library.js_interop) 'ocr_service_web.dart' as impl;

/// Whether text recognition can run right now, and what to install when it cannot.
class OcrAvailability {
  const OcrAvailability({required this.ready, this.engine, this.hint});
  final bool ready;

  /// e.g. "Tesseract (built in)".
  final String? engine;

  /// What to install (with the command for this system) when [ready] is false.
  final String? hint;
}

class OcrUnavailableException implements Exception {
  OcrUnavailableException(this.message);
  final String message;
  @override
  String toString() => message;
}

class OcrResult {
  final String text;

  /// Average Tesseract confidence, 0–100.
  final double confidence;

  /// One searchable PDF page (image + invisible text) per input image.
  final List<Uint8List> pdfPages;

  OcrResult(this.text, this.confidence, this.pdfPages);
}

/// Text recognition with Tesseract: the command-line engine in the Windows and Linux apps
/// (bundled with the Linux AppImage), Tesseract.js in the browser (downloaded on first use).
class OcrService {
  /// Languages offered in the UI, mapped to Tesseract language codes.
  static const Map<String, String> languages = {
    'English': 'eng',
    'Hindi': 'hin',
    'English + Hindi': 'eng+hin',
  };

  static bool get isSupported => impl.isSupported;

  /// Checks for the engine and the language data [languageCode] needs.
  static Future<OcrAvailability> availability(String languageCode) => impl.availability(languageCode);

  /// Recognizes text in [images] (PNG/JPEG bytes, one per page).
  static Future<OcrResult> recognize(
    List<Uint8List> images,
    String languageCode, {
    void Function(int done, int total)? onProgress,
  }) =>
      impl.recognize(images, languageCode, onProgress);
}
