import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:quickshare/core/constants.dart';
import 'package:quickshare/data/services/transfer_engine.dart';
import 'package:quickshare/data/services/app_update_service.dart';
import 'package:quickshare/features/dashboard/dashboard_screen.dart';
import 'package:quickshare/features/dashboard/widgets/sidebar.dart';
import 'package:quickshare/features/dashboard/widgets/dashboard_header.dart';
import 'package:quickshare/features/dashboard/widgets/statistic_card.dart';
import 'package:quickshare/features/dashboard/widgets/workspace_card.dart';
import 'package:quickshare/features/dashboard/widgets/recent_exchanges_section.dart';
import 'package:quickshare/features/clipboard/universal_clipboard_view.dart';
import 'package:quickshare/features/security/security_settings_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget buildTestWidget({
    Size size = const Size(1280, 800),
    required Widget child,
    TransferEngine? engine,
  }) {
    final effectiveEngine = engine ?? TransferEngine();
    effectiveEngine.stopTimers();
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<TransferEngine>.value(value: effectiveEngine),
        ChangeNotifierProvider<AppUpdateService>.value(
          value: AppUpdateService(),
        ),
      ],
      child: MaterialApp(
        theme: ThemeData(fontFamily: 'Poppins', brightness: Brightness.dark),
        home: MediaQuery(
          data: MediaQueryData(size: size),
          child: child,
        ),
      ),
    );
  }

  group('A. StatisticCard Tests', () {
    testWidgets('renders value and label correctly', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          child: const StatisticCard(
            value: '687027',
            label: 'Pairing Code',
            isAccent: true,
          ),
        ),
      );

      expect(find.text('687027'), findsOneWidget);
      expect(find.text('Pairing Code'), findsOneWidget);
    });
  });

  group('B. WorkspaceCard Tests', () {
    testWidgets('starts neutral and highlights when isSelected or hovered', (
      tester,
    ) async {
      var tapped = false;
      await tester.pumpWidget(
        buildTestWidget(
          child: Scaffold(
            body: WorkspaceCard(
              title: 'Universal Clipboard',
              subtitle: 'Smart sync text & images',
              icon: Icons.content_paste_rounded,
              isSelected: false,
              onTap: () => tapped = true,
            ),
          ),
        ),
      );

      expect(find.text('Universal Clipboard'), findsOneWidget);
      expect(find.text('Smart sync text & images'), findsOneWidget);
      expect(find.byIcon(Icons.content_paste_rounded), findsOneWidget);
      expect(
        tester.widget<Icon>(find.byIcon(Icons.content_paste_rounded)).color,
        AppColors.white,
      );
      final cardDecoration = tester
          .widget<AnimatedContainer>(
            find.ancestor(
              of: find.text('Universal Clipboard'),
              matching: find.byType(AnimatedContainer),
            ),
          )
          .decoration as BoxDecoration;
      expect((cardDecoration.border! as Border).top.color, AppColors.subtleBorder);

      final card = find.ancestor(
        of: find.text('Universal Clipboard'),
        matching: find.byType(InkWell),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(card));
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        tester.widget<Icon>(find.byIcon(Icons.content_paste_rounded)).color,
        AppColors.primaryAccent,
      );

      await tester.tap(find.text('Universal Clipboard'));
      await tester.pump();
      expect(tapped, isTrue);
    });

    testWidgets('highlights immediately when isSelected is true without hover', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildTestWidget(
          child: const Scaffold(
            body: WorkspaceCard(
              title: 'Universal Clipboard',
              subtitle: 'Smart sync text & images',
              icon: Icons.content_paste_rounded,
              isSelected: true,
            ),
          ),
        ),
      );

      expect(
        tester.widget<Icon>(find.byIcon(Icons.content_paste_rounded)).color,
        AppColors.primaryAccent,
      );
      final cardDecoration = tester
          .widget<AnimatedContainer>(
            find.ancestor(
              of: find.text('Universal Clipboard'),
              matching: find.byType(AnimatedContainer),
            ),
          )
          .decoration as BoxDecoration;
      expect(
        (cardDecoration.border! as Border).top.color,
        AppColors.primaryAccent.withValues(alpha: 0.70),
      );
    });
  });

  group('C. Sidebar Navigation Tests', () {
    testWidgets(
      'Sidebar displays branding, status, 11 navigation items (without Nearby Devices), badge, and toggle',
      (tester) async {
        await tester.pumpWidget(
          buildTestWidget(child: const Scaffold(body: Sidebar(width: 260.0))),
        );

        // Branding
        expect(find.text('QuickShare Studio'), findsOneWidget);
        expect(find.text('Lab Share & PDF Studio'), findsOneWidget);

        // Status capsule
        expect(find.text('Ready to Receive'), findsOneWidget);
        expect(find.text('0 Paired'), findsOneWidget);

        // Nearby Devices and Saved Templates must NOT be present; Screenshot Sessions is a section again
        expect(find.text('Nearby Devices'), findsNothing);
        expect(find.text('Saved Templates'), findsNothing);
        expect(find.text('Screenshot Sessions'), findsOneWidget);

        // 9 Navigation items in exact order
        expect(find.text('Dashboard'), findsOneWidget);
        expect(find.text('PDF Studio'), findsOneWidget);
        expect(find.text('Device Pairing'), findsOneWidget);
        expect(find.text('Send Files'), findsOneWidget);
        expect(find.text('Received Items'), findsOneWidget);
        // Badge beside Received Items mirrors the real count and is hidden when empty.
        final engine = TransferEngine();
        if (engine.receivedItems.isEmpty) {
          expect(find.text('0'), findsNothing);
        } else {
          expect(find.text('${engine.receivedItems.length}'), findsOneWidget);
        }
        expect(find.text('PDF Tools'), findsOneWidget);
        expect(find.text('Universal Clipboard'), findsOneWidget);
        expect(find.text('Transfer History'), findsOneWidget);
        expect(find.text('Settings & Privacy'), findsOneWidget);

        // Dark Forest appearance toggle
        expect(find.text('Dark Forest'), findsOneWidget);
        expect(find.byIcon(Icons.dark_mode_rounded), findsOneWidget);
      },
    );
  });

  group('D. DashboardHeader Tests', () {
    testWidgets(
      'DashboardHeader shows live engine data and 4 metric cards (no Nearby card)',
      (tester) async {
        final engine = TransferEngine();
        await tester.pumpWidget(
          buildTestWidget(
            engine: engine,
            child: const Scaffold(
              body: SingleChildScrollView(child: DashboardHeader()),
            ),
          ),
        );

        expect(find.text('Own Your Transfers, Shape Your Workflow'), findsOneWidget);
        expect(
          find.text('${engine.localDeviceName} · IP: ${engine.localIp} · Port: ${engine.localPort}'),
          findsOneWidget,
        );
        expect(find.text('Ready to Share'), findsOneWidget);
        expect(find.text('Paired Devices'), findsOneWidget);
        expect(find.text('Received Items'), findsOneWidget);
        expect(find.text('Completed'), findsOneWidget);
        expect(find.text('Pairing Code'), findsOneWidget);
        expect(find.text('Nearby Detected'), findsNothing);
        expect(find.text('0'), findsNWidgets(3));

        // Pairing code follows the engine and updates when regenerated.
        final firstCode = engine.currentPairingSession!.numericCode;
        expect(find.text(firstCode), findsOneWidget);
        engine.regeneratePairingCode();
        await tester.pump();
        final newCode = engine.currentPairingSession!.numericCode;
        expect(newCode, isNot(firstCode));
        expect(find.text(firstCode), findsNothing);
        expect(find.text(newCode), findsOneWidget);

        // Counts update live: a paired device and a received file.
        await tester.runAsync(() => engine.pairWithNumericCode('123456', deviceName: 'Test_Phone'));
        engine.receiveIncomingTransfer(
          senderDeviceName: 'Test_Phone',
          fileName: 'notes.pdf',
          bytes: Uint8List.fromList([1, 2, 3]),
        );
        await tester.pump();
        expect(find.text('1'), findsNWidgets(3)); // paired, received, completed

        // Status pill reflects paused receiving.
        engine.togglePauseReceiving();
        await tester.pump();
        expect(find.text('Receiving Paused'), findsOneWidget);

        engine.togglePauseReceiving();
        engine.pairedDevices.clear();
        engine.receivedItems.clear();
        engine.historyRecords.clear();
      },
    );
  });

  group('E. RecentExchangesSection Tests', () {
    testWidgets('displays heading and column headers', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          child: const Scaffold(
            body: SingleChildScrollView(child: RecentExchangesSection()),
          ),
        ),
      );

      expect(find.text('RECENT FILE EXCHANGES'), findsOneWidget);
      expect(find.text('FILE NAME'), findsOneWidget);
      expect(find.text('DEVICE / RECIPIENT'), findsOneWidget);
      expect(find.text('SIZE'), findsOneWidget);
      expect(find.text('STATUS'), findsOneWidget);
      expect(find.text('TIME'), findsOneWidget);
      if (TransferEngine().historyRecords.isEmpty) {
        expect(find.textContaining('No file exchanges yet'), findsOneWidget);
      }
    });

    testWidgets('lists real transfer history instead of placeholders', (tester) async {
      final engine = TransferEngine();
      engine.receiveIncomingTransfer(
        senderDeviceName: 'Test_Phone',
        fileName: 'lab_report.pdf',
        bytes: Uint8List.fromList([1, 2, 3]),
      );
      addTearDown(() {
        engine.receivedItems.clear();
        engine.historyRecords.clear();
      });
      await tester.pumpWidget(
        buildTestWidget(
          engine: engine,
          child: const Scaffold(
            body: SingleChildScrollView(child: RecentExchangesSection()),
          ),
        ),
      );
      expect(find.text('lab_report.pdf'), findsOneWidget);
      expect(find.text('Test_Phone'), findsOneWidget);
      expect(find.text('Lab_Protocol_V4.pdf'), findsNothing);
    });
  });

  group('F. Full DashboardScreen Tests', () {
    testWidgets(
      'Desktop view mounts full sidebar and all 8 workspace feature cards',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          buildTestWidget(
            size: const Size(1280, 800),
            child: const DashboardScreen(),
          ),
        );
        await tester.pumpAndSettle();

        // Heading
        expect(find.text('PRIMARY ACTIONS & WORKSPACE'), findsOneWidget);

        // Removed sections should not be found
        expect(find.text('Nearby Devices'), findsNothing);
        expect(find.text('Saved Templates'), findsNothing);

        // Workspace cards for available features
        expect(find.text('Create PDF'), findsOneWidget);
        expect(find.text('Multi-page studio & 7 layouts'), findsOneWidget);

        expect(find.text('Connect Device'), findsOneWidget);
        expect(find.text('QR code & 6-digit code pairing'), findsOneWidget);

        expect(find.text('Send Files'), findsWidgets); // in sidebar & card
        expect(
          find.text('Transfer to one or multiple devices'),
          findsOneWidget,
        );

        expect(find.text('Received Items'), findsWidgets); // in sidebar & card
        expect(find.text('View & download inbound files'), findsOneWidget);

        expect(find.text('PDF Tools'), findsWidgets); // in sidebar & card
        expect(find.text('Merge, split, compress, OCR'), findsOneWidget);

        expect(
          find.text('Universal Clipboard'),
          findsWidgets,
        ); // in sidebar & card
        expect(find.text('Smart sync text & images'), findsOneWidget);

        expect(
          find.text('Transfer History'),
          findsWidgets,
        ); // in sidebar & card
        expect(find.text('Inspect logs, verify & resend'), findsOneWidget);

        expect(
          find.text('Settings & Privacy'),
          findsWidgets,
        ); // in sidebar & card
        expect(find.text('Appearance, storage, updates'), findsOneWidget);
      },
    );

    testWidgets(
      'Dashboard cards start unselected, single-tap toggles active card, double-tap or second-tap opens section',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          buildTestWidget(
            size: const Size(1280, 800),
            child: const DashboardScreen(),
          ),
        );
        await tester.pumpAndSettle();

        // Test 1: On load, Universal Clipboard card must NOT be selected/highlighted
        final clipboardCards = find.widgetWithText(WorkspaceCard, 'Universal Clipboard');
        expect(clipboardCards, findsOneWidget);
        final initialClipboardCard = tester.widget<WorkspaceCard>(clipboardCards);
        expect(initialClipboardCard.isSelected, isFalse);

        // Test 2: Click Universal Clipboard -> becomes selected/highlighted
        await tester.tap(clipboardCards);
        await tester.pumpAndSettle();
        final selectedClipboardCard = tester.widget<WorkspaceCard>(clipboardCards);
        expect(selectedClipboardCard.isSelected, isTrue);

        // Test 3: Click Transfer History -> Universal Clipboard highlight immediately disappears,
        // Transfer History becomes highlighted
        final historyCards = find.widgetWithText(WorkspaceCard, 'Transfer History');
        expect(historyCards, findsOneWidget);
        await tester.tap(historyCards);
        await tester.pumpAndSettle();

        final unselectedClipboardCard = tester.widget<WorkspaceCard>(clipboardCards);
        final selectedHistoryCard = tester.widget<WorkspaceCard>(historyCards);
        expect(unselectedClipboardCard.isSelected, isFalse);
        expect(selectedHistoryCard.isSelected, isTrue);

        // Test 4: Click Settings & Privacy -> only Settings & Privacy is active
        final settingsCards = find.widgetWithText(WorkspaceCard, 'Settings & Privacy');
        expect(settingsCards, findsOneWidget);
        await tester.tap(settingsCards);
        await tester.pumpAndSettle();

        final unselectedHistoryCard = tester.widget<WorkspaceCard>(historyCards);
        final selectedSettingsCard = tester.widget<WorkspaceCard>(settingsCards);
        expect(unselectedHistoryCard.isSelected, isFalse);
        expect(selectedSettingsCard.isSelected, isTrue);

        // Test 5: Open section (by tapping already active card) and return to Dashboard ->
        // Universal Clipboard is NOT automatically selected
        await tester.tap(settingsCards);
        await tester.pumpAndSettle();
        // Now on SecuritySettingsView
        expect(find.byType(SecuritySettingsView), findsOneWidget);

        // Return to Dashboard via sidebar
        final dashboardSidebarItem = find.text('Dashboard');
        expect(dashboardSidebarItem, findsOneWidget);
        await tester.tap(dashboardSidebarItem);
        await tester.pumpAndSettle();

        // Dashboard is back, nothing is active
        final returnedClipboardCard = tester.widget<WorkspaceCard>(clipboardCards);
        expect(returnedClipboardCard.isSelected, isFalse);

        // Test 6: Double-tap / tapping twice opens section directly
        await tester.tap(clipboardCards);
        await tester.pump();
        await tester.tap(clipboardCards);
        await tester.pumpAndSettle();
        expect(find.byType(UniversalClipboardView), findsOneWidget);
      },
    );

    testWidgets('Mobile view mounts AppBar with menu and Drawer', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        buildTestWidget(
          size: const Size(400, 800),
          child: const DashboardScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Menu button exists
      expect(find.byIcon(Icons.menu_rounded), findsOneWidget);

      // Open drawer
      await tester.tap(find.byIcon(Icons.menu_rounded));
      await tester.pumpAndSettle();

      // Sidebar inside drawer is now visible
      expect(find.text('Ready to Receive'), findsOneWidget);
      expect(find.text('Dark Forest'), findsOneWidget);
    });

    testWidgets('Very narrow dashboard stays within its viewport', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(250, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        buildTestWidget(
          size: const Size(250, 800),
          child: const DashboardScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        find.text('Own Your Transfers, Shape Your Workflow'),
        findsOneWidget,
      );
    });

    testWidgets('Dashboard fits phone, tablet, and desktop widths', (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final width in [320.0, 360.0, 390.0, 600.0, 768.0, 1280.0]) {
        final size = Size(width, 900);
        tester.view.physicalSize = size;
        await tester.pumpWidget(buildTestWidget(size: size, child: const DashboardScreen()));
        await tester.pumpAndSettle();
        expect(find.text('Own Your Transfers, Shape Your Workflow'), findsOneWidget, reason: 'width: $width');
        expect(tester.takeException(), isNull, reason: 'width: $width');
      }
    });
  });
}
