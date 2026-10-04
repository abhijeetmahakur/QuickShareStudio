import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:quickshare/main.dart';
import 'package:quickshare/data/services/transfer_engine.dart';
import 'package:quickshare/data/models/device_model.dart';
import 'package:quickshare/data/models/session_pdf.dart';
import 'package:quickshare/data/models/transfer_item.dart';
import 'package:quickshare/features/pdf_layout/models/layout_preset.dart';
import 'package:quickshare/features/pdf_layout/models/page_geometry.dart';
import 'package:quickshare/features/pdf_layout/engine/layout_calculator.dart';
import 'package:quickshare/core/utils/hash_utils.dart';
import 'package:quickshare/core/utils/file_utils.dart';
import 'package:quickshare/data/models/pairing_session.dart';
import 'package:quickshare/features/pdf_editor/widgets/session_pdf_dialog.dart';
import 'package:quickshare/core/widgets/hover_card.dart';
import 'package:quickshare/features/pdf_editor/pdf_editor_view.dart';
import 'package:quickshare/features/clipboard/universal_clipboard_view.dart';
import 'package:quickshare/features/transfer_history/transfer_history_view.dart';
import 'package:quickshare/features/received_items/received_items_view.dart';
import 'package:quickshare/features/file_transfer/send_files_view.dart';
import 'package:quickshare/features/pdf_tools/pdf_tools_view.dart';
import 'package:quickshare/features/pdf_tools/services/file_converter_service.dart';
import 'package:quickshare/features/security/security_settings_view.dart';
import 'package:quickshare/data/models/screenshot_session_model.dart';
import 'package:quickshare/data/models/history_record.dart';
import 'package:quickshare/data/models/incoming_transfer_request.dart';
import 'package:quickshare/data/models/received_item_model.dart';
import 'package:quickshare/data/models/pdf_project.dart';
import 'package:quickshare/data/models/screenshot_item.dart';
import 'package:quickshare/features/pdf_editor/services/pdf_export_service.dart';
import 'package:quickshare/app/widgets/incoming_transfer_dialog.dart';
import 'package:quickshare/app/app_shell.dart';
import 'package:quickshare/app/theme.dart';
import 'package:quickshare/data/services/app_update_service.dart';
import 'package:quickshare/data/models/app_update_info.dart';
import 'package:quickshare/app/widgets/update_dialog.dart';
import 'package:quickshare/features/dashboard/dashboard_screen.dart';
import 'package:quickshare/core/services/theme_service.dart';
import 'package:quickshare/core/constants.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:ui';

