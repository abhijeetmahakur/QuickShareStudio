import 'dart:typed_data';
import 'ocr_service.dart';

// Tesseract.js only runs in the browser-based desktop app; native builds have no OCR engine yet.
const bool isSupported = false;

Future<OcrResult> recognize(
  List<Uint8List> images,
  String languageCode,
  void Function(int done, int total)? onProgress,
) {
  throw UnsupportedError('OCR is available in the QuickShare Studio desktop app (Windows/Linux).');
}
