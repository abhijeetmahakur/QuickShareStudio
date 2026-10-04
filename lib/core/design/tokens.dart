import 'package:flutter/material.dart';

import '../constants.dart';

/// Spacing scale (4-pt grid) shared by the connection and transfer screens.
abstract final class Space {
  static const double xs = 4;
  static const double s = 8;
  static const double m = 12;
  static const double l = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

abstract final class Radii {
  static const double chip = 8;
  static const double control = 12;
  static const double card = 18;
}

/// Minimum interactive size (Material / WCAG guidance).
const double minTapTarget = 48;

/// Typography built on the app font and the [AppColors] palette.
abstract final class TextStyles {
  static TextStyle get title => TextStyle(fontFamily: 'Poppins', fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.primaryText);
  static TextStyle get body => TextStyle(fontFamily: 'Poppins', fontSize: 13, color: AppColors.primaryText, height: 1.35);
  static TextStyle get caption => TextStyle(fontFamily: 'Poppins', fontSize: 11.5, color: AppColors.secondaryText, height: 1.35);
  static TextStyle get label => TextStyle(fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primaryText);
  static TextStyle get digits => TextStyle(
        fontFamily: 'Poppins',
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: 6,
        color: AppColors.primaryText,
        fontFeatures: const [FontFeature.tabularFigures()],
      );
}

/// A bordered surface used for cards in the transfer UI.
BoxDecoration cardDecoration({Color? border}) => BoxDecoration(
      color: AppColors.charcoalSurface,
      borderRadius: BorderRadius.circular(Radii.card),
      border: Border.all(color: border ?? AppColors.subtleBorder),
    );
