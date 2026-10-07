import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:quickshare/data/models/device_model.dart';
import 'package:quickshare/data/models/pairing_session.dart';
import 'package:quickshare/data/services/transfer_engine.dart';
import 'package:quickshare/features/pairing/pairing_view.dart';
import 'package:quickshare/transfer/app_config.dart';
import 'package:quickshare/transfer/transfer_method.dart';

Widget createPairingScreen(TransferEngine engine) {
  return ChangeNotifierProvider<TransferEngine>.value(
    value: engine,
    child: const MaterialApp(
      home: PairingView(),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Device Pairing Screen Tests', () {
    late TransferEngine engine;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      engine = TransferEngine();
      engine.pairedDevices.clear();
      engine.regeneratePairingCode();
    });

    testWidgets('1. Displays screen header, active session badge, and initial QR code mode', (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(createPairingScreen(engine));
      await tester.pumpAndSettle();

      expect(find.text('Device Pairing'), findsOneWidget);
      expect(find.text('Active Session'), findsOneWidget);
      expect(find.text('Show my QR code'), findsOneWidget);
      expect(find.text('Show my six-digit code'), findsOneWidget);
      expect(find.byKey(const Key('pairing_method_switch')), findsOneWidget);
      expect(
        tester.widget<SegmentedButton<TransferMethod>>(find.byKey(const Key('pairing_method_switch'))).selected,
        {TransferMethod.internet},
      );
      expect(engine.currentPairingSession!.ttl, AppConfig.current.codeTtl);
      expect(engine.currentPairingSession!.ttl, const Duration(minutes: 5));
      expect(engine.currentPairingSession!.preferredMethod, TransferMethod.internet);
      expect(find.byType(QrImageView), findsOneWidget);
      expect(find.text('Regenerate QR Code'), findsOneWidget);
      expect(find.text('Connect to another device'), findsOneWidget);
      expect(find.text('Connected Devices'), findsOneWidget);
    });

    testWidgets('Pairing screen fits phone, tablet, and desktop widths', (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final width in [320.0, 360.0, 390.0, 600.0, 768.0, 1280.0]) {
        tester.view.physicalSize = Size(width, 900);
        await tester.pumpWidget(createPairingScreen(engine));
        await tester.pumpAndSettle();
        expect(find.text('Device Pairing'), findsOneWidget, reason: 'width: $width');
        expect(tester.takeException(), isNull, reason: 'width: $width');
      }
    });

    testWidgets('2. Switches between "Show my QR code" and "Show my six-digit code" tabs', (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(createPairingScreen(engine));
      await tester.pumpAndSettle();
      final originalSessionId = engine.currentPairingSession!.sessionId;
      final originalCode = engine.currentPairingSession!.numericCode;

      // Initially in QR code mode
      expect(find.byType(QrImageView), findsOneWidget);
      expect(find.text('Regenerate QR Code'), findsOneWidget);

      // Tap "Show my six-digit code"
      await tester.tap(find.text('Show my six-digit code'));
      await tester.pumpAndSettle();

      // Now 6-digit code is visible and QR code is hidden
      expect(find.byType(QrImageView), findsNothing);
      expect(find.text('YOUR 6-DIGIT PAIRING CODE'), findsOneWidget);
      expect(find.text('Regenerate 6-Digit Code'), findsOneWidget);
      final currentFormatted = engine.currentPairingSession!.formattedCode;
      expect(find.text(currentFormatted), findsOneWidget);

      // Tap back to "Show my QR code"
      await tester.tap(find.text('Show my QR code'));
      await tester.pumpAndSettle();

      expect(find.byType(QrImageView), findsOneWidget);
      expect(find.text('Regenerate QR Code'), findsOneWidget);
      expect(engine.currentPairingSession!.sessionId, originalSessionId);
      expect(engine.currentPairingSession!.numericCode, originalCode);
    });

    testWidgets('Internet and Same Wi-Fi are a working route switch that rotates credentials', (tester) async {
      tester.view.physicalSize = const Size(1280, 1500);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(createPairingScreen(engine));
      await tester.pumpAndSettle();

      final internetSession = engine.currentPairingSession!;
      final wifiLabel = find.descendant(of: find.byKey(const Key('pairing_method_switch')), matching: find.text('Same Wi-Fi'));
      await tester.tapAt(tester.getCenter(wifiLabel));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      final wifiSession = engine.currentPairingSession!;
      expect(wifiSession.preferredMethod, TransferMethod.lan);
      expect(wifiSession.numericCode, isNot(internetSession.numericCode));
      expect(wifiSession.sessionId, isNot(internetSession.sessionId));
      expect(tester.widget<SegmentedButton<TransferMethod>>(find.byKey(const Key('pairing_method_switch'))).selected, {TransferMethod.lan});
      expect(wifiSession.qrPayload, contains('mode=lan'));

      final internetLabel = find.descendant(of: find.byKey(const Key('pairing_method_switch')), matching: find.text('Internet'));
      await tester.tapAt(tester.getCenter(internetLabel), pointer: 2, kind: ui.PointerDeviceKind.mouse);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      final refreshedInternetSession = engine.currentPairingSession!;
      expect(refreshedInternetSession.preferredMethod, TransferMethod.internet);
      expect(refreshedInternetSession.numericCode, isNot(wifiSession.numericCode));
      expect(refreshedInternetSession.qrPayload, contains('mode=internet'));
      expect(tester.widget<SegmentedButton<TransferMethod>>(find.byKey(const Key('pairing_method_switch'))).selected, {TransferMethod.internet});
    });

    testWidgets('3. Regenerate control replaces previous code with new code and invalidates the old code', (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(createPairingScreen(engine));
      await tester.pumpAndSettle();

      final initialCode = engine.currentPairingSession!.numericCode;
      final initialSessionId = engine.currentPairingSession!.sessionId;

      // Tap Regenerate QR Code
      await tester.tap(find.text('Regenerate QR Code'));
      await tester.pumpAndSettle();

      final newCode = engine.currentPairingSession!.numericCode;
      final newSessionId = engine.currentPairingSession!.sessionId;

      // Must be replaced
      expect(newCode, isNot(equals(initialCode)));
      expect(newSessionId, isNot(equals(initialSessionId)));

      // Old code must be marked invalidated in engine
      expect(engine.isCodeInvalidated(initialCode), isTrue);

      // Attempting to pair with old invalidated code must fail
      final pairResult = await engine.pairWithNumericCode(initialCode);
      expect(pairResult, isFalse);
    });

    testWidgets('4. Regenerating from 6-digit code tab replaces code and invalidates previous value', (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(createPairingScreen(engine));
      await tester.pumpAndSettle();

      // Switch to 6-digit code tab
      await tester.tap(find.text('Show my six-digit code'));
      await tester.pumpAndSettle();

      final oldCode = engine.currentPairingSession!.numericCode;
      final oldFormatted = engine.currentPairingSession!.formattedCode;
      expect(find.text(oldFormatted), findsOneWidget);

      // Tap Regenerate 6-Digit Code
      await tester.tap(find.text('Regenerate 6-Digit Code'));
      await tester.pumpAndSettle();

      final newCode = engine.currentPairingSession!.numericCode;
      final newFormatted = engine.currentPairingSession!.formattedCode;

      expect(newCode, isNot(equals(oldCode)));
      expect(find.text(newFormatted), findsOneWidget);
      expect(engine.isCodeInvalidated(oldCode), isTrue);
    });

    testWidgets('5. Connect section validates code length and shows error for incomplete code', (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(createPairingScreen(engine));
      await tester.pumpAndSettle();

      // Enter incomplete code (e.g. 123)
      await tester.enterText(find.byType(TextField), '123');
      await tester.pumpAndSettle();

      // Tap Pair / Connect button
      await tester.tap(find.text('Pair / Connect'));
      await tester.pumpAndSettle();

      expect(find.text('Please enter a valid 6-digit pairing code.'), findsOneWidget);
    });

    testWidgets('6. Connect section rejects entering own device code with clear feedback', (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(createPairingScreen(engine));
      await tester.pumpAndSettle();

      final myCode = engine.currentPairingSession!.numericCode;

      await tester.enterText(find.byType(TextField), myCode);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Pair / Connect'));
      await tester.pumpAndSettle();

      expect(find.text('Cannot pair with this device\'s own code. Enter the code from the other device.'), findsOneWidget);
    });

    testWidgets('7. Connect section rejects invalidated / expired code with specific feedback', (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(createPairingScreen(engine));
      await tester.pumpAndSettle();

      final oldCode = engine.currentPairingSession!.numericCode;

      // Regenerate to invalidate oldCode
      engine.regeneratePairingCode();
      await tester.pumpAndSettle();

      // Enter the old invalidated code
      await tester.enterText(find.byType(TextField), oldCode);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Pair / Connect'));
      await tester.pumpAndSettle();

      expect(find.text('This pairing code has been invalidated or expired. Please ask the sender to regenerate a new code.'), findsOneWidget);
    });

    testWidgets('8. Connect section pairs successfully with valid code and updates connected devices list', (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(createPairingScreen(engine));
      await tester.pumpAndSettle();

      expect(engine.pairedDevices.isEmpty, isTrue);
      expect(find.text('No Devices Connected Yet'), findsOneWidget);

      // Enter a valid 6-digit code (e.g. 784921)
      await tester.enterText(find.byType(TextField), '784921');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Pair / Connect'));
      // Handle the simulated network delay
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      expect(engine.pairedDevices.length, 1);
      expect(find.text('Device paired successfully! It has been added to Connected Devices below.'), findsOneWidget);
      expect(find.text('Connected Devices'), findsOneWidget);
      expect(find.text('Device_784'), findsOneWidget);
      expect(find.text('Windows'), findsOneWidget); // 7xx codes resolve to Windows
      expect(find.text('Online • Connected'), findsOneWidget);
    });

    testWidgets('9. Connected devices list shows device name, platform badge, connection status, and disconnect button', (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // Add two sample devices with different platforms
      engine.addPairedDevice(DeviceModel(
        name: 'Galaxy Tab S9',
        ip: '192.168.1.105',
        port: 8088,
        platform: 'Android',
        isOnline: true,
      ));
      engine.addPairedDevice(DeviceModel(
        name: 'MacBook Air M2',
        ip: '192.168.1.120',
        port: 8088,
        platform: 'macOS',
        isOnline: true,
      ));

      await tester.pumpWidget(createPairingScreen(engine));
      await tester.pumpAndSettle();

      expect(find.text('Galaxy Tab S9'), findsOneWidget);
      expect(find.text('Android'), findsOneWidget);
      expect(find.text('MacBook Air M2'), findsOneWidget);
      expect(find.text('macOS'), findsOneWidget);
      expect(find.text('Online • Connected'), findsNWidgets(2));
      expect(find.text('Disconnect'), findsNWidgets(2));
      expect(find.text('Disconnect All'), findsOneWidget);

      // Disconnect one device
      await tester.ensureVisible(find.text('Disconnect').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Disconnect').first);
      await tester.pumpAndSettle();

      expect(engine.pairedDevices.length, 1);
      expect(find.text('MacBook Air M2'), findsOneWidget);
      expect(find.text('Galaxy Tab S9'), findsNothing);

      // Disconnect All
      await tester.ensureVisible(find.text('Disconnect All'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Disconnect All'));
      await tester.pumpAndSettle();

      expect(engine.pairedDevices.isEmpty, isTrue);
      expect(find.text('No Devices Connected Yet'), findsOneWidget);
    });

    test('10. Fresh application sessions generate new temporary credentials without persistence', () async {
      final session1 = PairingSession.create(
        hostDeviceName: 'Device 1',
        hostIp: '10.0.0.1',
        hostPort: 8088,
      );

      final session2 = PairingSession.create(
        hostDeviceName: 'Device 2',
        hostIp: '10.0.0.2',
        hostPort: 8088,
      );

      // Credentials are completely temporary and new
      expect(session1.numericCode, isNotEmpty);
      expect(session2.numericCode, isNotEmpty);
      expect(session1.sessionId, isNot(equals(session2.sessionId)));

      // Verifying persistence does not store credentials
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('pairing_code'), isFalse);
      expect(prefs.containsKey('pairing_session_id'), isFalse);
    });

    testWidgets('11. Scan QR code tab shows dedicated camera option and completely omits Paste QR', (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(createPairingScreen(engine));
      await tester.pumpAndSettle();

      // Tap "Scan QR code" tab
      final scanTab = find.text('Scan QR code');
      await tester.tapAt(tester.getCenter(scanTab));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      // Verify "Paste QR" is completely absent
      expect(find.text('Paste QR'), findsNothing);

      // Verify dedicated camera option is present
      expect(find.text('Scan Pairing QR Code'), findsOneWidget);
      expect(find.text('Scan with Camera'), findsOneWidget);
      expect(find.byKey(const Key('scan_with_camera_button')), findsOneWidget);
      // Phones can also read a QR code from a saved screenshot.
      expect(find.byKey(const Key('open_qr_image_button')), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('That isn\'t a QuickShare pairing code.'), findsNothing);
      expect(find.text('Pair with QR Code'), findsNothing);
    });

    testWidgets('Linux QR scan panel opens a QR image instead of the camera', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      tester.view.physicalSize = const Size(1280, 1500);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(createPairingScreen(engine));
      final scanTab = find.text('Scan QR code');
      await tester.tapAt(tester.getCenter(scanTab));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.byKey(const Key('desktop_camera_unavailable_hint')), findsOneWidget);
      expect(find.byKey(const Key('open_qr_image_button')), findsOneWidget);
      expect(find.text('Open QR image'), findsOneWidget);
      expect(find.text('Scan with Camera'), findsNothing);
      expect(find.text('Paste QR'), findsNothing);
      debugDefaultTargetPlatformOverride = null;
    });
  });
}
