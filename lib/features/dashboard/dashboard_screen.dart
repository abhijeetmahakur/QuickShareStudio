import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants.dart';
import '../../core/services/theme_service.dart';
import 'widgets/sidebar.dart';
import 'widgets/dashboard_header.dart';
import 'widgets/workspace_card.dart';
import 'widgets/recent_exchanges_section.dart';
import '../pdf_editor/pdf_editor_view.dart';
import '../file_transfer/send_files_view.dart';
import '../pairing/pairing_view.dart';
import '../received_items/received_items_view.dart';
import '../pdf_tools/pdf_tools_view.dart';
import '../clipboard/universal_clipboard_view.dart';
import '../transfer_history/transfer_history_view.dart';
import '../security/security_settings_view.dart';

/// QuickShare Studio — Frontend Dashboard UI
/// Reproduces the reference layout, proportions, colors, and Poppins typography.
/// Integrates cross-device file sharing, device pairing, and received items navigation.
class DashboardScreen extends StatefulWidget {
  final int initialIndex;
  final VoidCallback? onToggleTheme;
  final bool? isDarkMode;

  const DashboardScreen({
    super.key,
    this.initialIndex = 0,
    this.onToggleTheme,
    this.isDarkMode,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late int _selectedIndex;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex;
  }

  void _onNavigate(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  // Primary workspace cards for the app's available features
  static const List<({String title, String subtitle, IconData icon, bool hasLimeOutline, int? targetIndex})> _workspaceItems = [
    (
      title: 'Create PDF',
      subtitle: 'Multi-page studio & 7 layouts',
      icon: Icons.picture_as_pdf_outlined,
      hasLimeOutline: false,
      targetIndex: 1,
    ),
    (
      title: 'Connect Device',
      subtitle: 'QR code & 6-digit code pairing',
      icon: Icons.qr_code_rounded,
      hasLimeOutline: false,
      targetIndex: 2,
    ),
    (
      title: 'Send Files',
      subtitle: 'Transfer to one or multiple devices',
      icon: Icons.arrow_upward_rounded,
      hasLimeOutline: false,
      targetIndex: 3,
    ),
    (
      title: 'Received Items',
      subtitle: 'View & download inbound files',
      icon: Icons.arrow_downward_rounded,
      hasLimeOutline: false,
      targetIndex: 4,
    ),
    (
      title: 'PDF Tools',
      subtitle: 'Merge, split, compress, OCR',
      icon: Icons.auto_fix_high_rounded,
      hasLimeOutline: false,
      targetIndex: 5,
    ),
    (
      title: 'Universal Clipboard',
      subtitle: 'Smart sync text & images',
      icon: Icons.content_paste_rounded,
      hasLimeOutline: true, // Subtle lime-green outline per specification
      targetIndex: 6,
    ),
    (
      title: 'Transfer History',
      subtitle: 'Inspect logs, verify & resend',
      icon: Icons.history_rounded,
      hasLimeOutline: false,
      targetIndex: 7,
    ),
    (
      title: 'Settings & Privacy',
      subtitle: 'Appearance, storage, updates',
      icon: Icons.settings_outlined,
      hasLimeOutline: false,
      targetIndex: 8,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    ThemeService? themeService;
    try {
      themeService = context.watch<ThemeService>();
    } catch (_) {}
    final isDark = widget.isDarkMode ?? themeService?.isDarkMode ?? (Theme.of(context).brightness == Brightness.dark);
    final onToggle = widget.onToggleTheme ?? () => (themeService?.toggleTheme() ?? ThemeService().toggleTheme());

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 960;

        if (isDesktop) {
          // Desktop Composition: Left Sidebar + Scrollable Main Content Area
          return Scaffold(
            backgroundColor: AppColors.dashboardBg,
            body: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Sidebar(
                  width: 260.0,
                  selectedIndex: _selectedIndex,
                  onItemSelected: _onNavigate,
                  onToggleTheme: onToggle,
                  isDarkMode: isDark,
                ),
                Expanded(
                  child: _buildActiveWorkspace(context),
                ),
              ],
            ),
          );
        } else {
          // Mobile & Tablet Composition: Drawer Sidebar + Scrollable Body
          return Scaffold(
            backgroundColor: AppColors.dashboardBg,
            drawer: Drawer(
              backgroundColor: AppColors.charcoalSurface,
              child: SafeArea(
                child: Sidebar(
                  isDrawer: true,
                  selectedIndex: _selectedIndex,
                  onItemSelected: (idx) {
                    Navigator.of(context).maybePop();
                    _onNavigate(idx);
                  },
                  onToggleTheme: onToggle,
                  isDarkMode: isDark,
                ),
              ),
            ),
            appBar: AppBar(
              backgroundColor: AppColors.charcoalSurface,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              leading: Builder(
                builder: (ctx) => IconButton(
                  icon: Icon(Icons.menu_rounded, color: AppColors.primaryText),
                  tooltip: 'Menu',
                  onPressed: () => Scaffold.of(ctx).openDrawer(),
                ),
              ),
              title: Row(
                children: [
                  Container(

                    width: 28.0,
                    height: 28.0,
                    decoration: BoxDecoration(
                      color: AppColors.primaryAccent,
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                    child: const Icon(
                      Icons.bolt_rounded,
                      color: AppColors.nearBlack,
                      size: 18.0,
                    ),
                  ),
                  const SizedBox(width: 10.0),
                  Expanded(
                    child: Text(
                      'QuickShare Studio',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 16.0,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primaryText,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            body: _buildActiveWorkspace(context),
          );
        }
      },
    );
  }

  Widget _buildActiveWorkspace(BuildContext context) {
    switch (_selectedIndex) {
      case 1: // PDF Studio
        return const PdfEditorView();
      case 2: // Device Pairing
        return PairingView(
          onNavigateToReceived: () => _onNavigate(4),
        );
      case 3: // Send Files
        return SendFilesView(
          onNavigateToPairing: () => _onNavigate(2),
        );
      case 4: // Received Items
        return ReceivedItemsView(
          onOpenSettings: () => _onNavigate(8),
        );
      case 5: // PDF Tools
        return const PdfToolsView();
      case 6: // Universal Clipboard
        return const UniversalClipboardView();
      case 7: // Transfer History
        return const TransferHistoryView();
      case 8: // Settings & Privacy
        return const SecuritySettingsView();
      case 0:
      default:
        return _buildMainContentArea(context);
    }
  }

  Widget _buildMainContentArea(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Panel with Workstation Details & 4 Statistic Cards
          const DashboardHeader(),
          const SizedBox(height: 28.0),

          // Primary Actions & Workspace Section Heading
          Text(
            'PRIMARY ACTIONS & WORKSPACE',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12.0,
              fontWeight: FontWeight.w700,
              color: AppColors.secondaryText,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 14.0),

          // Responsive 5-column / adaptive grid of the 10 Workspace Cards
          LayoutBuilder(
            builder: (context, gridConstraints) {
              final double width = gridConstraints.maxWidth;
              final int crossAxisCount;

              if (width >= 1050) {
                crossAxisCount = 5; // 5 columns on desktop wide view
              } else if (width >= 750) {
                crossAxisCount = 3; // 3 columns on tablet view
              } else if (width >= 480) {
                crossAxisCount = 2; // 2 columns on small screens
              } else {
                crossAxisCount = 1; // 1 column on very narrow mobile screens
              }

              return GridView.builder(
                physics: const NeverScrollableScrollPhysics(),
                shrinkWrap: true,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  mainAxisSpacing: 14.0,
                  crossAxisSpacing: 14.0,
                  mainAxisExtent: 145.0,
                ),
                itemCount: _workspaceItems.length,
                itemBuilder: (context, index) {
                  final item = _workspaceItems[index];
                  return WorkspaceCard(
                    title: item.title,
                    subtitle: item.subtitle,
                    icon: item.icon,
                    hasLimeOutline: item.hasLimeOutline,
                    onTap: item.targetIndex != null ? () => _onNavigate(item.targetIndex!) : null,
                  );
                },
              );
            },
          ),
          const SizedBox(height: 32.0),

          // Recent File Exchanges Section
          const RecentExchangesSection(),
        ],
      ),
    );
  }
}
