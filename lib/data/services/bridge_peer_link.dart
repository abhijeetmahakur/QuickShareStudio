import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/device_model.dart';
import '../models/received_item_model.dart';
import '../../core/utils/file_utils.dart';
import 'peer_link.dart';
import 'transfer_engine.dart';

/// [PeerLink] for the browser-based desktop app: the page cannot open network sockets,
/// so pairing and transfers go through the local launcher server (`scripts/server.py`),
/// which speaks the LAN peer protocol on the app's behalf.
class BridgePeerLink implements PeerLink {
  BridgePeerLink._(this._ip, this._port, this._seq);

  final String _ip;
  final int _port;
  int _seq;
  Timer? _poller;
  bool _polling = false;

  static Uri _api(String path, [Map<String, String>? query]) =>
      Uri.base.resolve(path).replace(queryParameters: query);

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
      link._poller = Timer.periodic(const Duration(milliseconds: 1500), (_) => link._poll());
      return link;
    } catch (e) {
      debugPrint('LAN bridge unavailable: $e');
      return null;
    }
  }

  @override
  bool get isAvailable => true;
  @override
  String get localIp => _ip;
  @override
  int get localPort => _port;

  Future<void> _restorePeers() async {
    final data = jsonDecode((await http.get(_api('/api/lan/peers'))).body) as Map<String, dynamic>;
    for (final p in (data['peers'] as List).cast<Map<String, dynamic>>()) {
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
          engine.addPairedDevice(_device(e['device'] as Map<String, dynamic>));
        } else if (e['type'] == 'file_received') {
          final res = await http.get(_api('/api/lan/file', {'id': e['fileId'] as String}));
          if (res.statusCode != 200) continue;
          final sender = e['sender'] as Map<String, dynamic>;
          final name = e['fileName'] as String;
          engine.receiveIncomingTransfer(
            senderDeviceName: '${sender['name']} (${sender['platform']})',
            fileName: name,
            bytes: res.bodyBytes,
            fileType: FileUtils.isPdfFilename(name)
                ? ReceivedFileType.pdf
                : FileUtils.isImageFilename(name)
                    ? ReceivedFileType.image
                    : ReceivedFileType.other,
            savedPath: e['path'] as String?,
          );
        }
      }
    } catch (e) {
      debugPrint('LAN bridge poll failed: $e');
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
    return _device(data['device'] as Map<String, dynamic>);
  }

  @override
  Future<DeviceModel> pairWithCode(String code) => _pair('/api/lan/pair', {'code': code});

  @override
  Future<DeviceModel> pairDirect(String host, int port, String code) =>
      _pair('/api/lan/pair-direct', {'ip': host, 'port': port, 'code': code});

  @override
  Future<void> sendFile(
    DeviceModel peer,
    String fileName,
    Uint8List bytes, {
    void Function(double progress)? onProgress,
  }) async {
    final http.Response res;
    try {
      res = await http.post(
        _api('/api/lan/send', {'peer': peer.id, 'name': fileName}),
        headers: {'Content-Type': 'application/octet-stream'},
        body: bytes,
      );
    } catch (_) {
      throw PeerLinkException('The QuickShare background service is not responding. Restart the app.');
    }
    if (res.statusCode != 200) {
      final error = (jsonDecode(res.body) as Map<String, dynamic>)['error'] as String?;
      throw PeerLinkException(error ?? 'Sending failed (HTTP ${res.statusCode}).');
    }
    onProgress?.call(1.0);
  }

  @override
  Future<void> unpair(String peerId) async {
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
