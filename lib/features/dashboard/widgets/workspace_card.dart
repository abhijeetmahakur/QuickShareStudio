import 'package:flutter/material.dart';

import '../../../core/constants.dart';

/// Reusable interactive card for the PRIMARY ACTIONS & WORKSPACE section.
/// Hover feedback stays neutral so it cannot be mistaken for an active selection.
class WorkspaceCard extends StatefulWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool isSelected;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;

  const WorkspaceCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.isSelected = false,
    this.onTap,
    this.onDoubleTap,
  });

  @override
  State<WorkspaceCard> createState() => _WorkspaceCardState();
}

class _WorkspaceCardState extends State<WorkspaceCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    // Selection is persistent state; hover only adds neutral elevation feedback.
    final isSelected = widget.isSelected;

    final cardContent = MouseRegion(
      cursor: widget.onTap != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        transform: _isHovered
            ? (Matrix4.translationValues(0.0, -2.5, 0.0))
            : Matrix4.identity(),
        padding: const EdgeInsets.all(13.0),
        decoration: BoxDecoration(
          color: _isHovered
              ? AppColors.surfaceElevated
              : AppColors.cardBg, // #1A1A1A -> #212121
          borderRadius: BorderRadius.circular(16.0),
          border: Border.all(
            color: isSelected
                ? AppColors.primaryAccent.withValues(alpha: 0.70)
                : (_isHovered
                      ? AppColors.subtleBorderLight
                      : AppColors.subtleBorder),
            width: isSelected ? 1.5 : 1.0,
          ),
          boxShadow: [
            if (isSelected)
              BoxShadow(
                color: AppColors.primaryAccent.withValues(alpha: 0.12),
                blurRadius: 12.0,
                offset: const Offset(0, 2),
              ),
            BoxShadow(
              color: Colors.black.withValues(alpha: _isHovered ? 0.35 : 0.2),
              blurRadius: _isHovered ? 10.0 : 4.0,
              offset: Offset(0, _isHovered ? 3 : 1),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Small rounded-square icon container with decorative icon
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 34.0,
              height: 34.0,
              decoration: BoxDecoration(
                color: _isHovered
                    ? AppColors.subtleBorderLight
                    : AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(8.0),
                border: Border.all(
                  color: isSelected
                      ? AppColors.primaryAccent.withValues(alpha: 0.5)
                      : (_isHovered
                            ? AppColors.subtleBorderLight
                            : AppColors.surfaceElevated),
                  width: 1.0,
                ),
              ),
              child: Icon(
                widget.icon,
                size: 18.0,
                color: isSelected ? AppColors.primaryAccent : AppColors.white,
              ),
            ),
            const SizedBox(height: 8.0),

            // Bold white title
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

            // Muted light-gray subtitle
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
    );

    if (widget.onTap != null || widget.onDoubleTap != null) {
      return InkWell(
        onTap: widget.onTap,
        onDoubleTap: widget.onDoubleTap,
        borderRadius: BorderRadius.circular(16.0),
        splashColor: AppColors.primaryAccent.withValues(alpha: 0.1),
        highlightColor: Colors.transparent,
        child: cardContent,
      );
    }
    return cardContent;
  }
}
