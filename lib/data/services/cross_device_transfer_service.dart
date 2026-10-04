import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
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
import 'peer_link.dart';
import 'transfer_engine.dart';

/// Native implementation of the LAN peer protocol (v1), shared with the desktop app's
/// `scripts/server.py`:
///
///   UDP  [AppConstants.discoveryPort]  "QUICKSHARE_DISCOVER_V1" -> JSON device info
///   HTTP [AppConstants.defaultHttpPort] GET /api/ping, /api/device-info
///        POST /api/pair      {code,id,name,platform,port} -> {token,...} when the code matches
///        POST /api/transfer  file body; requires x-sender-id + x-pair-token from pairing
class CrossDeviceTransferService extends ChangeNotifier implements PeerLink {
  static final CrossDeviceTransferService _instance = CrossDeviceTransferService._internal();
  factory CrossDeviceTransferService() => _instance;

  CrossDeviceTransferService._internal();

  static const int protocolVersion = 1;
  static const String discoverMessage = 'QUICKSHARE_DISCOVER_V1';
  static const int _pairFailureLimit = 8;
  static const Duration _pairFailureWindow = Duration(minutes: 5);

  HttpServer? _server;
  RawDatagramSocket? _discoverySocket;
  int _activePort = AppConstants.defaultHttpPort;
  String _activeIp = '127.0.0.1';
  bool _isServerRunning = false;
  String? _lastServerError;

  /// Pairing tokens by peer device id (the same token is used in both directions).
  final Map<String, String> _peerTokens = {};
  final Map<String, List<DateTime>> _pairFailures = {};

  int get activePort => _activePort;
  String get activeIp => _activeIp;
  bool get isServerRunning => _isServerRunning;
  String? get lastServerError => _lastServerError;

  @override
  bool get isAvailable => _isServerRunning;
  @override
  String get localIp => _activeIp;
  @override
  int get localPort => _activePort;

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

