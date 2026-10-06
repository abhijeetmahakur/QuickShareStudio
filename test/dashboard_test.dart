import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    testWidgets('starts neutral and clears mouse hover on exit', (
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
      final cardDecoration =
          tester
                  .widget<AnimatedContainer>(
                    find.ancestor(
                      of: find.text('Universal Clipboard'),
                      matching: find.byType(AnimatedContainer),
                    ),
                  )
                  .decoration
              as BoxDecoration;
      expect(
        (cardDecoration.border! as Border).top.color,
        AppColors.subtleBorder,
      );

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(find.byType(WorkspaceCard)));
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        tester.widget<Icon>(find.byIcon(Icons.content_paste_rounded)).color,
        AppColors.white,
      );
      final hoveredCardDecoration =
          tester
                  .widget<AnimatedContainer>(
                    find.ancestor(
                      of: find.text('Universal Clipboard'),
                      matching: find.byType(AnimatedContainer),
                    ),
                  )
                  .decoration
              as BoxDecoration;
      expect(
        (hoveredCardDecoration.border! as Border).top.color,
        AppColors.subtleBorderLight,
      );

      await mouse.moveTo(const Offset(900, 700));
      await tester.pump(const Duration(milliseconds: 200));
      final exitedCardDecoration =
          tester
                  .widget<AnimatedContainer>(
                    find.ancestor(
                      of: find.text('Universal Clipboard'),
                      matching: find.byType(AnimatedContainer),
                    ),
                  )
                  .decoration
              as BoxDecoration;
      expect(
        (exitedCardDecoration.border! as Border).top.color,
        AppColors.subtleBorder,
      );
      expect(
        tester.widget<Icon>(find.byIcon(Icons.content_paste_rounded)).color,
        AppColors.white,
      );

      await tester.tap(find.text('Universal Clipboard'));
      await tester.pump();
      expect(tapped, isTrue);
    });

    testWidgets(
      'keyboard focus appears on Tab and mouse click does not focus',
      (tester) async {
        var activatedByKeyboard = false;
        await tester.pumpWidget(
          buildTestWidget(
            child: Listener(
              onPointerDown: (_) =>
                  FocusManager.instance.primaryFocus?.unfocus(),
              child: Scaffold(
                body: WorkspaceCard(
                  title: 'Universal Clipboard',
                  subtitle: 'Smart sync text & images',
                  icon: Icons.content_paste_rounded,
                  onTap: () => activatedByKeyboard = true,
                ),
              ),
            ),
          ),
        );

        final cardText = find.text('Universal Clipboard');
        expect(
          (tester
                      .widget<AnimatedContainer>(
                        find.ancestor(
                          of: cardText,
                          matching: find.byType(AnimatedContainer),
                        ),
                      )
                      .decoration!
                  as BoxDecoration)
              .border!
              .top
              .color,
          isNot(AppColors.primaryAccent),
        );

        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        expect(
          (tester
                      .widget<AnimatedContainer>(
                        find.ancestor(
                          of: cardText,
                          matching: find.byType(AnimatedContainer),
                        ),
                      )
                      .decoration!
                  as BoxDecoration)
              .border!
              .top
              .color,
          AppColors.primaryAccent,
        );

        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(activatedByKeyboard, isTrue);

        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        await mouse.moveTo(tester.getCenter(find.byType(WorkspaceCard)));
        await mouse.down(tester.getCenter(find.byType(WorkspaceCard)));
        await mouse.up();
        await tester.pump();
        expect(
          (tester
                      .widget<AnimatedContainer>(
                        find.ancestor(
                          of: cardText,
                          matching: find.byType(AnimatedContainer),
                        ),
                      )
                      .decoration!
                  as BoxDecoration)
              .border!
              .top
              .color,
          isNot(AppColors.primaryAccent),
        );
        await mouse.removePointer();
      },
    );

    testWidgets('touch press feedback clears on release', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          child: Scaffold(
            body: WorkspaceCard(
              title: 'Universal Clipboard',
              subtitle: 'Smart sync text & images',
              icon: Icons.content_paste_rounded,
              onTap: () {},
            ),
          ),
        ),
      );

      final card = find.byType(WorkspaceCard);
      final touch = await tester.createGesture(kind: PointerDeviceKind.touch);
      await touch.down(tester.getCenter(card));
      await tester.pump();
      final pressedDecoration =
          tester
                  .widget<AnimatedContainer>(
                    find.ancestor(
                      of: find.text('Smart sync text & images'),
                      matching: find.byType(AnimatedContainer),
                    ),
                  )
                  .decoration
              as BoxDecoration;
      expect(pressedDecoration.color, AppColors.subtleBorderLight);

      await touch.up();
      await tester.pump();
      final releasedDecoration =
          tester
                  .widget<AnimatedContainer>(
                    find.ancestor(
                      of: find.text('Smart sync text & images'),
                      matching: find.byType(AnimatedContainer),
                    ),
                  )
                  .decoration
              as BoxDecoration;
      expect(releasedDecoration.color, AppColors.cardBg);

      await touch.down(tester.getCenter(card));
      await tester.pump();
      await touch.cancel();
      await tester.pump();
      final cancelledDecoration =
          tester
                  .widget<AnimatedContainer>(
                    find.ancestor(
                      of: find.text('Smart sync text & images'),
                      matching: find.byType(AnimatedContainer),
                    ),
                  )
                  .decoration
              as BoxDecoration;
      expect(cancelledDecoration.color, AppColors.cardBg);
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

    testWidgets('sidebar hover is mouse-only and clears on exit', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildTestWidget(child: const Scaffold(body: Sidebar(width: 260.0))),
      );

      final label = find.text('PDF Tools');
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(label));
      await tester.pump(const Duration(milliseconds: 200));

      var decoration =
          tester
                  .widget<AnimatedContainer>(
                    find.ancestor(
                      of: label,
                      matching: find.byType(AnimatedContainer),
                    ),
                  )
                  .decoration
              as BoxDecoration;
      expect(decoration.border, isNotNull);

      await mouse.moveTo(Offset.zero);
      await tester.pump(const Duration(milliseconds: 200));
      decoration =
          tester
                  .widget<AnimatedContainer>(
                    find.ancestor(
                      of: label,
                      matching: find.byType(AnimatedContainer),
                    ),
                  )
                  .decoration
              as BoxDecoration;
      expect(decoration.border, isNull);
      await mouse.removePointer();
    });
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

        expect(
          find.text('Own Your Transfers, Shape Your Workflow'),
          findsOneWidget,
        );
        expect(
          find.text(
            '${engine.localDeviceName} · IP: ${engine.localIp} · Port: ${engine.localPort}',
          ),
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
        await tester.runAsync(
          () => engine.pairWithNumericCode('123456', deviceName: 'Test_Phone'),
        );
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

    testWidgets('lists real transfer history instead of placeholders', (
      tester,
    ) async {
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
      'Dashboard cards start neutral and navigate on one tap without retaining highlight',
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

        final clipboardCards = find.widgetWithText(
          WorkspaceCard,
          'Universal Clipboard',
        );
        expect(clipboardCards, findsOneWidget);
        final initialDecoration =
            tester
                    .widget<AnimatedContainer>(
                      find.ancestor(
                        of: find.text('Universal Clipboard').last,
                        matching: find.byType(AnimatedContainer),
                      ),
                    )
                    .decoration
                as BoxDecoration;
        expect(
          (initialDecoration.border! as Border).top.color,
          AppColors.subtleBorder,
        );

        await tester.tap(clipboardCards);
        await tester.pumpAndSettle();
        expect(find.byType(UniversalClipboardView), findsOneWidget);

        await tester.tap(find.text('Dashboard'));
        await tester.pumpAndSettle();
        expect(find.text('PRIMARY ACTIONS & WORKSPACE'), findsOneWidget);

        final returnedDecoration =
            tester
                    .widget<AnimatedContainer>(
                      find.ancestor(
                        of: find.text('Universal Clipboard').last,
                        matching: find.byType(AnimatedContainer),
                      ),
                    )
                    .decoration
                as BoxDecoration;
        expect(
          (returnedDecoration.border! as Border).top.color,
          AppColors.subtleBorder,
        );
      },
    );

    testWidgets('dashboard lifecycle loss clears active card hover', (
      tester,
    ) async {
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

      final card = find.widgetWithText(WorkspaceCard, 'Universal Clipboard');
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(card));
      await tester.pump();
      var decoration =
          tester
                  .widget<AnimatedContainer>(
                    find.ancestor(
                      of: find.text('Smart sync text & images'),
                      matching: find.byType(AnimatedContainer),
                    ),
                  )
                  .decoration
              as BoxDecoration;
      expect(
        (decoration.border! as Border).top.color,
        AppColors.subtleBorderLight,
      );

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      decoration =
          tester
                  .widget<AnimatedContainer>(
                    find.ancestor(
                      of: find.text('Smart sync text & images'),
                      matching: find.byType(AnimatedContainer),
                    ),
                  )
                  .decoration
              as BoxDecoration;
      expect((decoration.border! as Border).top.color, AppColors.subtleBorder);
      await mouse.removePointer();
    });

    testWidgets('mouse click cannot leave a keyboard focus outline behind', (
      tester,
    ) async {
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

      final card = find.widgetWithText(WorkspaceCard, 'Universal Clipboard');
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(card));
      await tester.pump();
      await mouse.down(tester.getCenter(card));
      await mouse.up();
      await tester.pumpAndSettle();
      expect(find.byType(UniversalClipboardView), findsOneWidget);
      await tester.tap(find.text('Dashboard'));
      await tester.pumpAndSettle();
      await mouse.moveTo(const Offset(20, 20));
      await tester.pumpAndSettle();

      final decoration =
          tester
                  .widget<AnimatedContainer>(
                    find.ancestor(
                      of: find.text('Universal Clipboard').last,
                      matching: find.byType(AnimatedContainer),
                    ),
                  )
                  .decoration
              as BoxDecoration;
      expect((decoration.border! as Border).top.color, AppColors.subtleBorder);
      await mouse.removePointer();
    });

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

    testWidgets('Dashboard fits phone, tablet, and desktop widths', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final width in [320.0, 360.0, 390.0, 600.0, 768.0, 1280.0]) {
        final size = Size(width, 900);
        tester.view.physicalSize = size;
        await tester.pumpWidget(
          buildTestWidget(size: size, child: const DashboardScreen()),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('Own Your Transfers, Shape Your Workflow'),
          findsOneWidget,
          reason: 'width: $width',
        );
        expect(tester.takeException(), isNull, reason: 'width: $width');
      }
    });
  });
}
