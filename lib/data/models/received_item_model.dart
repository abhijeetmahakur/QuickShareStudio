import 'dart:convert';
import 'dart:typed_data';

enum ReceivedFileType { pdf, image, text, document, other }

class ReceivedItemModel {
  final String id;
  final String fileName;
  final int fileSizeBytes;
  final String senderDeviceName;
  final DateTime receivedAt;
  final Uint8List bytes;
  final String savedToPath;
  final ReceivedFileType fileType;
  final String sha256;
  final String? textContent;
  final bool isDownloaded;

  ReceivedItemModel({
    String? id,
    required this.fileName,
    required this.fileSizeBytes,
    required this.senderDeviceName,
    DateTime? receivedAt,
    required this.bytes,
    required this.savedToPath,
    this.fileType = ReceivedFileType.other,
    this.sha256 = '',
    this.textContent,
    this.isDownloaded = true,
  })  : id = id ?? 'rcv_${DateTime.now().millisecondsSinceEpoch}_${fileName.hashCode.abs()}',
        receivedAt = receivedAt ?? DateTime.now();

  ReceivedItemModel copyWith({
    String? fileName,
    int? fileSizeBytes,
    String? senderDeviceName,
    DateTime? receivedAt,
    Uint8List? bytes,
    String? savedToPath,
    ReceivedFileType? fileType,
    String? sha256,
    String? textContent,
    bool? isDownloaded,
  }) {
    return ReceivedItemModel(
      id: id,
      fileName: fileName ?? this.fileName,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
      senderDeviceName: senderDeviceName ?? this.senderDeviceName,
      receivedAt: receivedAt ?? this.receivedAt,
      bytes: bytes ?? this.bytes,
      savedToPath: savedToPath ?? this.savedToPath,
      fileType: fileType ?? this.fileType,
      sha256: sha256 ?? this.sha256,
      textContent: textContent ?? this.textContent,
      isDownloaded: isDownloaded ?? this.isDownloaded,
    );
  }

  static const int maxPersistedBytes = 1024 * 1024;

  Map<String, dynamic> toJson() => {
        'id': id,
        'fileName': fileName,
        'fileSizeBytes': fileSizeBytes,
        'senderDeviceName': senderDeviceName,
        'receivedAt': receivedAt.toIso8601String(),
        'savedToPath': savedToPath,
        'fileType': fileType.name,
        'sha256': sha256,
        'textContent': textContent,
        'isDownloaded': isDownloaded,
        // Browser storage is ~5 MB, so only small items keep their contents across restarts;
        // large files live in Downloads/QuickShare once downloaded.
        'bytesBase64': bytes.isNotEmpty && bytes.length <= maxPersistedBytes ? base64Encode(bytes) : '',
      };

  factory ReceivedItemModel.fromJson(Map<String, dynamic> json) {
    Uint8List parsedBytes = Uint8List(0);
    final b64 = json['bytesBase64'] as String?;
    if (b64 != null && b64.isNotEmpty) {
      try {
        parsedBytes = base64Decode(b64);
      } catch (_) {}
    }

    final typeStr = json['fileType'] as String? ?? 'other';
    final resolvedType = ReceivedFileType.values.firstWhere(
      (e) => e.name == typeStr,
      orElse: () => ReceivedFileType.other,
    );

    return ReceivedItemModel(
      id: json['id'] as String?,
      fileName: json['fileName'] as String? ?? 'Received_File',
      fileSizeBytes: json['fileSizeBytes'] as int? ?? parsedBytes.length,
      senderDeviceName: json['senderDeviceName'] as String? ?? 'Remote Device',
      receivedAt: DateTime.tryParse(json['receivedAt'] as String? ?? '') ?? DateTime.now(),
      bytes: parsedBytes,
      savedToPath: json['savedToPath'] as String? ?? '',
      fileType: resolvedType,
      sha256: json['sha256'] as String? ?? '',
      textContent: json['textContent'] as String?,
      isDownloaded: json['isDownloaded'] as bool? ?? true,
    );
  }
}
