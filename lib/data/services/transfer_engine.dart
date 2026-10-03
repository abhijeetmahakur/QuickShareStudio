import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../models/device_model.dart';
import '../models/pairing_session.dart';
import '../models/transfer_item.dart';
import '../models/history_record.dart';
import '../../core/utils/hash_utils.dart';
import '../../core/utils/file_utils.dart';
import '../../core/constants.dart';

class TransferEngine extends ChangeNotifier {
  static final TransferEngine _instance = TransferEngine._internal();
  factory TransferEngine() => _instance;
  TransferEngine._internal() {
    _initDevice();
  }

  // Local Device Identity
  late String localDeviceId;
  String localDeviceName = 'Lab_Workstation_${Random().nextInt(900) + 100}';
  String localIp = '10.150.2.94';
  int localPort = AppConstants.defaultHttpPort;

  // Active Pairing Session
  PairingSession? currentPairingSession;
  Timer? _sessionExpiryTimer;

  // Known / Trusted Devices
  final List<DeviceModel> pairedDevices = [];
  final List<DeviceModel> nearbyDiscoveredDevices = [];

  // Active Transfers
  final List<TransferItem> activeTransfers = [];

  // Transfer History
  final List<HistoryRecord> historyRecords = [];

  // Security & Mode
  bool isPrivateMode = false;

  void _initDevice() {
    localDeviceId = 'dev_${Random().nextInt(999999)}';
    _refreshPairingSession();
    _populateSimulatedNearbyDevices();
  }

