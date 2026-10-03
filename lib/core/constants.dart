import 'package:flutter/material.dart';

class AppColors {
  // Brand Primary (Vibrant Indigo / Violet gradient)
  static const Color primary = Color(0xFF6366F1);
  static const Color primaryLight = Color(0xFF818CF8);
  static const Color primaryDark = Color(0xFF4F46E5);
  static const Color primaryContainer = Color(0xFFEEF2FF);

  // Secondary (Electric Cyan / Teal)
  static const Color secondary = Color(0xFF06B6D4);
  static const Color secondaryLight = Color(0xFF22D3EE);
  static const Color secondaryContainer = Color(0xFFECFEFF);

  // Accent (Emerald Green & Amber)
  static const Color success = Color(0xFF10B981);
  static const Color successContainer = Color(0xFFD1FAE5);
  static const Color warning = Color(0xFFF59E0B);
  static const Color warningContainer = Color(0xFFFEF3C7);
  static const Color error = Color(0xFFEF4444);
  static const Color errorContainer = Color(0xFFFEE2E2);

  // Dark Theme Neutral Surfaces
  static const Color darkBg = Color(0xFF0F172A); // Slate 900
  static const Color darkSurface = Color(0xFF1E293B); // Slate 800
  static const Color darkSurfaceVariant = Color(0xFF334155); // Slate 700
  static const Color darkBorder = Color(0xFF334155);
  static const Color darkText = Color(0xFFF8FAFC);
  static const Color darkTextMuted = Color(0xFF94A3B8);

  // Light Theme Neutral Surfaces
  static const Color lightBg = Color(0xFFF8FAFC);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceVariant = Color(0xFFF1F5F9);
  static const Color lightBorder = Color(0xFFE2E8F0);
  static const Color lightText = Color(0xFF0F172A);
  static const Color lightTextMuted = Color(0xFF64748B);
}

class AppConstants {
  static const String appName = 'QuickShare Studio';
  static const String appTagline = 'Cross-Platform File Sharing & Professional PDF Studio';
  static const String appVersion = '1.0.0';

  // Network & Pairing Defaults
  static const int defaultHttpPort = 8088;
  static const int defaultWsPort = 8089;
  static const int pairingCodeExpirationMinutes = 5;
  static const int chunkSize = 512 * 1024; // 512 KB chunks

  // PDF Page Sizes (in PDF points, 72 points per inch)
  static const double a4Width = 595.28;
  static const double a4Height = 841.89;
  static const double a3Width = 841.89;
  static const double a3Height = 1190.55;
  static const double a5Width = 419.53;
  static const double a5Height = 595.28;
  static const double letterWidth = 612.0;
  static const double letterHeight = 792.0;
}
