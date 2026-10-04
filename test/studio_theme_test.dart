import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:quickshare/app/theme.dart';
import 'package:quickshare/core/constants.dart';
import 'package:quickshare/core/services/theme_service.dart';
import 'package:quickshare/core/widgets/hover_card.dart';
import 'package:quickshare/data/services/app_update_service.dart';
import 'package:quickshare/data/services/transfer_engine.dart';
import 'package:quickshare/features/security/security_settings_view.dart';
import 'package:quickshare/features/transfer_history/transfer_history_view.dart';
import 'package:quickshare/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Transfer History uses the charcoal and lime Studio palette', (
    tester,
  ) async {
    final engine = TransferEngine();
    engine.stopTimers();

    await tester.pumpWidget(
      ChangeNotifierProvider<TransferEngine>.value(
        value: engine,
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: const TransferHistoryView(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, AppColors.dashboardBg);

    final search = tester.widget<TextField>(find.byType(TextField));
    expect(search.decoration?.fillColor, AppColors.charcoalSurface);

    final dropdown = tester.widget<DropdownButton<String>>(
      find.byType(DropdownButton<String>).first,
    );
    expect(dropdown.dropdownColor, AppColors.cardBg);

    await tester.pumpWidget(const SizedBox());
    engine.stopTimers();
  });

  testWidgets('Settings uses charcoal panels and lime primary controls', (
    tester,
  ) async {
    final engine = TransferEngine();
    engine.stopTimers();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<TransferEngine>.value(value: engine),
          ChangeNotifierProvider<AppUpdateService>.value(
            value: AppUpdateService(),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: const SecuritySettingsView(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final layoutException = tester.takeException();
    expect(
      layoutException,
      isNull,
      reason: 'Settings layout raised: $layoutException',
    );

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, AppColors.dashboardBg);
    expect(
      find.byType(HoverCard).evaluate().every((element) {
        return (element.widget as HoverCard).color == AppColors.charcoalSurface;
      }),
      isTrue,
    );

    final savePath = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Save Path'),
    );
    expect(
      savePath.style?.backgroundColor?.resolve({}),
      AppColors.primaryAccent,
    );
    expect(savePath.style?.foregroundColor?.resolve({}), AppColors.nearBlack);

    await tester.pumpWidget(const SizedBox());
    engine.stopTimers();
  });

  testWidgets('Settings dark-mode switch repaints the whole app in the light palette and back', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final engine = TransferEngine();
    engine.stopTimers();
    final themeService = ThemeService();
    await themeService.setThemeMode(ThemeMode.dark);
    addTearDown(() => themeService.setThemeMode(ThemeMode.dark));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<TransferEngine>.value(value: engine),
          ChangeNotifierProvider<AppUpdateService>.value(value: AppUpdateService()),
          ChangeNotifierProvider<ThemeService>.value(value: themeService),
        ],
        child: const QuickShareApp(home: SecuritySettingsView()),
      ),
    );
    await tester.pumpAndSettle();

    Color scaffoldBg() => tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor!;
    expect(scaffoldBg(), const Color(0xFF0C0C0C));
    expect(find.text('Dark Mode (Enabled)'), findsOneWidget);

    await tester.tap(find.widgetWithText(SwitchListTile, 'Dark Mode (Enabled)'));
    await tester.pumpAndSettle();

    expect(AppColors.isDark, isFalse);
    expect(scaffoldBg(), const Color(0xFFF4F5F0));
    expect(find.text('Light Mode (Enabled)'), findsOneWidget);
    expect(
      find.byType(HoverCard).evaluate().every((element) {
        return (element.widget as HoverCard).color == const Color(0xFFFFFFFF);
      }),
      isTrue,
      reason: 'settings panels must switch to light surfaces',
    );

    await tester.tap(find.widgetWithText(SwitchListTile, 'Light Mode (Enabled)'));
    await tester.pumpAndSettle();
    expect(AppColors.isDark, isTrue);
    expect(scaffoldBg(), const Color(0xFF0C0C0C));

    await tester.pumpWidget(const SizedBox());
    engine.stopTimers();
  });
}