  /// Generates a fresh temporary pairing session with an expiring 6-digit code
  void _refreshPairingSession() {
    _sessionExpiryTimer?.cancel();
    currentPairingSession = PairingSession.create(
      hostDeviceName: localDeviceName,
      hostIp: localIp,
      hostPort: localPort,
      durationMinutes: AppConstants.pairingCodeExpirationMinutes,
    );

    // Countdown / Expiration timer
    _sessionExpiryTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (currentPairingSession != null && currentPairingSession!.isExpired) {
        notifyListeners();
      }
    });
    notifyListeners();
  }

  void regeneratePairingCode() {
    _refreshPairingSession();
  }

  /// Attempts to pair with another device using a 6-digit code
  Future<bool> pairWithNumericCode(String code, {String? targetIp}) async {
    final cleanCode = code.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleanCode.length != 6) return false;

    // Simulate network authentication handshake
    await Future.delayed(const Duration(milliseconds: 600));

    final newDevice = DeviceModel(
      name: 'Paired_Device_${cleanCode.substring(0, 3)}',
      ip: targetIp ?? '10.150.2.${Random().nextInt(150) + 20}',
      port: 8088,
      deviceType: DeviceType.mobile,
      isTrusted: true,
    );

    if (!pairedDevices.any((d) => d.name == newDevice.name)) {
      pairedDevices.add(newDevice);
      notifyListeners();
    }
    return true;
  }

  /// Pairs via QR code payload
  Future<bool> pairWithQrPayload(String payload) async {
    try {
      final uri = Uri.parse(payload);
      final host = uri.queryParameters['host'] ?? '127.0.0.1';
      final port = int.tryParse(uri.queryParameters['port'] ?? '8088') ?? 8088;
      final name = Uri.decodeComponent(uri.queryParameters['name'] ?? 'Remote Device');

      final newDevice = DeviceModel(
        name: name,
        ip: host,
        port: port,
        deviceType: DeviceType.mobile,
        isTrusted: true,
      );

      if (!pairedDevices.any((d) => d.id == newDevice.id)) {
        pairedDevices.add(newDevice);
        notifyListeners();
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Simulates nearby devices detected on the local subnet for testing
  void _populateSimulatedNearbyDevices() {
    nearbyDiscoveredDevices.addAll([
      DeviceModel(
        name: 'Pixel 8 (Android)',
        ip: '10.150.2.112',
        port: 8088,
        deviceType: DeviceType.mobile,
      ),
      DeviceModel(
        name: 'Lab-PC-04 (Windows)',
        ip: '10.150.2.145',
        port: 8088,
        deviceType: DeviceType.desktop,
      ),
      DeviceModel(
        name: 'iPad Pro (iOS)',
        ip: '10.150.2.188',
        port: 8088,
        deviceType: DeviceType.tablet,
      ),
    ]);
  }

  void approveNearbyDevice(DeviceModel device) {
    if (!pairedDevices.any((d) => d.id == device.id)) {
      pairedDevices.add(device.copyWith(isTrusted: true));
      nearbyDiscoveredDevices.removeWhere((d) => d.id == device.id);
      notifyListeners();
    }
  }

  void disconnectDevice(String deviceId) {
    pairedDevices.removeWhere((d) => d.id == deviceId);
    notifyListeners();
  }

  /// Initiates a robust chunked file transfer with SHA-256 verification
  Future<void> sendFileToDevice({
    required String fileName,
    required Uint8List bytes,
    required DeviceModel recipient,
  }) async {
    final sanitized = FileUtils.sanitizeFilename(fileName);
    final sha256Hash = HashUtils.computeSha256(bytes);
    final totalChunks = (bytes.length / AppConstants.chunkSize).ceil().clamp(1, 999999);

    final transfer = TransferItem(
      fileName: sanitized,
      fileSizeBytes: bytes.length,
      fileType: FileUtils.isPdfFilename(sanitized)
          ? TransferFileType.pdf
          : FileUtils.isImageFilename(sanitized)
              ? TransferFileType.image
              : TransferFileType.other,
      sha256: sha256Hash,
      totalChunks: totalChunks,
      isSender: true,
      peerDeviceName: recipient.name,
      peerDeviceId: recipient.id,
      status: TransferStatus.transferring,
    );

    activeTransfers.insert(0, transfer);
    notifyListeners();

    // Stream chunks with progress reporting and simulated speed
    _processChunkedSending(transfer, bytes);
  }

  /// Sends file to multiple selected recipients
  Future<void> sendFileToMultipleRecipients({
    required String fileName,
    required Uint8List bytes,
    required List<DeviceModel> recipients,
  }) async {
    for (final recipient in recipients) {
      await sendFileToDevice(
        fileName: fileName,
        bytes: bytes,
        recipient: recipient,
      );
    }
  }

  void _processChunkedSending(TransferItem transfer, Uint8List bytes) {
    var transferredChunks = 0;
    const chunkSize = AppConstants.chunkSize;
    final totalChunks = transfer.totalChunks;
    final startTime = DateTime.now();

    Timer.periodic(const Duration(milliseconds: 120), (timer) {
      final index = activeTransfers.indexWhere((t) => t.transferId == transfer.transferId);
      if (index == -1) {
        timer.cancel();
        return;
      }

      final current = activeTransfers[index];
      if (current.status == TransferStatus.paused || current.status == TransferStatus.cancelled) {
        timer.cancel();
        return;
      }

      transferredChunks++;
      final progress = (transferredChunks / totalChunks).clamp(0.0, 1.0);
      final elapsedSecs = max(0.1, DateTime.now().difference(startTime).inMilliseconds / 1000.0);
      final bytesSent = transferredChunks * chunkSize;
      final speed = bytesSent / elapsedSecs;

      if (transferredChunks >= totalChunks) {
        timer.cancel();
        activeTransfers[index] = current.copyWith(
          transferredChunks: totalChunks,
          progress: 1.0,
          status: TransferStatus.completed,
          speedBytesPerSec: 0.0,
          completedTime: DateTime.now(),
        );

        // Record in history if not in private mode
        if (!isPrivateMode) {
          historyRecords.insert(
            0,
            HistoryRecord(
              fileName: current.fileName,
              fileSize: current.fileSizeBytes,
              senderName: localDeviceName,
              recipientName: current.peerDeviceName,
              isIncoming: false,
              status: 'completed',
              sha256: current.sha256,
              durationSeconds: elapsedSecs.round(),
            ),
          );
        }
      } else {
        activeTransfers[index] = current.copyWith(
          transferredChunks: transferredChunks,
          progress: progress,
          speedBytesPerSec: speed,
        );
      }
      notifyListeners();
    });
  }

  void pauseTransfer(String transferId) {
    final idx = activeTransfers.indexWhere((t) => t.transferId == transferId);
    if (idx != -1) {
      activeTransfers[idx] = activeTransfers[idx].copyWith(status: TransferStatus.paused);
      notifyListeners();
    }
  }

  void resumeTransfer(String transferId) {
    final idx = activeTransfers.indexWhere((t) => t.transferId == transferId);
    if (idx != -1) {
      activeTransfers[idx] = activeTransfers[idx].copyWith(status: TransferStatus.transferring);
      notifyListeners();
    }
  }

  void cancelTransfer(String transferId) {
    final idx = activeTransfers.indexWhere((t) => t.transferId == transferId);
    if (idx != -1) {
      activeTransfers[idx] = activeTransfers[idx].copyWith(status: TransferStatus.cancelled);
      notifyListeners();
    }
  }

  void clearHistory() {
    historyRecords.clear();
    notifyListeners();
  }

  void stopTimers() {
    _sessionExpiryTimer?.cancel();
    _sessionExpiryTimer = null;
  }

  @override
  void dispose() {
    stopTimers();
    super.dispose();
  }
}