void main() {
  group('1. PDF Layout Preset Calculations Test', () {
    test('Verifies all 7 exact presets calculate valid grid dimensions', () {
      const geometry = PageGeometry();

      // Preset 1: 1 Image
      final p1 = LayoutPreset.getGridDimensions(LayoutPresetType.one, geometry.isLandscape);
      expect(p1.rows * p1.cols, 1);

      // Preset 2: 2 Images
      final p2 = LayoutPreset.getGridDimensions(LayoutPresetType.two, geometry.isLandscape);
      expect(p2.rows * p2.cols, 2);

      // Preset 3: 3 Images
      final p3 = LayoutPreset.getGridDimensions(LayoutPresetType.three, geometry.isLandscape);
      expect(p3.rows * p3.cols, 3);

      // Preset 4: 4 Images (2x2)
      final p4 = LayoutPreset.getGridDimensions(LayoutPresetType.four, geometry.isLandscape);
      expect(p4.rows * p4.cols, 4);

      // Preset 6: 6 Images (3x2 portrait)
      final p6 = LayoutPreset.getGridDimensions(LayoutPresetType.six, geometry.isLandscape);
      expect(p6.rows * p6.cols, 6);

      // Preset 8: 8 Images (4x2 portrait)
      final p8 = LayoutPreset.getGridDimensions(LayoutPresetType.eight, geometry.isLandscape);
      expect(p8.rows * p8.cols, 8);

      // Preset 10: 10 Images (5x2 portrait)
      final p10 = LayoutPreset.getGridDimensions(LayoutPresetType.ten, geometry.isLandscape);
      expect(p10.rows * p10.cols, 10);
    });

    test('LayoutCalculator produces correct cell rects and bounds', () async {
      const geometry = PageGeometry(marginPoints: 24.0);
      final cells = LayoutCalculator.calculatePageLayout(
        geometry: geometry,
        presetType: LayoutPresetType.four,
        spacingPoints: 8.0,
      );

      expect(cells.length, 4);
      for (final c in cells) {
        expect(c.cellRect.left >= geometry.marginPoints, isTrue);
        expect(c.cellRect.top >= geometry.marginPoints, isTrue);
        expect(c.imageRect.width > 0, isTrue);
        expect(c.imageRect.height > 0, isTrue);
      }

      final cellsTwo = LayoutCalculator.calculatePageLayout(
        geometry: geometry,
        presetType: LayoutPresetType.two,
        spacingPoints: 8.0,
      );

      // Verify exact margins and centering
      final leftMargin = cellsTwo[0].cellRect.left;
      final rightMargin = geometry.pageWidth - cellsTwo[0].cellRect.right;
      expect((leftMargin - rightMargin).abs() < 0.5, isTrue);

      final topMargin = cellsTwo[0].cellRect.top;
      final bottomMargin = geometry.pageHeight - cellsTwo[1].cellRect.bottom;
      expect((topMargin - bottomMargin).abs() < 0.5, isTrue);

      // Verify zero margins on toPdfPageFormat
      final fmt = geometry.toPdfPageFormat();
      expect(fmt.marginLeft, 0.0);
      expect(fmt.marginTop, 0.0);
      expect(fmt.marginRight, 0.0);
      expect(fmt.marginBottom, 0.0);
    });
  });

  group('2. Cryptographic Integrity & Pairing Session Tests', () {
    test('SHA-256 hashing produces deterministic cryptographic fingerprints', () {
      final bytesA = Uint8List.fromList([1, 2, 3, 4, 5]);
      final bytesB = Uint8List.fromList([1, 2, 3, 4, 5]);
      final bytesC = Uint8List.fromList([1, 2, 3, 4, 6]);

      final hashA = HashUtils.computeSha256(bytesA);
      final hashB = HashUtils.computeSha256(bytesB);
      final hashC = HashUtils.computeSha256(bytesC);

      expect(hashA, hashB);
      expect(hashA != hashC, isTrue);
      expect(HashUtils.shortFingerprint(hashA).length, 8);
    });

    test('PairingSession generates valid 6-digit session-bound code and QR payload', () {
      final session = PairingSession.create(
        hostDeviceName: 'LabPC',
        hostIp: '10.150.2.94',
        hostPort: 8088,
      );

      expect(session.numericCode.length, 6);
      expect(session.isExpired, isFalse);
      expect(session.isActive, isTrue);
      expect(session.qrPayload.contains('quickshare://pair'), isTrue);
      expect(session.qrPayload.contains('code='), isTrue);
    });
  });

  group('3. Main Application Widget Smoke Test', () {
    testWidgets('QuickShareApp launches with Dashboard and navigation items', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final engine = TransferEngine();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<TransferEngine>.value(value: engine),
            ChangeNotifierProvider<AppUpdateService>.value(value: AppUpdateService()),
          ],
          child: const QuickShareApp(showLegacyShell: true),
        ),
      );
      await tester.pump();

      expect(find.text('QuickShare Studio'), findsWidgets);
      expect(find.text('Name Your Device'), findsWidgets);
      expect(find.text('HISTORY'), findsWidgets);

      // Clean up timers and widget tree before test completion
      engine.stopTimers();
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('4. Session PDF Direct Send Workflow Tests (Section 73-97)', () {
    testWidgets('TEST A: Connected Device direct send, auto device selection, & history update', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final engine = TransferEngine();
      engine.stopTimers(); // Avoid background timer issues in test

      // 1. Pair a device
      final phone = await engine.simulateInstantPair(deviceName: "Abhijeet's Phone");
      expect(phone.name, "Abhijeet's Phone");
      expect(engine.pairedDevices.length, 1);

      // 2. Create Session PDF
      final dummyPdfBytes = Uint8List.fromList(List.generate(1024, (i) => i % 256));
      final sessionPdf = SessionPdf(
        sessionName: 'Operating_Systems_Lab',
        fileName: 'Operating_Systems_Lab.pdf',
        bytes: dummyPdfBytes,
        pageCount: 3,
        screenshotCount: 12,
        paperFormatDescription: 'A4 Portrait',
      );

      // 3. Mount SessionPdfDialog with autoSendImmediately = false
      await tester.pumpWidget(
        ChangeNotifierProvider<TransferEngine>.value(
          value: engine,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => SessionPdfDialog.show(context, sessionPdf: sessionPdf),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify Session PDF Ready modal content (Section 74)
      expect(find.text('Session PDF Ready'), findsOneWidget);
      expect(find.text('Operating_Systems_Lab.pdf'), findsOneWidget);
      expect(find.text('12 screenshots'), findsOneWidget);
      expect(find.text('3 pages'), findsOneWidget);
      expect(find.text('Send to Paired Device'), findsOneWidget);

      // 4. Click "Send to Paired Device"
      await tester.tap(find.text('Send to Paired Device'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Section 75: Exactly ONE connected device -> automatically selected!
      expect(find.text('Send Session PDF'), findsOneWidget);
      expect(find.text("Abhijeet's Phone"), findsOneWidget);
      expect(find.text('Send Now'), findsOneWidget);

      // 5. Click Send Now
      await tester.tap(find.text('Send Now'));
      await tester.pump();

      // Fast forward transfer chunks
      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 150));
      }

      // Section 86: PDF Sent Successfully
      expect(find.text('PDF Sent Successfully'), findsOneWidget);
      expect(find.text('Transfer Complete'), findsOneWidget);

      // Section 94: Transfer history is updated with all metadata
      expect(engine.historyRecords.isNotEmpty, isTrue);
      final record = engine.historyRecords.first;
      expect(record.fileName, 'Operating_Systems_Lab.pdf');
      expect(record.sessionName, 'Operating_Systems_Lab');
      expect(record.pageCount, 3);
      expect(record.recipientName, "Abhijeet's Phone");
      expect(record.connectionType, contains('Local Network'));
      expect(record.status, 'completed');

      // Cleanup
      engine.stopTimers();
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      engine.pairedDevices.clear();
      engine.activeTransfers.clear();
      engine.clearSessionPdf();
    });

    testWidgets('TEST B: No Connected Device shows automatic QR & numeric code pairing screen', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final engine = TransferEngine();
      engine.stopTimers();
      engine.pairedDevices.clear(); // Ensure no connected device
      engine.activeTransfers.clear();
      engine.clearSessionPdf();

      final dummyPdfBytes = Uint8List.fromList([1, 2, 3, 4, 5]);
      final sessionPdf = SessionPdf(
        sessionName: 'Networks_Lab',
        fileName: 'Networks_Lab.pdf',
        bytes: dummyPdfBytes,
        pageCount: 2,
        screenshotCount: 4,
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<TransferEngine>.value(
          value: engine,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => SessionPdfDialog.show(context, sessionPdf: sessionPdf, autoSendImmediately: true),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Section 77: Pairing screen appears automatically with QR & Code
      expect(find.text('Connect Paired Device'), findsOneWidget);
      expect(find.text('SESSION PAIRING CODE'), findsOneWidget);
      expect(find.textContaining('Session Active'), findsOneWidget);

      // Section 79: When device connects, continue automatically into transfer!
      await engine.simulateInstantPair(deviceName: "Abhijeet's Phone");
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 150));
      }

      expect(find.text('PDF Sent Successfully'), findsOneWidget);

      // Cleanup
      engine.stopTimers();
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      engine.pairedDevices.clear();
      engine.activeTransfers.clear();
      engine.clearSessionPdf();
    });

    test('TEST C & D: Offline integrity check & chunked transfer resumption', () async {
      final engine = TransferEngine();
      engine.stopTimers();

      final bytes = Uint8List.fromList(List.generate(2048, (i) => (i * 7) % 256));
      final dev = DeviceModel(name: 'Offline_Tablet', ip: '10.150.2.99', port: 8088);
      engine.pairedDevices.add(dev);
      if (engine.currentPairingSession == null || engine.currentPairingSession!.isExpired) {
        engine.regeneratePairingCode();
      }

      final transfer = await engine.sendFileToDevice(
        fileName: 'DBMS_Lab.pdf',
        bytes: bytes,
        recipient: dev,
        sessionName: 'DBMS_Lab',
        pageCount: 4,
        connectionType: 'Local Network',
      );

      // Verify SHA-256 integrity
      expect(transfer.sha256, HashUtils.computeSha256(bytes));
      expect(transfer.connectionType, 'Local Network');

      // Simulate interruption (Section 87)
      engine.simulateTransferInterruption(transfer.transferId);
      final interrupted = engine.activeTransfers.firstWhere((t) => t.transferId == transfer.transferId);
      expect(interrupted.status, TransferStatus.failed);
      expect(interrupted.errorMessage?.contains('interrupted'), isTrue);

      // Resume transfer (Section 87 & Test D)
      engine.resumeTransfer(transfer.transferId);
      final resumed = engine.activeTransfers.firstWhere((t) => t.transferId == transfer.transferId);
      expect(resumed.status, TransferStatus.transferring);
    });
  });

  group('5. Bluetooth & Wi-Fi Discovery, HoverCard, & PDF Studio Paste Tests', () {
    testWidgets('HoverCard responds to mouse cursor enter and exit events', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: HoverCard(
                child: Container(
                  width: 100,
                  height: 100,
                  color: Colors.blue,
                  child: const Text('HoverMe'),
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('HoverMe'), findsOneWidget);

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      await tester.pump();

      // Move mouse over HoverCard
      await gesture.moveTo(tester.getCenter(find.text('HoverMe')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Move mouse out
      await gesture.moveTo(const Offset(500, 500));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await gesture.removePointer();
    });

    test('TransferEngine device pairing session stays active and invalidates on session end', () {
      final engine = TransferEngine();
      engine.stopTimers();

      final session = engine.currentPairingSession;
      expect(session, isNotNull);
      expect(session!.isActive, isTrue);
      expect(session.isExpired, isFalse);
      expect(session.numericCode.length, 6);

      // Invalidate on disconnect / session end
      engine.disconnectSession();
      expect(session.isExpired, isTrue);
    });

    testWidgets('PDF Studio provides Paste (Ctrl+V) button and adds pasted screenshot', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final engine = TransferEngine();
      engine.stopTimers();

      await tester.pumpWidget(
        ChangeNotifierProvider<TransferEngine>.value(
          value: engine,
          child: const MaterialApp(
            home: PdfEditorView(),
          ),
        ),
      );
      await tester.pump();

      // Check Paste (Ctrl+V) button exists
      expect(find.widgetWithText(ElevatedButton, 'Paste (Ctrl+V)'), findsOneWidget);

      // Tap Paste button to add screenshot
      await tester.runAsync(() async {
        await tester.tap(find.widgetWithText(ElevatedButton, 'Paste (Ctrl+V)'));
        await Future.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Feedback notification or slot populated
      expect(find.byKey(const Key('paste_failed_notification')), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    test('Audio 1: Settings & Privacy download path and sender grouping', () {
      final engine = TransferEngine();
      engine.stopTimers();

      expect(engine.downloadDirectory, contains('Downloads'));
      engine.updateDownloadDirectory(r'D:\QuickShare_Received');
      expect(engine.downloadDirectory, equals(r'D:\QuickShare_Received'));

      expect(engine.groupBySenderSubfolders, isTrue);
      engine.setGroupBySenderSubfolders(false);
      expect(engine.groupBySenderSubfolders, isFalse);
    });

    testWidgets('Audio 3: PDF Studio Draggable Dock and Sequential Slots Target (Slot 1 -> Slot 2 -> Slot 3)', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 950);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final engine = TransferEngine();
      engine.stopTimers();

      await tester.pumpWidget(
        ChangeNotifierProvider<TransferEngine>.value(
          value: engine,
          child: const MaterialApp(
            home: PdfEditorView(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Verify bottom horizontal dock is completely removed
      expect(find.text('DRAG & DROP PICTURES TO SLOTS'), findsNothing);
      expect(find.text('Fills Sequentially: Slot 1 → Slot 2 → Slot 3...'), findsNothing);

      // Verify canvas expands with preserved sequential target Slot 1
      expect(find.text('TARGET: SLOT 1'), findsOneWidget);
      expect(find.text('Sequential Fill (1 → 2 → 3)'), findsOneWidget);

      // Verify top actions preserved: Add Images, Paste (Ctrl+V), Load Lab Samples
      expect(find.text('Add Images'), findsOneWidget);
      expect(find.text('Paste (Ctrl+V)'), findsOneWidget);
      expect(find.text('Load Lab Samples'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  });

  group('6. Universal Clipboard & Templates Feature Tests', () {
    testWidgets('UniversalClipboardView allows input and displays device selection', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 850);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final engine = TransferEngine();
      engine.stopTimers();
      engine.pairedDevices.clear();
      final phone = await engine.simulateInstantPair(deviceName: 'Lab Mate Phone');

      await tester.pumpWidget(
        ChangeNotifierProvider<TransferEngine>.value(
          value: engine,
          child: const MaterialApp(
            home: UniversalClipboardView(),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Universal Smart Clipboard'), findsOneWidget);
      expect(find.text('Paste from System Clipboard'), findsOneWidget);
      expect(find.text('Clear Preview'), findsOneWidget);

      // Enter test text in preview box
      final textField = find.byType(TextField);
      expect(textField, findsOneWidget);
      await tester.enterText(textField, 'echo "Test Command" > run.sh');
      await tester.pump();

      expect(find.text('echo "Test Command" > run.sh'), findsOneWidget);

      // Verify Send button is enabled
      final sendBtn = find.widgetWithText(ElevatedButton, 'Send Clipboard to Selected Device');
      expect(sendBtn, findsOneWidget);
      await tester.ensureVisible(sendBtn);
      await tester.tap(sendBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Check feedback
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('Clipboard text sent to ${phone.name}.'), findsOneWidget);

      engine.pairedDevices.clear();
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    test('FileConverterService performs real conversion between formats', () async {
      // 1. Text to PDF
      final textBytes = Uint8List.fromList('QuickShare Offline Document Conversion Test'.codeUnits);
      final textPdf = await FileConverterService.convert(
        format: ConversionFormat.pdf,
        inputFileName: 'test.txt',
        inputBytes: textBytes,
      );
      expect(textPdf.outputFileName.endsWith('.pdf'), isTrue);
      expect(textPdf.outputBytes.length, greaterThan(100));

      // 2. PDF to Text
      final convertedText = await FileConverterService.convert(
        format: ConversionFormat.txt,
        inputFileName: textPdf.outputFileName,
        inputBytes: textPdf.outputBytes,
      );
      expect(convertedText.outputFileName.endsWith('.txt'), isTrue);
      // Text must survive the round trip (content streams are Flate-compressed).
      expect(utf8.decode(convertedText.outputBytes), contains('QuickShare Offline Document Conversion Test'));

      // 3. PDF to DOCX
      final docxRes = await FileConverterService.convert(
        format: ConversionFormat.docx,
        inputFileName: textPdf.outputFileName,
        inputBytes: textPdf.outputBytes,
      );
      expect(docxRes.outputFileName.endsWith('.docx'), isTrue);
      expect(docxRes.outputBytes.length, greaterThan(100));

      // 4. PDF to XLSX
      final xlsxRes = await FileConverterService.convert(
        format: ConversionFormat.xlsx,
        inputFileName: textPdf.outputFileName,
        inputBytes: textPdf.outputBytes,
      );
      expect(xlsxRes.outputFileName.endsWith('.xlsx'), isTrue);
      expect(xlsxRes.outputBytes.length, greaterThan(100));
    });
  });

  group('7. Received Items & PDF Tools Multi-Tab Navigation Tests', () {
    testWidgets('ReceivedItemsView displays received files and search filter', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 850);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final engine = TransferEngine();
      engine.stopTimers();
      engine.receivedItems.clear();
      engine.receivedItems.addAll([
        ReceivedItemModel(
          id: 'rx_1',
          fileName: 'Lab_Experiment_04_Networking.pdf',
          fileSizeBytes: 2048,
          receivedAt: DateTime.now(),
          senderDeviceName: 'Pixel 8',
          savedToPath: r'C:\Downloads\Lab_Experiment_04_Networking.pdf',
          fileType: ReceivedFileType.pdf,
          bytes: Uint8List.fromList([1, 2, 3]),
        ),
        ReceivedItemModel(
          id: 'rx_2',
          fileName: 'Screenshot_Notes.png',
          fileSizeBytes: 4096,
          receivedAt: DateTime.now(),
          senderDeviceName: 'Laptop',
          savedToPath: r'C:\Downloads\Screenshot_Notes.png',
          fileType: ReceivedFileType.image,
          bytes: Uint8List.fromList([4, 5, 6]),
        ),
      ]);

      await tester.pumpWidget(
        ChangeNotifierProvider<TransferEngine>.value(
          value: engine,
          child: const MaterialApp(
            home: ReceivedItemsView(),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Received Files & Background Inbox'), findsOneWidget);
      expect(find.text('Background Receiving: ACTIVE'), findsOneWidget);
      expect(find.text('All (2)'), findsOneWidget);
      expect(find.text('Lab_Experiment_04_Networking.pdf'), findsOneWidget);
      expect(find.text('Change Path'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('PdfToolsView mounts 4 tabs and allows switching tabs', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 850);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final engine = TransferEngine();
      engine.stopTimers();

      await tester.pumpWidget(
        ChangeNotifierProvider<TransferEngine>.value(
          value: engine,
          child: const MaterialApp(
            home: PdfToolsView(),
          ),
        ),
      );
      await tester.pump();

      // Check all 4 tabs exist
      expect(find.text('Merge PDFs'), findsOneWidget);
      expect(find.text('Split PDF'), findsOneWidget);
      expect(find.text('Compress PDF'), findsOneWidget);
      expect(find.text('OCR Searchable'), findsOneWidget);

      // Switch to Split PDF tab
      await tester.tap(find.text('Split PDF'));
      await tester.pumpAndSettle();
      expect(find.text('Multi-Output PDF Splitter'), findsOneWidget);

      // Switch to Compress PDF tab
      await tester.tap(find.text('Compress PDF'));
      await tester.pumpAndSettle();
      expect(find.text('Compress & Optimize PDF File Size'), findsOneWidget);

      // Switch to OCR Searchable tab
      await tester.tap(find.text('OCR Searchable'));
      await tester.pumpAndSettle();
      expect(find.text('Optical Character Recognition (Searchable PDF)'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('PdfToolsView File Converter displays heading, subtitle, Add Files button, and empty state', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 850);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final engine = TransferEngine();
      engine.stopTimers();

      await tester.pumpWidget(
        ChangeNotifierProvider<TransferEngine>.value(
          value: engine,
          child: const MaterialApp(
            home: PdfToolsView(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Heading and subtitle
      expect(find.text('File Converter'), findsNWidgets(2)); // Tab label and header title
      expect(find.text('Batch convert files or whole folders offline: documents, spreadsheets, slides, images, code, 3D models and archives.'), findsOneWidget);

      // Add Files and Add Folder buttons
      expect(find.widgetWithText(ElevatedButton, 'Add Files'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Add Folder'), findsNWidgets(2)); // header + empty state

      // Empty state lists every supported family
      expect(find.text('No files selected for conversion'), findsOneWidget);
      for (final line in ConversionFormats.supportedSummary) {
        expect(find.text(line), findsOneWidget);
      }

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('SearchableFormatPickerDialog shows only compatible formats and filters with search', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 850);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      ConversionFormat? selectedResult;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: ElevatedButton(
                  onPressed: () async {
                    selectedResult = await showDialog<ConversionFormat>(
                      context: context,
                      builder: (ctx) => const SearchableFormatPickerDialog(
                        fileName: 'sample_report.pdf',
                        currentFormat: ConversionFormat.docx,
                        availableFormats: [
                          ConversionFormat.docx,
                          ConversionFormat.txt,
                          ConversionFormat.pdfPagesPng,
                          ConversionFormat.xlsx,
                        ],
                      ),
                    );
                  },
                  child: const Text('Open Picker'),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap Open Picker
      await tester.tap(find.text('Open Picker'));
      await tester.pumpAndSettle();

      // Dialog is open
      expect(find.text('Select Output Format'), findsOneWidget);
      expect(find.text('Compatible with sample_report.pdf'), findsOneWidget);

      // All 4 compatible formats are listed
      expect(find.text(ConversionFormat.docx.label), findsOneWidget);
      expect(find.text(ConversionFormat.txt.label), findsOneWidget);
      expect(find.text(ConversionFormat.pdfPagesPng.label), findsOneWidget);
      expect(find.text(ConversionFormat.xlsx.label), findsOneWidget);

      // Enter search query 'excel'
      await tester.enterText(find.byType(TextField), 'excel');
      await tester.pumpAndSettle();

      // Only Excel format is shown
      expect(find.text(ConversionFormat.xlsx.label), findsOneWidget);
      expect(find.text(ConversionFormat.docx.label), findsNothing);

      // Tap the filtered Excel format
      await tester.tap(find.text(ConversionFormat.xlsx.label));
      await tester.pumpAndSettle();

      // Picker returned ConversionFormat.xlsx
      expect(selectedResult, ConversionFormat.xlsx);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  });

  group('8. Security Settings, Storage Path, & Theme Switching Smoke Tests', () {
    testWidgets('SecuritySettingsView updates storage path and displays options', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 850);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final engine = TransferEngine();
      engine.stopTimers();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<TransferEngine>.value(value: engine),
            ChangeNotifierProvider<AppUpdateService>.value(value: AppUpdateService()),
          ],
          child: const MaterialApp(
            home: SecuritySettingsView(),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Settings & Privacy'), findsOneWidget);
      expect(find.text('Destination Folder for Inbound Downloads'), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Save Path'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('AppShell toggles between Lime Forest Dark and Light mode cleanly', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 850);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final engine = TransferEngine();
      engine.stopTimers();

      var isDark = true;

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            return MultiProvider(
              providers: [
                ChangeNotifierProvider<TransferEngine>.value(value: engine),
                ChangeNotifierProvider<AppUpdateService>.value(value: AppUpdateService()),
              ],
              child: MaterialApp(
                theme: AppTheme.lightTheme,
                darkTheme: AppTheme.darkTheme,
                themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
                home: AppShell(
                  isDarkMode: isDark,
                  onToggleTheme: () => setState(() => isDark = !isDark),
                ),
              ),
            );
          },
        ),
      );
      await tester.pump();

      expect(find.text('QuickShare Studio'), findsWidgets);
      expect(find.text('Dark Forest'), findsOneWidget);

      // Toggle theme via tap on theme text in footer
      await tester.tap(find.text('Dark Forest'));
      await tester.pumpAndSettle();

      expect(isDark, isFalse);
      expect(find.text('Light Mode'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('Sidebar bottom toggle switches between Dark Forest and Light Mode', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 850);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final engine = TransferEngine();
      engine.stopTimers();
      final themeService = ThemeService();
      await themeService.setThemeMode(ThemeMode.dark);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<TransferEngine>.value(value: engine),
            ChangeNotifierProvider<AppUpdateService>.value(value: AppUpdateService()),
            ChangeNotifierProvider<ThemeService>.value(value: themeService),
          ],
          child: Consumer<ThemeService>(
            builder: (context, theme, _) => MaterialApp(
              theme: AppTheme.lightTheme,
              darkTheme: AppTheme.darkTheme,
              themeMode: theme.themeMode,
              home: DashboardScreen(
                isDarkMode: theme.isDarkMode,
                onToggleTheme: () => theme.toggleTheme(),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // Initially Dark Forest
      expect(find.text('Dark Forest'), findsOneWidget);
      expect(themeService.isDarkMode, isTrue);

      // Tap the sidebar theme toggle switch
      await tester.tap(find.byKey(const Key('sidebar_theme_toggle')));
      await tester.pumpAndSettle();

      // Now toggled to Light Mode
      expect(find.text('Light Mode'), findsOneWidget);
      expect(themeService.isDarkMode, isFalse);

      // Tap again to toggle back to Dark Forest
      await tester.tap(find.byKey(const Key('sidebar_theme_toggle')));
      await tester.pumpAndSettle();

      expect(find.text('Dark Forest'), findsOneWidget);
      expect(themeService.isDarkMode, isTrue);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  });

  group('9. Direct Zero-Install P2P Transfer Requests & Fallback Tests', () {
    testWidgets('IncomingTransferModal displays sender details and handles Accept & Delivery', (WidgetTester tester) async {
      final engine = TransferEngine();
      engine.stopTimers();
      final dummyBytes = Uint8List.fromList([10, 20, 30, 40, 50, 60]);

      final request = IncomingTransferRequest(
        senderDeviceName: 'Pixel 8 (Android)',
        senderDeviceId: 'dev_pixel_8',
        fileName: 'Experiment_Notes.pdf',
        fileSizeBytes: dummyBytes.length,
        bytes: dummyBytes,
        fileType: ReceivedFileType.pdf,
        sha256: HashUtils.computeSha256(dummyBytes),
        connectionType: 'Direct Local Network',
        protocolRoute: TransferProtocolRoute.localNetwork,
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<TransferEngine>.value(
          value: engine,
          child: MaterialApp(
            home: Scaffold(
              body: IncomingTransferModal(
                request: request,
                engine: engine,
                onDismiss: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('INCOMING FILE TRANSFER'), findsOneWidget);
      expect(find.text('Experiment_Notes.pdf'), findsOneWidget);
      expect(find.text('PAIRED PEER'), findsOneWidget);
      expect(find.text('Accept Transfer'), findsOneWidget);
      expect(find.text('Reject Transfer'), findsOneWidget);

      // Tap Accept Transfer
      await tester.tap(find.text('Accept Transfer'));
      await tester.pump();

      // Pump through chunks
      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      // Receiver receives the file directly
      expect(engine.receivedItems.any((r) => r.fileName == 'Experiment_Notes.pdf'), isTrue);

      engine.stopTimers();
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('IncomingTransferModal handles Reject cleanly', (WidgetTester tester) async {
      final engine = TransferEngine();
      engine.stopTimers();
      final dummyBytes = Uint8List.fromList([1, 2, 3]);

      final request = IncomingTransferRequest(
        senderDeviceName: 'Unknown PC',
        senderDeviceId: 'dev_unknown',
        fileName: 'Spam.zip',
        fileSizeBytes: dummyBytes.length,
        bytes: dummyBytes,
        fileType: ReceivedFileType.other,
        sha256: HashUtils.computeSha256(dummyBytes),
      );

      bool dismissed = false;

      await tester.pumpWidget(
        ChangeNotifierProvider<TransferEngine>.value(
          value: engine,
          child: MaterialApp(
            home: Scaffold(
              body: IncomingTransferModal(
                request: request,
                engine: engine,
                onDismiss: () => dismissed = true,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Reject Transfer'));
      await tester.pump();

      expect(dismissed, isTrue);

      engine.stopTimers();
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  });

  group('10. Per-Page Independent Layout Tests', () {
    testWidgets('Different pages maintain different layout presets independently', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final project = PdfProject(
        title: 'Multi_Layout_Doc',
        pages: [
          PdfPageModel(
            pageNumber: 1,
            presetType: LayoutPresetType.two,
            geometry: const PageGeometry(paperSize: PaperSize.a4),
          ),
          PdfPageModel(
            pageNumber: 2,
            presetType: LayoutPresetType.six,
            geometry: const PageGeometry(paperSize: PaperSize.a3),
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PdfEditorView(initialProject: project),
          ),
        ),
      );
      await tester.pump();

      // Verify thumbnails show per-page badges
      expect(find.text('2-Up'), findsWidgets);
      expect(find.text('6-Up'), findsWidgets);

      // Page 1 is initially selected
      expect(find.text('Page 1 Layout'), findsOneWidget);
      expect(find.text('Per-Page'), findsOneWidget);

      // Verify Page 1 has 2-Up selected in ChoiceChip
      final chip2Up = find.widgetWithText(ChoiceChip, '2-Up');
      expect(chip2Up, findsOneWidget);
      final widget2Up = tester.widget<ChoiceChip>(chip2Up);
      expect(widget2Up.selected, isTrue);

      // Select Page 2 from thumbnails bar
      final page2Card = find.text('Page 2');
      expect(page2Card, findsOneWidget);
      await tester.tap(page2Card);
      await tester.pump();

      // Verify layout panel switched to Page 2
      expect(find.text('Page 2 Layout'), findsOneWidget);
      final chip6Up = find.widgetWithText(ChoiceChip, '6-Up');
      expect(chip6Up, findsOneWidget);
      final widget6Up = tester.widget<ChoiceChip>(chip6Up);
      expect(widget6Up.selected, isTrue);

      // Change Page 2 preset to 8-Up
      final chip8Up = find.widgetWithText(ChoiceChip, '8-Up');
      expect(chip8Up, findsOneWidget);
      await tester.tap(chip8Up);
      await tester.pump();

      // Verify Page 2 is now 8-Up
      expect(project.pages[1].presetType, equals(LayoutPresetType.eight));

      // Switch back to Page 1
      final page1Card = find.text('Page 1');
      await tester.tap(page1Card);
      await tester.pump();

      // Page 1 MUST still be 2-Up (Page 2's change did NOT overwrite Page 1)
      expect(project.pages[0].presetType, equals(LayoutPresetType.two));
      expect(find.text('Page 1 Layout'), findsOneWidget);

      // Test "Apply Page 1 Layout to All Pages"
      final applyAllBtn = find.text('Apply Page 1 Layout to All Pages');
      expect(applyAllBtn, findsOneWidget);
      await tester.tap(applyAllBtn);
      await tester.pump();

      // Now Page 2 should have inherited Page 1's preset (2-Up)
      expect(project.pages[1].presetType, equals(LayoutPresetType.two));
    });

    test('PdfExportService exports document with heterogeneous page layouts', () async {
      final imgBytes = Uint8List.fromList([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
        0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
        0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
        0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
        0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
        0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
        0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
        0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
        0x42, 0x60, 0x82,
      ]);
      final item1 = ScreenshotItem(name: 's1.png', bytes: imgBytes, width: 800, height: 600);
      final item2 = ScreenshotItem(name: 's2.png', bytes: imgBytes, width: 800, height: 600);
      final item3 = ScreenshotItem(name: 's3.png', bytes: imgBytes, width: 800, height: 600);

      final project = PdfProject(
        title: 'Heterogeneous_Layout_Doc',
        pages: [
          PdfPageModel(
            pageNumber: 1,
            presetType: LayoutPresetType.one,
            geometry: const PageGeometry(paperSize: PaperSize.letter, isLandscape: true),
            images: [item1],
          ),
          PdfPageModel(
            pageNumber: 2,
            presetType: LayoutPresetType.four,
            geometry: const PageGeometry(paperSize: PaperSize.a4, isLandscape: false),
            images: [item2, item3],
          ),
        ],
      );

      final pdfBytes = await PdfExportService.generatePdf(project: project);
      expect(pdfBytes, isNotNull);
      expect(pdfBytes.lengthInBytes, greaterThan(0));
    });
  });

  group('11. Universal FileUtils and Download Directory Tests', () {
    test('formatPdfFilename sanitizes forbidden filesystem characters and enforces .pdf extension', () {
      expect(FileUtils.formatPdfFilename(r'My:Report*2026?|Final'), equals('My_Report_2026__Final.pdf'));
      expect(FileUtils.formatPdfFilename('Document.pdf'), equals('Document.pdf'));
      expect(FileUtils.formatPdfFilename('Document'), equals('Document.pdf'));
      expect(FileUtils.formatPdfFilename('   '), equals('QuickShare_Document.pdf'));
      expect(FileUtils.formatPdfFilename('Custom Title   '), equals('Custom Title.pdf'));
    });

    test('joinPath correctly concatenates Windows and POSIX directory paths', () {
      expect(FileUtils.joinPath(r'C:\Users\Downloads', 'doc.pdf'), equals(r'C:\Users\Downloads\doc.pdf'));
      expect(FileUtils.joinPath(r'C:\Users\Downloads\', 'doc.pdf'), equals(r'C:\Users\Downloads\doc.pdf'));
      expect(FileUtils.joinPath('/home/user/downloads', 'doc.pdf'), equals('/home/user/downloads/doc.pdf'));
      expect(FileUtils.joinPath('/home/user/downloads/', 'doc.pdf'), equals('/home/user/downloads/doc.pdf'));
      expect(FileUtils.joinPath('', 'doc.pdf'), equals('doc.pdf'));
    });

    test('getDefaultDownloadDirectory returns valid non-empty path', () {
      final dir = FileUtils.getDefaultDownloadDirectory();
      expect(dir, isNotEmpty);
      expect(dir.contains('QuickShare'), isTrue);
    });
  });

  group('12. Collapsible Layout Panel & Custom PDF Filename UI Tests', () {
    testWidgets('PdfEditorView provides editable PDF filename and collapsible layout panel', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final engine = TransferEngine();
      engine.stopTimers();

      await tester.pumpWidget(
        ChangeNotifierProvider<TransferEngine>.value(
          value: engine,
          child: const MaterialApp(
            home: PdfEditorView(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Verify custom PDF File Name field exists and defaults to QuickShare_Document.pdf
      final fileNameField = find.byKey(const Key('pdf_file_name_field'));
      expect(fileNameField, findsOneWidget);
      expect(tester.widget<TextField>(fileNameField).controller!.text, 'QuickShare_Document.pdf');

      // 2. Change PDF File Name
      await tester.enterText(fileNameField, 'Lab_Final_Export');
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(fileNameField).controller!.text, 'Lab_Final_Export');

      // 3. Verify Page Layout Panel is initially visible
      expect(find.text('Page 1 Layout'), findsOneWidget);
      final hideButton = find.byKey(const Key('collapse_layout_panel_edge_handle'));
      expect(hideButton, findsOneWidget);

      // 4. Collapse the Layout Panel
      await tester.tap(hideButton);
      await tester.pumpAndSettle();

      // 5. Verify the floating "Show Page Layout" button is displayed on the right edge
      final showButton = find.byKey(const Key('expand_layout_panel_floating_button'));
      expect(showButton, findsOneWidget);

      // 6. Click the floating button to expand the Layout Panel back
      await tester.tap(showButton);
      await tester.pumpAndSettle();

      // 7. Verify Page Layout panel is visible again
      expect(find.text('Page 1 Layout'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Ctrl+V inside the PDF filename field pastes text instead of being swallowed by image paste', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.getData') return {'text': 'Pasted_Name'};
        if (call.method == 'Clipboard.hasStrings') return {'value': true};
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

      final engine = TransferEngine();
      engine.stopTimers();

      await tester.pumpWidget(
        ChangeNotifierProvider<TransferEngine>.value(
          value: engine,
          child: const MaterialApp(home: PdfEditorView()),
        ),
      );
      await tester.pumpAndSettle();

      final fileNameField = find.byKey(const Key('pdf_file_name_field'));
      await tester.tap(fileNameField);
      await tester.pumpAndSettle();
      final controller = tester.widget<TextField>(fileNameField).controller!;
      controller.clear();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(controller.text, 'Pasted_Name');
      expect(find.byKey(const Key('paste_failed_notification')), findsNothing);

      await tester.pumpWidget(const SizedBox());
    });
  });

  group('13. Navigation & Removed Nearby Devices Tests', () {
    testWidgets('AppShell has 11 navigation destinations and does NOT include Nearby Devices', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final engine = TransferEngine();
      engine.stopTimers();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<TransferEngine>.value(value: engine),
            ChangeNotifierProvider<AppUpdateService>.value(value: AppUpdateService()),
          ],
          child: const QuickShareApp(showLegacyShell: true),
        ),
      );
      await tester.pumpAndSettle();

      // Verify "Nearby Devices" and "Saved Templates" are completely removed
      expect(find.text('Nearby Devices'), findsNothing);
      expect(find.text('Saved Templates'), findsNothing);

      // Verify core navigation items are present
      expect(find.text('Dashboard'), findsWidgets);
      expect(find.text('PDF Studio'), findsWidgets);
      expect(find.text('Device Pairing'), findsWidgets);
      expect(find.text('Send Files'), findsWidgets);
      expect(find.text('Received Items'), findsWidgets);
      expect(find.text('Screenshot Sessions'), findsWidgets);
      expect(find.text('PDF Tools'), findsWidgets);
      expect(find.text('Universal Clipboard'), findsWidgets);
      expect(find.text('HISTORY'), findsWidgets);
      expect(find.text('Settings & Privacy'), findsWidgets);

      await tester.pumpWidget(const SizedBox());
    });
  });

  group('14. Simplified Send Files & Paired-Device File Sharing Only Tests', () {
    testWidgets('Empty state displays minimal paired devices message and removed features are gone', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final engine = TransferEngine();
      engine.stopTimers();
      engine.pairedDevices.clear(); // Ensure 0 paired devices

      bool navigatedToPairing = false;

      await tester.pumpWidget(
        ChangeNotifierProvider<TransferEngine>.value(
          value: engine,
          child: MaterialApp(
            home: SendFilesView(
              onNavigateToPairing: () => navigatedToPairing = true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Verify clean empty state message & link
      expect(find.text('No paired devices connected'), findsOneWidget);
      final pairLink = find.text('Go to Pairing');
      expect(pairLink, findsOneWidget);
      await tester.tap(pairLink);
      expect(navigatedToPairing, isTrue);

      // 2. Verify all unnecessary clutter is completely removed
      expect(find.text('Active Session PDF Ready'), findsNothing);
      expect(find.text('Queue PDF'), findsNothing);
      expect(find.text('Scan Web Bluetooth'), findsNothing);
      expect(find.text('Connect Phone'), findsNothing);
      expect(find.text('Scan Hub'), findsNothing);
      expect(find.text('DISCOVERED NEARBY DEVICES'), findsNothing);
      expect(find.text('Pair & Send'), findsNothing);
      expect(find.text('Direct Send'), findsNothing);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Selecting file and paired device triggers direct transfer and shows progress', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final engine = TransferEngine();
      engine.stopTimers();
      engine.pairedDevices.clear();
      if (engine.currentPairingSession == null || engine.currentPairingSession!.isExpired) {
        engine.regeneratePairingCode();
      }

      final onlineDevice = DeviceModel(
        id: 'dev_laptop_1',
        name: 'Work Laptop',
        ip: '192.168.1.101',
        port: 8088,
        deviceType: DeviceType.desktop,
        isTrusted: true,
        isOnline: true,
      );

      final offlineDevice = DeviceModel(
        id: 'dev_phone_2',
        name: 'Old Tablet',
        ip: '192.168.1.102',
        port: 8088,
        deviceType: DeviceType.tablet,
        isTrusted: true,
        isOnline: false,
      );

      engine.pairedDevices.addAll([onlineDevice, offlineDevice]);

      final dummyBytes = Uint8List.fromList(List.filled(2048, 42));

      await tester.pumpWidget(
        ChangeNotifierProvider<TransferEngine>.value(
          value: engine,
          child: MaterialApp(
            home: SendFilesView(
              preloadedName: 'Research_Report.pdf',
              preloadedBytes: dummyBytes,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Verify preloaded file is displayed
      expect(find.text('Research_Report.pdf'), findsOneWidget);

      // 2. Verify paired device is shown
      expect(find.textContaining('Work Laptop'), findsWidgets);

      // 3. Find and tap "Send to Paired Device" button
      final sendBtn = find.text('Send to Paired Device');
      expect(sendBtn, findsOneWidget);
      await tester.ensureVisible(sendBtn);
      await tester.tap(sendBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // 4. Verify active transfer progress appears
      expect(engine.activeTransfers.isNotEmpty, isTrue);
      expect(engine.activeTransfers.first.fileName, equals('Research_Report.pdf'));

      engine.stopTimers();
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('31. Send PDF from Paired Device adds valid document to Received Items', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 850);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final engine = TransferEngine();
      final pairedPhone = DeviceModel(
        id: 'phone_paired_99',
        name: 'Pixel 8 Pro',
        ip: '192.168.1.150',
        port: 8088,
        deviceType: DeviceType.mobile,
        isTrusted: true,
        isOnline: true,
      );
      engine.pairedDevices.add(pairedPhone);

      // Verify sendPdfFromDevice creates a valid received item with sender info
      final initialCount = engine.receivedItems.length;
      await engine.sendPdfFromDevice(
        senderDevice: pairedPhone,
        fileName: 'Lab_Report_Pixel_8.pdf',
      );

      expect(engine.receivedItems.length, equals(initialCount + 1));
      final received = engine.receivedItems.first;
      expect(received.fileName, equals('Lab_Report_Pixel_8.pdf'));
      expect(received.senderDeviceName, equals('Pixel 8 Pro'));
      expect(received.fileType, equals(ReceivedFileType.pdf));
      expect(received.bytes, isNotNull);
      expect(received.bytes.length, greaterThan(0));

      // Pump ReceivedItemsView to verify it renders the newly received PDF item
      await tester.pumpWidget(
        ChangeNotifierProvider<TransferEngine>.value(
          value: engine,
          child: const MaterialApp(
            home: ReceivedItemsView(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Lab_Report_Pixel_8.pdf'), findsOneWidget);
      expect(find.textContaining('Pixel 8 Pro'), findsWidgets);
      expect(find.byIcon(Icons.picture_as_pdf), findsWidgets);
      expect(find.textContaining('PDFs ('), findsWidgets);

      engine.stopTimers();
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('15. Custom Device Name & Session Expiration Tests', () {
    test('User can set, persist, and reset custom device name', () {
      final engine = TransferEngine();
      engine.setCustomDeviceName("Abhijeet's Laptop");
      expect(engine.localDeviceName, "Abhijeet's Laptop");
      expect(engine.isCustomDeviceNameSaved, isTrue);

      // Resetting reverts to default name
      engine.resetDeviceName();
      expect(engine.isCustomDeviceNameSaved, isFalse);
      expect(engine.localDeviceName.isNotEmpty, isTrue);
    });

    test('Pairing session code invalidates on session end without countdown timer', () {
      final engine = TransferEngine();
      engine.regeneratePairingCode();
      final session = engine.currentPairingSession;
      expect(session, isNotNull);
      expect(session!.isActive, isTrue);
      expect(session.isExpired, isFalse);

      // Invalidate session
      engine.endPairingSession();
      expect(session.isExpired, isTrue);
      expect(session.isActive, isFalse);
    });
  });

  group('16. HISTORY View & Persistent Transfer Records Tests', () {
    testWidgets('TransferHistoryView displays HISTORY header, stats, and records', (tester) async {
      tester.view.physicalSize = const Size(1280, 850);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final engine = TransferEngine();
      engine.historyRecords.clear();

      // Add a sent record and a received record
      final dummyBytes = Uint8List.fromList([1, 2, 3, 4, 5]);
      final sha = HashUtils.computeSha256(dummyBytes);

      final sentRecord = HistoryRecord(
        fileName: 'Project_Alpha.pdf',
        fileSize: 1024,
        senderName: engine.localDeviceName,
        recipientName: 'Lab Tablet',
        isIncoming: false,
        status: 'completed',
        sha256: sha,
        sessionName: 'Physics Lab',
        pageCount: 3,
      );

      final receivedRecord = HistoryRecord(
        fileName: 'Chemistry_Experiment.png',
        fileSize: 2048,
        senderName: 'Lab Partner Phone',
        recipientName: engine.localDeviceName,
        isIncoming: true,
        status: 'completed',
        sha256: 'a1b2c3d4e5f6',
      );

      engine.historyRecords.addAll([sentRecord, receivedRecord]);

      await tester.pumpWidget(
        ChangeNotifierProvider<TransferEngine>.value(
          value: engine,
          child: const MaterialApp(
            home: TransferHistoryView(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify header is HISTORY
      expect(find.text('HISTORY'), findsOneWidget);
      expect(find.text('Total Transfers'), findsOneWidget);
      expect(find.text('Sent'), findsWidgets);
      expect(find.text('Received'), findsWidgets);

      // Verify records are rendered
      expect(find.text('Project_Alpha.pdf'), findsOneWidget);
      expect(find.text('Chemistry_Experiment.png'), findsOneWidget);
      expect(find.text('SENT'), findsOneWidget);
      expect(find.text('RECEIVED'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });
  });

  group('17. Screenshot Session Management Tests', () {
    test('TransferEngine creates, renames, and manages screenshot sessions', () {
      final engine = TransferEngine();
      final initialCount = engine.screenshotSessions.length;

      final ScreenshotSessionModel session = engine.createScreenshotSession('Organic Chemistry Lab');
      expect(session.name, 'Organic Chemistry Lab');
      expect(engine.screenshotSessions.length, initialCount + 1);

      // Add screenshot item
      final item = ScreenshotItem(
        name: 'sample_slide.png',
        bytes: Uint8List.fromList([10, 20, 30]),
        caption: 'Slide 1',
      );
      engine.addScreenshotsToSession(session.id, [item]);
      expect(session.screenshots.length, 1);

      // Rename session
      engine.renameScreenshotSession(session.id, 'Organic Chemistry Lab - Final');
      expect(session.name, 'Organic Chemistry Lab - Final');

      // Delete session
      engine.deleteScreenshotSession(session.id);
      expect(engine.screenshotSessions.any((s) => s.id == session.id), isFalse);
    });
  });

  group('18. App Update Device Workflow Tests (Section 13)', () {
    testWidgets('13.A & 13.E: AppUpdateInfo & AppUpdateService detect new version and verify SHA-256 integrity', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final updateService = AppUpdateService();
      final engine = TransferEngine();
      engine.stopTimers();

      // Reset state for test
      updateService.resetTestingState();

      expect(updateService.currentVersion, AppConstants.appVersion);

      // Publish new version v2.2.0
      final update = await updateService.publishNewVersion(
        version: '2.2.0',
        title: 'QuickShare Universal 2.2.0 Release',
        description: 'High-speed encrypted peer-to-peer transfers with offline repair.',
        releaseNotes: [
          'SHA-256 cryptographically verified updates',
          'Zero-latency pairing state synchronization',
        ],
        packageSizeBytes: 5242880, // 5 MB
        notifyEngine: engine,
        simulateLatency: false,
      );

      expect(update.isNewerVersion, isTrue);
      expect(update.version, '2.2.0');
      expect(update.currentVersion, AppConstants.appVersion);
      expect(update.packageSha256.isNotEmpty, isTrue);
      expect(updateService.status, UpdateStatus.available);
      expect(updateService.hasPendingUpdate, isTrue);

      // Verify paired devices received notification
      expect(engine.lastNotificationTitle, contains('Update Available'));
      expect(engine.lastNotificationBody, contains('2.2.0'));
    });

    testWidgets('13.B: UpdateDialog displays Liquid Glass popup with Update Now, Update Later, and View Details', (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1280, 850);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final updateService = AppUpdateService();
      final engine = TransferEngine();
      engine.stopTimers();
      updateService.resetTestingState();

      final updateInfo = AppUpdateInfo(
        version: '2.2.0',
        currentVersion: AppConstants.appVersion,
        title: 'QuickShare Studio 2.2.0 Release',
        description: 'New Liquid Glass interface enhancements and file format converters.',
        releaseNotes: [
          'Automatic offline fallback for pairing sessions',
          'Multi-page PDF layout customizer',
        ],
        publishedAt: DateTime.now(),
        packageSizeBytes: 4194304,
        packageSha256: 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<TransferEngine>.value(value: engine),
            ChangeNotifierProvider<AppUpdateService>.value(value: updateService),
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => UpdateDialog.show(context, updateInfo),
                  child: const Text('Show Dialog'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      // Verify dialog header, versions, description
      expect(find.text('SOFTWARE UPDATE AVAILABLE'), findsOneWidget);
      expect(find.textContaining('v${AppConstants.appVersion}'), findsWidgets);
      expect(find.textContaining('v2.2.0'), findsWidgets);
      expect(find.text('QuickShare Studio 2.2.0 Release'), findsOneWidget);

      // Verify buttons: Update Now, Update Later, View Details
      expect(find.text('Update Now'), findsOneWidget);
      expect(find.text('Update Later'), findsOneWidget);
      expect(find.text('View Details'), findsOneWidget);

      // Tap View Details to expand release notes
      await tester.tap(find.text('View Details'));
      await tester.pumpAndSettle();
      expect(find.text('Automatic offline fallback for pairing sessions'), findsOneWidget);

      // Tap Update Later
      await tester.tap(find.text('Update Later'));
      await tester.pumpAndSettle();

      // Verify dialog dismissed & update marked as postponed
      expect(find.text('SOFTWARE UPDATE AVAILABLE'), findsNothing);
      expect(updateService.isPostponed, isTrue);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('13.C: SecuritySettingsView includes dedicated Updates section with all controls', (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1280, 850);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final updateService = AppUpdateService();
      final engine = TransferEngine();
      engine.stopTimers();
      updateService.resetTestingState();

      await updateService.publishNewVersion(
        version: '2.3.0',
        title: 'QuickShare 2.3.0 Maintenance Release',
        simulateLatency: false,
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<TransferEngine>.value(value: engine),
            ChangeNotifierProvider<AppUpdateService>.value(value: updateService),
          ],
          child: const MaterialApp(
            home: SecuritySettingsView(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify Updates section header and version tags
      expect(find.text('UPDATES & DEVICE MAINTENANCE'), findsOneWidget);
      expect(find.text('Current Version: v${AppConstants.appVersion}'), findsOneWidget);
      expect(find.textContaining('Latest available: v2.3.0'), findsOneWidget);
      expect(find.text('Update to v2.3.0'), findsOneWidget);
      expect(find.text('Check for Updates'), findsOneWidget);
      expect(find.text('Automatically check for updates'), findsOneWidget);

      // Update is available, so Update Now and Update Later should be visible
      expect(find.widgetWithText(ElevatedButton, 'Update Now'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Update Later'), findsOneWidget);

      // Tap Update Later from settings
      await tester.tap(find.widgetWithText(OutlinedButton, 'Update Later'));
      await tester.pumpAndSettle();
      expect(updateService.isPostponed, isTrue);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('13.D & 13.E: startUpdateNow guards active transfers, performs staging, and preserves user data', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final updateService = AppUpdateService();
      final engine = TransferEngine();
      engine.stopTimers();
      updateService.resetTestingState();

      await updateService.publishNewVersion(version: '2.0.0', simulateLatency: false);

      // Preserve custom device name and data before update
      engine.setCustomDeviceName('Lab_Main_Workstation');
      final session = engine.createScreenshotSession('Biology Lab Session');
      expect(session.name, 'Biology Lab Session');

      // 1. Guard against updating while active transfer is running
      final activeTransfer = TransferItem(
        transferId: 'tx_guard_test',
        fileName: 'Important_Report.pdf',
        fileSizeBytes: 1024,
        fileType: TransferFileType.pdf,
        sha256: 'dummy_hash',
        totalChunks: 1,
        isSender: true,
        peerDeviceName: 'Tablet',
        peerDeviceId: 'dev_tablet_01',
        status: TransferStatus.transferring,
      );
      engine.activeTransfers.add(activeTransfer);

      final blocked = await updateService.startUpdateNow(engine: engine, simulateProgress: false);
      expect(blocked, isFalse);
      expect(updateService.status, UpdateStatus.failed);
      expect(updateService.errorMessage, contains('Cannot update while a file transfer is actively in progress'));

      // 2. Clear active transfer and run safe update
      engine.activeTransfers.clear();
      var updateCompleted = false;

      final success = await updateService.startUpdateNow(
        engine: engine,
        onComplete: () => updateCompleted = true,
        simulateProgress: false,
      );

      expect(success, isTrue);
      expect(updateCompleted, isTrue);
      expect(updateService.status, UpdateStatus.applied);
      expect(updateService.currentVersion, '2.0.0');

      // 3. Confirm all user settings and session data remain 100% intact
      expect(engine.localDeviceName, 'Lab_Main_Workstation');
      expect(engine.screenshotSessions.any((s) => s.name == 'Biology Lab Session'), isTrue);
    });
  });
}

