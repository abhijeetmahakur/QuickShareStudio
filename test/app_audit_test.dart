import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:quickshare/data/services/app_update_service.dart';
import 'package:quickshare/data/services/transfer_engine.dart';
import 'package:quickshare/features/dashboard/dashboard_screen.dart';

/// Whole-app audit checks: every section renders without layout errors at desktop,
/// tablet and phone widths, and key workflows behave as labelled.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const sections = [
    'Dashboard',
    'PDF Studio',
    'Device Pairing',
    'Send Files',
    'Received Items',
    'PDF Tools',
    'Universal Clipboard',
    'Transfer History',
    'Settings & Privacy',
  ];

  Future<void> pumpApp(WidgetTester tester, Size size, {int initialIndex = 0}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final engine = TransferEngine()..stopTimers();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<TransferEngine>.value(value: engine),
          ChangeNotifierProvider<AppUpdateService>.value(value: AppUpdateService()),
        ],
        child: MaterialApp(
          theme: ThemeData(fontFamily: 'Poppins', brightness: Brightness.dark),
          home: DashboardScreen(initialIndex: initialIndex),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
  }

  group('Layout: every section renders cleanly', () {
    const sizes = {
      'desktop 1366x850': Size(1366, 850),
      'tablet 900x700': Size(900, 700),
      'phone 412x900': Size(412, 900),
    };
    for (final entry in sizes.entries) {
      for (var i = 0; i < sections.length; i++) {
        testWidgets('${sections[i]} @ ${entry.key}', (tester) async {
          await pumpApp(tester, entry.value, initialIndex: i);
          final error = tester.takeException();
          expect(error, isNull, reason: error is FlutterError ? error.toStringDeep() : '$error');
        });
      }
    }
  });

  testWidgets('Switching sections keeps work (PDF Tools split setup survives a round trip)', (tester) async {
    await pumpApp(tester, const Size(1366, 850), initialIndex: 5);
    await tester.tap(find.text('Split PDF'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Load 5-Page Sample Lab PDF'));
    await tester.pumpAndSettle();
    expect(find.textContaining('5 Pages'), findsWidgets);

    // Go to the Dashboard and back via the sidebar.
    await tester.tap(find.text('Dashboard').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('PDF Tools').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('5 Pages'), findsWidgets, reason: 'split source should still be loaded');
  });

  testWidgets('Split rejects pages that do not exist instead of inventing them', (tester) async {
    await pumpApp(tester, const Size(1366, 850), initialIndex: 5);
    await tester.tap(find.text('Split PDF'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Load 5-Page Sample Lab PDF'));
    await tester.pumpAndSettle();

    final pageField = find.widgetWithText(TextField, 'Pages to Extract (from Source)').first;
    await tester.enterText(pageField, '1, 9');
    await tester.pump();
    // Let the "Loaded sample" snackbar go away so it does not cover the button.
    ScaffoldMessenger.of(tester.element(find.text('Split PDF'))).hideCurrentSnackBar();
    await tester.pumpAndSettle();
    final execute = find.textContaining('Execute Multi-PDF Split');
    await tester.ensureVisible(execute);
    await tester.pumpAndSettle();
    await tester.tap(execute);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('page 9 does not exist'), findsOneWidget);
    expect(find.text('GENERATED SPLIT DOCUMENTS (READY TO DOWNLOAD & OPEN):'), findsNothing);
  });

  testWidgets('Pairing screen warns that transfers are simulated when no network service runs', (tester) async {
    await pumpApp(tester, const Size(1366, 850), initialIndex: 2);
    expect(find.textContaining('Demo mode'), findsOneWidget);
  });
}
