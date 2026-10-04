import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants.dart';
import '../../../core/services/theme_service.dart';
import '../../../data/services/transfer_engine.dart';

/// Left sidebar navigation for QuickShare Studio.
/// Supports both 'Dark Forest' (dark mode) and 'Light Mode' with interactive toggle switch.
class Sidebar extends StatelessWidget {
  final bool isDrawer;
  final double width;
  final int selectedIndex;
  final ValueChanged<int>? onItemSelected;
  final VoidCallback? onToggleTheme;
  final bool? isDarkMode;

  const Sidebar({
    super.key,
    this.isDrawer = false,
    this.width = 270.0,
    this.selectedIndex = 0,
    this.onItemSelected,
    this.onToggleTheme,
    this.isDarkMode,
  });

  @override
  Widget build(BuildContext context) {
    ThemeService? themeService;
    try {
      themeService = context.watch<ThemeService>();
    } catch (_) {}

    // Live values for the status capsule and Received Items badge.
    TransferEngine? engine;
    try {
      engine = context.watch<TransferEngine>();
    } catch (_) {}
    final pairedCount = engine?.pairedDevices.length ?? 0;
    final receivedCount = engine?.receivedItems.length ?? 0;
    final isPaused = engine?.isReceivingPaused ?? false;

    final effectiveIsDark = isDarkMode ?? themeService?.isDarkMode ?? (Theme.of(context).brightness == Brightness.dark);
    final effectiveToggle = onToggleTheme ?? () => (themeService?.toggleTheme() ?? ThemeService().toggleTheme());

    final sidebarBg = AppColors.charcoalSurface;
    final sidebarBorder = AppColors.subtleBorder;
    final primaryTextColor = AppColors.primaryText;
    final secondaryTextColor = AppColors.secondaryText;
    final capsuleBg = AppColors.surfaceElevated;
    final capsuleBorder = AppColors.subtleBorderLight;
    final badgeBg = AppColors.surfaceElevated;
    final dividerColor = AppColors.surfaceElevated;

    return Container(
      width: isDrawer ? null : width,
      decoration: BoxDecoration(
        color: sidebarBg,
        border: isDrawer
            ? null
            : Border(
                right: BorderSide(
                  color: sidebarBorder,
                  width: 1.0,
                ),
              ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top branding and status area
          Padding(
            padding: const EdgeInsets.fromLTRB(18.0, 20.0, 18.0, 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // App Logo + Title + Subtitle
                Row(
                  children: [
                    Container(
                      width: 38.0,
                      height: 38.0,
                      decoration: BoxDecoration(
                        color: AppColors.primaryAccent, // #D5FF40
                        borderRadius: BorderRadius.circular(10.0),
                      ),
                      child: const Icon(
                        Icons.bolt_rounded,
                        color: AppColors.nearBlack,
                        size: 24.0,
                      ),
                    ),
                    const SizedBox(width: 12.0),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'QuickShare Studio',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 15.0,
                              fontWeight: FontWeight.w700,
                              color: primaryTextColor,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 2.0),
                          Text(
                            'Lab Share & PDF Studio',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 11.0,
                              fontWeight: FontWeight.w400,
                              color: secondaryTextColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16.0),

                // Status capsule: Ready to Receive & 0 Paired
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                  decoration: BoxDecoration(
                    color: capsuleBg,
                    borderRadius: BorderRadius.circular(10.0),
                    border: Border.all(
                      color: capsuleBorder,
                      width: 1.0,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 7.0,
                        height: 7.0,
                        decoration: BoxDecoration(
                          color: AppColors.statusIndicator,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.statusIndicator.withValues(alpha: 0.6),
                              blurRadius: 4.0,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8.0),
                      Expanded(
                        child: Text(
                          isPaused ? 'Receiving Paused' : 'Ready to Receive',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 11.0,
                            fontWeight: FontWeight.w500,
                            color: primaryTextColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6.0),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7.0, vertical: 2.0),
                        decoration: BoxDecoration(
                          color: badgeBg,
                          borderRadius: BorderRadius.circular(6.0),
                        ),
                        child: Text(
                          '$pairedCount Paired',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 10.0,
                            fontWeight: FontWeight.w400,
                            color: secondaryTextColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          Divider(
            color: dividerColor,
            height: 1.0,
            thickness: 1.0,
          ),

          // Scrollable navigation list (9 items in exact order)
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
              child: Column(
                children: [
                  _buildNavItem(
                    label: 'Dashboard',
                    icon: Icons.grid_view_rounded,
                    isSelected: selectedIndex == 0,
                    isDarkMode: effectiveIsDark,
                    onTap: () => onItemSelected?.call(0),
                  ),
                  _buildNavItem(
                    label: 'PDF Studio',
                    icon: Icons.picture_as_pdf_outlined,
                    isSelected: selectedIndex == 1,
                    isDarkMode: effectiveIsDark,
                    onTap: () => onItemSelected?.call(1),
                  ),
                  _buildNavItem(
                    label: 'Device Pairing',
                    icon: Icons.devices_rounded,
                    isSelected: selectedIndex == 2,
                    isDarkMode: effectiveIsDark,
                    onTap: () => onItemSelected?.call(2),
                  ),
                  _buildNavItem(
                    label: 'Send Files',
                    icon: Icons.arrow_upward_rounded,
                    isSelected: selectedIndex == 3,
                    isDarkMode: effectiveIsDark,
                    onTap: () => onItemSelected?.call(3),
                  ),
                  _buildNavItem(
                    label: 'Received Items',
                    icon: Icons.arrow_downward_rounded,
                    badgeText: receivedCount > 0 ? '$receivedCount' : null,
                    isSelected: selectedIndex == 4,
                    isDarkMode: effectiveIsDark,
                    onTap: () => onItemSelected?.call(4),
                  ),
                  _buildNavItem(
                    label: 'PDF Tools',
                    icon: Icons.auto_fix_high_rounded,
                    isSelected: selectedIndex == 5,
                    isDarkMode: effectiveIsDark,
                    onTap: () => onItemSelected?.call(5),
                  ),
                  _buildNavItem(
                    label: 'Universal Clipboard',
                    icon: Icons.content_paste_rounded,
                    isSelected: selectedIndex == 6,
                    isDarkMode: effectiveIsDark,
                    onTap: () => onItemSelected?.call(6),
                  ),
                  _buildNavItem(
                    label: 'Transfer History',
                    icon: Icons.history_rounded,
                    isSelected: selectedIndex == 7,
                    isDarkMode: effectiveIsDark,
                    onTap: () => onItemSelected?.call(7),
                  ),
                  _buildNavItem(
                    label: 'Settings & Privacy',
                    icon: Icons.settings_outlined,
                    isSelected: selectedIndex == 8,
                    isDarkMode: effectiveIsDark,
                    onTap: () => onItemSelected?.call(8),
                  ),
                ],
              ),
            ),
          ),

          Divider(
            color: dividerColor,
            height: 1.0,
            thickness: 1.0,
          ),

          // Bottom interactive appearance toggle: Dark Forest / Light Mode
          Padding(
            padding: const EdgeInsets.all(14.0),
            child: Tooltip(
              message: effectiveIsDark ? 'Switch to Light Mode' : 'Switch to Dark Forest',
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  key: const Key('sidebar_theme_toggle'),
                  borderRadius: BorderRadius.circular(10.0),
                  onTap: effectiveToggle,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
                    decoration: BoxDecoration(
                      color: capsuleBg,
                      borderRadius: BorderRadius.circular(10.0),
                      border: Border.all(
                        color: capsuleBorder,
                        width: 1.0,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          effectiveIsDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                          color: AppColors.secondaryText,
                          size: 18.0,
                        ),
                        const SizedBox(width: 10.0),
                        Text(
                          effectiveIsDark ? 'Dark Forest' : 'Light Mode',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 12.0,
                            fontWeight: FontWeight.w600,
                            color: primaryTextColor,
                          ),
                        ),
                        const Spacer(),
                        // Smooth animated switch visual
                        Container(
                          width: 38.0,
                          height: 22.0,
                          padding: const EdgeInsets.all(2.5),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceElevated,
                            borderRadius: BorderRadius.circular(11.0),
                            border: Border.all(
                              color: AppColors.subtleBorderLight,
                              width: 1.0,
                            ),
                          ),
                          child: AnimatedAlign(
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeInOutCubic,
                            alignment: effectiveIsDark ? Alignment.centerRight : Alignment.centerLeft,
                            child: Container(
                              width: 14.0,
                              height: 14.0,
                              decoration: BoxDecoration(
                                color: AppColors.primaryAccent,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: (AppColors.primaryAccent).withValues(alpha: 0.4),
                                    blurRadius: 4.0,
                                    spreadRadius: 0.5,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem({
    required String label,
    required IconData icon,
    bool isSelected = false,
    bool isDarkMode = true,
    String? badgeText,
    VoidCallback? onTap,
  }) {
    return _SidebarNavItem(
      label: label,
      icon: icon,
      isSelected: isSelected,
      isDarkMode: isDarkMode,
      badgeText: badgeText,
      onTap: onTap,
    );
  }
}

class _SidebarNavItem extends StatefulWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final bool isDarkMode;
  final String? badgeText;
  final VoidCallback? onTap;

  const _SidebarNavItem({
    required this.label,
    required this.icon,
    this.isSelected = false,
    this.isDarkMode = true,
    this.badgeText,
    this.onTap,
  });

  @override
  State<_SidebarNavItem> createState() => _SidebarNavItemState();
}

class _SidebarNavItemState extends State<_SidebarNavItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isSelected = widget.isSelected;
    final isHovered = _isHovered && !isSelected;
    final isDark = widget.isDarkMode;

    final hoverBg = AppColors.surfaceElevated;
    final unselectedIconColor = AppColors.secondaryText;
    final unselectedTextColor = AppColors.secondaryText;
    final hoveredTextColor = AppColors.primaryText;

    final item = MouseRegion(
      cursor: widget.onTap != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutCubic,
        margin: const EdgeInsets.only(bottom: 3.0),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primaryAccent
              : (isHovered ? hoverBg : Colors.transparent),
          borderRadius: BorderRadius.circular(10.0),
          border: isHovered
              ? Border.all(
                  color: AppColors.primaryAccent.withValues(alpha: 0.28),
                  width: 1.0,
                )
              : null,
          boxShadow: isHovered
              ? [
                  BoxShadow(
                    color: isDark
                        ? AppColors.primaryAccent.withValues(alpha: 0.09)
                        : Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8.0,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
        child: Row(
          children: [
            Icon(
              widget.icon,
              size: 18.0,
              color: isSelected
                  ? AppColors.nearBlack
                  : (isHovered ? (AppColors.primaryAccent) : unselectedIconColor),
            ),
            const SizedBox(width: 12.0),
            Expanded(
              child: Text(
                widget.label,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12.5,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                  color: isSelected
                      ? AppColors.nearBlack
                      : (isHovered ? hoveredTextColor : unselectedTextColor),
                ),
              ),
            ),
            if (widget.badgeText != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6.5, vertical: 1.5),
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(10.0),
                  border: Border.all(
                    color: AppColors.subtleBorderLight,
                    width: 1.0,
                  ),
                ),
                child: Text(
                  widget.badgeText!,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 10.0,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryText,
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    if (widget.onTap != null) {
      return InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(10.0),
        splashColor: AppColors.primaryAccent.withValues(alpha: 0.1),
        highlightColor: Colors.transparent,
        child: item,
      );
    }
    return item;
  }
}
