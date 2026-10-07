import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:zxing2/qrcode.dart';

/// Reads a pairing QR code from a picture: a screenshot of the other device's code, or a
/// photo of its screen. Desktop builds have no camera scanner, so this is how they scan.
class QrImageDecoder {
  QrImageDecoder._();

  /// Pictures are scaled down to this before decoding; QR codes survive it easily.
  static const maxSide = 1600;

  /// The text of the first QR code found in [bytes], or null when there is none.
  static Future<String?> decode(Uint8List bytes) => compute(decodeSync, bytes);

  @visibleForTesting
  static String? decodeSync(Uint8List bytes) {
    img.Image? image;
    try {
      image = img.decodeImage(bytes);
    } catch (_) {
      // Not a picture the decoder understands (the image package throws on some garbage).
    }
    if (image == null) return null;
    if (image.width > maxSide || image.height > maxSide) {
      image = image.width >= image.height
          ? img.copyResize(image, width: maxSide)
          : img.copyResize(image, height: maxSide);
    }
    // Transparent pixels would read as black: flatten onto white first.
    final flat = img.Image(width: image.width, height: image.height, numChannels: 4)
      ..clear(img.ColorRgba8(255, 255, 255, 255));
    img.compositeImage(flat, image);
    // ARGB ints, as RGBLuminanceSource expects (bgra bytes on little-endian machines).
    final bgra = flat.getBytes(order: img.ChannelOrder.bgra);
    final pixels = Int32List.view(bgra.buffer, bgra.offsetInBytes, bgra.lengthInBytes ~/ 4);
    final source = RGBLuminanceSource(flat.width, flat.height, pixels);
    final hints = DecodeHints()..put(DecodeHintType.tryHarder);
    // Light-on-dark codes (dark mode screenshots) only decode inverted.
    for (final candidate in <LuminanceSource>[source, InvertedLuminanceSource(source)]) {
      for (final binarizer in <Binarizer>[HybridBinarizer(candidate), GlobalHistogramBinarizer(candidate)]) {
        try {
          return QRCodeReader().decode(BinaryBitmap(binarizer), hints: hints).text;
        } on ReaderException {
          // Try the next combination.
        }
      }
    }
    return null;
  }
}
