import 'package:flutter/material.dart';
import '../../../core/constants.dart';

/// Reusable interactive statistic card for the QuickShare Studio Dashboard.
/// Displays key metric values with a smooth hover effect.
class StatisticCard extends StatefulWidget {
  final String value;
  final String label;
  final bool isAccent;

  const StatisticCard({
    super.key,
    required this.value,
    required this.label,
    this.isAccent = false,
  });

  @override
  State<StatisticCard> createState() => _StatisticCardState();
}

class _StatisticCardState extends State<StatisticCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 180;

        return MouseRegion(
          cursor: SystemMouseCursors.basic,
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            transform: _isHovered
                ? (Matrix4.translationValues(0.0, -2.0, 0.0))
                : Matrix4.identity(),
            padding: EdgeInsets.symmetric(
              horizontal: isCompact ? 8.0 : 18.0,
              vertical: 14.0,
            ),
            decoration: BoxDecoration(
              color: _isHovered
                  ? AppColors.surfaceElevated
                  : AppColors.dashboardBg,
              borderRadius: BorderRadius.circular(14.0),
              border: Border.all(
                color: _isHovered
                    ? AppColors.primaryAccent.withValues(alpha: 0.40)
                    : AppColors.subtleBorder,
                width: 1.0,
              ),
              boxShadow: [
                if (_isHovered)
                  BoxShadow(
                    color: AppColors.primaryAccent.withValues(alpha: 0.10),
                    blurRadius: 12.0,
                    offset: const Offset(0, 3),
                  ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.value,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: isCompact ? 16.0 : 26.0,
                    fontWeight: FontWeight.w700,
                    color: widget.isAccent
                        ? AppColors.primaryAccent
                        : AppColors.primaryText,
                    letterSpacing: -0.5,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 4.0),
                Text(
                  widget.label,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: isCompact ? 10.0 : 12.0,
                    fontWeight: FontWeight.w400,
                    color: AppColors.secondaryText,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
