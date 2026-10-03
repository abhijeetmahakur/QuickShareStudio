import 'package:flutter/material.dart';
import 'dashboard_view.dart';
import '../features/pdf_editor/pdf_editor_view.dart';
import '../features/pairing/pairing_view.dart';
import '../features/nearby_devices/nearby_devices_view.dart';
import '../features/file_transfer/send_files_view.dart';
import '../features/screenshot_collections/screenshot_collections_view.dart';
import '../features/pdf_tools/pdf_tools_view.dart';
import '../features/clipboard/universal_clipboard_view.dart';
import '../features/transfer_history/transfer_history_view.dart';
import '../features/templates/templates_view.dart';
import '../features/security/security_settings_view.dart';
import '../core/constants.dart';

class AppShell extends StatefulWidget {
  final VoidCallback onToggleTheme;
  final bool isDarkMode;

  const AppShell({
    super.key,
    required this.onToggleTheme,
    required this.isDarkMode,
  });

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;

  late final List<Widget> _views;

  @override
  void initState() {
    super.initState();
    _views = [
      DashboardView(onNavigate: (idx) => setState(() => _selectedIndex = idx)),
      const PdfEditorView(),
      const PairingView(),
      const NearbyDevicesView(),
      const SendFilesView(),
      const ScreenshotCollectionsView(),
      const PdfToolsView(),
      const UniversalClipboardView(),
      const TransferHistoryView(),
      const TemplatesView(),
      const SecuritySettingsView(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 960;

    if (isDesktop) {
      return Scaffold(
        body: Row(
          children: [
            // Desktop Sidebar Navigation
            _buildSidebar(),

            // Active View Workspace
            Expanded(
              child: IndexedStack(
                index: _selectedIndex,
                children: _views,
              ),
            ),
          ],
        ),
      );
    }

    // Mobile / Tablet Navigation
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.bolt, color: AppColors.primary),
            SizedBox(width: 8),
            Text(AppConstants.appName, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: _views,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex.clamp(0, 4),
        onDestinationSelected: (idx) => setState(() => _selectedIndex = idx),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.picture_as_pdf_outlined), selectedIcon: Icon(Icons.picture_as_pdf), label: 'PDF Studio'),
          NavigationDestination(icon: Icon(Icons.qr_code_scanner), selectedIcon: Icon(Icons.qr_code), label: 'Pairing'),
          NavigationDestination(icon: Icon(Icons.send_outlined), selectedIcon: Icon(Icons.send), label: 'Send'),
          NavigationDestination(icon: Icon(Icons.collections_outlined), selectedIcon: Icon(Icons.collections), label: 'Lab Sessions'),
        ],
      ),
    );
  }

  Widget _buildSidebar() {
    final navItems = [
      (title: 'Dashboard', icon: Icons.dashboard_outlined, activeIcon: Icons.dashboard),
      (title: 'PDF Studio', icon: Icons.picture_as_pdf_outlined, activeIcon: Icons.picture_as_pdf),
      (title: 'Device Pairing', icon: Icons.qr_code_scanner, activeIcon: Icons.qr_code),
      (title: 'Nearby Devices', icon: Icons.wifi_find_outlined, activeIcon: Icons.wifi_find),
      (title: 'Send Files', icon: Icons.send_outlined, activeIcon: Icons.send),
      (title: 'Screenshot Sessions', icon: Icons.collections_outlined, activeIcon: Icons.collections),
      (title: 'PDF Tools', icon: Icons.build_outlined, activeIcon: Icons.build),
      (title: 'Universal Clipboard', icon: Icons.content_paste_outlined, activeIcon: Icons.content_paste),
      (title: 'Transfer History', icon: Icons.history_outlined, activeIcon: Icons.history),
      (title: 'Saved Templates', icon: Icons.dashboard_customize_outlined, activeIcon: Icons.dashboard_customize),
      (title: 'Settings & Security', icon: Icons.security_outlined, activeIcon: Icons.security),
    ];

    return Container(
      width: 250,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(
          right: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.1)),
        ),
      ),
      child: Column(
        children: [
          // App Logo & Title
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.primary, AppColors.secondary],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.bolt, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppConstants.appName,
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: -0.3),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Lab Share & PDF Studio',
                        style: TextStyle(color: Colors.grey, fontSize: 11),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Navigation Items List
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              itemCount: navItems.length,
              separatorBuilder: (_, _) => const SizedBox(height: 2),
              itemBuilder: (context, idx) {
                final item = navItems[idx];
                final isSelected = _selectedIndex == idx;

                return InkWell(
                  onTap: () => setState(() => _selectedIndex = idx),
                  borderRadius: BorderRadius.circular(8),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.primary.withValues(alpha: 0.12)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isSelected ? item.activeIcon : item.icon,
                          size: 19,
                          color: isSelected ? AppColors.primary : Colors.grey.shade600,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            item.title,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                              color: isSelected ? AppColors.primary : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // Bottom Theme & Version Footer
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      widget.isDarkMode ? Icons.dark_mode : Icons.light_mode,
                      size: 18,
                      color: Colors.grey,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      widget.isDarkMode ? 'Dark Theme' : 'Light Theme',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
                Switch(
                  value: widget.isDarkMode,
                  onChanged: (val) => widget.onToggleTheme(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
