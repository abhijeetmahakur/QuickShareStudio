import 'dart:typed_data';
import 'package:uuid/uuid.dart';
import '../../core/utils/hash_utils.dart';

class ScreenshotItem {
  final String id;
  final String name;
  final Uint8List bytes;
  final String sha256;
  final int rotationDegrees; // 0, 90, 180, 270
  final String? caption;
  final double aspectRatio; // width / height
  final int width;
  final int height;
  final DateTime importedAt;

  ScreenshotItem({
    String? id,
    required this.name,
    required this.bytes,
    String? sha256,
    this.rotationDegrees = 0,
    this.caption,
    this.aspectRatio = 16 / 9,
    this.width = 1920,
    this.height = 1080,
    DateTime? importedAt,
  })  : id = id ?? const Uuid().v4(),
        sha256 = sha256 ?? HashUtils.computeSha256(bytes),
        importedAt = importedAt ?? DateTime.now();

  ScreenshotItem copyWith({
    String? name,
    Uint8List? bytes,
    String? sha256,
    int? rotationDegrees,
    String? caption,
    double? aspectRatio,
    int? width,
    int? height,
  }) {
    return ScreenshotItem(
      id: id,
      name: name ?? this.name,
      bytes: bytes ?? this.bytes,
      sha256: sha256 ?? this.sha256,
      rotationDegrees: rotationDegrees ?? this.rotationDegrees,
      caption: caption ?? this.caption,
      aspectRatio: aspectRatio ?? this.aspectRatio,
      width: width ?? this.width,
      height: height ?? this.height,
      importedAt: importedAt,
    );
  }
}
