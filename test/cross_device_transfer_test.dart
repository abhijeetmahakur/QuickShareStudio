import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:quickshare/data/models/device_model.dart';
import 'package:quickshare/data/models/transfer_item.dart';
import 'package:quickshare/data/services/cross_device_transfer_service.dart';
import 'package:quickshare/data/services/peer_link.dart';
import 'package:quickshare/data/services/transfer_engine.dart';
import 'package:quickshare/core/utils/hash_utils.dart';

class _RealHttpOverrides extends HttpOverrides {}

/// Real-network tests of the LAN peer protocol (v1) in the native service, including
/// interoperability with the desktop app's scripts/server.py.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = _RealHttpOverrides();

  late CrossDeviceTransferService service;
  late TransferEngine engine;

  setUp(() {
    service = CrossDeviceTransferService()..resetPairingState();
    engine = TransferEngine();
    engine.pairedDevices.clear();
    engine.activeTransfers.clear();
    engine.historyRecords.clear();
    engine.receivedItems.clear();
    if (engine.isReceivingPaused) engine.togglePauseReceiving();
    engine.regeneratePairingCode();
  });

  tearDown(() async {
    await service.stopReceiverServer();
  });

  String code() => engine.currentPairingSession!.numericCode;

  Future<http.Response> pair(String pairCode, {String id = 'android_device_101'}) => http.post(
        Uri.parse('http://127.0.0.1:${service.activePort}/api/pair'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'code': pairCode,
          'id': id,
          'name': 'Pixel 8 Pro (Mobile)',
          'platform': 'Android',
          'port': 8088,
        }),
      );

  Future<http.StreamedResponse> upload(Uint8List bytes, {String? token, String? sha, String sender = 'android_device_101'}) {
    final request = http.StreamedRequest('POST', Uri.parse('http://127.0.0.1:${service.activePort}/api/transfer'));
    request.headers['x-file-name'] = Uri.encodeComponent('experiment_data.csv');
    request.headers['x-sender-id'] = sender;
    request.headers['x-sender-name'] = Uri.encodeComponent('Ubuntu Station');
    request.headers['x-sender-platform'] = 'Linux';
    if (token != null) request.headers['x-pair-token'] = token;
    request.headers['x-sha256'] = sha ?? HashUtils.computeSha256(bytes);
    request.headers['Content-Type'] = 'application/octet-stream';
    request.sink.add(bytes);
    request.sink.close();
    return request.send();
  }

  group('Cross-Device & Cross-Platform Transfer Tests', () {
    test('1. Platform Detection reports valid OS platform string', () {
      expect(['Windows', 'Android', 'macOS', 'iOS', 'Linux', 'Web', 'Universal'].contains(service.currentPlatformName), isTrue);
    });

    test('2. Receiver Server starts on local port and responds to /api/ping', () async {
      final started = await service.startReceiverServer(preferredPort: 9091);
      expect(started, isTrue);
      expect(service.isServerRunning, isTrue);
      final res = await http.get(Uri.parse('http://127.0.0.1:${service.activePort}/api/ping'));
      expect(res.statusCode, 200);
      expect((jsonDecode(res.body) as Map)['status'], 'ok');
    });

    test('3. Device Info Endpoint returns name, platform, protocol and readiness', () async {
      await service.startReceiverServer(preferredPort: 9092);
      final data = jsonDecode((await http.get(Uri.parse('http://127.0.0.1:${service.activePort}/api/device-info'))).body)
          as Map<String, dynamic>;
      for (final key in ['id', 'name', 'platform', 'port', 'readyToReceive', 'protocol']) {
        expect(data.containsKey(key), isTrue, reason: key);
      }
      expect(data['readyToReceive'], isTrue);
      expect(data['protocol'], 1);
    });

    test('4. Pairing requires the code shown on this device and returns a token', () async {
      await service.startReceiverServer(preferredPort: 9093);

      final wrong = await pair('000000');
      expect(wrong.statusCode, 403);
      expect(engine.pairedDevices, isEmpty);

      final res = await pair(code());
      expect(res.statusCode, 200);
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      expect(data['status'], 'paired');
      expect((data['token'] as String).length, 32);

      final paired = engine.pairedDevices.firstWhere((d) => d.name == 'Pixel 8 Pro (Mobile)');
      expect(paired.platform, 'Android');
      expect(paired.deviceType, DeviceType.mobile);
    });

    test('5. Only paired devices can send; delivered file is verified and recorded', () async {
      await service.startReceiverServer(preferredPort: 9094);
      final content = Uint8List.fromList('Cross-Platform Transfer Content - Windows to Android'.codeUnits);

      final unpaired = await upload(content, token: 'forged');
      expect(unpaired.statusCode, 401);
      expect(engine.receivedItems, isEmpty);

      final token = (jsonDecode((await pair(code())).body) as Map)['token'] as String;
      final response = await upload(content, token: token);
      expect(response.statusCode, 200);
      final data = jsonDecode(await response.stream.bytesToString()) as Map<String, dynamic>;
      expect(data['status'], 'success');
      expect(data['bytesReceived'], content.length);

      final received = engine.receivedItems.firstWhere((item) => item.fileName == 'experiment_data.csv');
      expect(received.senderDeviceName, contains('Ubuntu Station'));
      expect(received.senderDeviceName, contains('Linux'));
      expect(received.bytes, content);
    });

    test('6. Corrupted payload from a paired device is rejected (SHA-256 mismatch)', () async {
      await service.startReceiverServer(preferredPort: 9095);
      final token = (jsonDecode((await pair(code())).body) as Map)['token'] as String;
      final response = await upload(
        Uint8List.fromList('Real Bytes'.codeUnits),
        token: token,
        sha: '0000000000000000000000000000000000000000000000000000000000000000',
      );
      expect(response.statusCode, 400);
      expect(await response.stream.bytesToString(), contains('Checksum mismatch'));
    });

    test('7. Wrong codes are rate limited', () async {
      await service.startReceiverServer(preferredPort: 9096);
      final statuses = <int>[];
      for (var i = 0; i < 10; i++) {
        statuses.add((await pair('999999', id: 'attacker')).statusCode);
      }
      expect(statuses.first, 403);
      expect(statuses, contains(429));
    });

    test('8. Pair + streaming transfer end to end (sender and receiver on this machine)', () async {
      await service.startReceiverServer(preferredPort: 9097);
      final self = await service.pairDirect('127.0.0.1', service.activePort, code());

      final testBytes = Uint8List.fromList(List.generate(128 * 1024, (i) => i % 256));
      final transfer = await service.sendFileCrossPlatform(recipient: self, fileName: 'dataset_archive.bin', bytes: testBytes);
      expect(transfer.fileName, 'dataset_archive.bin');

      final completed = engine.activeTransfers.firstWhere((t) => t.fileName == 'dataset_archive.bin');
      expect(completed.status, TransferStatus.completed);
      expect(completed.progress, 1.0);
      expect(engine.receivedItems.any((i) => i.fileName == 'dataset_archive.bin'), isTrue);
      expect(engine.historyRecords.any((h) => h.fileName == 'dataset_archive.bin'), isTrue);
    });

    test('9. Sending fails with a clear error when the device is unpaired or unreachable', () async {
      final stranger = DeviceModel(name: 'Offline macOS Laptop', ip: '127.0.0.1', port: 19999, platform: 'macOS');
      await expectLater(
        service.sendFile(stranger, 'notes.txt', Uint8List.fromList([1, 2, 3])),
        throwsA(isA<PeerLinkException>().having((e) => e.message, 'message', contains('not paired'))),
      );

      await service.startReceiverServer(preferredPort: 9098);
      final self = await service.pairDirect('127.0.0.1', service.activePort, code());
      await service.stopReceiverServer();
      try {
        await service.sendFileCrossPlatform(recipient: self, fileName: 'notes.txt', bytes: Uint8List.fromList([1, 2, 3]));
        fail('Expected exception for unreachable device');
      } on PeerLinkException catch (e) {
        expect(e.message, contains('Could not reach'));
        expect(engine.activeTransfers.first.status, TransferStatus.failed);
      }
    });
  });

  group('Interoperability with the desktop server (scripts/server.py)', () {
    late Process python;
    late int appPort;
    late Directory sandbox;
    const lanPort = 18288;
    const discoveryPort = 18289;

    Future<Map<String, dynamic>> appApi(String path, [Object? body]) async {
      final uri = Uri.parse('http://127.0.0.1:$appPort$path');
      final res = body == null ? await http.get(uri) : await http.post(uri, body: jsonEncode(body));
      return jsonDecode(res.body) as Map<String, dynamic>;
    }

    setUpAll(() async {
      sandbox = await Directory.systemTemp.createTemp('qs_interop_');
      final serverDir = Directory('${sandbox.path}${Platform.pathSeparator}app')..createSync();
      File('scripts/server.py').copySync('${serverDir.path}${Platform.pathSeparator}server.py');
      Directory('${serverDir.path}${Platform.pathSeparator}web').createSync();
      python = await Process.start(
        Platform.isWindows ? 'python' : 'python3',
        ['${serverDir.path}${Platform.pathSeparator}server.py'],
        environment: {
          'QUICKSHARE_LAN_PORT': '$lanPort',
          'QUICKSHARE_DISCOVERY_PORT': '$discoveryPort',
          'HOME': sandbox.path,
          'USERPROFILE': sandbox.path,
        },
      );
      final portFile = File('${serverDir.path}${Platform.pathSeparator}active_port.txt');
      for (var i = 0; i < 100 && !(portFile.existsSync() && portFile.readAsStringSync().trim().isNotEmpty); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      appPort = int.parse(portFile.readAsStringSync().trim());
      for (var i = 0; i < 50; i++) {
        try {
          if ((await appApi('/api/lan/status'))['available'] == true) break;
        } catch (_) {}
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      await appApi('/api/lan/session', {'code': '246810', 'deviceId': 'pc-desktop', 'deviceName': 'Lab PC'});
    });

    tearDownAll(() async {
      python.kill();
      await python.exitCode;
      try {
        sandbox.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('phone app discovers the PC and pairs with its code, then sends it a file', () async {
      await service.startReceiverServer(preferredPort: 9190);

      final found = await service.discoverDevices(discoveryPort: discoveryPort);
      expect(found.any((d) => d['id'] == 'pc-desktop'), isTrue);

      await expectLater(service.pairDirect('127.0.0.1', lanPort, '111111'), throwsA(isA<PeerLinkException>()));
      final pc = await service.pairDirect('127.0.0.1', lanPort, '246810');
      expect(pc.name, 'Lab PC');

      final bytes = Uint8List.fromList(utf8.encode('Practical 7 output — ✓'));
      await service.sendFile(pc, 'practical7.txt', bytes);

      final events = (await appApi('/api/lan/events?since=0'))['events'] as List;
      final received = events.cast<Map<String, dynamic>>().lastWhere((e) => e['type'] == 'file_received');
      expect(received['fileName'], 'practical7.txt');
      final file = await http.get(Uri.parse('http://127.0.0.1:$appPort/api/lan/file?id=${received['fileId']}'));
      expect(file.bodyBytes, bytes);
    });

    test('PC pairs with the phone app using the phone code, then sends it a file', () async {
      await service.startReceiverServer(preferredPort: 9191);

      final paired = await appApi('/api/lan/pair-direct', {'ip': '127.0.0.1', 'port': service.activePort, 'code': code()});
      expect(paired['device'], isNotNull, reason: '$paired');
      expect((paired['device'] as Map)['id'], engine.localDeviceId);
      expect(engine.pairedDevices.any((d) => d.id == 'pc-desktop'), isTrue);

      final res = await http.post(
        Uri.parse('http://127.0.0.1:$appPort/api/lan/send?peer=${Uri.encodeComponent(engine.localDeviceId)}&name=lab_manual.pdf'),
        body: Uint8List.fromList([37, 80, 68, 70, 45, 49]),
      );
      expect(res.statusCode, 200, reason: res.body);
      final item = engine.receivedItems.firstWhere((i) => i.fileName == 'lab_manual.pdf');
      expect(item.bytes, [37, 80, 68, 70, 45, 49]);
      expect(item.senderDeviceName, contains('Lab PC'));
    });
  });
}
