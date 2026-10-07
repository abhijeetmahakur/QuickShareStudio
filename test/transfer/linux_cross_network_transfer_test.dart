import 'dart:async';

import 'package:async/async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickshare/transfer/app_config.dart';
import 'package:quickshare/transfer/channel.dart';
import 'package:quickshare/transfer/connect_flow.dart';
import 'package:quickshare/transfer/file_source.dart';
import 'package:quickshare/transfer/protocol/handshake.dart';
import 'package:quickshare/transfer/protocol/streaming_sha256.dart';
import 'package:quickshare/transfer/protocol/transfer_protocol.dart';
import 'package:quickshare/transfer/sinks.dart';

class TestDevice {
  const TestDevice({
    required this.id,
    required this.name,
    required this.platform,
  });

  final String id;
  final String name;
  final String platform;

  RemoteIdentity toRemote() =>
      RemoteIdentity(id: id, name: name, platform: platform);
}

class TransferProtocolTestSession {
  TransferProtocolTestSession({
    required this.senderDevice,
    required this.receiverDevice,
    this.config = const AppConfig(),
  }) {
    final (a, b) = MemoryFrameChannel.pair(highWaterMark: 4 * 1024 * 1024);
    senderChannel = a;
    receiverChannel = b;

    senderSession = PeerSession(
      channel: senderChannel,
      frames: StreamQueue(senderChannel.frames),
      remote: receiverDevice.toRemote(),
      config: config,
      onOffer: (_) async => false,
      openSink: (offer, i) async => CountingFileSink(offer.files[i].name),
    )..start();

    receiverSession = PeerSession(
      channel: receiverChannel,
      frames: StreamQueue(receiverChannel.frames),
      remote: senderDevice.toRemote(),
      config: config,
      partials: PartialTransferStore(),
      onOffer: (offer) async => true,
      openSink: (offer, i) async {
        final sink = CountingFileSink(offer.files[i].name);
        receivedSinks.add(sink);
        return sink;
      },
    )..start();

    receiverSession.incomingUpdates.listen(receivedUpdates.add);
  }

  final TestDevice senderDevice;
  final TestDevice receiverDevice;
  final AppConfig config;

  late final MemoryFrameChannel senderChannel;
  late final MemoryFrameChannel receiverChannel;
  late final PeerSession senderSession;
  late final PeerSession receiverSession;
  final List<CountingFileSink> receivedSinks = [];
  final List<TransferSnapshot> receivedUpdates = [];

  Future<void> sendAndVerify({
    required String fileName,
    required int byteSize,
    required GeneratedFileSource source,
    required String expectedHash,
  }) async {
    debugPrint(
      '[QuickShare] Protocol test sending $fileName ($byteSize bytes) over an in-memory channel.',
    );

    final out = OutgoingTransfer(
      files: [source],
      config: config,
      peerName: receiverDevice.name,
    );

    final result = await out.run(senderSession);

    expect(result.phase, TransferPhase.completed, reason: result.error);
    expect(result.bytesDone, byteSize);
    expect(receivedSinks.length, 1);
    expect(receivedSinks.first.length, byteSize);
    expect(receivedSinks.first.mismatches, 0);

    await pumpEventQueue();
    final done = receivedUpdates.isNotEmpty ? receivedUpdates.last : null;
    expect(done?.phase, TransferPhase.completed);
    expect(done?.received.first.sha256, expectedHash);
    debugPrint(
      '[QuickShare] Transfer completed & verified checksum for $fileName: $expectedHash',
    );
  }

  Future<void> dispose() async {
    await senderSession.close();
    await receiverSession.close();
  }
}

Future<String> _computeHash(FileSource source) async {
  final hasher = StreamingSha256();
  await for (final chunk in source.openRead()) {
    hasher.add(chunk);
  }
  return hasher.finish();
}