  /// Initialize local network IP, start the receiver and discovery, and attach to the engine.
  Future<void> initialize({int preferredPort = AppConstants.defaultHttpPort}) async {
    if (kIsWeb) {
      _activeIp = '127.0.0.1';
      _activePort = preferredPort;
      notifyListeners();
      return;
    }

    _activeIp = await detectLocalIpAddress();
    final started = await startReceiverServer(preferredPort: preferredPort);
    if (started) {
      await _startDiscoveryResponder();
      TransferEngine().attachPeerLink(this);
    }
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
        _server = await HttpServer.bind(InternetAddress.anyIPv4, port);

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

  /// Closes the HTTP receiver server and discovery responder
  Future<void> stopReceiverServer() async {
    _discoverySocket?.close();
    _discoverySocket = null;
    if (_server != null) {
      await _server!.close(force: true);
      _server = null;
      _isServerRunning = false;
      notifyListeners();
    }
  }

  Map<String, Object?> _deviceInfo() {
    final engine = TransferEngine();
    return {
      'id': engine.localDeviceId,
      'name': engine.localDeviceName,
      'platform': currentPlatformName,
      'ip': _activeIp,
      'port': _activePort,
      'protocol': protocolVersion,
      'readyToReceive': !engine.isReceivingPaused,
    };
  }

  // The engine owns the pairing code; the native server reads it directly.
  @override
  void updateSession({required String? code, required String deviceId, required String deviceName}) {}

  Future<void> _startDiscoveryResponder() async {
    try {
      final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        AppConstants.discoveryPort,
        reuseAddress: true,
      );
      _discoverySocket = socket;
      socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = socket.receive();
        if (datagram == null) return;
        if (utf8.decode(datagram.data, allowMalformed: true).trim() == discoverMessage) {
          socket.send(utf8.encode(jsonEncode(_deviceInfo())), datagram.address, datagram.port);
        }
      });
    } catch (e) {
      // Without discovery, pairing still works through the QR code (direct IP + port).
      debugPrint('Discovery responder unavailable: $e');
    }
  }

  Future<void> _writeJson(HttpRequest request, int status, Object body) async {
    request.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body));
    await request.response.close();
  }

  /// Request listener for receiver HTTP server
  void _listenToRequests(HttpServer server) {
    server.listen(
      (HttpRequest request) async {
        final path = request.uri.path;
        final engine = TransferEngine();

        try {
          if (path == '/api/device-info' && request.method == 'GET') {
            await _writeJson(request, HttpStatus.ok, _deviceInfo());
          } else if (path == '/api/pair' && request.method == 'POST') {
            await _handlePairRequest(request, engine);
          } else if (path == '/api/transfer' && request.method == 'POST') {
            await _handleInboundTransfer(request, engine);
          } else if (path == '/api/ping' && request.method == 'GET') {
            await _writeJson(request, HttpStatus.ok, {'status': 'ok'});
          } else {
            await _writeJson(request, HttpStatus.notFound, {'error': 'not found'});
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

  /// Pairing: only a device that knows the code currently shown here gets a token.
  Future<void> _handlePairRequest(HttpRequest request, TransferEngine engine) async {
    final remoteIp = request.connectionInfo?.remoteAddress.address ?? '0.0.0.0';
    final now = DateTime.now();
    final failures = (_pairFailures[remoteIp] ?? [])
        .where((t) => now.difference(t) < _pairFailureWindow)
        .toList();
    _pairFailures[remoteIp] = failures;
    if (failures.length >= _pairFailureLimit) {
      await _writeJson(request, HttpStatus.tooManyRequests, {'error': 'too many wrong codes, try again later'});
      return;
    }

    final Map<String, dynamic> data;
    try {
      data = jsonDecode(await utf8.decodeStream(request)) as Map<String, dynamic>;
    } catch (_) {
      await _writeJson(request, HttpStatus.badRequest, {'error': 'bad request'});
      return;
    }

    final code = (data['code']?.toString() ?? '').replaceAll(RegExp(r'\D'), '');
    final session = engine.currentPairingSession;
    if (session == null || !session.isActive || code.isEmpty || code != session.numericCode) {
      failures.add(now);
      await _writeJson(request, HttpStatus.forbidden, {'error': 'wrong or expired code'});
      return;
    }

    final token = _newToken();
    final platform = data['platform'] as String?;
    final remoteDevice = DeviceModel(
      id: data['id'] as String?,
      name: data['name'] as String? ?? 'Remote Device',
      ip: remoteIp, // the address the request actually came from
      port: (data['port'] as num?)?.toInt() ?? AppConstants.defaultHttpPort,
      deviceType: _parseDeviceType(platform),
      platform: platform,
      isTrusted: true,
      isOnline: true,
    );
    _peerTokens[remoteDevice.id] = token;
    engine.addPairedDevice(remoteDevice);

    await _writeJson(request, HttpStatus.ok, {..._deviceInfo(), 'status': 'paired', 'token': token});
  }

  /// Inbound file reception handler: only paired devices may send.
  Future<void> _handleInboundTransfer(HttpRequest request, TransferEngine engine) async {
    final senderId = request.headers.value('x-sender-id') ?? '';
    final token = request.headers.value('x-pair-token') ?? '';
    final expectedToken = _peerTokens[senderId];
    if (expectedToken == null || token.isEmpty || token != expectedToken) {
      await request.drain<void>();
      await _writeJson(request, HttpStatus.unauthorized, {'error': 'not paired with this device'});
      return;
    }

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
      await _writeJson(request, HttpStatus.badRequest, {
        'status': 'error',
        'message': 'Checksum mismatch: expected $expectedSha256, got $calculatedSha256',
      });
      return;
    }

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

    await _writeJson(request, HttpStatus.ok, {
      'status': 'success',
      'fileName': fileName,
      'bytesReceived': fileBytes.length,
      'sha256': calculatedSha256,
    });
  }

  String _newToken() {
    final random = Random.secure();
    return List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
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
  // Client side
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

  /// Tests connectivity with a remote device at [ip]:[port] (does not pair).
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

  /// Broadcasts a discovery request and returns the devices that answered.
  Future<List<Map<String, dynamic>>> discoverDevices({
    Duration timeout = const Duration(milliseconds: 1500),
    int? discoveryPort,
  }) async {
    final port = discoveryPort ?? AppConstants.discoveryPort;
    final found = <String, Map<String, dynamic>>{};
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    socket.broadcastEnabled = true;
    final ownId = TransferEngine().localDeviceId;
    final sub = socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final datagram = socket.receive();
      if (datagram == null) return;
      try {
        final info = jsonDecode(utf8.decode(datagram.data)) as Map<String, dynamic>;
        if (info['id'] == ownId) return;
        if (!datagram.address.isLoopback) info['ip'] = datagram.address.address;
        found[info['id'].toString()] = info;
      } catch (_) {}
    });

    final targets = <String>{'255.255.255.255', '127.0.0.1'};
    final parts = _activeIp.split('.');
    if (parts.length == 4) targets.add('${parts[0]}.${parts[1]}.${parts[2]}.255');
    for (final target in targets) {
      try {
        socket.send(utf8.encode(discoverMessage), InternetAddress(target), port);
      } catch (_) {}
    }
    await Future<void>.delayed(timeout);
    await sub.cancel();
    socket.close();
    return found.values.toList();
  }

  @override
  Future<DeviceModel> pairDirect(String host, int port, String code) async {
    final engine = TransferEngine();
    final http.Response response;
    try {
      response = await http
          .post(
            Uri.parse('http://$host:$port/api/pair'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'code': code,
              'id': engine.localDeviceId,
              'name': engine.localDeviceName,
              'platform': currentPlatformName,
              'port': _activePort,
            }),
          )
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      throw PeerLinkException('Could not reach $host:$port. Make sure both devices are on the same Wi-Fi.');
    }
    if (response.statusCode == HttpStatus.forbidden) {
      throw PeerLinkException('That code is wrong or has expired.');
    }
    if (response.statusCode == HttpStatus.tooManyRequests) {
      throw PeerLinkException('Too many wrong codes. Wait a few minutes and try again.');
    }
    if (response.statusCode != HttpStatus.ok) {
      throw PeerLinkException('The device refused pairing (HTTP ${response.statusCode}).');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final platform = data['platform'] as String?;
    final device = DeviceModel(
      id: data['id'] as String?,
      name: data['name'] as String? ?? 'Remote Device',
      ip: host,
      port: (data['port'] as num?)?.toInt() ?? port,
      platform: platform,
      deviceType: _parseDeviceType(platform),
      isTrusted: true,
      isOnline: true,
    );
    _peerTokens[device.id] = data['token'] as String;
    return device;
  }

  @override
  Future<DeviceModel> pairWithCode(String code) async {
    final devices = await discoverDevices();
    if (devices.isEmpty) {
      throw PeerLinkException(
        'No QuickShare devices answered on this network. Check that both devices are on the '
        'same Wi-Fi and the app is open, or pair with the QR code instead.',
      );
    }
    final attempts = devices.map((info) async {
      try {
        return await pairDirect(
          info['ip'].toString(),
          (info['port'] as num?)?.toInt() ?? AppConstants.defaultHttpPort,
          code,
        );
      } catch (_) {
        return null;
      }
    });
    final results = await Future.wait(attempts);
    final paired = results.whereType<DeviceModel>();
    if (paired.isEmpty) {
      throw PeerLinkException('No device on this network is showing that code. Check the code and try again.');
    }
    return paired.first;
  }

  @override
  Future<void> unpair(String peerId) async {
    _peerTokens.remove(peerId);
  }

  @override
  Future<void> sendFile(
    DeviceModel peer,
    String fileName,
    Uint8List bytes, {
    void Function(double progress)? onProgress,
  }) async {
    final token = _peerTokens[peer.id];
    if (token == null) {
      throw PeerLinkException('"${peer.name}" is not paired with this device. Pair again from Device Pairing.');
    }
    final engine = TransferEngine();
    final request = http.StreamedRequest('POST', Uri.parse('http://${peer.ip}:${peer.port}/api/transfer'))
      ..headers.addAll({
        'x-file-name': Uri.encodeComponent(fileName),
        'x-file-size': bytes.length.toString(),
        'x-sender-id': engine.localDeviceId,
        'x-sender-name': Uri.encodeComponent(engine.localDeviceName),
        'x-sender-platform': currentPlatformName,
        'x-pair-token': token,
        'x-sha256': HashUtils.computeSha256(bytes),
        'Content-Type': 'application/octet-stream',
      })
      ..contentLength = bytes.length;

    Future<void> feed() async {
      const chunkSize = 64 * 1024;
      for (var offset = 0; offset < bytes.length; offset += chunkSize) {
        final end = min(offset + chunkSize, bytes.length);
        request.sink.add(bytes.sublist(offset, end));
        onProgress?.call(end / bytes.length);
        await Future<void>.delayed(Duration.zero);
      }
      await request.sink.close();
    }

    try {
      unawaited(feed());
      final response = await request.send().timeout(Duration(seconds: 30 + bytes.length ~/ (256 * 1024)));
      final body = await response.stream.bytesToString();
      if (response.statusCode == HttpStatus.unauthorized) {
        throw PeerLinkException('"${peer.name}" no longer recognises this device. Pair again.');
      }
      if (response.statusCode != HttpStatus.ok) {
        throw PeerLinkException('"${peer.name}" rejected the file (HTTP ${response.statusCode}): $body');
      }
    } on PeerLinkException {
      rethrow;
    } catch (_) {
      throw PeerLinkException(
        'Could not reach "${peer.name}" at ${peer.ip}:${peer.port}. '
        'Ensure both devices are on the same Wi-Fi / hotspot network and QuickShare Studio is open.',
      );
    }
  }

  /// Sends a file and tracks it as a transfer in [TransferEngine] (progress + history).
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
      connectionType: 'Local Network (${recipient.platform ?? "Device"})',
      rawBytes: bytes,
      status: TransferStatus.transferring,
    );

    engine.fileDataStore[sanitized] = bytes;
    engine.fileDataStore[sha256Hash] = bytes;
    engine.addActiveTransfer(transfer);

    void update(TransferItem Function(TransferItem t) change) {
      final idx = engine.activeTransfers.indexWhere((t) => t.transferId == transfer.transferId);
      if (idx != -1) engine.updateTransfer(change(engine.activeTransfers[idx]));
    }

    final startTime = DateTime.now();
    try {
      await sendFile(recipient, sanitized, bytes, onProgress: (progress) {
        final elapsed = DateTime.now().difference(startTime).inMilliseconds;
        update((t) => t.copyWith(
              transferredChunks: (progress * totalChunks).floor(),
              progress: progress,
              speedBytesPerSec: elapsed > 0 ? bytes.length * progress / (elapsed / 1000) : 0,
            ));
      });
      update((t) => t.copyWith(
            transferredChunks: totalChunks,
            progress: 1.0,
            status: TransferStatus.completed,
            completedTime: DateTime.now(),
          ));
      engine.addHistoryRecord(HistoryRecord(
        fileName: sanitized,
        fileSize: bytes.length,
        senderName: engine.localDeviceName,
        recipientName: '${recipient.name} (${recipient.platform ?? "Peer"})',
        isIncoming: false,
        status: 'completed',
        sha256: sha256Hash,
        sessionName: sessionName,
        connectionType: transfer.connectionType,
      ));
      return transfer;
    } on PeerLinkException catch (e) {
      update((t) => t.copyWith(status: TransferStatus.failed, errorMessage: e.message));
      rethrow;
    }
  }
}
