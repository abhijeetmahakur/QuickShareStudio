import 'dart:typed_data';
import 'package:uuid/uuid.dart';
import 'received_item_model.dart';

enum TransferProtocolRoute {
  localNetwork,
  directSocket,
  offlineChunkQueue,
}

class IncomingTransferRequest {
  final String requestId;
  final String senderDeviceName;
  final String senderDeviceId;
  final String fileName;
  final int fileSizeBytes;
  final Uint8List bytes;
  final ReceivedFileType fileType;
  final String sha256;
  final TransferProtocolRoute protocolRoute;
  final String connectionType;
  final DateTime timestamp;

  IncomingTransferRequest({
    String? requestId,
    required this.senderDeviceName,
    required this.senderDeviceId,
    required this.fileName,
    required this.fileSizeBytes,
    required this.bytes,
    required this.fileType,
    required this.sha256,
    this.protocolRoute = TransferProtocolRoute.localNetwork,
    this.connectionType = 'Direct Local Network',
    DateTime? timestamp,
  })  : requestId = requestId ?? const Uuid().v4(),
        timestamp = timestamp ?? DateTime.now();

  String get routeDescription {
    switch (protocolRoute) {
      case TransferProtocolRoute.localNetwork:
        return 'Direct Local Network Transfer';
      case TransferProtocolRoute.directSocket:
        return 'Direct LAN Socket';
      case TransferProtocolRoute.offlineChunkQueue:
        return 'Peer Chunk Queue';
    }
  }
}