void main() {
  const linuxDevice = TestDevice(
    id: 'dev-linux',
    name: 'Ubuntu Desktop',
    platform: 'Linux',
  );
  const androidDevice = TestDevice(
    id: 'dev-android',
    name: 'Pixel Phone',
    platform: 'Android',
  );
  const windowsDevice = TestDevice(
    id: 'dev-windows',
    name: 'Windows Laptop',
    platform: 'Windows',
  );

  late final GeneratedFileSource source1MB;
  late final String hash1MB;
  late final GeneratedFileSource source20MB;
  late final String hash20MB;

  setUpAll(() async {
    source1MB = GeneratedFileSource('1MB.bin', 1024 * 1024, seed: 101);
    hash1MB = await _computeHash(source1MB);

    source20MB = GeneratedFileSource(
      'document.pdf',
      20 * 1024 * 1024,
      seed: 202,
    );
    hash20MB = await _computeHash(source20MB);
  });

  group('Shared transfer protocol (in-memory transport)', () {
    test('Linux-role sender to Android-role receiver, 1 MB', () async {
      final session = TransferProtocolTestSession(
        senderDevice: linuxDevice,
        receiverDevice: androidDevice,
      );
      await session.sendAndVerify(
        fileName: 'document.txt',
        byteSize: 1024 * 1024,
        source: source1MB,
        expectedHash: hash1MB,
      );
      await session.dispose();
    });

    test(
      'Linux-role sender to Android-role receiver, 20 MB .pdf-named payload',
      () async {
        final session = TransferProtocolTestSession(
          senderDevice: linuxDevice,
          receiverDevice: androidDevice,
        );
        await session.sendAndVerify(
          fileName: 'large_document.pdf',
          byteSize: 20 * 1024 * 1024,
          source: source20MB,
          expectedHash: hash20MB,
        );
        await session.dispose();
      },
    );

    test('Android-role sender to Linux-role receiver, 1 MB', () async {
      final session = TransferProtocolTestSession(
        senderDevice: androidDevice,
        receiverDevice: linuxDevice,
      );
      await session.sendAndVerify(
        fileName: 'mobile_photo.jpg',
        byteSize: 1024 * 1024,
        source: source1MB,
        expectedHash: hash1MB,
      );
      await session.dispose();
    });

    test(
      'Android-role sender to Linux-role receiver, 20 MB .pdf-named payload',
      () async {
        final session = TransferProtocolTestSession(
          senderDevice: androidDevice,
          receiverDevice: linuxDevice,
        );
        await session.sendAndVerify(
          fileName: 'manual_android.pdf',
          byteSize: 20 * 1024 * 1024,
          source: source20MB,
          expectedHash: hash20MB,
        );
        await session.dispose();
      },
    );

    test('Linux-role sender to Windows-role receiver, 1 MB', () async {
      final session = TransferProtocolTestSession(
        senderDevice: linuxDevice,
        receiverDevice: windowsDevice,
      );
      await session.sendAndVerify(
        fileName: 'notes.md',
        byteSize: 1024 * 1024,
        source: source1MB,
        expectedHash: hash1MB,
      );
      await session.dispose();
    });

    test(
      'Linux-role sender to Windows-role receiver, 20 MB .pdf-named payload',
      () async {
        final session = TransferProtocolTestSession(
          senderDevice: linuxDevice,
          receiverDevice: windowsDevice,
        );
        await session.sendAndVerify(
          fileName: 'presentation.pdf',
          byteSize: 20 * 1024 * 1024,
          source: source20MB,
          expectedHash: hash20MB,
        );
        await session.dispose();
      },
    );

    test('Windows-role sender to Linux-role receiver, 1 MB', () async {
      final session = TransferProtocolTestSession(
        senderDevice: windowsDevice,
        receiverDevice: linuxDevice,
      );
      await session.sendAndVerify(
        fileName: 'report.xlsx',
        byteSize: 1024 * 1024,
        source: source1MB,
        expectedHash: hash1MB,
      );
      await session.dispose();
    });

    test(
      'Windows-role sender to Linux-role receiver, 20 MB .pdf-named payload',
      () async {
        final session = TransferProtocolTestSession(
          senderDevice: windowsDevice,
          receiverDevice: linuxDevice,
        );
        await session.sendAndVerify(
          fileName: 'windows_guide.pdf',
          byteSize: 20 * 1024 * 1024,
          source: source20MB,
          expectedHash: hash20MB,
        );
        await session.dispose();
      },
    );

    test(
      '9. ConnectFlow correctly shows Direct vs Relay route in UI state',
      () async {
        final directFlow = ConnectFlow<bool>(
          lan: (_) => Completer<bool>().future,
          internetStun: (_) async =>
              false, // false indicates direct / not relayed
          internetRelay: (_) => Completer<bool>().future,
          isOnline: () async => true,
          connectionLabel: (isRelayed, attempted) =>
              isRelayed ? 'Relay' : 'Direct',
        );
        expect(await directFlow.run(), isFalse);
        expect(directFlow.state.value.statusText, 'Connected via Direct');

        final relayFlow = ConnectFlow<bool>(
          lan: (_) => Completer<bool>().future,
          internetStun: (_) async => throw Exception('NAT traversal failed'),
          internetRelay: (_) async => true, // true indicates relayed
          isOnline: () async => true,
          connectionLabel: (isRelayed, attempted) =>
              isRelayed ? 'Relay' : 'Direct',
        );
        expect(await relayFlow.run(), isTrue);
        expect(relayFlow.state.value.statusText, 'Connected via Relay');
      },
    );
  });
}
