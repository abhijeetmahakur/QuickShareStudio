import 'package:flutter/material.dart';

/// The single QuickShare Studio palette: lime accent on charcoal (dark) or on soft paper (light).
///
/// Every token resolves against the active theme, so screens stay uniform and follow the
/// light/dark switch. [ThemeService] flips [isDark]; QuickShareApp then rebuilds the tree.
/// Legacy token names (primary, darkSurface, glass*, ...) are kept as aliases of the same palette.
class AppColors {
  static bool isDark = true;

  static Color _pick(Color dark, Color light) => isDark ? dark : light;

  // Core brand accent. On light backgrounds a deeper lime keeps icons and text readable.
  static Color get limeGreen => _pick(const Color(0xFFD5FF40), const Color(0xFF65A30D));
  static Color get primaryAccent => limeGreen;
  static Color get statusIndicator => limeGreen;
  static Color get glassBorderLime => limeGreen;
  static Color get glassGlowLime => limeGreen.withValues(alpha: 0.2);

  /// Foreground used on top of accent fills (buttons, selected chips). Dark in both modes.
  static const Color nearBlack = Color(0xFF0C0C0B);

  // Surfaces
  static Color get dashboardBg => _pick(const Color(0xFF0C0C0C), const Color(0xFFF4F5F0));
  static Color get charcoalSurface => _pick(const Color(0xFF171717), const Color(0xFFFFFFFF));
  static Color get cardBg => _pick(const Color(0xFF1A1A1A), const Color(0xFFFFFFFF));
  static Color get surfaceElevated => _pick(const Color(0xFF222222), const Color(0xFFECEEE6));
  static Color get secondarySurface => _pick(const Color(0xFFC0C2B8), const Color(0xFFE4E6DD));

  // Text
  static Color get primaryText => _pick(const Color(0xFFFFFFFF), const Color(0xFF151613));
  static Color get secondaryText => _pick(const Color(0xFFC0C2B8), const Color(0xFF55584F));
  static Color get mutedText => _pick(const Color(0xFF7A7D73), const Color(0xFF8A8D84));
  static Color get white => primaryText;
  static Color get softGray => secondaryText;

  // Borders & overlays
  static Color get subtleBorder => _pick(const Color(0xFF262626), const Color(0xFFE2E4DC));
  static Color get subtleBorderLight => _pick(const Color(0xFF333333), const Color(0xFFD4D7CC));
  /// Base for translucent overlays/hairlines: white on dark, black on light.
  static Color get overlay => _pick(const Color(0xFFFFFFFF), const Color(0xFF000000));
  static Color get glassBorder => overlay.withValues(alpha: isDark ? 0.16 : 0.10);

  // Glass surfaces
  static Color get glassSurfaceDark => charcoalSurface.withValues(alpha: 0.9);
  static Color get glassCardBg => cardBg.withValues(alpha: 0.85);
  static Color get glassSurfaceLight => overlay.withValues(alpha: 0.1);
  static Color get glassInputBg => _pick(const Color(0x1F2A2A28), const Color(0xFFF4F5F0));

  // Status
  static Color get success => _pick(const Color(0xFF34D399), const Color(0xFF059669));
  static Color get successContainer => success.withValues(alpha: 0.15);
  static Color get warning => _pick(const Color(0xFFFBBF24), const Color(0xFFD97706));
  static Color get warningContainer => warning.withValues(alpha: 0.15);
  static Color get error => _pick(const Color(0xFFF87171), const Color(0xFFDC2626));
  static Color get errorContainer => error.withValues(alpha: 0.15);

  // Legacy aliases (formerly a separate blue/navy palette) mapped onto the one palette.
  static Color get primary => limeGreen;
  static Color get primaryLight => limeGreen;
  static Color get primaryDark => limeGreen;
  static Color get primaryContainer => surfaceElevated;
  static Color get secondary => limeGreen;
  static Color get secondaryLight => limeGreen;
  static Color get secondaryContainer => surfaceElevated;
  static const Color onLimeText = nearBlack;
  static const Color onLimeMuted = Color(0xFF3A3D33);
  static const Color onPrimary = nearBlack;
  static const Color onSecondary = nearBlack;
  static Color get accent => limeGreen;
  static Color get surface => charcoalSurface;
  static Color get border => subtleBorder;
  static Color get darkBg => dashboardBg;
  static Color get darkSurface => charcoalSurface;
  static Color get darkSurfaceVariant => surfaceElevated;
  static Color get darkBorder => glassBorder;
  static Color get darkBorderGlow => limeGreen.withValues(alpha: 0.25);
  static Color get darkText => primaryText;
  static Color get darkTextMuted => secondaryText;
  static Color get lightBg => dashboardBg;
  static Color get lightSurface => charcoalSurface;
  static Color get lightSurfaceVariant => surfaceElevated;
  static Color get lightBorder => subtleBorder;
  static Color get lightText => primaryText;
  static Color get lightTextMuted => secondaryText;

  // Gradients
  static LinearGradient get primaryGradient => LinearGradient(
        colors: [limeGreen, Color.lerp(limeGreen, nearBlack, 0.15)!],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
  static LinearGradient get heroLimeGradient => heroGlassGradient;
  static LinearGradient get heroGlassGradient => LinearGradient(
        colors: [surfaceElevated, charcoalSurface],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
  static LinearGradient get darkForestGradient => heroGlassGradient;
  static LinearGradient get glassCardGradient => LinearGradient(
        colors: [cardBg, charcoalSurface],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
  static LinearGradient get skyGlassGradient => primaryGradient;
  static RadialGradient get ambientSkyGradient => RadialGradient(
        center: const Alignment(0.0, -0.8),
        radius: 1.4,
        colors: [surfaceElevated, charcoalSurface, dashboardBg],
        stops: const [0.0, 0.45, 1.0],
      );
}

class AppConstants {
  static const String appName = 'QuickShare Studio';
  static const String appTagline = 'Cross-Platform File Sharing & Professional PDF Studio';
  static const String appVersion = '2.0.16';

  // Network & Pairing Defaults
  static const int defaultHttpPort = 8088;
  // UDP port for "who is on this Wi-Fi?" discovery (LAN peer protocol v1).
  static const int discoveryPort = 8089;
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
