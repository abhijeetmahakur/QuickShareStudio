import 'dart:typed_data';
import 'ocr_service_io.dart' if (dart.library.js_interop) 'ocr_service_web.dart' as impl;

class OcrResult {
  final String text;

  /// Average Tesseract confidence, 0–100.
  final double confidence;

  /// One searchable PDF page (image + invisible text) per input image.
  final List<Uint8List> pdfPages;

  OcrResult(this.text, this.confidence, this.pdfPages);
}

/// Text recognition with Tesseract.js (desktop/web app). The engine and language data
/// are downloaded on first use, so OCR needs an internet connection.
class OcrService {
  /// Languages offered in the UI, mapped to Tesseract language codes.
  static const Map<String, String> languages = {
    'English': 'eng',
    'Hindi': 'hin',
    'English + Hindi': 'eng+hin',
  };

  static bool get isSupported => impl.isSupported;

  /// Recognizes text in [images] (PNG/JPEG bytes, one per page).
  static Future<OcrResult> recognize(
    List<Uint8List> images,
    String languageCode, {
    void Function(int done, int total)? onProgress,
  }) =>
      impl.recognize(images, languageCode, onProgress);
}
