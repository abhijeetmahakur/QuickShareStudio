import 'dart:typed_data';
import 'package:uuid/uuid.dart';
import '../../core/utils/hash_utils.dart';

class SessionPdf {
  final String id;
  final String sessionName;
  final String fileName;
  final Uint8List bytes;
  final int pageCount;
  final int screenshotCount;
  final String paperFormatDescription;
  final int fileSizeBytes;
  final String sha256;
  final DateTime createdAt;
  final bool isRecovered;

  String get name => fileName;

  SessionPdf({
    String? id,
    required this.sessionName,
    required this.fileName,
    required this.bytes,
    required this.pageCount,
    required this.screenshotCount,
    this.paperFormatDescription = 'A4 Portrait',
    DateTime? createdAt,
    this.isRecovered = false,
  })  : id = id ?? const Uuid().v4(),
        fileSizeBytes = bytes.length,
        sha256 = HashUtils.computeSha256(bytes),
        createdAt = createdAt ?? DateTime.now();

  SessionPdf copyWith({
    String? sessionName,
    String? fileName,
    Uint8List? bytes,
    int? pageCount,
    int? screenshotCount,
    String? paperFormatDescription,
    bool? isRecovered,
  }) {
    return SessionPdf(
      id: id,
      sessionName: sessionName ?? this.sessionName,
      fileName: fileName ?? this.fileName,
      bytes: bytes ?? this.bytes,
      pageCount: pageCount ?? this.pageCount,
      screenshotCount: screenshotCount ?? this.screenshotCount,
      paperFormatDescription: paperFormatDescription ?? this.paperFormatDescription,
      createdAt: createdAt,
      isRecovered: isRecovered ?? this.isRecovered,
    );
  }
}
