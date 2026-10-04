import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:quickshare/data/models/device_model.dart';
import 'package:quickshare/data/models/received_item_model.dart';
import 'package:quickshare/data/models/transfer_item.dart';
import 'package:quickshare/data/services/transfer_engine.dart';
import 'package:quickshare/features/file_transfer/send_files_view.dart';
import 'package:quickshare/features/pairing/pairing_view.dart';
import 'package:quickshare/features/received_items/received_items_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('File Sharing & Multi-Device Pairing Tests', () {
    late TransferEngine engine;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      engine = TransferEngine();
      engine.stopTimers();
      engine.pairedDevices.clear();
      engine.activeTransfers.clear();
      engine.receivedItems.clear();
      engine.regeneratePairingCode();
    });

    tearDown(() {
      engine.stopTimers();
    });

    // =========================================================================
    // 1. Multi-Device Pairing Tests
    // =========================================================================
    test('1. Multi-Device Pairing: Supports adding and managing multiple devices across OS platforms', () async {
      final androidDev = DeviceModel(
        id: 'dev_android_1',
        name: 'Pixel 8 Pro',
        ip: '192.168.1.101',
        port: 8088,
        deviceType: DeviceType.mobile,
        platform: 'Android',
        isOnline: true,
      );

      final windowsDev = DeviceModel(
        id: 'dev_windows_2',
        name: 'Work Desktop',
        ip: '192.168.1.102',
        port: 8088,
        deviceType: DeviceType.desktop,
        platform: 'Windows',
        isOnline: true,
      );

      final macDev = DeviceModel(
        id: 'dev_mac_3',
        name: 'MacBook Pro',
        ip: '192.168.1.103',
        port: 8088,
        deviceType: DeviceType.desktop,
        platform: 'macOS',
        isOnline: true,
      );

      final iosDev = DeviceModel(
        id: 'dev_ios_4',
        name: 'iPad Pro',
        ip: '192.168.1.104',
        port: 8088,
        deviceType: DeviceType.tablet,
        platform: 'iOS',
        isOnline: false,
      );

      engine.addPairedDevice(androidDev);
      engine.addPairedDevice(windowsDev);
      engine.addPairedDevice(macDev);
      engine.addPairedDevice(iosDev);

      expect(engine.pairedDevices.length, equals(4));
      expect(engine.pairedDevices.map((d) => d.platform), containsAll(['Android', 'Windows', 'macOS', 'iOS']));

      // Disconnect individual device
      engine.removePairedDevice(macDev.id);
      expect(engine.pairedDevices.length, equals(3));
      expect(engine.pairedDevices.any((d) => d.name == 'MacBook Pro'), isFalse);

      // Disconnect all
      engine.disconnectAllDevices();
      expect(engine.pairedDevices.isEmpty, isTrue);
    });

    test('2. Credential Regeneration: Regenerating code immediately invalidates previous QR and 6-digit codes', () async {
      final initialSession = engine.currentPairingSession;
      expect(initialSession, isNotNull);
      final initialCode = initialSession!.numericCode;
      final initialQrPayload = initialSession.qrPayload;

      // Regenerate credentials
      engine.regeneratePairingCode();

      final newSession = engine.currentPairingSession;
      expect(newSession, isNotNull);
      expect(newSession!.numericCode, isNot(equals(initialCode)));
      expect(newSession.qrPayload, isNot(equals(initialQrPayload)));

      // Verifying invalidation tracking
      expect(engine.isCodeInvalidated(initialCode), isTrue);

      // Pairing with invalidated numeric code must be rejected
      final pairOldCodeResult = await engine.pairWithNumericCode(initialCode);
      expect(pairOldCodeResult, isFalse);

      // Pairing with invalidated QR payload must be rejected
      final pairOldQrResult = await engine.pairWithQrPayload(initialQrPayload);
      expect(pairOldQrResult, isFalse);

      // Pairing with new valid code succeeds
      final pairNewCodeResult = await engine.pairWithNumericCode('772184', deviceName: 'Partner Surface', platform: 'Windows');
      expect(pairNewCodeResult, isTrue);
      expect(engine.pairedDevices.any((d) => d.name == 'Partner Surface'), isTrue);
    });

    test('3. QR Code Pairing: Successfully pairs device from QR URI payload across platforms', () async {
      const qrPayload = 'quickshare://pair?code=845129&sid=test_session_123&host=192.168.1.188&port=8088&name=Galaxy+S24&platform=Android';

      final success = await engine.pairWithQrPayload(qrPayload);
      expect(success, isTrue);

      final paired = engine.pairedDevices.firstWhere((d) => d.name == 'Galaxy S24');
      expect(paired.ip, equals('192.168.1.188'));
      expect(paired.port, equals(8088));
      expect(paired.platform, equals('Android'));
      expect(paired.isOnline, isTrue);
    });

    test('4. Temporary Credentials: No reuse of previous credentials; fresh credentials on launch', () {
      final session1 = engine.currentPairingSession;
      expect(session1, isNotNull);

      // Ending session invalidates credentials
      engine.endPairingSession();
      expect(session1!.isExpired, isTrue);
      expect(engine.isCodeInvalidated(session1.numericCode), isTrue);

      // Re-initializing (simulating app relaunch) generates brand new session
      engine.regeneratePairingCode();
      final session2 = engine.currentPairingSession;
      expect(session2!.numericCode, isNot(equals(session1.numericCode)));
      expect(session2.isActive, isTrue);
    });

    // =========================================================================
    // 2. File Sharing & Multi-Device Recipient Tests
    // =========================================================================
    test('5. File Formats & Content Preservation: Preserves name, format, and raw contents for all file types', () async {
      final recipient = DeviceModel(
        id: 'dev_test_rec',
        name: 'Target Station',
        ip: '192.168.1.200',
        port: 8088,
        platform: 'Linux',
        isOnline: true,
      );
      engine.addPairedDevice(recipient);

      // Test PDF
      final pdfBytes = Uint8List.fromList(utf8.encode('%PDF-1.4 test document content'));
      final pdfTransfer = await engine.sendFileToDevice(
        fileName: 'Invoice_2026.pdf',
        bytes: pdfBytes,
        recipient: recipient,
      );
      expect(pdfTransfer.fileName, equals('Invoice_2026.pdf'));
      expect(pdfTransfer.fileSizeBytes, equals(pdfBytes.length));
      expect(pdfTransfer.rawBytes, equals(pdfBytes));

      // Test Photo / Screenshot (PNG)
      final pngBytes = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3]);
      final pngTransfer = await engine.sendFileToDevice(
        fileName: 'Screenshot_Chart.png',
        bytes: pngBytes,
        recipient: recipient,
      );
      expect(pngTransfer.fileName, equals('Screenshot_Chart.png'));
      expect(pngTransfer.fileSizeBytes, equals(pngBytes.length));
      expect(pngTransfer.rawBytes, equals(pngBytes));

      // Test GIF
      final gifBytes = Uint8List.fromList(utf8.encode('GIF89a sample animation'));
      final gifTransfer = await engine.sendFileToDevice(
        fileName: 'Loader_Animation.gif',
        bytes: gifBytes,
        recipient: recipient,
      );
      expect(gifTransfer.fileName, equals('Loader_Animation.gif'));
      expect(gifTransfer.fileSizeBytes, equals(gifBytes.length));

      // Test Video (MP4)
      final videoBytes = Uint8List.fromList(List.filled(4096, 99));
      final videoTransfer = await engine.sendFileToDevice(
        fileName: 'App_Demo_Recording.mp4',
        bytes: videoBytes,
        recipient: recipient,
      );
      expect(videoTransfer.fileName, equals('App_Demo_Recording.mp4'));
      expect(videoTransfer.fileSizeBytes, equals(4096));

      // Test Document (DOCX / Markdown)
      final docBytes = Uint8List.fromList(utf8.encode('# Specification Document\nDetails here.'));
      final docTransfer = await engine.sendFileToDevice(
        fileName: 'Project_Specification.docx',
        bytes: docBytes,
        recipient: recipient,
      );
      expect(docTransfer.fileName, equals('Project_Specification.docx'));
      expect(docTransfer.rawBytes, equals(docBytes));

      // Test Any/Other binary format
      final customBytes = Uint8List.fromList([0xCA, 0xFE, 0xBA, 0xBE, 42, 100]);
      final customTransfer = await engine.sendFileToDevice(
        fileName: 'Firmware_Patch.bin',
        bytes: customBytes,
        recipient: recipient,
      );
      expect(customTransfer.fileName, equals('Firmware_Patch.bin'));
      expect(customTransfer.rawBytes, equals(customBytes));
    });

    test('6. Multi-Recipient Transmission: Dispatches file to multiple connected devices simultaneously', () async {
      final dev1 = DeviceModel(id: 'dev_1', name: 'MacBook Air', ip: '192.168.1.11', port: 8088, platform: 'macOS', isOnline: true);
      final dev2 = DeviceModel(id: 'dev_2', name: 'Pixel Tablet', ip: '192.168.1.12', port: 8088, platform: 'Android', isOnline: true);
      final dev3 = DeviceModel(id: 'dev_3', name: 'Windows Rig', ip: '192.168.1.13', port: 8088, platform: 'Windows', isOnline: true);

      engine.pairedDevices.addAll([dev1, dev2, dev3]);

      final fileBytes = Uint8List.fromList(List.filled(1024, 7));
      final transfers = await engine.sendFileToMultipleRecipients(
        fileName: 'Shared_Report.pdf',
        bytes: fileBytes,
        recipients: [dev1, dev2, dev3],
      );

      expect(transfers.length, equals(3));
      expect(transfers.map((t) => t.peerDeviceName), containsAll(['MacBook Air', 'Pixel Tablet', 'Windows Rig']));
      expect(engine.activeTransfers.length, greaterThanOrEqualTo(3));
    });

    test('7. Transfer Cancellation & Retry: Allows cancelling active transfers and retrying failed/cancelled transfers', () async {
      final dev = DeviceModel(id: 'dev_cancel_test', name: 'Studio PC', ip: '192.168.1.40', port: 8088, isOnline: true);
      engine.addPairedDevice(dev);

      final dummyBytes = Uint8List.fromList(List.filled(50000, 25));
      final transfer = await engine.sendFileToDevice(
        fileName: 'Heavy_Dataset.zip',
        bytes: dummyBytes,
        recipient: dev,
      );

      // Cancel transfer
      engine.cancelTransfer(transfer.transferId);
      final cancelled = engine.activeTransfers.firstWhere((t) => t.transferId == transfer.transferId);
      expect(cancelled.status, equals(TransferStatus.cancelled));

      // Retry transfer
      final retried = await engine.retryTransfer(transfer.transferId);
      expect(retried, isNotNull);
      expect(retried!.fileName, equals('Heavy_Dataset.zip'));
      expect(retried.status, equals(TransferStatus.transferring));
    });

    // =========================================================================
    // 3. Widget UI Tests for SendFilesView & PairingView
    // =========================================================================
    testWidgets('8. SendFilesView: Renders all file format options, multi-recipients, and multi-send button', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final devA = DeviceModel(id: 'rec_a', name: 'Work Surface', ip: '192.168.1.51', port: 8088, platform: 'Windows', isOnline: true);
      final devB = DeviceModel(id: 'rec_b', name: 'Android Tablet', ip: '192.168.1.52', port: 8088, platform: 'Android', isOnline: true);
      engine.pairedDevices.addAll([devA, devB]);

      final dummyPdf = Uint8List.fromList(List.filled(1024, 9));

      await tester.pumpWidget(
        ChangeNotifierProvider<TransferEngine>.value(
          value: engine,
          child: MaterialApp(
            home: SendFilesView(
              preloadedName: 'Annual_Summary.pdf',
              preloadedBytes: dummyPdf,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify file choosers for all common types
      expect(find.text('PDF File'), findsOneWidget);
      expect(find.text('Photo / Image'), findsOneWidget);
      expect(find.text('GIF Animation'), findsOneWidget);
      expect(find.text('Video'), findsOneWidget);
      expect(find.text('Document'), findsOneWidget);
      expect(find.text('Any File'), findsOneWidget);

      // Verify preloaded file is displayed in selected files
      expect(find.text('Annual_Summary.pdf'), findsOneWidget);

      // Verify both recipients appear in connected recipients
      expect(find.textContaining('Work Surface'), findsWidgets);
      expect(find.textContaining('Android Tablet'), findsWidgets);

      // Tap Select All to choose both devices
      final selectAllBtn = find.text('Select All');
      expect(selectAllBtn, findsOneWidget);
      await tester.tap(selectAllBtn);
      await tester.pumpAndSettle();

      // Button should now read 'Send to 2 Paired Devices'
      final multiSendBtn = find.text('Send to 2 Paired Devices');
      expect(multiSendBtn, findsOneWidget);

      // Tap Send
      await tester.ensureVisible(multiSendBtn);
      await tester.tap(multiSendBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Verifying transfers dispatched to both recipients
      expect(engine.activeTransfers.length, greaterThanOrEqualTo(2));
      final names = engine.activeTransfers.map((t) => t.peerDeviceName).toSet();
      expect(names.contains('Work Surface'), isTrue);
      expect(names.contains('Android Tablet'), isTrue);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('9. PairingView: Displays QR & 6-digit tabs, regeneration control, and connected devices', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final samplePhone = DeviceModel(id: 'phone_10', name: 'Pixel 8', ip: '192.168.1.90', port: 8088, platform: 'Android', isOnline: true);
      engine.pairedDevices.add(samplePhone);

      await tester.pumpWidget(
        ChangeNotifierProvider<TransferEngine>.value(
          value: engine,
          child: const MaterialApp(
            home: PairingView(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Verify two ways to pair tabs
      expect(find.text('Show my QR code'), findsOneWidget);
      expect(find.text('Show my six-digit code'), findsOneWidget);

      // 2. Verify prominent Regenerate control
      expect(find.text('Regenerate QR Code'), findsOneWidget);

      // Switch to 6-digit code tab
      await tester.tap(find.text('Show my six-digit code'));
      await tester.pumpAndSettle();

      expect(find.text('Regenerate 6-Digit Code'), findsOneWidget);

      // 3. Verify Connect to another device section
      expect(find.text('Connect to another device'), findsOneWidget);
      expect(find.text('Enter 6-digit code'), findsOneWidget);
      expect(find.text('Scan QR code'), findsOneWidget);

      // 4. Verify Connected Devices list at bottom
      expect(find.text('Connected Devices'), findsOneWidget);
      expect(find.textContaining('Pixel 8'), findsWidgets);
      expect(find.textContaining('Android'), findsWidgets);
      expect(find.textContaining('Online'), findsWidgets);

      // 5. Verify NO Nearby Devices section
      expect(find.text('Nearby Devices'), findsNothing);
      expect(find.text('DISCOVERED NEARBY DEVICES'), findsNothing);

      await tester.pumpWidget(const SizedBox());
    });

    // =========================================================================
    // 5. Received Items Storage, Persistence, and Download Tests
    // =========================================================================
    test('10. Received Items: Every received file is stored in Received Items, preserving original name, format, and contents', () async {
      SharedPreferences.setMockInitialValues({});

      final rawPdfBytes = Uint8List.fromList([0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x34]); // %PDF-1.4
      final rawImageBytes = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]); // PNG header
      final rawDocBytes = Uint8List.fromList([0x50, 0x4B, 0x03, 0x04, 0x00, 0x00]); // ZIP / DOCX header

      // 1. Receive PDF from Android device
      engine.receiveIncomingTransfer(
        senderDeviceName: 'Pixel 8 Pro (Android)',
        fileName: 'Q4_Financial_Report.pdf',
        bytes: rawPdfBytes,
        fileType: ReceivedFileType.pdf,
      );

      // 2. Receive Image from iOS device
      engine.receiveIncomingTransfer(
        senderDeviceName: 'iPad Pro (iOS)',
        fileName: 'Project_Design_Mockup.png',
        bytes: rawImageBytes,
        fileType: ReceivedFileType.image,
      );

      // 3. Receive Document from Windows device
      engine.receiveIncomingTransfer(
        senderDeviceName: 'Desktop PC (Windows)',
        fileName: 'Contract_Agreement_2026.docx',
        bytes: rawDocBytes,
        fileType: ReceivedFileType.document,
      );

      // Verify all 3 files are stored in Received Items
      expect(engine.receivedItems.length, equals(3));

      final docItem = engine.receivedItems.firstWhere((i) => i.fileName == 'Contract_Agreement_2026.docx');
      expect(docItem.fileType, equals(ReceivedFileType.document));
      expect(docItem.bytes, equals(rawDocBytes));
      expect(docItem.senderDeviceName, equals('Desktop PC (Windows)'));

      final imgItem = engine.receivedItems.firstWhere((i) => i.fileName == 'Project_Design_Mockup.png');
      expect(imgItem.fileType, equals(ReceivedFileType.image));
      expect(imgItem.bytes, equals(rawImageBytes));
      expect(imgItem.senderDeviceName, equals('iPad Pro (iOS)'));

      final pdfItem = engine.receivedItems.firstWhere((i) => i.fileName == 'Q4_Financial_Report.pdf');
      expect(pdfItem.fileType, equals(ReceivedFileType.pdf));
      expect(pdfItem.bytes, equals(rawPdfBytes));
      expect(pdfItem.senderDeviceName, equals('Pixel 8 Pro (Android)'));

      // Verify fileDataStore holds original binary contents
      expect(engine.fileDataStore['Q4_Financial_Report.pdf'], equals(rawPdfBytes));
      expect(engine.fileDataStore['Project_Design_Mockup.png'], equals(rawImageBytes));
      expect(engine.fileDataStore['Contract_Agreement_2026.docx'], equals(rawDocBytes));
    });

    test('11. Received Items: Persists across app close and reopen, preserving files and contents', () async {
      SharedPreferences.setMockInitialValues({});

      final rawPdfBytes = Uint8List.fromList([10, 20, 30, 40, 50, 60, 70, 80]);
      engine.receiveIncomingTransfer(
        senderDeviceName: 'Galaxy S24 (Android)',
        fileName: 'Network_Topology_Diagram.pdf',
        bytes: rawPdfBytes,
        fileType: ReceivedFileType.pdf,
      );
      await engine.saveReceivedItems();

      // Verify item stored
      expect(engine.receivedItems.any((i) => i.fileName == 'Network_Topology_Diagram.pdf'), isTrue);

      // Simulate app closing and clearing volatile memory
      engine.receivedItems.clear();
      engine.fileDataStore.clear();
      expect(engine.receivedItems.isEmpty, isTrue);
      expect(engine.fileDataStore.isEmpty, isTrue);

      // Simulate app reopening and reloading persisted state
      await engine.loadPersistedState();

      // Verify received items and byte contents are fully restored
      expect(engine.receivedItems.length, greaterThanOrEqualTo(1));
      final restored = engine.receivedItems.firstWhere((i) => i.fileName == 'Network_Topology_Diagram.pdf');
      expect(restored.fileName, equals('Network_Topology_Diagram.pdf'));
      expect(restored.senderDeviceName, equals('Galaxy S24 (Android)'));
      expect(restored.fileType, equals(ReceivedFileType.pdf));
      expect(restored.bytes, equals(rawPdfBytes));
      expect(engine.fileDataStore['Network_Topology_Diagram.pdf'], equals(rawPdfBytes));
    });

    testWidgets('12. ReceivedItemsView: Shows received files list with Download / Save to device option', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      SharedPreferences.setMockInitialValues({});
      engine.receivedItems.clear();

      final sampleBytes = Uint8List.fromList([1, 2, 3, 4, 5]);
      engine.receiveIncomingTransfer(
        senderDeviceName: 'MacBook Air (macOS)',
        fileName: 'Presentation_Slides.pdf',
        bytes: sampleBytes,
        fileType: ReceivedFileType.pdf,
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<TransferEngine>.value(
          value: engine,
          child: const MaterialApp(
            home: ReceivedItemsView(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Verify file item in list
      expect(find.text('Presentation_Slides.pdf'), findsOneWidget);
      expect(find.textContaining('MacBook Air (macOS)'), findsWidgets);

      // 2. Verify prominent Download button exists for the item
      expect(find.widgetWithText(ElevatedButton, 'Download'), findsWidgets);

      // 3. Tap Download button to verify download/save action triggers
      final downloadBtn = find.widgetWithText(ElevatedButton, 'Download').first;
      await tester.tap(downloadBtn);
      await tester.pumpAndSettle();

      // Verify item download state is marked true
      final item = engine.receivedItems.firstWhere((i) => i.fileName == 'Presentation_Slides.pdf');
      expect(item.isDownloaded, isTrue);

      await tester.pumpWidget(const SizedBox());
    });
  });
}

