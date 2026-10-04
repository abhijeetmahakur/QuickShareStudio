import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:async/async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../data/services/transfer_engine.dart';
import '../connection_manager.dart';
import '../protocol/handshake.dart';
import '../secure_channel.dart';
import 'ble_handshake.dart';
import 'bluetooth_support.dart';
import 'socket_frame_channel.dart';

/// A QuickShare device found over Bluetooth.
class NearbyDevice {
  NearbyDevice({required this.address, required this.name, required this.rssi, required this.sessionId, required this.lastSeen});
  final String address;
  final String name;
  final int rssi;
  final String sessionId;
  final DateTime lastSeen;

  /// 0-4 bars from the signal strength.
  int get bars => rssi >= -55 ? 4 : rssi >= -67 ? 3 : rssi >= -78 ? 2 : rssi >= -90 ? 1 : 0;
}

class BluetoothException implements Exception {
  BluetoothException(this.message);
  final String message;
  @override
  String toString() => message;
}

enum BluetoothStage { idle, connecting, exchangingKeys, startingWifi, joiningWifi, securing, connected, failed }

/// Bluetooth discovery + handshake, Wi-Fi Direct for the data (Android only).
class BluetoothTransport extends ChangeNotifier {
  BluetoothTransport._();
  static final BluetoothTransport instance = BluetoothTransport._();

  static const _events = EventChannel('quickshare/bluetooth/events');
  MethodChannel get _methods => BluetoothSupport.channel;

  Stream<Map<Object?, Object?>>? _eventStream;
  Stream<Map<Object?, Object?>> get _stream =>
      _eventStream ??= _events.receiveBroadcastStream().map((e) => (e as Map).cast<Object?, Object?>()).asBroadcastStream();

  final Map<String, NearbyDevice> _devices = {};
  StreamSubscription<Map<Object?, Object?>>? _scanSub;
  Timer? _pruneTimer;
  bool scanning = false;

  bool visible = false;
  StreamSubscription<Map<Object?, Object?>>? _serverSub;
  final Map<String, MessageAssembler> _assemblers = {};
  final Map<String, int> _centralMtu = {};
  ServerSocket? _serverSocket;
  bool _receiving = false;

  BluetoothStage stage = BluetoothStage.idle;
  String? stageError;

  final Uint8List _sessionId = Uint8List.fromList(List.generate(4, (_) => Random.secure().nextInt(256)));

  List<NearbyDevice> get devices => _devices.values.toList()..sort((a, b) => b.rssi.compareTo(a.rssi));

  void _setStage(BluetoothStage s, [String? error]) {
    stage = s;
    stageError = error;
    notifyListeners();
  }

  // -------------------------------------------------------------------------------------
  // Scanning (sender)
  // -------------------------------------------------------------------------------------

  Future<void> startScan() async {
    if (scanning) return;
    _scanSub = _stream.listen((e) {
      if (e['type'] == 'scan') {
        final session = (e['session'] as Uint8List?) ?? Uint8List(0);
        final hex = session.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
        if (hex == _sessionId.map((b) => b.toRadixString(16).padLeft(2, '0')).join()) return; // ourselves
        _devices[e['address'] as String] = NearbyDevice(
          address: e['address'] as String,
          name: (e['name'] as String?)?.trim().isNotEmpty == true ? e['name'] as String : 'QuickShare device',
          rssi: (e['rssi'] as int?) ?? -100,
          sessionId: hex,
          lastSeen: DateTime.now(),
        );
        notifyListeners();
      } else if (e['type'] == 'scanFailed') {
        scanning = false;
        _setStage(BluetoothStage.failed, 'Bluetooth scanning failed (code ${e['code']}). Turn Bluetooth off and on, then retry.');
      }
    });
    try {
      await _methods.invokeMethod('startScan');
      scanning = true;
      // Devices that stop advertising drop off the list.
      _pruneTimer = Timer.periodic(const Duration(seconds: 3), (_) {
        final cutoff = DateTime.now().subtract(const Duration(seconds: 12));
        final before = _devices.length;
        _devices.removeWhere((_, d) => d.lastSeen.isBefore(cutoff));
        if (_devices.length != before) notifyListeners();
      });
    } on PlatformException catch (e) {
      await _scanSub?.cancel();
      throw BluetoothException(_friendly(e));
    }
    notifyListeners();
  }

  Future<void> stopScan() async {
    _pruneTimer?.cancel();
    await _scanSub?.cancel();
    _scanSub = null;
    if (scanning) {
      try {
        await _methods.invokeMethod('stopScan');
      } catch (_) {}
    }
    scanning = false;
    _devices.clear();
    notifyListeners();
  }

  // -------------------------------------------------------------------------------------
  // Being visible (receiver)
  // -------------------------------------------------------------------------------------

  Future<void> becomeVisible() async {
    if (visible) return;
    final engine = TransferEngine();
    _serverSub = _stream.listen(_onServerEvent);
    try {
      await _methods.invokeMethod('startAdvertising', {'name': engine.localDeviceName, 'session': _sessionId});
      visible = true;
    } on PlatformException catch (e) {
      await _serverSub?.cancel();
      throw BluetoothException(_friendly(e));
    }
    notifyListeners();
  }

