import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/device_model.dart';
import '../../transfer/channel.dart';
import '../../transfer/lan/ws_frame_channel.dart';
import 'peer_link.dart';
import 'transfer_engine.dart';

/// [PeerLink] for the browser-based desktop app: the page cannot open network sockets,
/// so pairing goes through the local launcher server (`scripts/server.py`), and transfer
/// sessions are relayed by it (WebSocket tunnel). Encryption happens here in the app, so the
/// server only ever relays ciphertext.
class BridgePeerLink implements PeerLink {
  BridgePeerLink._(this._ip, this._port, this._seq);

  final String _ip;
  final int _port;
  int _seq;
  Timer? _poller;
  bool _polling = false;
  final Map<String, String> _tokens = {};
  final _incoming = StreamController<IncomingLanSession>.broadcast();

  static Uri _api(String path, [Map<String, String>? query]) =>
      Uri.base.resolve(path).replace(queryParameters: query);

  static Uri _socket(String path, Map<String, String> query) {
    final http = _api(path, query);
    return http.replace(scheme: http.scheme == 'https' ? 'wss' : 'ws');
  }

  /// Connects to the local server; returns null when it has no LAN support
  /// (e.g. the app was opened from a plain static file server).
  static Future<BridgePeerLink?> connect() async {
    try {
      final status = jsonDecode((await http.get(_api('/api/lan/status')).timeout(const Duration(seconds: 3))).body)
          as Map<String, dynamic>;
      if (status['available'] != true) return null;
      final events = jsonDecode((await http.get(_api('/api/lan/events', {'since': '0'}))).body) as Map<String, dynamic>;
      final link = BridgePeerLink._(
        status['ip'] as String? ?? '127.0.0.1',
        (status['port'] as num?)?.toInt() ?? 8088,
        // Older events were already handled before a page reload.
        (events['seq'] as num?)?.toInt() ?? 0,
      );
      await link._restorePeers();
      link._poller = Timer.periodic(const Duration(milliseconds: 800), (_) => link._poll());
      return link;
    } catch (e) {
      debugPrint('LAN bridge unavailable');
      return null;
    }
  }

  @override
  bool get isAvailable => true;
  @override
  String get localIp => _ip;
  @override
  int get localPort => _port;

  @override
  Stream<IncomingLanSession> get incomingSessions => _incoming.stream;

  @override
  String? pairingToken(String peerId) => _tokens[peerId];

  Future<void> _restorePeers() async {
    final data = jsonDecode((await http.get(_api('/api/lan/peers'))).body) as Map<String, dynamic>;
    for (final p in (data['peers'] as List).cast<Map<String, dynamic>>()) {
      final token = p['token'] as String?;
      if (token != null) _tokens[p['id'] as String] = token;
      TransferEngine().addPairedDevice(_device(p));
    }
  }

  static DeviceModel _device(Map<String, dynamic> p) {
    final platform = p['platform'] as String?;
    final lower = (platform ?? '').toLowerCase();
    return DeviceModel(
      id: p['id'] as String?,
      name: p['name'] as String? ?? 'Device',
      ip: p['ip'] as String? ?? '',
      port: (p['port'] as num?)?.toInt() ?? 8088,
      platform: platform,
      deviceType: lower.contains('android') || lower.contains('ios')
          ? DeviceType.mobile
          : DeviceType.desktop,
      isTrusted: true,
      isOnline: true,
    );
  }

  Future<void> _poll() async {
    if (_polling) return;
    _polling = true;
    try {
      final data = jsonDecode((await http.get(_api('/api/lan/events', {'since': '$_seq'}))).body)
          as Map<String, dynamic>;
      final engine = TransferEngine();
      for (final e in (data['events'] as List).cast<Map<String, dynamic>>()) {
        _seq = (e['seq'] as num).toInt();
        if (e['type'] == 'peer_paired') {
          await _restorePeers();
          engine.addPairedDevice(_device(e['device'] as Map<String, dynamic>));
        } else if (e['type'] == 'tunnel_incoming') {
          final peer = e['peer'] as Map<String, dynamic>;
          if (!_tokens.containsKey(peer['id'])) await _restorePeers();
          try {
            final socket = WebSocketChannel.connect(_socket('/api/lan/tunnel', {'accept': e['tunnelId'] as String}));
            await socket.ready;
            _incoming.add(IncomingLanSession(WebSocketFrameChannel(socket), peer['id'] as String));
          } catch (_) {
            // The other device gave up waiting; nothing to clean up.
          }
        }
      }
    } catch (_) {
      // The local server restarted or is busy; the next poll retries.
    } finally {
      _polling = false;
    }
  }

  @override
  void updateSession({required String? code, required String deviceId, required String deviceName}) {
    http
        .post(
          _api('/api/lan/session'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'code': code, 'deviceId': deviceId, 'deviceName': deviceName}),
        )
        .catchError((Object e) => http.Response('', 0));
  }

  Future<DeviceModel> _pair(String path, Map<String, Object?> body) async {
    final http.Response res;
    try {
      res = await http
          .post(_api(path), headers: {'Content-Type': 'application/json'}, body: jsonEncode(body))
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      throw PeerLinkException('The QuickShare background service is not responding. Restart the app.');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200) throw PeerLinkException(data['error'] as String? ?? 'Pairing failed.');
    await _restorePeers();
    return _device(data['device'] as Map<String, dynamic>);
  }

  @override
  Future<DeviceModel> pairWithCode(String code) => _pair('/api/lan/pair', {'code': code});

  @override
  Future<DeviceModel> pairDirect(String host, int port, String code) =>
      _pair('/api/lan/pair-direct', {'ip': host, 'port': port, 'code': code});

  @override
  Future<FrameChannel> openSession(DeviceModel peer) async {
    if (!_tokens.containsKey(peer.id)) await _restorePeers();
    if (!_tokens.containsKey(peer.id)) {
      throw PeerLinkException('"${peer.name}" is not paired with this PC. Pair again from Device Pairing.');
    }
    try {
      final socket = WebSocketChannel.connect(_socket('/api/lan/tunnel', {'peer': peer.id}));
      await socket.ready.timeout(const Duration(seconds: 10));
      return WebSocketFrameChannel(socket);
    } catch (_) {
      // The server answers with an error instead of upgrading when the device is unreachable.
      throw PeerLinkException('Could not reach "${peer.name}". Make sure it is on the same Wi-Fi and QuickShare is open.');
    }
  }

  @override
  Future<void> unpair(String peerId) async {
    _tokens.remove(peerId);
    try {
      await http.post(
        _api('/api/lan/unpair'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'peer': peerId}),
      );
    } catch (_) {}
  }

  void dispose() => _poller?.cancel();
}
