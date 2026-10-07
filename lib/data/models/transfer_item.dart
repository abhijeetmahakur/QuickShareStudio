import 'dart:typed_data';
import 'package:uuid/uuid.dart';
import '../../transfer/transfer_method.dart';

enum TransferStatus {
  queued,
  transferring,
  paused,
  completed,
  failed,
  cancelled,
}

enum TransferFileType {
  image,
  pdf,
  archive,
  text,
  other,
}

class TransferItem {
  final String transferId;
  final String fileName;
  final int fileSizeBytes;
  final TransferFileType fileType;
  final String sha256;
  final int totalChunks;
  final int transferredChunks;
  final double progress; // 0.0 - 1.0
  final TransferStatus status;
  final double speedBytesPerSec;
  final bool isSender;
  final String peerDeviceName;
  final String peerDeviceId;
  final DateTime startTime;
  final DateTime? completedTime;
  final String? errorMessage;
  final String? sessionName;
  final int? pageCount;
  final String connectionType;
  final Uint8List? rawBytes;

  /// Real transfers: how the bytes travel (null in demo mode).
  final TransferMethod? method;

  /// True when WebRTC selected a TURN relay for the active peer connection.
  final bool relayed;

  /// Interrupted by a lost connection and can continue where it stopped.
  final bool resumable;
  final Duration? eta;
  final int fileCount;

  TransferItem({
    String? transferId,
    required this.fileName,
    required this.fileSizeBytes,
    required this.fileType,
    required this.sha256,
    required this.totalChunks,
    this.transferredChunks = 0,
    this.progress = 0.0,
    this.status = TransferStatus.queued,
    this.speedBytesPerSec = 0.0,
    required this.isSender,
    required this.peerDeviceName,
    required this.peerDeviceId,
    DateTime? startTime,
    this.completedTime,
    this.errorMessage,
    this.sessionName,
    this.pageCount,
    this.connectionType = 'Local Network',
    this.rawBytes,
    this.method,
    this.relayed = false,
    this.resumable = false,
    this.eta,
    this.fileCount = 1,
  })  : transferId = transferId ?? const Uuid().v4(),
        startTime = startTime ?? DateTime.now();

  TransferItem copyWith({
    int? transferredChunks,
    double? progress,
    TransferStatus? status,
    double? speedBytesPerSec,
    DateTime? completedTime,
    String? errorMessage,
    String? sessionName,
    int? pageCount,
    String? connectionType,
    Uint8List? rawBytes,
    bool? relayed,
    bool? resumable,
    Duration? eta,
    bool clearEta = false,
  }) {
    return TransferItem(
      transferId: transferId,
      fileName: fileName,
      fileSizeBytes: fileSizeBytes,
      fileType: fileType,
      sha256: sha256,
      totalChunks: totalChunks,
      transferredChunks: transferredChunks ?? this.transferredChunks,
      progress: progress ?? this.progress,
      status: status ?? this.status,
      speedBytesPerSec: speedBytesPerSec ?? this.speedBytesPerSec,
      isSender: isSender,
      peerDeviceName: peerDeviceName,
      peerDeviceId: peerDeviceId,
      startTime: startTime,
      completedTime: completedTime ?? this.completedTime,
      errorMessage: errorMessage ?? this.errorMessage,
      sessionName: sessionName ?? this.sessionName,
      pageCount: pageCount ?? this.pageCount,
      connectionType: connectionType ?? this.connectionType,
      rawBytes: rawBytes ?? this.rawBytes,
      method: method,
      relayed: relayed ?? this.relayed,
      resumable: resumable ?? this.resumable,
      eta: clearEta ? null : (eta ?? this.eta),
      fileCount: fileCount,
    );
  }
}
