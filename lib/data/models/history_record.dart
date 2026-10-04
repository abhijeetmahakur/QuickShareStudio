import 'package:uuid/uuid.dart';

class HistoryRecord {
  final String id;
  final String fileName;
  final int fileSize;
  final String senderName;
  final String recipientName;
  final bool isIncoming;
  final String status; // 'completed', 'failed', 'cancelled'
  final DateTime timestamp;
  final String sha256;
  final int durationSeconds;
  final String? sessionName;
  final int? pageCount;
  final String connectionType; // e.g. 'Local Network'

  HistoryRecord({
    String? id,
    required this.fileName,
    required this.fileSize,
    required this.senderName,
    required this.recipientName,
    required this.isIncoming,
    required this.status,
    DateTime? timestamp,
    required this.sha256,
    this.durationSeconds = 0,
    this.sessionName,
    this.pageCount,
    this.connectionType = 'Local Network',
  })  : id = id ?? const Uuid().v4(),
        timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'fileName': fileName,
        'fileSize': fileSize,
        'senderName': senderName,
        'recipientName': recipientName,
        'isIncoming': isIncoming,
        'status': status,
        'timestamp': timestamp.toIso8601String(),
        'sha256': sha256,
        'durationSeconds': durationSeconds,
        'sessionName': sessionName,
        'pageCount': pageCount,
        'connectionType': connectionType,
      };

  factory HistoryRecord.fromJson(Map<String, dynamic> json) => HistoryRecord(
        id: json['id'] as String,
        fileName: json['fileName'] as String,
        fileSize: json['fileSize'] as int? ?? 0,
        senderName: json['senderName'] as String? ?? '',
        recipientName: json['recipientName'] as String? ?? '',
        isIncoming: json['isIncoming'] as bool? ?? false,
        status: json['status'] as String? ?? 'completed',
        timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
        sha256: json['sha256'] as String? ?? '',
        durationSeconds: json['durationSeconds'] as int? ?? 0,
        sessionName: json['sessionName'] as String?,
        pageCount: json['pageCount'] as int?,
        connectionType: json['connectionType'] as String? ?? 'Local Network',
      );
}
