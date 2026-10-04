// LAN regression against a real Android device (or emulator), through the real desktop
// launcher (scripts/server.py). Not part of `flutter test`; run explicitly:
//
//   adb forward tcp:18088 tcp:8088
//   flutter test tool/e2e/lan_phone_test.dart --dart-define=PHONE_CODE=123456 --dart-define=PHONE_PORT=18088
//
// The PC pairs with the phone's code over the LAN protocol, then plays the desktop app:
// it opens a tunnel through server.py, runs the encrypted session and sends a file. Accept it
// on the phone.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:async/async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:quickshare/transfer/app_config.dart';
import 'package:quickshare/transfer/file_source.dart';
import 'package:quickshare/transfer/lan/ws_frame_channel.dart';
import 'package:quickshare/transfer/protocol/handshake.dart';
import 'package:quickshare/transfer/protocol/transfer_protocol.dart';
import 'package:quickshare/transfer/secure_channel.dart';
import 'package:quickshare/transfer/sinks.dart';
import 'package:web_socket_channel/io.dart';

class _RealHttp extends HttpOverrides {}

const _phoneCode = String.fromEnvironment('PHONE_CODE');
const _phonePort = int.fromEnvironment('PHONE_PORT', defaultValue: 18088);
const _mb = int.fromEnvironment('MB', defaultValue: 20);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = _RealHttp();

  test('PC (desktop launcher) pairs with the phone and sends it an encrypted file over LAN', () async {
    final sandbox = await Directory.systemTemp.createTemp('qs_lan_phone_');
    final dir = Directory('${sandbox.path}${Platform.pathSeparator}app')..createSync();
    File('scripts/server.py').copySync('${dir.path}${Platform.pathSeparator}server.py');
    Directory('${dir.path}${Platform.pathSeparator}web').createSync();
    final python = await Process.start(Platform.isWindows ? 'python' : 'python3', ['${dir.path}${Platform.pathSeparator}server.py'],
        environment: {'QUICKSHARE_LAN_PORT': '18388', 'QUICKSHARE_DISCOVERY_PORT': '18389', 'HOME': sandbox.path, 'USERPROFILE': sandbox.path});
    addTearDown(() async {
      python.kill();
      await python.exitCode;
      try {
        sandbox.deleteSync(recursive: true);
      } catch (_) {}
    });
    final portFile = File('${dir.path}${Platform.pathSeparator}active_port.txt');
    for (var i = 0; i < 100 && !(portFile.existsSync() && portFile.readAsStringSync().trim().isNotEmpty); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    final appPort = int.parse(portFile.readAsStringSync().trim());
    Future<Map<String, dynamic>> api(String path, [Object? body]) async {
      final uri = Uri.parse('http://127.0.0.1:$appPort$path');
      final res = body == null ? await http.get(uri) : await http.post(uri, body: jsonEncode(body));
      return jsonDecode(res.body) as Map<String, dynamic>;
    }

    for (var i = 0; i < 50; i++) {
      try {
        if ((await api('/api/lan/status'))['available'] == true) break;
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    await api('/api/lan/session', {'code': '135790', 'deviceId': 'pc-e2e', 'deviceName': 'E2E Lab PC'});

    // 1. Pair with the phone's code (LAN protocol, unchanged from v1).
    final paired = await api('/api/lan/pair-direct', {'ip': '127.0.0.1', 'port': _phonePort, 'code': _phoneCode});
    expect(paired['device'], isNotNull, reason: '$paired');
    final phone = paired['device'] as Map<String, dynamic>;
    // ignore: avoid_print
    print('Paired with ${phone['name']} (${phone['platform']}), id ${phone['id']}');

    // 2. Desktop app role: tunnel through the launcher, encrypt with the pairing token.
    final peers = ((await api('/api/lan/peers'))['peers'] as List).cast<Map<String, dynamic>>();
    final token = peers.firstWhere((p) => p['id'] == phone['id'])['token'] as String;
    final socket = await WebSocket.connect('ws://127.0.0.1:$appPort/api/lan/tunnel?peer=${Uri.encodeComponent(phone['id'] as String)}');
    final raw = WebSocketFrameChannel(IOWebSocketChannel(socket));
    final secure = await SecureFrameChannel.establish(raw, StreamQueue(raw.frames), initiator: true, psk: utf8.encode(token));
    // ignore: avoid_print
    print('E2E VERIFY ${secure.verificationCode} (accept on the phone)');
    final session = PeerSession(
      channel: secure,
      frames: StreamQueue(secure.frames),
      remote: RemoteIdentity(id: phone['id'] as String, name: phone['name'] as String, platform: 'Android'),
      config: const AppConfig(),
      onOffer: (_) async => false,
      openSink: (o, i) async => MemoryFileSink('x'),
    )..start();
    final source = GeneratedFileSource('lan-from-pc.bin', _mb * 1024 * 1024, seed: 21);
    final sw = Stopwatch()..start();
    final result = await OutgoingTransfer(files: [source], config: const AppConfig(), peerName: phone['name'] as String).run(session);
    expect(result.phase, TransferPhase.completed, reason: result.error);
    // ignore: avoid_print
    print('E2E LAN PASS: $_mb MB in ${(sw.elapsedMilliseconds / 1000).toStringAsFixed(1)} s, '
        'encrypted frames ${secure.encryptedFrames}');
    expect(secure.encryptedFrames, greaterThan(source.size ~/ const AppConfig().chunkSize));
    await session.close();
    unawaited(Future<void>.value(Uint8List(0)));
  }, timeout: const Timeout(Duration(minutes: 10)), skip: _phoneCode.isEmpty ? 'set PHONE_CODE' : false);
}