  Future<void> stopVisible() async {
    await _serverSub?.cancel();
    _serverSub = null;
    if (visible) {
      try {
        await _methods.invokeMethod('stopAdvertising');
      } catch (_) {}
    }
    visible = false;
    _assemblers.clear();
    notifyListeners();
  }

  void _onServerEvent(Map<Object?, Object?> e) {
    final address = e['address'] as String?;
    if (address == null) return;
    switch (e['type']) {
      case 'centralMtu':
        _centralMtu[address] = (e['mtu'] as int?) ?? 23;
      case 'centralWrite':
        final value = e['value'] as Uint8List;
        try {
          final message = (_assemblers[address] ??= MessageAssembler()).add(value);
          if (message != null) unawaited(_onSenderHello(address, message));
        } on FormatException {
          _assemblers.remove(address);
        }
      case 'centralDisconnected':
        _assemblers.remove(address);
    }
  }

  Future<void> _notify(String address, Map<String, dynamic> message) async {
    for (final piece in chunkMessage(utf8.encode(jsonEncode(message)), _centralMtu[address] ?? 23)) {
      final ok = await _methods.invokeMethod<bool>('notify', {'address': address, 'value': piece}) ?? false;
      if (!ok) throw BluetoothException('The other phone stopped listening over Bluetooth.');
    }
  }

  Future<void> _onSenderHello(String address, Uint8List helloBytes) async {
    if (_receiving) return; // one Bluetooth connection at a time
    _receiving = true;
    ServerSocket? server;
    try {
      final hello = jsonDecode(utf8.decode(helloBytes)) as Map<String, dynamic>;
      if (hello['t'] != 'hello') return;
      final senderPub = base64.decode(hello['pub'] as String);
      if (senderPub.length != 32) return;
      final engine = TransferEngine();
      final keys = await BleKeyAgreement.create();
      final key = await keys.derive(peerPublicKey: senderPub, senderPub: senderPub, receiverPub: keys.publicKey);
      await _notify(address, helloMessage(publicKey: keys.publicKey, name: engine.localDeviceName, id: engine.localDeviceId, platform: 'Android'));
      _setStage(BluetoothStage.startingWifi);

      final group = await _methods.invokeMapMethod<String, Object?>('createGroup');
      server = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
      _serverSocket = server;
      final creds = WifiCredentials(
        ssid: group!['ssid'] as String,
        passphrase: group['passphrase'] as String,
        ip: group['ip'] as String,
        port: server.port,
      );
      await _notify(address, {'t': 'wifi', 'box': await creds.seal(key)});
      _setStage(BluetoothStage.joiningWifi);

      final socket = await server.first.timeout(const Duration(seconds: 60));
      _setStage(BluetoothStage.securing);
      final raw = SocketFrameChannel(socket);
      final secure = await SecureFrameChannel.establish(raw, StreamQueue(raw.frames), initiator: false, psk: key);
      final link = ConnectionManager.instance.adoptBluetooth(
        channel: secure,
        frames: StreamQueue(secure.frames),
        remote: RemoteIdentity.fromJson({'id': hello['id'], 'name': hello['name'], 'platform': hello['p'] ?? 'Android'}),
        verificationCode: secure.verificationCode,
      );
      unawaited(link.session.closed.then((_) => _methods.invokeMethod('removeGroup').catchError((_) {})));
      _setStage(BluetoothStage.connected);
      HapticFeedback.mediumImpact();
    } catch (e) {
      _setStage(BluetoothStage.failed, e is BluetoothException ? e.message : 'The Bluetooth connection failed. Try again.');
      try {
        await _methods.invokeMethod('removeGroup');
      } catch (_) {}
    } finally {
      await server?.close();
      _serverSocket = null;
      _receiving = false;
    }
  }

  // -------------------------------------------------------------------------------------
  // Connecting (sender)
  // -------------------------------------------------------------------------------------

