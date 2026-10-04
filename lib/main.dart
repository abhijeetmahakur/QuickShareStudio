import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'data/services/transfer_engine.dart';
import 'data/services/app_update_service.dart';
import 'data/services/cross_device_transfer_service.dart';
import 'data/services/bridge_peer_link.dart';
import 'core/services/theme_service.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'app/app_shell.dart';
import 'app/theme.dart';
import 'core/constants.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Real device-to-device networking: native builds run their own LAN server; the
  // browser-based desktop app goes through the local launcher server (server.py).
  if (kIsWeb) {
    BridgePeerLink.connect().then((link) {
      if (link != null) TransferEngine().attachPeerLink(link);
    });
  } else {
    CrossDeviceTransferService().initialize();
  }
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => TransferEngine()),
        ChangeNotifierProvider(create: (_) => AppUpdateService()),
        ChangeNotifierProvider(create: (_) => CrossDeviceTransferService()),
        ChangeNotifierProvider(create: (_) => ThemeService()),
      ],
      child: const QuickShareApp(),
    ),
  );
}

class QuickShareApp extends StatefulWidget {
  final bool? initialOnboardingComplete;
  final bool? forceOnboarding;
  final bool showLegacyShell;
  final Widget? home;

  const QuickShareApp({
    super.key,
    this.initialOnboardingComplete,
    this.forceOnboarding,
    this.showLegacyShell = false,
    this.home,
  });

  @override
  State<QuickShareApp> createState() => _QuickShareAppState();
}

class _QuickShareAppState extends State<QuickShareApp> {
  ThemeMode _themeMode = ThemeMode.dark;
  late bool _isOnboardingComplete;
  bool? _builtWithDarkPalette;

  @override
  void initState() {
    super.initState();
    _isOnboardingComplete = widget.forceOnboarding == true
        ? false
        : (widget.initialOnboardingComplete ?? true);
  }

  void _toggleTheme() {
    setState(() {
      _themeMode = _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    });
  }

  void _onOnboardingCompleted() {
    setState(() {
      _isOnboardingComplete = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    ThemeService? themeService;
    try {
      themeService = context.watch<ThemeService>();
    } catch (_) {}

    final currentThemeMode = themeService?.themeMode ?? _themeMode;
    final isDark = currentThemeMode == ThemeMode.dark;

    // Screens read AppColors tokens directly, so a theme flip must rebuild the whole tree
    // (in place, keeping navigation and editor state) for every token to repaint.
    AppColors.isDark = isDark;
    if (_builtWithDarkPalette != null && _builtWithDarkPalette != isDark) {
      void markAll(Element element) {
        element.markNeedsBuild();
        element.visitChildren(markAll);
      }
      (context as Element).visitChildren(markAll);
    }
    _builtWithDarkPalette = isDark;

    void handleToggleTheme() {
      if (themeService != null) {
        themeService.toggleTheme();
      } else {
        _toggleTheme();
      }
    }

    final Widget effectiveHome;
    if (widget.home != null) {
      effectiveHome = widget.home!;
    } else if (widget.showLegacyShell || widget.forceOnboarding != null || widget.initialOnboardingComplete != null) {
      effectiveHome = _isOnboardingComplete
          ? AppShell(
              onToggleTheme: handleToggleTheme,
              isDarkMode: isDark,
            )
          : OnboardingScreen(
              onComplete: _onOnboardingCompleted,
            );
    } else {
      effectiveHome = DashboardScreen(
        onToggleTheme: handleToggleTheme,
        isDarkMode: isDark,
      );
    }

    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: currentThemeMode,
      // Instant switch: an animated lerp would mix old and new palettes mid-transition.
      themeAnimationDuration: Duration.zero,
      home: effectiveHome,
    );
  }
}

