import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/device_model.dart';
import '../models/transfer_item.dart';
import '../models/history_record.dart';
import '../models/received_item_model.dart';
import '../../core/utils/hash_utils.dart';
import '../../core/utils/file_utils.dart';
import '../../core/constants.dart';
import 'transfer_engine.dart';

/// CrossDeviceTransferService coordinates cross-platform file transfers
/// over local Wi-Fi / LAN networks across Windows, macOS, Linux, Android, iOS, etc.
class CrossDeviceTransferService extends ChangeNotifier {
  static final CrossDeviceTransferService _instance = CrossDeviceTransferService._internal();
  factory CrossDeviceTransferService() => _instance;

  CrossDeviceTransferService._internal();

  HttpServer? _server;
  int _activePort = AppConstants.defaultHttpPort;
  String _activeIp = '127.0.0.1';
  bool _isServerRunning = false;
  String? _lastServerError;

  int get activePort => _activePort;
  String get activeIp => _activeIp;
  bool get isServerRunning => _isServerRunning;
  String? get lastServerError => _lastServerError;

  /// Returns the current device operating system platform name
  String get currentPlatformName {
    if (kIsWeb) return 'Web';
    if (Platform.isWindows) return 'Windows';
    if (Platform.isAndroid) return 'Android';
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isIOS) return 'iOS';
    if (Platform.isLinux) return 'Linux';
    return 'Universal';
  }

  /// Initialize local network IP and start the HTTP receiving server
  Future<void> initialize({int preferredPort = AppConstants.defaultHttpPort}) async {
    if (kIsWeb) {
      _activeIp = '127.0.0.1';
      _activePort = preferredPort;
      notifyListeners();
      return;
    }

    _activeIp = await detectLocalIpAddress();
    await startReceiverServer(preferredPort: preferredPort);

    // Sync IP and port with TransferEngine
    final engine = TransferEngine();
    engine.localIp = _activeIp;
    engine.localPort = _activePort;
    notifyListeners();
  }

  /// Detects the active non-loopback local IPv4 address
  Future<String> detectLocalIpAddress() async {
    if (kIsWeb) return '127.0.0.1';

    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );

      // Prioritize Wi-Fi, Ethernet, and local subnet addresses
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final ip = addr.address;
          if (ip.startsWith('192.168.') || ip.startsWith('10.') || ip.startsWith('172.')) {
            return ip;
          }
        }
      }

      // Fallback to first available IPv4
      if (interfaces.isNotEmpty && interfaces.first.addresses.isNotEmpty) {
        return interfaces.first.addresses.first.address;
      }
    } catch (e) {
      debugPrint('Error detecting local IP address: $e');
    }

    return '127.0.0.1';
  }

  /// Starts the HTTP server that receives cross-device transfers
  Future<bool> startReceiverServer({int preferredPort = AppConstants.defaultHttpPort}) async {
    if (kIsWeb) return false;
    if (_isServerRunning && _server != null) return true;

    int port = preferredPort;
    const maxAttempts = 10;

    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        _server = await HttpServer.bind(
          InternetAddress.anyIPv4,
          port,
          shared: true,
        );

        _activePort = port;
        _isServerRunning = true;
        _lastServerError = null;
        debugPrint('QuickShare receiver listening on http://${_server!.address.address}:$_activePort');

        _listenToRequests(_server!);
        notifyListeners();
        return true;
      } catch (e) {
        debugPrint('Port $port busy or unavailable, trying ${port + 1}...');
        port++;
      }
    }

    _lastServerError = 'Failed to bind receiver server after $maxAttempts attempts.';
    _isServerRunning = false;
    notifyListeners();
    return false;
  }

  /// Closes the HTTP receiver server
  Future<void> stopReceiverServer() async {
    if (_server != null) {
      await _server!.close(force: true);
      _server = null;
      _isServerRunning = false;
      notifyListeners();
    }
  }

  /// Request listener for receiver HTTP server
  void _listenToRequests(HttpServer server) {
    server.listen(
      (HttpRequest request) async {
        final path = request.uri.path;
        final engine = TransferEngine();

        // Enable CORS for cross-device requests
        request.response.headers.add('Access-Control-Allow-Origin', '*');
        request.response.headers.add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
        request.response.headers.add('Access-Control-Allow-Headers', '*');

        if (request.method == 'OPTIONS') {
          request.response.statusCode = HttpStatus.ok;
          await request.response.close();
          return;
        }

        try {
          if (path == '/api/device-info' && request.method == 'GET') {
            // Return device identity & platform
            final json = jsonEncode({
              'id': engine.localDeviceId,
              'name': engine.localDeviceName,
              'platform': currentPlatformName,
              'ip': _activeIp,
              'port': _activePort,
              'readyToReceive': !engine.isReceivingPaused,
            });
            request.response
              ..statusCode = HttpStatus.ok
              ..headers.contentType = ContentType.json
              ..write(json);
            await request.response.close();
          } else if (path == '/api/pair' && request.method == 'POST') {
            // Handshake pairing
            final content = await utf8.decodeStream(request);
            final data = jsonDecode(content) as Map<String, dynamic>;

            final remoteDevice = DeviceModel(
              id: data['id'] as String?,
              name: data['name'] as String? ?? 'Remote Device',
              ip: data['ip'] as String? ?? request.connectionInfo?.remoteAddress.address ?? _activeIp,
              port: (data['port'] as num?)?.toInt() ?? AppConstants.defaultHttpPort,
              deviceType: _parseDeviceType(data['platform'] as String?),
              platform: data['platform'] as String?,
              isTrusted: true,
              isOnline: true,
            );

            engine.addPairedDevice(remoteDevice);

            request.response
              ..statusCode = HttpStatus.ok
              ..headers.contentType = ContentType.json
              ..write(jsonEncode({'status': 'paired', 'localDeviceName': engine.localDeviceName}));
            await request.response.close();
          } else if (path == '/api/transfer' && request.method == 'POST') {
            // Inbound cross-device file transfer
            await _handleInboundTransfer(request, engine);
          } else if (path == '/api/ping' && request.method == 'GET') {
            request.response
              ..statusCode = HttpStatus.ok
              ..headers.contentType = ContentType.json
              ..write(jsonEncode({'status': 'ok'}));
            await request.response.close();
          } else {
            request.response.statusCode = HttpStatus.notFound;
            await request.response.close();
          }
        } catch (e) {
          debugPrint('Error handling request $path: $e');
          request.response.statusCode = HttpStatus.internalServerError;
          try {
            await request.response.close();
          } catch (_) {}
        }
      },
      onError: (err) {
        debugPrint('Receiver server error: $err');
      },
    );
  }

  /// Inbound file reception handler
  Future<void> _handleInboundTransfer(HttpRequest request, TransferEngine engine) async {
    final rawFileName = request.headers.value('x-file-name') ?? 'Received_File';
    final fileName = Uri.decodeComponent(rawFileName);
    final rawSender = request.headers.value('x-sender-name') ?? 'Remote Device';
    final senderName = Uri.decodeComponent(rawSender);
    final senderPlatform = request.headers.value('x-sender-platform') ?? 'Universal';
    final expectedSha256 = request.headers.value('x-sha256');

    // Read bytes from the request stream
    final builder = BytesBuilder(copy: false);
    await for (final chunk in request) {
      builder.add(chunk);
    }
    final fileBytes = builder.takeBytes();

    // Verify SHA-256 integrity
    final calculatedSha256 = HashUtils.computeSha256(fileBytes);
    if (expectedSha256 != null && expectedSha256.isNotEmpty && calculatedSha256 != expectedSha256) {
      request.response
        ..statusCode = HttpStatus.badRequest
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({
          'status': 'error',
          'message': 'Checksum mismatch: expected $expectedSha256, got $calculatedSha256',
        }));
      await request.response.close();
      return;
    }

    // Pass received bytes to TransferEngine
    engine.receiveIncomingTransfer(
      senderDeviceName: '$senderName ($senderPlatform)',
      fileName: fileName,
      bytes: fileBytes,
      fileType: FileUtils.isPdfFilename(fileName)
          ? ReceivedFileType.pdf
          : FileUtils.isImageFilename(fileName)
              ? ReceivedFileType.image
              : ReceivedFileType.other,
      isFromTrustedDevice: true,
      recordInHistory: true,
    );

    // Ensure sender is in pairedDevices with its platform
    final remoteIp = request.connectionInfo?.remoteAddress.address ?? '127.0.0.1';
    engine.addPairedDevice(
      DeviceModel(
        name: senderName,
        ip: remoteIp,
        port: AppConstants.defaultHttpPort,
        platform: senderPlatform,
        deviceType: _parseDeviceType(senderPlatform),
        isTrusted: true,
        isOnline: true,
      ),
    );

    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.json
      ..write(jsonEncode({
        'status': 'success',
        'fileName': fileName,
        'bytesReceived': fileBytes.length,
        'sha256': calculatedSha256,
      }));
    await request.response.close();
  }

  DeviceType _parseDeviceType(String? platform) {
    if (platform == null) return DeviceType.desktop;
    final lower = platform.toLowerCase();
    if (lower.contains('android') || lower.contains('phone')) return DeviceType.mobile;
    if (lower.contains('ios') || lower.contains('iphone')) return DeviceType.mobile;
    if (lower.contains('ipad') || lower.contains('tablet')) return DeviceType.tablet;
    return DeviceType.desktop;
  }

  // -------------------------------------------------------------
  // Sender Client Implementation
  // -------------------------------------------------------------

  /// Quickly checks if a remote device is listening at [ip]:[port]
  Future<bool> isDeviceReachable(String ip, int port) async {
    try {
      final url = Uri.parse('http://$ip:$port/api/ping');
      final res = await http.get(url).timeout(const Duration(milliseconds: 600));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Tests connectivity with a remote device at [ip]:[port]
  Future<DeviceModel?> probeRemoteDevice(String ip, int port) async {
    try {
      final url = Uri.parse('http://$ip:$port/api/device-info');
      final response = await http.get(url).timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return DeviceModel(
          id: data['id'] as String?,
          name: data['name'] as String? ?? 'Remote Device',
          ip: ip,
          port: port,
          platform: data['platform'] as String? ?? 'Universal',
          deviceType: _parseDeviceType(data['platform'] as String?),
          isTrusted: true,
          isOnline: true,
        );
      }
    } catch (e) {
      debugPrint('Probe failed for $ip:$port: $e');
    }
    return null;
  }

  /// Sends a pairing handshake request to a remote device
  Future<bool> pairWithRemote(String ip, int port) async {
    final engine = TransferEngine();
    try {
      final url = Uri.parse('http://$ip:$port/api/pair');
      final body = jsonEncode({
        'id': engine.localDeviceId,
        'name': engine.localDeviceName,
        'platform': currentPlatformName,
        'ip': _activeIp,
        'port': _activePort,
      });

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: body,
      ).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        // Probe and add to local pairedDevices
        final remote = await probeRemoteDevice(ip, port);
        if (remote != null) {
          engine.addPairedDevice(remote);
          return true;
        }
      }
    } catch (e) {
      debugPrint('Pairing request failed to $ip:$port: $e');
    }
    return false;
  }

  /// Sends a file stream to a cross-platform target device with real-time progress callbacks
  Future<TransferItem> sendFileCrossPlatform({
    required DeviceModel recipient,
    required String fileName,
    required Uint8List bytes,
    String? sessionName,
  }) async {
    final engine = TransferEngine();
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
      sessionName: sessionName,
      connectionType: 'Cross-Platform (${recipient.platform ?? "Universal"})',
      rawBytes: bytes,
      status: TransferStatus.transferring,
    );

    engine.fileDataStore[sanitized] = bytes;
    engine.fileDataStore[sha256Hash] = bytes;
    engine.addActiveTransfer(transfer);

    final targetUrl = Uri.parse('http://${recipient.ip}:${recipient.port}/api/transfer');

    try {
      final request = http.StreamedRequest('POST', targetUrl);
      request.headers['x-file-name'] = Uri.encodeComponent(sanitized);
      request.headers['x-file-size'] = bytes.length.toString();
      request.headers['x-sender-name'] = Uri.encodeComponent(engine.localDeviceName);
      request.headers['x-sender-platform'] = currentPlatformName;
      request.headers['x-sha256'] = sha256Hash;
      request.headers['Content-Type'] = 'application/octet-stream';

      // Stream file bytes with chunked progress updates
      const chunkSize = 64 * 1024; // 64 KB streaming chunks
      int transferredBytes = 0;
      final startTime = DateTime.now();

      final controller = StreamController<List<int>>();
      request.contentLength = bytes.length;

      // Pipe controller into request
      request.sink.addStream(controller.stream).then((_) {
        request.sink.close();
      });

      // Feed chunks asynchronously
      Future<void> feedData() async {
        for (int offset = 0; offset < bytes.length; offset += chunkSize) {
          final end = (offset + chunkSize < bytes.length) ? offset + chunkSize : bytes.length;
          final chunk = bytes.sublist(offset, end);
          controller.add(chunk);

          transferredBytes += chunk.length;
          final double progress = (transferredBytes / bytes.length).clamp(0.0, 1.0);
          final elapsed = DateTime.now().difference(startTime).inMilliseconds;
          final speed = elapsed > 0 ? (transferredBytes / (elapsed / 1000.0)) : 0.0;
          final int chunkIndex = (transferredBytes / AppConstants.chunkSize).ceil().clamp(0, totalChunks);

          final idx = engine.activeTransfers.indexWhere((t) => t.transferId == transfer.transferId);
          if (idx != -1) {
            final updated = engine.activeTransfers[idx].copyWith(
              transferredChunks: chunkIndex,
              progress: progress,
              speedBytesPerSec: speed,
              status: TransferStatus.transferring,
            );
            engine.updateTransfer(updated);
          }

          // Small yield to let UI render progress updates
          await Future.delayed(const Duration(milliseconds: 15));
        }
        await controller.close();
      }

      feedData();

      // Send request and await receiver response
      final streamedResponse = await request.send().timeout(const Duration(seconds: 45));
      final responseBody = await streamedResponse.stream.bytesToString();

      if (streamedResponse.statusCode == 200) {
        // Successful transfer
        final idx = engine.activeTransfers.indexWhere((t) => t.transferId == transfer.transferId);
        if (idx != -1) {
          final completed = engine.activeTransfers[idx].copyWith(
            transferredChunks: totalChunks,
            progress: 1.0,
            status: TransferStatus.completed,
            completedTime: DateTime.now(),
          );
          engine.updateTransfer(completed);

          // Record in Transfer History
          final record = HistoryRecord(
            fileName: completed.fileName,
            fileSize: completed.fileSizeBytes,
            senderName: engine.localDeviceName,
            recipientName: '${recipient.name} (${recipient.platform ?? "Peer"})',
            isIncoming: false,
            status: 'completed',
            sha256: completed.sha256,
            sessionName: completed.sessionName,
            connectionType: completed.connectionType,
          );
          engine.addHistoryRecord(record);
        }
        return transfer;
      } else {
        throw HttpException('Receiver returned status code ${streamedResponse.statusCode}: $responseBody');
      }
    } catch (e) {
      debugPrint('Cross-device transfer failed: $e');
      final idx = engine.activeTransfers.indexWhere((t) => t.transferId == transfer.transferId);
      if (idx != -1) {
        String friendlyError = e.toString();
        if (e is SocketException) {
          friendlyError = 'Could not reach "${recipient.name}" at ${recipient.ip}:${recipient.port}. '
              'Ensure both devices are on the same Wi-Fi / hotspot network and QuickShare Studio is open.';
        } else if (e is TimeoutException) {
          friendlyError = 'Transfer timed out while connecting to ${recipient.ip}:${recipient.port}.';
        }

        final failed = engine.activeTransfers[idx].copyWith(
          status: TransferStatus.failed,
          errorMessage: friendlyError,
        );
        engine.updateTransfer(failed);
      }
      rethrow;
    }
  }
}