  /// Connects to [device]: BLE handshake, then Wi-Fi Direct and an encrypted socket.
  Future<ActiveLink> connect(NearbyDevice device) async {
    await stopScan();
    final engine = TransferEngine();
    final queue = StreamQueue(_stream);
    try {
      _setStage(BluetoothStage.connecting);
      await _methods.invokeMethod('connectGatt', {'address': device.address});
      final ready = await _next(queue, {'peripheralReady'}, const Duration(seconds: 20),
          'Could not connect to ${device.name} over Bluetooth. Move closer and retry.');
      final mtu = (ready['mtu'] as int?) ?? 23;

      _setStage(BluetoothStage.exchangingKeys);
      final keys = await BleKeyAgreement.create();
      final hello = helloMessage(publicKey: keys.publicKey, name: engine.localDeviceName, id: engine.localDeviceId, platform: 'Android');
      for (final piece in chunkMessage(utf8.encode(jsonEncode(hello)), mtu)) {
        final ok = await _methods.invokeMethod<bool>('write', {'value': piece}) ?? false;
        if (!ok) throw BluetoothException('Bluetooth write failed. Retry.');
      }
      final assembler = MessageAssembler();
      Future<Map<String, dynamic>> nextMessage(Duration timeout, String timeoutMessage) async {
        while (true) {
          final e = await _next(queue, {'peripheralNotify'}, timeout, timeoutMessage);
          final message = assembler.add(e['value'] as Uint8List);
          if (message != null) return jsonDecode(utf8.decode(message)) as Map<String, dynamic>;
        }
      }

      final reply = await nextMessage(const Duration(seconds: 15), '${device.name} did not answer over Bluetooth.');
      final receiverPub = base64.decode(reply['pub'] as String);
      final key = await keys.derive(peerPublicKey: receiverPub, senderPub: keys.publicKey, receiverPub: receiverPub);

      _setStage(BluetoothStage.startingWifi);
      final wifi = await nextMessage(const Duration(seconds: 40), '${device.name} could not start Wi-Fi Direct.');
      final creds = await WifiCredentials.open(wifi['box'] as String, key);

      _setStage(BluetoothStage.joiningWifi);
      final joined = await _methods.invokeMapMethod<String, Object?>('connectGroup', {'ssid': creds.ssid, 'passphrase': creds.passphrase});
      final ip = (joined?['ip'] as String?) ?? creds.ip;
      await _methods.invokeMethod('disconnectGatt');

      _setStage(BluetoothStage.securing);
      Socket? socket;
      for (var attempt = 0; attempt < 10 && socket == null; attempt++) {
        try {
          socket = await Socket.connect(ip, creds.port, timeout: const Duration(seconds: 3));
        } on SocketException {
          await Future<void>.delayed(const Duration(milliseconds: 700)); // DHCP may still be settling
        }
      }
      if (socket == null) throw BluetoothException('Joined Wi-Fi Direct but could not reach ${device.name}. Retry.');
      final raw = SocketFrameChannel(socket);
      final secure = await SecureFrameChannel.establish(raw, StreamQueue(raw.frames), initiator: true, psk: key);
      final link = ConnectionManager.instance.adoptBluetooth(
        channel: secure,
        frames: StreamQueue(secure.frames),
        remote: RemoteIdentity.fromJson({'id': reply['id'], 'name': reply['name'], 'platform': reply['p'] ?? 'Android'}),
        verificationCode: secure.verificationCode,
      );
      unawaited(link.session.closed.then((_) => _methods.invokeMethod('removeGroup').catchError((_) {})));
      _setStage(BluetoothStage.connected);
      HapticFeedback.mediumImpact();
      return link;
    } on PlatformException catch (e) {
      final message = _friendly(e);
      _setStage(BluetoothStage.failed, message);
      await _cleanupSender();
      throw BluetoothException(message);
    } on BluetoothException catch (e) {
      _setStage(BluetoothStage.failed, e.message);
      await _cleanupSender();
      rethrow;
    } catch (_) {
      const message = 'The Bluetooth connection failed. Try again.';
      _setStage(BluetoothStage.failed, message);
      await _cleanupSender();
      throw BluetoothException(message);
    } finally {
      await queue.cancel();
    }
  }

  Future<void> _cleanupSender() async {
    try {
      await _methods.invokeMethod('disconnectGatt');
      await _methods.invokeMethod('removeGroup');
    } catch (_) {}
  }

  Future<Map<Object?, Object?>> _next(StreamQueue<Map<Object?, Object?>> queue, Set<String> types, Duration timeout, String timeoutMessage) async {
    final deadline = DateTime.now().add(timeout);
    while (true) {
      final left = deadline.difference(DateTime.now());
      if (left <= Duration.zero) throw BluetoothException(timeoutMessage);
      final Map<Object?, Object?> e;
      try {
        e = await queue.next.timeout(left);
      } on TimeoutException {
        throw BluetoothException(timeoutMessage);
      }
      if (types.contains(e['type'])) return e;
      if (e['type'] == 'peripheralDisconnected') throw BluetoothException('The Bluetooth connection dropped. Move closer and retry.');
      if (e['type'] == 'peripheralError') throw BluetoothException(e['message'] as String? ?? 'Not a QuickShare device.');
    }
  }

  static String _friendly(PlatformException e) => switch (e.code) {
        'permission' => 'QuickShare is missing a Bluetooth or nearby-devices permission.',
        'off' => 'Bluetooth is off. Turn it on and retry.',
        'unsupported' => e.message ?? "This device can't do that over Bluetooth.",
        'group' || 'connect' || 'timeout' => e.message ?? 'Wi-Fi Direct failed. Make sure Wi-Fi is on, then retry.',
        _ => e.message ?? 'Bluetooth error. Retry.',
      };

  /// Releases everything (leaving the Nearby screen).
  Future<void> shutdown() async {
    await stopScan();
    await stopVisible();
    await _serverSocket?.close();
    _serverSocket = null;
    if (stage != BluetoothStage.connected) _setStage(BluetoothStage.idle);
  }
}
