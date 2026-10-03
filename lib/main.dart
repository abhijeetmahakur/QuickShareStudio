import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'data/services/transfer_engine.dart';
import 'app/app_shell.dart';
import 'app/theme.dart';
import 'core/constants.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => TransferEngine()),
      ],
      child: const QuickShareApp(),
    ),
  );
}

class QuickShareApp extends StatefulWidget {
  const QuickShareApp({super.key});

  @override
  State<QuickShareApp> createState() => _QuickShareAppState();
}

class _QuickShareAppState extends State<QuickShareApp> {
  ThemeMode _themeMode = ThemeMode.dark;

  void _toggleTheme() {
    setState(() {
      _themeMode = _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: _themeMode,
      home: AppShell(
        onToggleTheme: _toggleTheme,
        isDarkMode: _themeMode == ThemeMode.dark,
      ),
    );
  }
}
