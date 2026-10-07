import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../../data/models/screenshot_item.dart';
import '../platform/native_channels.dart';
import 'web_interop_stub.dart' if (dart.library.js_interop) 'web_interop_web.dart';

class ClipboardImageService {
  /// How to put a screenshot on the clipboard on this platform (shown when a paste finds none).
  static String get copyHint {
    if (kIsWeb) return 'Copy an image, then paste.';
    return switch (defaultTargetPlatform) {
      TargetPlatform.windows => 'Copy an image (Win+Shift+S / PrtScn), then paste.',
      TargetPlatform.linux => 'Copy an image (PrtScn, or Copy Image in any app), then paste.',
      _ => 'Copy an image, then paste.',
    };
  }

  /// The clipboard image as PNG bytes (system clipboard, or the browser's), or null. Unlike
  /// [readPastedImage] this never guesses images from text.
  static Future<Uint8List?> readImageBytes() async {
    final native = await NativeClipboard.readImage();
    if (native != null) return native;
    try {
      final webB64 = await readWebClipboardImageAsync();
      if (webB64 != null && webB64.isNotEmpty) return _decodeBase64(webB64);
    } catch (_) {}
    return null;
  }

  /// Attempts to read an image from the clipboard.
  /// 1. The system clipboard image (Linux, Windows and Android apps).
  /// 2. Checks browser paste event buffer captured in JS (for Flutter Web).
  /// 3. Checks text clipboard for data URL / base64 image strings.
  static Future<ScreenshotItem?> readPastedImage() async {
    // 1. Native clipboard: screenshots and images copied from any app, as PNG.
    try {
      final png = await NativeClipboard.readImage();
      if (png != null) {
        final now = DateTime.now();
        return await ScreenshotItem.create(
          name: 'Pasted_Screenshot_${now.millisecondsSinceEpoch.toString().substring(7)}.png',
          bytes: png,
        );
      }
    } catch (e) {
      debugPrint('Error reading clipboard image: $e');
    }

    // 2. Check async web clipboard (supports both toolbar button click and native paste)
    try {
      final webB64 = await readWebClipboardImageAsync();
      if (webB64 != null && webB64.isNotEmpty) {
        final bytes = _decodeBase64(webB64);
        if (bytes != null && bytes.isNotEmpty) {
          final now = DateTime.now();
          final name = 'Pasted_Screenshot_${now.millisecondsSinceEpoch.toString().substring(7)}.png';
          return await ScreenshotItem.create(
            name: name,
            bytes: bytes,
          );
        }
      }
    } catch (e) {
      debugPrint('Error reading async web clipboard image: $e');
    }

    // 3. Check standard text clipboard for base64 or data URLs
    try {
      final clipData = await Clipboard.getData(Clipboard.kTextPlain);
      final text = clipData?.text?.trim();
      if (text != null && text.isNotEmpty) {
        if (text.startsWith('data:image/') || (text.length > 100 && !text.contains(' '))) {
          final bytes = _decodeBase64(text);
          if (bytes != null && bytes.isNotEmpty) {
            final now = DateTime.now();
            final name = 'Pasted_Image_${now.millisecondsSinceEpoch.toString().substring(7)}.png';
            return await ScreenshotItem.create(
              name: name,
              bytes: bytes,
            );
          }
        }
      }
    } catch (e) {
      debugPrint('Error reading text clipboard: $e');
    }

    return null;
  }

  /// Web only: receives each native browser paste outside text fields
  /// (an image data URL, or null when the clipboard held no image).
  static void setWebPasteHandler(void Function(String? dataUrl)? handler) =>
      setWebPasteImageHandler(handler);

  /// Converts an image data URL delivered by the browser's native paste event into a screenshot.
  static Future<ScreenshotItem?> screenshotFromDataUrl(String dataUrl) async {
    final bytes = _decodeBase64(dataUrl);
    if (bytes == null || bytes.isEmpty) return null;
    final now = DateTime.now();
    final name = 'Pasted_Screenshot_${now.millisecondsSinceEpoch.toString().substring(7)}.png';
    return ScreenshotItem.create(name: name, bytes: bytes);
  }

  static Uint8List? _decodeBase64(String input) {
    try {
      String clean = input.trim();
      if (clean.contains(',')) {
        clean = clean.split(',').last;
      }
      clean = clean.replaceAll('\n', '').replaceAll('\r', '').replaceAll(' ', '');
      return base64Decode(clean);
    } catch (_) {
      return null;
    }
  }

  /// Reads images dropped into the browser window via HTML5 drag-and-drop
  static Future<List<ScreenshotItem>> readDroppedImages() async {
    final jsonStr = popWebDroppedImagesJson();
    if (jsonStr == null || jsonStr.isEmpty) return [];

    final result = <ScreenshotItem>[];
    try {
      final list = jsonDecode(jsonStr) as List<dynamic>;
      for (final item in list) {
        final map = item as Map<String, dynamic>;
        final name = (map['name'] as String?) ?? 'Dropped_Image.png';
        final dataStr = map['data'] as String?;
        if (dataStr != null) {
          final bytes = _decodeBase64(dataStr);
          if (bytes != null && bytes.isNotEmpty) {
            final screenshot = await ScreenshotItem.create(
              name: name,
              bytes: bytes,
            );
            result.add(screenshot);
          }
        }
      }
    } catch (e) {
      debugPrint('Error decoding dropped images: $e');
    }
    return result;
  }

  static int _sampleCounter = 0;

  /// Creates a synthetic test screenshot for instant demonstration if needed
  static Future<ScreenshotItem> createSamplePastedScreenshot() async {
    _sampleCounter++;
    final now = DateTime.now();
    final name = 'Screenshot_Pasted_${now.minute}_${now.second}_$_sampleCounter.png';
    // Minimal valid 1x1 RGBA PNG
    final pngHeader = [
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
      0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
      0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
      0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
      0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
      0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
      0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
      0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
      0x42, 0x60, 0x82,
    ];
    return ScreenshotItem(
      name: name,
      bytes: Uint8List.fromList(pngHeader),
      sha256: 'sample_${DateTime.now().microsecondsSinceEpoch}_$_sampleCounter',
      width: 1920,
      height: 1080,
      aspectRatio: 16.0 / 9.0,
    );
  }
}
