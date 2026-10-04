import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/io.dart';
import '../models/device_model.dart';
import '../../core/constants.dart';
import '../../transfer/channel.dart';
import '../../transfer/lan/ws_frame_channel.dart';
import 'peer_link.dart';
import 'transfer_engine.dart';

/// Native implementation of the LAN peer protocol (v2), shared with the desktop app's
/// `scripts/server.py`:
///
///   UDP  [AppConstants.discoveryPort]  "QUICKSHARE_DISCOVER_V1" -> JSON device info
///   HTTP [AppConstants.defaultHttpPort] GET /api/ping, /api/device-info
///        POST /api/pair      {code,id,name,platform,port} -> {token,...} when the code matches
///        GET  /api/v2/session?from=ID   WebSocket for paired devices; carries the
///             end-to-end encrypted transfer protocol (see lib/transfer/)
class CrossDeviceTransferService extends ChangeNotifier implements PeerLink {
  static final CrossDeviceTransferService _instance = CrossDeviceTransferService._internal();
  factory CrossDeviceTransferService() => _instance;

  CrossDeviceTransferService._internal();

  static const int protocolVersion = 2;
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
  final _incomingSessions = StreamController<IncomingLanSession>.broadcast();

  @override
  Stream<IncomingLanSession> get incomingSessions => _incomingSessions.stream;

  @override
  String? pairingToken(String peerId) => _peerTokens[peerId];
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

  /// Forgets pairing tokens and wrong-code history (tests start from a clean state).
  @visibleForTesting
  void resetPairingState() {
    _peerTokens.clear();
    _pairFailures.clear();
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
          } else if (path == '/api/v2/session' && request.method == 'GET') {
            await _handleSession(request);
          } else if (path == '/api/transfer' && request.method == 'POST') {
            // Protocol v1 sent files without asking and without encryption.
            await request.drain<void>();
            await _writeJson(request, 426, {'error': 'This device runs QuickShare 2. Update QuickShare on the sending device.'});
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

  /// A paired device opens an encrypted transfer session (WebSocket).
  Future<void> _handleSession(HttpRequest request) async {
    final peerId = request.uri.queryParameters['from'] ?? '';
    if (!_peerTokens.containsKey(peerId) || !WebSocketTransformer.isUpgradeRequest(request)) {
      await _writeJson(request, HttpStatus.unauthorized, {'error': 'not paired with this device'});
      return;
    }
    final socket = await WebSocketTransformer.upgrade(request);
    final channel = WebSocketFrameChannel(IOWebSocketChannel(socket));
    if (!_incomingSessions.hasListener) {
      await channel.close();
      return;
    }
    _incomingSessions.add(IncomingLanSession(channel, peerId));
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
  Future<FrameChannel> openSession(DeviceModel peer) async {
    if (!_peerTokens.containsKey(peer.id)) {
      throw PeerLinkException('"${peer.name}" is not paired with this device. Pair again from Device Pairing.');
    }
    final uri = Uri(
      scheme: 'ws',
      host: peer.ip,
      port: peer.port,
      path: '/api/v2/session',
      queryParameters: {'from': TransferEngine().localDeviceId},
    );
    try {
      final socket = await WebSocket.connect(uri.toString()).timeout(const Duration(seconds: 5));
      return WebSocketFrameChannel(IOWebSocketChannel(socket));
    } on WebSocketException catch (e) {
      if (e.message.contains('401')) {
        throw PeerLinkException('"${peer.name}" no longer recognises this device. Pair again.');
      }
      if (e.message.contains('426') || e.message.contains('404')) {
        throw PeerLinkException('"${peer.name}" runs an older QuickShare. Update it to send files.');
      }
      throw PeerLinkException(_unreachable(peer));
    } catch (_) {
      throw PeerLinkException(_unreachable(peer));
    }
  }

  String _unreachable(DeviceModel peer) => 'Could not reach "${peer.name}" on this network. '
      'Make sure both devices are on the same Wi-Fi and QuickShare is open.';
}
