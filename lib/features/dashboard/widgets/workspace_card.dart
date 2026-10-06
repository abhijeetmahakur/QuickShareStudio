import 'package:flutter/material.dart';
import '../../../core/constants.dart';

/// Reusable interactive card for the PRIMARY ACTIONS & WORKSPACE section.
/// Features a subtle hover effect with soft glow and highlight fitting the design palette.
class WorkspaceCard extends StatefulWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback? onTap;

  const WorkspaceCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.onTap,
  });

  @override
  State<WorkspaceCard> createState() => _WorkspaceCardState();
}

class _WorkspaceCardState extends State<WorkspaceCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    // Workspace cards are actions, not active-page indicators. Lime emphasis
    // is reserved for pointer hover; the sidebar tracks the selected page.
    final isHighlighted = _isHovered;

    final cardContent = MouseRegion(
      cursor: widget.onTap != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
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
          color: _isHovered ? AppColors.surfaceElevated : AppColors.cardBg, // #1A1A1A -> #212121
          borderRadius: BorderRadius.circular(16.0),
          border: Border.all(
            color: isHighlighted
                ? AppColors.primaryAccent.withValues(alpha: _isHovered ? 0.85 : 0.70)
                : AppColors.subtleBorder,
            width: isHighlighted ? 1.5 : 1.0,
          ),
          boxShadow: [
            if (_isHovered)
              BoxShadow(
                color: AppColors.primaryAccent.withValues(alpha: 0.16),
                blurRadius: 16.0,
                spreadRadius: 0.5,
                offset: const Offset(0, 4),
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
                color: _isHovered ? AppColors.subtleBorderLight : AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(8.0),
                border: Border.all(
                  color: isHighlighted
                      ? AppColors.primaryAccent.withValues(alpha: 0.5)
                      : AppColors.surfaceElevated,
                  width: 1.0,
                ),
              ),
              child: Icon(
                widget.icon,
                size: 18.0,
                color: isHighlighted ? AppColors.primaryAccent : AppColors.white,
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

    if (widget.onTap != null) {
      return InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(16.0),
        splashColor: AppColors.primaryAccent.withValues(alpha: 0.1),
        highlightColor: Colors.transparent,
        child: cardContent,
      );
    }
    return cardContent;
  }
}
