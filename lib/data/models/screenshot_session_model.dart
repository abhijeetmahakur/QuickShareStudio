import 'dart:convert';
import 'package:uuid/uuid.dart';
import 'screenshot_item.dart';

/// Represents a distinct screenshot-processing session.
/// Keeps session screenshots, metadata, and PDF settings isolated.
class ScreenshotSessionModel {
  final String id;
  String name;
  final DateTime createdAt;
  DateTime lastModified;
  String status; // 'Active', 'Draft', 'Exported'
  final List<ScreenshotItem> screenshots;
  String? customPdfName;

  ScreenshotSessionModel({
    String? id,
    required this.name,
    DateTime? createdAt,
    DateTime? lastModified,
    this.status = 'Draft',
    List<ScreenshotItem>? screenshots,
    this.customPdfName,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now(),
        lastModified = lastModified ?? DateTime.now(),
        screenshots = screenshots ?? [];

  int get screenshotCount => screenshots.length;

  int get totalSizeBytes =>
      screenshots.fold(0, (sum, item) => sum + item.fileSizeBytes);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
        'lastModified': lastModified.toIso8601String(),
        'status': status,
        'customPdfName': customPdfName,
        'screenshots': screenshots
            .map((s) => {
                  'id': s.id,
                  'name': s.name,
                  'bytes': base64Encode(s.bytes),
                  'sha256': s.sha256,
                  'rotationDegrees': s.rotationDegrees,
                  'caption': s.caption,
                  'aspectRatio': s.aspectRatio,
                  'width': s.width,
                  'height': s.height,
                  'importedAt': s.importedAt.toIso8601String(),
                })
            .toList(),
      };

  factory ScreenshotSessionModel.fromJson(Map<String, dynamic> json) {
    final rawScreenshots = json['screenshots'] as List<dynamic>? ?? [];
    final items = <ScreenshotItem>[];
    for (final raw in rawScreenshots) {
      if (raw is Map<String, dynamic>) {
        final bytesBase64 = raw['bytes'] as String? ?? '';
        final bytes = base64Decode(bytesBase64);
        items.add(ScreenshotItem(
          id: raw['id'] as String?,
          name: raw['name'] as String? ?? 'Screenshot',
          bytes: bytes,
          sha256: raw['sha256'] as String?,
          rotationDegrees: raw['rotationDegrees'] as int? ?? 0,
          caption: raw['caption'] as String?,
          aspectRatio: (raw['aspectRatio'] as num?)?.toDouble() ?? 16 / 9,
          width: raw['width'] as int? ?? 1920,
          height: raw['height'] as int? ?? 1080,
          importedAt: DateTime.tryParse(raw['importedAt'] as String? ?? '') ?? DateTime.now(),
        ));
      }
    }

    return ScreenshotSessionModel(
      id: json['id'] as String?,
      name: json['name'] as String? ?? 'Untitled Session',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
      lastModified: DateTime.tryParse(json['lastModified'] as String? ?? '') ?? DateTime.now(),
      status: json['status'] as String? ?? 'Draft',
      customPdfName: json['customPdfName'] as String?,
      screenshots: items,
    );
  }
}
