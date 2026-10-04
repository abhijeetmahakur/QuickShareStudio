import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:quickshare/data/models/device_model.dart';
import 'package:quickshare/data/models/transfer_item.dart';
import 'package:quickshare/data/services/cross_device_transfer_service.dart';
import 'package:quickshare/data/services/transfer_engine.dart';
import 'package:quickshare/core/utils/hash_utils.dart';

import 'dart:io';

class _RealHttpOverrides extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = _RealHttpOverrides();

  late CrossDeviceTransferService service;
  late TransferEngine engine;

  setUp(() {
    service = CrossDeviceTransferService();
    engine = TransferEngine();
    engine.pairedDevices.clear();
    engine.activeTransfers.clear();
    engine.historyRecords.clear();
    engine.receivedItems.clear();
  });

  tearDown(() async {
    await service.stopReceiverServer();
  });

  group('Cross-Device & Cross-Platform Transfer Tests', () {
    test('1. Platform Detection reports valid OS platform string', () {
      final platform = service.currentPlatformName;
      expect(
        ['Windows', 'Android', 'macOS', 'iOS', 'Linux', 'Web', 'Universal'].contains(platform),
        isTrue,
      );
    });

    test('2. Receiver Server starts on local port and responds to /api/ping', () async {
      final started = await service.startReceiverServer(preferredPort: 9091);
      expect(started, isTrue);
      expect(service.isServerRunning, isTrue);
      expect(service.activePort, greaterThanOrEqualTo(9091));

      // Query ping
      final res = await http.get(Uri.parse('http://127.0.0.1:${service.activePort}/api/ping'));
      expect(res.statusCode, equals(200));
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      expect(json['status'], equals('ok'));
    });

    test('3. Device Info Endpoint (/api/device-info) returns name, OS platform, and readiness', () async {
      await service.startReceiverServer(preferredPort: 9092);

      final res = await http.get(Uri.parse('http://127.0.0.1:${service.activePort}/api/device-info'));
      expect(res.statusCode, equals(200));
      final data = jsonDecode(res.body) as Map<String, dynamic>;

      expect(data.containsKey('id'), isTrue);
      expect(data.containsKey('name'), isTrue);
      expect(data.containsKey('platform'), isTrue);
      expect(data.containsKey('port'), isTrue);
      expect(data.containsKey('readyToReceive'), isTrue);
      expect(data['readyToReceive'], isTrue);
    });

    test('4. Pairing Handshake (/api/pair) pairs remote device with OS tag', () async {
      await service.startReceiverServer(preferredPort: 9093);

      final payload = jsonEncode({
        'id': 'android_device_101',
        'name': 'Pixel 8 Pro (Mobile)',
        'platform': 'Android',
        'ip': '192.168.1.15',
        'port': 8088,
      });

      final res = await http.post(
        Uri.parse('http://127.0.0.1:${service.activePort}/api/pair'),
        headers: {'Content-Type': 'application/json'},
        body: payload,
      );

      expect(res.statusCode, equals(200));
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      expect(data['status'], equals('paired'));

      // Check TransferEngine pairedDevices
      expect(engine.pairedDevices.any((d) => d.name == 'Pixel 8 Pro (Mobile)'), isTrue);
      final paired = engine.pairedDevices.firstWhere((d) => d.name == 'Pixel 8 Pro (Mobile)');
      expect(paired.platform, equals('Android'));
      expect(paired.deviceType, equals(DeviceType.mobile));
    });

    test('5. Inbound File Transfer (/api/transfer) receives bytes, verifies SHA-256, and records item', () async {
      await service.startReceiverServer(preferredPort: 9094);

      final testContent = Uint8List.fromList('Cross-Platform Transfer Content - Windows to Android'.codeUnits);
      final checksum = HashUtils.computeSha256(testContent);

      final request = http.StreamedRequest(
        'POST',
        Uri.parse('http://127.0.0.1:${service.activePort}/api/transfer'),
      );
      request.headers['x-file-name'] = Uri.encodeComponent('experiment_data.csv');
      request.headers['x-file-size'] = testContent.length.toString();
      request.headers['x-sender-name'] = Uri.encodeComponent('Ubuntu Station');
      request.headers['x-sender-platform'] = 'Linux';
      request.headers['x-sha256'] = checksum;
      request.headers['Content-Type'] = 'application/octet-stream';
      request.sink.add(testContent);
      request.sink.close();

      final response = await request.send();
      expect(response.statusCode, equals(200));
      final body = await response.stream.bytesToString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      expect(data['status'], equals('success'));
      expect(data['bytesReceived'], equals(testContent.length));
      expect(data['sha256'], equals(checksum));

      // Verify item delivered to receivedItems in TransferEngine
      expect(engine.receivedItems.any((item) => item.fileName == 'experiment_data.csv'), isTrue);
      final received = engine.receivedItems.firstWhere((item) => item.fileName == 'experiment_data.csv');
      expect(received.senderDeviceName, contains('Ubuntu Station'));
      expect(received.senderDeviceName, contains('Linux'));
      expect(received.bytes, equals(testContent));
    });

    test('6. Inbound File Transfer rejects corrupted payload with SHA-256 mismatch', () async {
      await service.startReceiverServer(preferredPort: 9095);

      final testContent = Uint8List.fromList('Real Bytes'.codeUnits);
      const forgedChecksum = '0000000000000000000000000000000000000000000000000000000000000000';

      final request = http.StreamedRequest(
        'POST',
        Uri.parse('http://127.0.0.1:${service.activePort}/api/transfer'),
      );
      request.headers['x-file-name'] = Uri.encodeComponent('corrupted.pdf');
      request.headers['x-sender-name'] = Uri.encodeComponent('Suspicious Peer');
      request.headers['x-sender-platform'] = 'Android';
      request.headers['x-sha256'] = forgedChecksum;
      request.headers['Content-Type'] = 'application/octet-stream';
      request.sink.add(testContent);
      request.sink.close();

      final response = await request.send();
      expect(response.statusCode, equals(400));
      final body = await response.stream.bytesToString();
      expect(body, contains('Checksum mismatch'));
    });

    test('7. Client probeRemoteDevice detects and returns remote DeviceModel', () async {
      await service.startReceiverServer(preferredPort: 9096);

      final probe = await service.probeRemoteDevice('127.0.0.1', service.activePort);
      expect(probe, isNotNull);
      expect(probe!.ip, equals('127.0.0.1'));
      expect(probe.port, equals(service.activePort));
      expect(probe.platform, equals(service.currentPlatformName));
      expect(probe.isOnline, isTrue);
    });

    test('8. Full End-to-End Streaming Transfer between Sender and Receiver', () async {
      await service.startReceiverServer(preferredPort: 9097);

      final recipient = DeviceModel(
        name: 'Target Android Phone',
        ip: '127.0.0.1',
        port: service.activePort,
        platform: 'Android',
        deviceType: DeviceType.mobile,
        isTrusted: true,
        isOnline: true,
      );

      final testBytes = Uint8List.fromList(List.generate(128 * 1024, (i) => i % 256)); // 128 KB
      final transfer = await service.sendFileCrossPlatform(
        recipient: recipient,
        fileName: 'dataset_archive.bin',
        bytes: testBytes,
      );

      expect(transfer.status, equals(TransferStatus.transferring));
      expect(transfer.fileName, equals('dataset_archive.bin'));
      expect(transfer.fileSizeBytes, equals(128 * 1024));

      // Wait a moment for chunks to complete streaming
      await Future.delayed(const Duration(milliseconds: 300));

      // Verify active transfer marked completed
      final completed = engine.activeTransfers.firstWhere((t) => t.fileName == 'dataset_archive.bin');
      expect(completed.status, equals(TransferStatus.completed));
      expect(completed.progress, equals(1.0));

      // Verify delivery into receivedItems on the receiver side
      expect(engine.receivedItems.any((i) => i.fileName == 'dataset_archive.bin'), isTrue);

      // Verify outgoing history record recorded
      expect(engine.historyRecords.any((h) => h.fileName == 'dataset_archive.bin'), isTrue);
    });

    test('9. sendFileCrossPlatform fails cleanly with descriptive error when target is unreachable', () async {
      final unreachableDevice = DeviceModel(
        name: 'Offline macOS Laptop',
        ip: '127.0.0.1',
        port: 19999, // Unused port
        platform: 'macOS',
        deviceType: DeviceType.desktop,
        isTrusted: true,
        isOnline: true,
      );

      final dummyBytes = Uint8List.fromList([1, 2, 3]);

      try {
        await service.sendFileCrossPlatform(
          recipient: unreachableDevice,
          fileName: 'notes.txt',
          bytes: dummyBytes,
        );
        fail('Expected exception for unreachable device');
      } catch (e) {
        expect(engine.activeTransfers.isNotEmpty, isTrue);
        final failedTransfer = engine.activeTransfers.first;
        expect(failedTransfer.status, equals(TransferStatus.failed));
        expect(failedTransfer.errorMessage, isNotNull);
        expect(failedTransfer.errorMessage, contains('Could not reach'));
      }
    });
  });
}
