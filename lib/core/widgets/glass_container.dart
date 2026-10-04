import 'dart:ui';
import 'package:flutter/material.dart';
import '../constants.dart';

/// Reusable Liquid Glass container implementing glassmorphism with backdrop blur,
/// semi-transparent dark surface, reflective borders, and subtle ambient glows.
class GlassContainer extends StatelessWidget {
  final Widget child;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final double blur;
  final Color? surfaceColor;
  final Color? borderColor;
  final double borderWidth;
  final Color? glowColor;
  final double glowRadius;
  final bool enableGlow;
  final VoidCallback? onTap;
  final BoxConstraints? constraints;
  final AlignmentGeometry? alignment;

  const GlassContainer({
    super.key,
    required this.child,
    this.width,
    this.height,
    this.padding,
    this.margin,
    this.borderRadius = 24.0,
    this.blur = 16.0,
    this.surfaceColor,
    this.borderColor,
    this.borderWidth = 1.0,
    this.glowColor,
    this.glowRadius = 16.0,
    this.enableGlow = false,
    this.onTap,
    this.constraints,
    this.alignment,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveBorderRadius = BorderRadius.circular(borderRadius);
    final effectiveSurfaceColor = surfaceColor ?? AppColors.glassCardBg;
    final effectiveBorderColor = borderColor ?? AppColors.glassBorder;

    final shadows = <BoxShadow>[
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.45),
        blurRadius: 24,
        offset: const Offset(0, 10),
      ),
      if (enableGlow && glowColor != null)
        BoxShadow(
          color: glowColor!.withValues(alpha: 0.35),
          blurRadius: glowRadius,
          spreadRadius: -2,
        ),
    ];

    Widget body = Container(
      width: width,
      height: height,
      constraints: constraints,
      alignment: alignment,
      padding: padding ?? const EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        color: effectiveSurfaceColor,
        borderRadius: effectiveBorderRadius,
        border: Border.all(
          color: effectiveBorderColor,
          width: borderWidth,
        ),
        boxShadow: shadows,
      ),
      child: child,
    );

    // Apply backdrop filter on supported platforms (safe with web and desktop)
    if (blur > 0) {
      body = ClipRRect(
        borderRadius: effectiveBorderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: body,
        ),
      );
    }

    if (margin != null) {
      body = Padding(padding: margin!, child: body);
    }

    if (onTap != null) {
      body = InkWell(
        onTap: onTap,
        borderRadius: effectiveBorderRadius,
        hoverColor: AppColors.limeGreen.withValues(alpha: 0.04),
        splashColor: AppColors.limeGreen.withValues(alpha: 0.1),
        child: body,
      );
    }

    return body;
  }
}
