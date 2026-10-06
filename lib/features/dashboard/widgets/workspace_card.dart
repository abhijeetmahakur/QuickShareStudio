import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants.dart';

/// Reusable interactive card for the PRIMARY ACTIONS & WORKSPACE section.
/// A soft accent glow distinguishes mouse hover from keyboard focus and touch press.
class WorkspaceCard extends StatefulWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final int interactionResetToken;
  final VoidCallback? onTap;

  const WorkspaceCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.interactionResetToken = 0,
    this.onTap,
  });

  @override
  State<WorkspaceCard> createState() => _WorkspaceCardState();
}

class _WorkspaceCardState extends State<WorkspaceCard> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'Dashboard workspace card');
  bool _isHovered = false;
  bool _isPressed = false;
  bool _showKeyboardFocus = false;

  @override
  void didUpdateWidget(covariant WorkspaceCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.interactionResetToken != widget.interactionResetToken) {
      _isHovered = false;
      _isPressed = false;
      _showKeyboardFocus = false;
      _focusNode.unfocus();
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _setHovered(bool hovered) {
    if (_isHovered == hovered || !mounted) return;
    setState(() => _isHovered = hovered);
  }

  void _setPressed(bool pressed) {
    if (_isPressed == pressed || !mounted) return;
    setState(() => _isPressed = pressed);
  }

  @override
  Widget build(BuildContext context) {
    final isFocused = _showKeyboardFocus;
    final isHovered = _isHovered && !isFocused;
    final backgroundColor = _isPressed
        ? AppColors.subtleBorderLight
        : (isHovered ? AppColors.surfaceElevated : AppColors.cardBg);

    return FocusableActionDetector(
      focusNode: _focusNode,
      onShowFocusHighlight: (show) {
        final shouldShow =
            show &&
            FocusManager.instance.highlightMode ==
                FocusHighlightMode.traditional;
        if (_showKeyboardFocus != shouldShow && mounted) {
          setState(() => _showKeyboardFocus = shouldShow);
        }
      },
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      },
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onTap?.call();
            return null;
          },
        ),
      },
      child: MouseRegion(
        cursor: widget.onTap != null
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onEnter: (event) {
          if (event.kind == PointerDeviceKind.mouse) _setHovered(true);
        },
        onExit: (_) => _setHovered(false),
        child: InkWell(
          canRequestFocus: false,
          onTap: widget.onTap,
          onTapDown: (details) {
            if (details.kind == PointerDeviceKind.touch) _setPressed(true);
          },
          onTapUp: (_) => _setPressed(false),
          onTapCancel: () => _setPressed(false),
          borderRadius: BorderRadius.circular(16.0),
          splashColor: AppColors.primaryAccent.withValues(alpha: 0.1),
          highlightColor: Colors.transparent,
          focusColor: Colors.transparent,
          hoverColor: Colors.transparent,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            transform: isHovered
                ? Matrix4.translationValues(0.0, -2.5, 0.0)
                : Matrix4.identity(),
            padding: const EdgeInsets.all(13.0),
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(16.0),
              border: Border.all(
                color: isFocused
                    ? AppColors.primaryAccent
                    : (isHovered
                          ? AppColors.primaryAccent.withValues(alpha: 0.48)
                          : AppColors.subtleBorder),
                width: isFocused ? 1.5 : 1.0,
              ),
              boxShadow: [
                if (isFocused || isHovered)
                  BoxShadow(
                    color: AppColors.primaryAccent.withValues(
                      alpha: isFocused ? 0.12 : 0.20,
                    ),
                    blurRadius: isHovered ? 22.0 : 12.0,
                    spreadRadius: isHovered ? 1.0 : 0.0,
                    offset: Offset(0, isHovered ? 3 : 2),
                  ),
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha: isHovered ? 0.35 : 0.2,
                  ),
                  blurRadius: isHovered ? 10.0 : 4.0,
                  offset: Offset(0, isHovered ? 3 : 1),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 34.0,
                  height: 34.0,
                  decoration: BoxDecoration(
                    color: isHovered
                        ? AppColors.subtleBorderLight
                        : AppColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(8.0),
                    border: Border.all(
                      color: isFocused
                          ? AppColors.primaryAccent.withValues(alpha: 0.5)
                          : (isHovered
                                ? AppColors.subtleBorderLight
                                : AppColors.surfaceElevated),
                      width: 1.0,
                    ),
                  ),
                  child: Icon(
                    widget.icon,
                    size: 18.0,
                    color: isFocused
                        ? AppColors.primaryAccent
                        : AppColors.white,
                  ),
                ),
                const SizedBox(height: 8.0),
                Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 14.0,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryText,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 4.0),
                Text(
                  widget.subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11.5,
                    fontWeight: FontWeight.w400,
                    color: AppColors.secondaryText,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
