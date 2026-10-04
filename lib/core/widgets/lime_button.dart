import 'package:flutter/material.dart';
import '../constants.dart';

enum LimeButtonVariant { primary, secondary, ghost }

class LimeButton extends StatefulWidget {
  final String text;
  final VoidCallback? onPressed;
  final Widget? icon;
  final Widget? trailingIcon;
  final LimeButtonVariant variant;
  final bool isLoading;
  final double? width;
  final double height;
  final double borderRadius;
  final EdgeInsetsGeometry padding;

  const LimeButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.icon,
    this.trailingIcon,
    this.variant = LimeButtonVariant.primary,
    this.isLoading = false,
    this.width,
    this.height = 50.0,
    this.borderRadius = 28.0,
    this.padding = const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
  });

  const LimeButton.secondary({
    super.key,
    required this.text,
    required this.onPressed,
    this.icon,
    this.trailingIcon,
    this.isLoading = false,
    this.width,
    this.height = 50.0,
    this.borderRadius = 28.0,
    this.padding = const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
  }) : variant = LimeButtonVariant.secondary;


  const LimeButton.ghost({
    super.key,
    required this.text,
    required this.onPressed,
    this.icon,
    this.trailingIcon,
    this.isLoading = false,
    this.width,
    this.height = 50.0,
    this.borderRadius = 28.0,
    this.padding = const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
  }) : variant = LimeButtonVariant.ghost;

  @override
  State<LimeButton> createState() => _LimeButtonState();
}

class _LimeButtonState extends State<LimeButton> {
  bool _isHovered = false;
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final isEnabled = widget.onPressed != null && !widget.isLoading;

    Color bgColor;
    Color fgColor;
    Border? border;
    List<BoxShadow> shadows = [];

    switch (widget.variant) {
      case LimeButtonVariant.primary:
        bgColor = isEnabled
            ? (_isHovered ? const Color(0xFFE2FF66) : AppColors.limeGreen)
            : AppColors.limeGreen.withValues(alpha: 0.35);
        fgColor = isEnabled ? AppColors.nearBlack : AppColors.nearBlack.withValues(alpha: 0.5);
        if (isEnabled) {
          shadows = [
            BoxShadow(
              color: AppColors.limeGreen.withValues(alpha: _isHovered ? 0.45 : 0.25),
              blurRadius: _isHovered ? 20 : 12,
              offset: const Offset(0, 4),
            ),
          ];
        }
        break;

      case LimeButtonVariant.secondary:
        bgColor = _isHovered ? AppColors.overlay.withValues(alpha: 0.18) : AppColors.overlay.withValues(alpha: 0.10);
        fgColor = isEnabled ? AppColors.white : AppColors.softGray.withValues(alpha: 0.5);
        border = Border.all(
          color: _isHovered ? AppColors.limeGreen : AppColors.glassBorder,
          width: 1.2,
        );
        break;

      case LimeButtonVariant.ghost:
        bgColor = _isHovered ? AppColors.overlay.withValues(alpha: 0.08) : Colors.transparent;
        fgColor = isEnabled
            ? (_isHovered ? AppColors.white : AppColors.softGray)
            : AppColors.softGray.withValues(alpha: 0.4);
        break;
    }

    Widget content = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.isLoading) ...[
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              valueColor: AlwaysStoppedAnimation<Color>(fgColor),
            ),
          ),
          const SizedBox(width: 8),
        ] else if (widget.icon != null) ...[
          widget.icon!,
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Text(
            widget.text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: fgColor,
              letterSpacing: 0.2,
            ),
          ),
        ),
        if (widget.trailingIcon != null && !widget.isLoading) ...[
          const SizedBox(width: 8),
          widget.trailingIcon!,
        ],
      ],
    );


    return Semantics(
      button: true,
      enabled: isEnabled,
      label: widget.text,
      child: FocusableActionDetector(
        onShowFocusHighlight: (f) => setState(() => _isFocused = f),
        child: MouseRegion(
          cursor: isEnabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: AnimatedScale(
            scale: _isHovered && isEnabled ? 1.015 : 1.0,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: widget.width,
              height: widget.height,
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(widget.borderRadius),
                border: _isFocused
                    ? Border.all(color: AppColors.limeGreen, width: 2.0)
                    : border,
                boxShadow: shadows,
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: isEnabled ? widget.onPressed : null,
                  borderRadius: BorderRadius.circular(widget.borderRadius),
                  splashColor: widget.variant == LimeButtonVariant.primary
                      ? Colors.black.withValues(alpha: 0.12)
                      : AppColors.limeGreen.withValues(alpha: 0.15),
                  highlightColor: Colors.transparent,
                  child: Padding(
                    padding: widget.padding,
                    child: Center(child: content),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
