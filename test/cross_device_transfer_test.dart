import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:async/async.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:quickshare/data/models/device_model.dart';
import 'package:quickshare/data/models/transfer_item.dart';
import 'package:quickshare/data/services/cross_device_transfer_service.dart';
import 'package:quickshare/data/services/peer_link.dart';
import 'package:quickshare/data/services/transfer_engine.dart';
import 'package:quickshare/transfer/app_config.dart';
import 'package:quickshare/transfer/connection_manager.dart';
import 'package:quickshare/transfer/file_source.dart';
import 'package:quickshare/transfer/lan/ws_frame_channel.dart';
import 'package:quickshare/transfer/protocol/handshake.dart';
import 'package:quickshare/transfer/protocol/transfer_protocol.dart';
import 'package:quickshare/transfer/secure_channel.dart';
import 'package:quickshare/transfer/sinks.dart';
import 'package:quickshare/transfer/transfer_settings.dart';
import 'package:web_socket_channel/io.dart';

class _RealHttpOverrides extends HttpOverrides {}

Future<void> _waitFor(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 20),
  String? what,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Timed out waiting for ${what ?? 'condition'}');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

/// Real-network tests of the LAN peer protocol (v2) in the native service: pairing, the
/// end-to-end encrypted session, accept/decline, and interoperability with the desktop
/// app's scripts/server.py.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = _RealHttpOverrides();

  late CrossDeviceTransferService service;
  late TransferEngine engine;
  late ConnectionManager manager;
  late Directory downloads;

  setUp(() async {
    service = CrossDeviceTransferService()..resetPairingState();
    engine = TransferEngine();
    manager = ConnectionManager.instance..resetForTest();
    manager.config = const AppConfig();
    TransferSettings.instance.reset();
    engine.pairedDevices.clear();
    engine.activeTransfers.clear();
    engine.historyRecords.clear();
    engine.receivedItems.clear();
    if (engine.isReceivingPaused) engine.togglePauseReceiving();
    downloads = await Directory.systemTemp.createTemp('qs_downloads_');
    engine.downloadDirectory = downloads.path;
    engine.attachPeerLink(service);
  });

  tearDown(() async {
    await service.stopReceiverServer();
    try {
      downloads.deleteSync(recursive: true);
    } catch (_) {}
  });

  String code() => engine.currentPairingSession!.numericCode;

  Future<http.Response> pair(
    String pairCode, {
    String id = 'android_device_101',
  }) => http.post(
    Uri.parse('http://127.0.0.1:${service.activePort}/api/pair'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({
      'code': pairCode,
      'id': id,
      'name': 'Pixel 8 Pro',
      'platform': 'Android',
      'port': 8088,
    }),
  );

  /// Pairs this device with itself through the real HTTP API (sender and receiver are the
  /// same process, talking over sockets).
  Future<DeviceModel> pairWithSelf() async {
    final self = await service.pairDirect(
      '127.0.0.1',
      service.activePort,
      code(),
    );
    engine.addPairedDevice(self);
    return self;
  }

  group('LAN protocol v2 (native service)', () {
    test('1. Platform detection reports a valid OS name', () {
      expect([
        'Windows',
        'Android',
        'macOS',
        'iOS',
        'Linux',
        'Web',
        'Universal',
      ], contains(service.currentPlatformName));
    });

    test('2. Receiver server starts and answers /api/ping', () async {
      expect(await service.startReceiverServer(preferredPort: 9091), isTrue);
      final res = await http.get(
        Uri.parse('http://127.0.0.1:${service.activePort}/api/ping'),
      );
      expect(res.statusCode, 200);
    });

    test('3. Device info reports protocol 2', () async {
      await service.startReceiverServer(preferredPort: 9092);
      final res = await http.get(
        Uri.parse('http://127.0.0.1:${service.activePort}/api/device-info'),
      );
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      expect(data['protocol'], 2);
      expect(data['name'], engine.localDeviceName);
    });

    test(
      '4. Pairing requires the code shown on this device and returns a token',
      () async {
        await service.startReceiverServer(preferredPort: 9093);
        final originalCode = code();
        expect((await pair('000000')).statusCode, HttpStatus.forbidden);
        final ok = await pair(originalCode);
        expect(ok.statusCode, HttpStatus.ok);
        final token =
            (jsonDecode(ok.body) as Map<String, dynamic>)['token'] as String;
        expect(token.length, 32);
        expect(service.pairingToken('android_device_101'), token);
        expect(
          engine.pairedDevices.any((d) => d.id == 'android_device_101'),
          isTrue,
        );
        expect(code(), isNot(originalCode));
        expect((await pair(originalCode)).statusCode, HttpStatus.forbidden);
      },
    );

    test('5. v1 transfers (no accept, no encryption) are refused', () async {
      await service.startReceiverServer(preferredPort: 9094);
      final token =
          (jsonDecode((await pair(code())).body)
                  as Map<String, dynamic>)['token']
              as String;
      final res = await http.post(
        Uri.parse('http://127.0.0.1:${service.activePort}/api/transfer'),
        headers: {
          'x-sender-id': 'android_device_101',
          'x-pair-token': token,
          'x-file-name': 'x.txt',
        },
        body: 'hello',
      );
      expect(res.statusCode, 426);
      expect(engine.receivedItems, isEmpty);
    });

    test('6. An unpaired device cannot open a session', () async {
      await service.startReceiverServer(preferredPort: 9095);
      await expectLater(
        WebSocket.connect(
          'ws://127.0.0.1:${service.activePort}/api/v2/session?from=stranger',
        ),
        throwsA(isA<WebSocketException>()),
      );
    });

    test('7. A paired device with the wrong token cannot complete the encrypted handshake', () async {
      await service.startReceiverServer(preferredPort: 9096);
      await pair(code());
      final socket = await WebSocket.connect(
        'ws://127.0.0.1:${service.activePort}/api/v2/session?from=android_device_101',
      );
      final raw = WebSocketFrameChannel(IOWebSocketChannel(socket));
      await expectLater(
        SecureFrameChannel.establish(
          raw,
          StreamQueue(raw.frames),
          initiator: true,
          psk: utf8.encode('f' * 32),
        ),
        throwsA(isA<SecureChannelException>()),
      );
      expect(engine.activeTransfers, isEmpty);
    });

    test('8. Encrypted transfer end to end: offer -> accept -> saved to disk -> SHA-256 verified', () async {
      await service.startReceiverServer(preferredPort: 9097);
      final self = await pairWithSelf();
      final content = Uint8List.fromList(
        List.generate(3 * 1024 * 1024 + 77, (i) => (i * 7 + 3) & 0xFF),
      );

      final item = await manager.send(self, [
        BytesFileSource('dataset_archive.bin', content),
      ]);
      await _waitFor(
        () => manager.pendingOffers.isNotEmpty,
        what: 'accept prompt',
      );
      final offer = manager.pendingOffers.single;
      expect(offer.offer.files.single.name, 'dataset_archive.bin');
      expect(offer.offer.totalBytes, content.length);
      expect(offer.link.verificationCode, matches(RegExp(r'^\d{4}$')));
      expect(
        downloads.listSync(),
        isEmpty,
        reason: 'nothing is written before Accept',
      );
      manager.acceptOffer(offer);

      expect(await engine.waitForTransfer(item.transferId), isTrue);
      await _waitFor(
        () => engine.receivedItems.isNotEmpty,
        what: 'received item',
      );
      final received = engine.receivedItems.first;
      expect(received.fileName, 'dataset_archive.bin');
      expect(received.sha256, sha256.convert(content).toString());
      final onDisk = File(received.savedToPath);
      expect(onDisk.existsSync(), isTrue);
      expect(await onDisk.readAsBytes(), content);
      expect(
        downloads.listSync().where((f) => f.path.endsWith('.part')),
        isEmpty,
      );
      expect(
        engine.historyRecords.where(
          (r) => r.isIncoming && r.status == 'completed',
        ),
        isNotEmpty,
      );
      expect(
        engine.historyRecords.where(
          (r) => !r.isIncoming && r.status == 'completed',
        ),
        isNotEmpty,
      );
    });

    test(
      '9. Decline on the receiver: nothing is received or written',
      () async {
        await service.startReceiverServer(preferredPort: 9098);
        final self = await pairWithSelf();
        final item = await manager.send(self, [
          BytesFileSource('private.zip', Uint8List(500000)),
        ]);
        await _waitFor(
          () => manager.pendingOffers.isNotEmpty,
          what: 'accept prompt',
        );
        manager.declineOffer(manager.pendingOffers.single);
        expect(await engine.waitForTransfer(item.transferId), isFalse);
        final sent = engine.activeTransfers.firstWhere(
          (t) => t.transferId == item.transferId,
        );
        expect(sent.status, TransferStatus.cancelled);
        expect(sent.errorMessage, contains('declined'));
        expect(engine.receivedItems, isEmpty);
        expect(downloads.listSync(), isEmpty);
      },
    );

    test(
      '10. Cancel mid-transfer removes the partial file on the receiver',
      () async {
        await service.startReceiverServer(preferredPort: 9099);
        TransferSettings.instance.autoAccept = true;
        final self = await pairWithSelf();
        final item = await manager.send(self, [
          GeneratedFileSource('big.bin', 300 * 1024 * 1024),
        ]);
        // Sender and receiver are the same engine here, so they share one transfer entry.
        await _waitFor(
          () => engine.activeTransfers.any(
            (t) => t.transferId == item.transferId && t.progress > 0.01,
          ),
          what: 'transfer progress',
        );
        engine.cancelTransfer(item.transferId);
        await _waitFor(
          () =>
              engine.activeTransfers
                  .firstWhere((t) => t.transferId == item.transferId)
                  .status ==
              TransferStatus.cancelled,
        );
        await _waitFor(
          () => downloads.listSync().isEmpty,
          what: 'partial file deleted',
        );
        expect(engine.receivedItems, isEmpty);
      },
    );

    test(
      '11. Sending to an unpaired device fails with a clear error',
      () async {
        await service.startReceiverServer(preferredPort: 9100);
        final stranger = DeviceModel(
          name: 'Stranger',
          ip: '127.0.0.1',
          port: service.activePort,
        );
        await expectLater(
          manager.send(stranger, [
            BytesFileSource('notes.txt', Uint8List.fromList([1, 2, 3])),
          ]),
          throwsA(
            isA<PeerLinkException>().having(
              (e) => e.message,
              'message',
              contains('not paired'),
            ),
          ),
        );
      },
    );

    test('12. An unreachable paired device fails with a clear error', () async {
      await service.startReceiverServer(preferredPort: 9101);
      final self = await pairWithSelf();
      await service.stopReceiverServer();
      await expectLater(
        manager.send(self, [
          BytesFileSource('notes.txt', Uint8List.fromList([1, 2, 3])),
        ]),
        throwsA(
          isA<PeerLinkException>().having(
            (e) => e.message,
            'message',
            contains('Could not reach'),
          ),
        ),
      );
    });

    test('13. Wrong codes are rate limited', () async {
      await service.startReceiverServer(preferredPort: 9102);
      final statuses = <int>[];
      for (var i = 0; i < 10; i++) {
        statuses.add((await pair('999999', id: 'attacker')).statusCode);
      }
      expect(statuses.first, HttpStatus.forbidden);
      expect(statuses, contains(HttpStatus.tooManyRequests));
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
      final res = body == null
          ? await http.get(uri)
          : await http.post(uri, body: jsonEncode(body));
      return jsonDecode(res.body) as Map<String, dynamic>;
    }

    /// What the desktop app (BridgePeerLink + ConnectionManager) does with an incoming
    /// session: pick it up through the loopback tunnel, decrypt with the pairing token and
    /// run the receiving side of the protocol.
    Future<TransferSnapshot> desktopAppReceives(
      String fromPeerId, {
      required int sinceSeq,
    }) async {
      Map<String, dynamic>? event;
      final deadline = DateTime.now().add(const Duration(seconds: 20));
      while (event == null && DateTime.now().isBefore(deadline)) {
        final events =
            (await appApi('/api/lan/events?since=$sinceSeq'))['events'] as List;
        event = events
            .cast<Map<String, dynamic>>()
            .where((e) => e['type'] == 'tunnel_incoming')
            .firstOrNull;
        if (event == null) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }
      expect(event, isNotNull);
      expect((event!['peer'] as Map)['id'], fromPeerId);
      final peers = ((await appApi('/api/lan/peers'))['peers'] as List)
          .cast<Map<String, dynamic>>();
      final token =
          peers.firstWhere((p) => p['id'] == fromPeerId)['token'] as String;
      final socket = await WebSocket.connect(
        'ws://127.0.0.1:$appPort/api/lan/tunnel?accept=${event['tunnelId']}',
      );
      final raw = WebSocketFrameChannel(IOWebSocketChannel(socket));
      final secure = await SecureFrameChannel.establish(
        raw,
        StreamQueue(raw.frames),
        initiator: false,
        psk: utf8.encode(token),
      );
      final done = Completer<TransferSnapshot>();
      final session = PeerSession(
        channel: secure,
        frames: StreamQueue(secure.frames),
        remote: RemoteIdentity(
          id: fromPeerId,
          name: 'Phone',
          platform: 'Android',
        ),
        config: const AppConfig(),
        onOffer: (_) async => true,
        openSink: (offer, i) async => MemoryFileSink(offer.files[i].name),
      )..start();
      session.incomingUpdates.listen((s) {
        if (s.phase.isFinal && !done.isCompleted) done.complete(s);
      });
      return done.future.timeout(const Duration(seconds: 30));
    }

    setUpAll(() async {
      sandbox = await Directory.systemTemp.createTemp('qs_interop_');
      final serverDir = Directory('${sandbox.path}${Platform.pathSeparator}app')
        ..createSync();
      File('scripts/server.py')
          .copySync('${serverDir.path}${Platform.pathSeparator}server.py');
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
      final portFile = File(
        '${serverDir.path}${Platform.pathSeparator}active_port.txt',
      );
      for (
        var i = 0;
        i < 100 &&
            !(portFile.existsSync() &&
                portFile.readAsStringSync().trim().isNotEmpty);
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      appPort = int.parse(portFile.readAsStringSync().trim());
      for (var i = 0; i < 50; i++) {
        try {
          if ((await appApi('/api/lan/status'))['available'] == true) break;
        } catch (_) {}
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      await appApi('/api/lan/session', {
        'code': '246810',
        'deviceId': 'pc-desktop',
        'deviceName': 'Lab PC',
      });
    });

    tearDownAll(() async {
      python.kill();
      await python.exitCode;
      try {
        sandbox.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('phone discovers the PC, pairs with its code and sends it an encrypted file', () async {
      await service.startReceiverServer(preferredPort: 9190);
      final found = await service.discoverDevices(discoveryPort: discoveryPort);
      expect(found.any((d) => d['id'] == 'pc-desktop'), isTrue);

      await expectLater(
        service.pairDirect('127.0.0.1', lanPort, '111111'),
        throwsA(isA<PeerLinkException>()),
      );
      final pc = await service.pairDirect('127.0.0.1', lanPort, '246810');
      expect(pc.name, 'Lab PC');
      engine.addPairedDevice(pc);

      final seq = (await appApi('/api/lan/events?since=0'))['seq'] as int;
      final bytes = Uint8List.fromList(
        utf8.encode('Practical 7 output - ✓' * 2000),
      );
      final pcReceives = desktopAppReceives(
        engine.localDeviceId,
        sinceSeq: seq,
      );
      final item = await manager.send(pc, [
        BytesFileSource('practical7.txt', bytes),
      ]);
      final received = await pcReceives;
      expect(received.phase, TransferPhase.completed);
      expect(received.received.single.bytes, bytes);
      expect(await engine.waitForTransfer(item.transferId), isTrue);
    });

    test('PC pairs with the phone using the phone code, then sends it an encrypted file', () async {
      await service.startReceiverServer(preferredPort: 9191);
      TransferSettings.instance.autoAccept = true;
      final paired = await appApi('/api/lan/pair-direct', {
        'ip': '127.0.0.1',
        'port': service.activePort,
        'code': code(),
      });
      expect(paired['device'], isNotNull, reason: '$paired');
      expect(engine.pairedDevices.any((d) => d.id == 'pc-desktop'), isTrue);

      // The desktop app opens a tunnel to the phone and runs the sending side.
      final peers = ((await appApi('/api/lan/peers'))['peers'] as List)
          .cast<Map<String, dynamic>>();
      final token =
          peers.firstWhere((p) => p['id'] == engine.localDeviceId)['token']
              as String;
      final socket = await WebSocket.connect(
        'ws://127.0.0.1:$appPort/api/lan/tunnel?peer=${Uri.encodeComponent(engine.localDeviceId)}',
      );
      final raw = WebSocketFrameChannel(IOWebSocketChannel(socket));
      final secure = await SecureFrameChannel.establish(
        raw,
        StreamQueue(raw.frames),
        initiator: true,
        psk: utf8.encode(token),
      );
      final session = PeerSession(
        channel: secure,
        frames: StreamQueue(secure.frames),
        remote: const RemoteIdentity(
          id: 'phone',
          name: 'Phone',
          platform: 'Android',
        ),
        config: const AppConfig(),
        onOffer: (_) async => false,
        openSink: (o, i) async => MemoryFileSink('x'),
      )..start();
      final pdf = Uint8List.fromList([
        37,
        80,
        68,
        70,
        45,
        49,
        ...List.filled(70000, 32),
      ]);
      final result = await OutgoingTransfer(
        files: [BytesFileSource('lab_manual.pdf', pdf)],
        config: const AppConfig(),
        peerName: 'Phone',
      ).run(session);
      expect(result.phase, TransferPhase.completed, reason: result.error);
      await _waitFor(
        () => engine.receivedItems.any((i) => i.fileName == 'lab_manual.pdf'),
      );
      final item = engine.receivedItems.firstWhere(
        (i) => i.fileName == 'lab_manual.pdf',
      );
      expect(item.bytes, pdf);
      expect(item.senderDeviceName, contains('Lab PC'));
      expect(File(item.savedToPath).readAsBytesSync(), pdf);
    });
  });
}
