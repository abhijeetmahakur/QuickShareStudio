import 'package:flutter/material.dart';
import '../constants.dart';

class HoverCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double liftOffset;
  final double scale;
  final Color? borderColor;
  final Color? hoverBorderColor;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Color? color;
  final Color? hoverColor;
  final bool enableHover;
  final MouseCursor cursor;

  const HoverCard({
    super.key,
    required this.child,
    this.onTap,
    this.liftOffset = 3.5,
    this.scale = 1.015,
    this.borderColor,
    this.hoverBorderColor,
    this.borderRadius,
    this.padding,
    this.margin,
    this.color,
    this.hoverColor,
    this.enableHover = true,
    this.cursor = SystemMouseCursors.click,
  });

  @override
  State<HoverCard> createState() => _HoverCardState();
}

class _HoverCardState extends State<HoverCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    if (!widget.enableHover) {
      return widget.child;
    }

    final br = widget.borderRadius ?? BorderRadius.circular(18);
    final defaultBg = widget.color ?? (AppColors.cardBg);
    final hoverBg = widget.hoverColor ??
        (AppColors.surfaceElevated);
    final defaultBorder = widget.borderColor ??
        (AppColors.overlay.withValues(alpha: 0.14));
    final hoverBorder = widget.hoverBorderColor ?? AppColors.primary;

    return MouseRegion(
      cursor: widget.cursor,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          margin: widget.margin,
          transform: _isHovered
              ? (Matrix4.translationValues(0.0, -widget.liftOffset, 0.0)
                ..scaleByDouble(widget.scale, widget.scale, 1.0, 1.0))
              : Matrix4.identity(),
          padding: widget.padding,
          decoration: BoxDecoration(
            color: _isHovered ? hoverBg : defaultBg,
            borderRadius: br,
            border: Border.all(
              color: _isHovered ? hoverBorder : defaultBorder,
              width: _isHovered ? 1.6 : 1.0,
            ),
            boxShadow: _isHovered
                ? [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.28),
                      blurRadius: 20,
                      spreadRadius: 1,
                      offset: const Offset(0, 6),
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
          ),
          child: Material(
            type: MaterialType.transparency,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
