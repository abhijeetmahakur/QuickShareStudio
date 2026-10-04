import 'package:flutter/material.dart';
import '../core/constants.dart';

class AppTheme {
  static ThemeData get lightTheme => _build(dark: false);
  static ThemeData get darkTheme => _build(dark: true);

  /// Builds a Material theme from the [AppColors] palette for the requested brightness.
  static ThemeData _build({required bool dark}) {
    final previous = AppColors.isDark;
    AppColors.isDark = dark;
    try {
      final inputBorder = OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.subtleBorderLight),
      );
      return ThemeData(
        useMaterial3: true,
        brightness: dark ? Brightness.dark : Brightness.light,
        fontFamily: 'Poppins',
        colorScheme: (dark ? const ColorScheme.dark() : const ColorScheme.light()).copyWith(
          primary: AppColors.limeGreen,
          onPrimary: AppColors.nearBlack,
          primaryContainer: AppColors.surfaceElevated,
          onPrimaryContainer: AppColors.primaryText,
          secondary: AppColors.limeGreen,
          onSecondary: AppColors.nearBlack,
          secondaryContainer: AppColors.surfaceElevated,
          onSecondaryContainer: AppColors.primaryText,
          surface: AppColors.charcoalSurface,
          onSurface: AppColors.primaryText,
          onSurfaceVariant: AppColors.secondaryText,
          surfaceContainerHighest: AppColors.surfaceElevated,
          outline: AppColors.subtleBorderLight,
          outlineVariant: AppColors.subtleBorder,
          error: AppColors.error,
          onError: Colors.white,
        ),
        scaffoldBackgroundColor: AppColors.dashboardBg,
        canvasColor: AppColors.dashboardBg,
        dividerColor: AppColors.subtleBorder,
        cardTheme: CardThemeData(
          color: AppColors.cardBg,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: AppColors.subtleBorder),
          ),
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: AppColors.charcoalSurface,
          foregroundColor: AppColors.primaryText,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            fontFamily: 'Poppins',
            color: AppColors.primaryText,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.limeGreen,
            foregroundColor: AppColors.nearBlack,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
            textStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w700),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primaryText,
            side: BorderSide(color: AppColors.subtleBorderLight, width: 1.2),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
            textStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: AppColors.limeGreen,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          ),
        ),
        iconTheme: IconThemeData(color: AppColors.primaryText),
        listTileTheme: ListTileThemeData(
          iconColor: AppColors.secondaryText,
          textColor: AppColors.primaryText,
        ),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected) ? AppColors.nearBlack : AppColors.secondaryText,
          ),
          trackColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected) ? AppColors.limeGreen : AppColors.surfaceElevated,
          ),
          trackOutlineColor: WidgetStateProperty.all(AppColors.subtleBorderLight),
        ),
        checkboxTheme: CheckboxThemeData(
          fillColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected) ? AppColors.limeGreen : Colors.transparent,
          ),
          checkColor: WidgetStateProperty.all(AppColors.nearBlack),
          side: BorderSide(color: AppColors.secondaryText, width: 1.4),
        ),
        progressIndicatorTheme: ProgressIndicatorThemeData(
          color: AppColors.limeGreen,
          linearTrackColor: AppColors.surfaceElevated,
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: AppColors.charcoalSurface,
          surfaceTintColor: Colors.transparent,
          elevation: 16,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: AppColors.subtleBorderLight),
          ),
          titleTextStyle: TextStyle(
            fontFamily: 'Poppins',
            color: AppColors.primaryText,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
          contentTextStyle: TextStyle(fontFamily: 'Poppins', color: AppColors.secondaryText, fontSize: 14),
        ),
        bottomSheetTheme: BottomSheetThemeData(
          backgroundColor: AppColors.charcoalSurface,
          surfaceTintColor: Colors.transparent,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        ),
        popupMenuTheme: PopupMenuThemeData(
          color: AppColors.charcoalSurface,
          surfaceTintColor: Colors.transparent,
          textStyle: TextStyle(fontFamily: 'Poppins', color: AppColors.primaryText),
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: AppColors.surfaceElevated,
          contentTextStyle: TextStyle(fontFamily: 'Poppins', color: AppColors.primaryText),
          actionTextColor: AppColors.limeGreen,
        ),
        tooltipTheme: TooltipThemeData(
          decoration: BoxDecoration(
            color: AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.subtleBorderLight),
          ),
          textStyle: TextStyle(fontFamily: 'Poppins', color: AppColors.primaryText, fontSize: 12),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.cardBg,
          hintStyle: TextStyle(color: AppColors.mutedText, fontSize: 13),
          labelStyle: TextStyle(color: AppColors.secondaryText, fontSize: 13),
          border: inputBorder,
          enabledBorder: inputBorder,
          focusedBorder: inputBorder.copyWith(
            borderSide: BorderSide(color: AppColors.limeGreen, width: 1.6),
          ),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: AppColors.cardBg,
          selectedColor: AppColors.limeGreen,
          labelStyle: TextStyle(color: AppColors.primaryText, fontSize: 12, fontWeight: FontWeight.w600),
          secondaryLabelStyle: const TextStyle(color: AppColors.nearBlack, fontSize: 12, fontWeight: FontWeight.bold),
          side: BorderSide(color: AppColors.subtleBorderLight),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        ),
        tabBarTheme: TabBarThemeData(
          labelColor: AppColors.limeGreen,
          unselectedLabelColor: AppColors.secondaryText,
          indicatorColor: AppColors.limeGreen,
          dividerColor: AppColors.subtleBorder,
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: AppColors.charcoalSurface,
          indicatorColor: AppColors.limeGreen.withValues(alpha: 0.25),
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        ),
        drawerTheme: DrawerThemeData(backgroundColor: AppColors.charcoalSurface),
        textSelectionTheme: TextSelectionThemeData(
          cursorColor: AppColors.limeGreen,
          selectionColor: AppColors.limeGreen.withValues(alpha: 0.35),
          selectionHandleColor: AppColors.limeGreen,
        ),
      );
    } finally {
      AppColors.isDark = previous;
    }
  }

  // Poppins Typography Helpers (Official Design System)
  static TextStyle poppinsRegular({
    double fontSize = 14,
    Color? color,
    double? height,
    double? letterSpacing,
  }) => TextStyle(
    fontFamily: 'Poppins',
    fontSize: fontSize,
    fontWeight: FontWeight.w400,
    color: color ?? AppColors.secondaryText,
    height: height,
    letterSpacing: letterSpacing,
  );

  static TextStyle poppinsSemiBold({
    double fontSize = 16,
    Color? color,
    double? height,
    double? letterSpacing,
  }) => TextStyle(
    fontFamily: 'Poppins',
    fontSize: fontSize,
    fontWeight: FontWeight.w600,
    color: color ?? AppColors.primaryText,
    height: height,
    letterSpacing: letterSpacing,
  );

  static TextStyle poppinsBold({
    double fontSize = 20,
    Color? color,
    double? height,
    double? letterSpacing,
  }) => TextStyle(
    fontFamily: 'Poppins',
    fontSize: fontSize,
    fontWeight: FontWeight.w700,
    color: color ?? AppColors.primaryText,
    height: height,
    letterSpacing: letterSpacing,
  );
}

