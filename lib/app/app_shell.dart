import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dashboard_view.dart';
import '../features/pdf_editor/pdf_editor_view.dart';
import '../features/pairing/pairing_view.dart';
import '../features/file_transfer/send_files_view.dart';
import '../features/received_items/received_items_view.dart';
import '../features/screenshot_collections/screenshot_collections_view.dart';
import '../features/pdf_tools/pdf_tools_view.dart';
import '../features/clipboard/universal_clipboard_view.dart';
import '../features/transfer_history/transfer_history_view.dart';
import '../features/security/security_settings_view.dart';
import '../data/services/transfer_engine.dart';
import '../data/services/app_update_service.dart';
import 'widgets/update_dialog.dart';
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

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  int _selectedIndex = 0;
  late final List<Widget> _views;
  late final AppLifecycleListener _lifecycleListener;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _lifecycleListener = AppLifecycleListener(
      onExitRequested: () async {
        final engine = context.read<TransferEngine>();
        if (engine.autoDisconnectOnExit) {
          engine.disconnectAllDevices();
        }
        return AppExitResponse.exit;
      },
      onDetach: () {
        final engine = context.read<TransferEngine>();
        if (engine.autoDisconnectOnExit) {
          engine.disconnectAllDevices();
        }
      },
    );

    _views = [
      DashboardView(onNavigate: (idx) => setState(() => _selectedIndex = idx)),
      const PdfEditorView(),
      PairingView(onNavigateToReceived: () => setState(() => _selectedIndex = 4)),
      SendFilesView(onNavigateToPairing: () => setState(() => _selectedIndex = 2)),
      ReceivedItemsView(onOpenSettings: () => setState(() => _selectedIndex = 9)),
      const ScreenshotCollectionsView(),
      const PdfToolsView(),
      const UniversalClipboardView(),
      const TransferHistoryView(),
      const SecuritySettingsView(),
    ];
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      final engine = context.read<TransferEngine>();
      if (engine.autoDisconnectOnExit) {
        engine.disconnectAllDevices();
      }
    }
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 960;
    final engine = context.watch<TransferEngine>();
    final updateService = context.watch<AppUpdateService>();

    Widget content;
    if (isDesktop) {
      content = Scaffold(
        body: Container(
          decoration: BoxDecoration(
            color: AppColors.dashboardBg,
            gradient: RadialGradient(
              center: Alignment(0.2, -0.85),
              radius: 1.5,
              colors: [
                AppColors.surfaceElevated,
                AppColors.cardBg,
                AppColors.dashboardBg,
              ],
              stops: [0.0, 0.45, 1.0],
            ),
          ),
          child: Row(
            children: [
              // Desktop Sidebar Navigation
              _buildSidebar(engine, updateService),

              // Active View Workspace
              Expanded(
                child: IndexedStack(
                  index: _selectedIndex.clamp(0, _views.length - 1),
                  children: _views,
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      // Mobile / Tablet Navigation
      content = Scaffold(
        drawer: Drawer(
          backgroundColor: AppColors.dashboardBg,
          child: SafeArea(
            child: _buildSidebar(engine, updateService, isDrawer: true),
          ),
        ),
        body: Container(
          decoration: BoxDecoration(
            color: AppColors.dashboardBg,
            gradient: RadialGradient(
              center: Alignment(0.0, -0.8),
              radius: 1.4,
              colors: [
                AppColors.surfaceElevated,
                AppColors.cardBg,
                AppColors.dashboardBg,
              ],
              stops: [0.0, 0.45, 1.0],
            ),
          ),
          child: Column(
            children: [
              AppBar(
                backgroundColor: AppColors.dashboardBg.withValues(alpha: 0.92),
                elevation: 0,
                leading: Builder(
                  builder: (ctx) => IconButton(
                    icon: Icon(Icons.menu, color: AppColors.white),
                    tooltip: 'All Features Menu',
                    onPressed: () => Scaffold.of(ctx).openDrawer(),
                  ),
                ),
                title: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        gradient: AppColors.primaryGradient,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.4),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Icon(Icons.bolt, color: AppColors.nearBlack, size: 18),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        AppConstants.appName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.white),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: IndexedStack(
                  index: _selectedIndex.clamp(0, _views.length - 1),
                  children: _views,
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          decoration: BoxDecoration(
            color: AppColors.cardBg.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: AppColors.white.withValues(alpha: 0.16), width: 1.2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.2),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(32),
            child: NavigationBar(
              backgroundColor: Colors.transparent,
              indicatorColor: AppColors.primary.withValues(alpha: 0.35),
              selectedIndex: _selectedIndex.clamp(0, 4),
              onDestinationSelected: (idx) => setState(() => _selectedIndex = idx),
              destinations: [
                NavigationDestination(
                  icon: Icon(Icons.dashboard_outlined, color: AppColors.secondaryText),
                  selectedIcon: Icon(Icons.dashboard, color: AppColors.primaryAccent),
                  label: 'Home',
                ),
                NavigationDestination(
                  icon: Icon(Icons.picture_as_pdf_outlined, color: AppColors.secondaryText),
                  selectedIcon: Icon(Icons.picture_as_pdf, color: AppColors.primaryAccent),
                  label: 'PDF Studio',
                ),
                NavigationDestination(
                  icon: Icon(Icons.qr_code_scanner, color: AppColors.secondaryText),
                  selectedIcon: Icon(Icons.qr_code, color: AppColors.primaryAccent),
                  label: 'Pairing',
                ),
                NavigationDestination(
                  icon: Icon(Icons.send_outlined, color: AppColors.secondaryText),
                  selectedIcon: Icon(Icons.send, color: AppColors.primaryAccent),
                  label: 'Send',
                ),
                NavigationDestination(
                  icon: Icon(Icons.move_to_inbox_outlined, color: AppColors.secondaryText),
                  selectedIcon: Icon(Icons.move_to_inbox, color: AppColors.primaryAccent),
                  label: 'Received',
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Stack(
      children: [
        content,
        if (engine.lastNotificationTitle != null)
          Positioned(
            top: 16,
            right: 24,
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: 360,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppColors.cardBg,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: AppColors.white.withValues(alpha: 0.2), width: 1.2),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.35),
                      blurRadius: 24,
                      spreadRadius: 1,
                      offset: const Offset(0, 6),
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            gradient: AppColors.primaryGradient,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.cloud_download, color: AppColors.nearBlack, size: 18),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            engine.lastNotificationTitle!,
                            style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.white, fontSize: 13),
                          ),
                        ),
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: Icon(Icons.close, color: AppColors.secondaryText, size: 16),
                          onPressed: () => engine.clearNotification(),
                        ),
                      ],
                    ),
                    if (engine.lastNotificationBody != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        engine.lastNotificationBody!,
                        style: TextStyle(color: AppColors.secondaryText, fontSize: 12),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.secondaryText,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          ),
                          onPressed: () => engine.clearNotification(),
                          child: const Text('Dismiss', style: TextStyle(fontSize: 12)),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: AppColors.nearBlack,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                          ),
                          onPressed: () {
                            final isUpdateNotice = engine.lastNotificationTitle?.contains('Update') ?? false;
                            engine.clearNotification();
                            if (isUpdateNotice) {
                              setState(() => _selectedIndex = 9); // Settings & Privacy
                            } else {
                              setState(() => _selectedIndex = 4); // Go to Received Items
                            }
                          },
                          child: Text(
                            (engine.lastNotificationTitle?.contains('Update') ?? false) ? 'View Updates' : 'Open Received',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

        // Software Update Available Floating Banner (Requirement 13.A & 13.B)
        if (updateService.latestUpdate != null && !updateService.isUpdatePostponed)
          Positioned(
            top: engine.lastNotificationTitle != null ? 180 : 16,
            right: 24,
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: 380,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppColors.cardBg,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: AppColors.primaryAccent.withValues(alpha: 0.35), width: 1.2),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.35),
                      blurRadius: 24,
                      offset: const Offset(0, 6),
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            gradient: AppColors.primaryGradient,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(Icons.system_update_alt_rounded, color: AppColors.nearBlack, size: 18),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'NEW VERSION AVAILABLE',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.2,
                                  color: AppColors.secondary,
                                ),
                              ),
                              Text(
                                'QuickShare Studio v${updateService.latestUpdate!.version}',
                                style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.white, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: Icon(Icons.close, color: AppColors.secondaryText, size: 16),
                          tooltip: 'Update Later',
                          onPressed: () => updateService.postponeUpdate(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      updateService.latestUpdate!.description,
                      style: TextStyle(color: AppColors.secondaryText, fontSize: 11.5),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () {
                            UpdateDialog.show(context, updateService.latestUpdate!);
                          },
                          child: Text('View Details', style: TextStyle(fontSize: 11.5, color: AppColors.primaryAccent)),
                        ),
                        const SizedBox(width: 4),
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          onPressed: () => updateService.postponeUpdate(),
                          child: const Text('Update Later', style: TextStyle(fontSize: 11.5)),
                        ),
                        const SizedBox(width: 6),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: AppColors.nearBlack,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          onPressed: () {
                            updateService.startUpdateNow(
                              engine: engine,
                              onComplete: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Updated to v${updateService.currentVersion}!')),
                                );
                              },
                            );
                          },
                          child: const Text('Update Now', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSidebar(TransferEngine engine, AppUpdateService updateService, {bool isDrawer = false}) {
    final navItems = [
      (title: 'Dashboard', icon: Icons.dashboard_outlined, activeIcon: Icons.dashboard),
      (title: 'PDF Studio', icon: Icons.picture_as_pdf_outlined, activeIcon: Icons.picture_as_pdf),
      (title: 'Device Pairing', icon: Icons.qr_code_scanner, activeIcon: Icons.qr_code),
      (title: 'Send Files', icon: Icons.send_outlined, activeIcon: Icons.send),
      (title: 'Received Items', icon: Icons.move_to_inbox_outlined, activeIcon: Icons.move_to_inbox),
      (title: 'Screenshot Sessions', icon: Icons.collections_outlined, activeIcon: Icons.collections),
      (title: 'PDF Tools', icon: Icons.build_outlined, activeIcon: Icons.build),
      (title: 'Universal Clipboard', icon: Icons.content_paste_outlined, activeIcon: Icons.content_paste),
      (title: 'HISTORY', icon: Icons.history_outlined, activeIcon: Icons.history),
      (title: 'Settings & Privacy', icon: Icons.settings_suggest_outlined, activeIcon: Icons.settings_suggest),
    ];

    return Container(
      width: isDrawer ? null : 256,
      decoration: BoxDecoration(
        color: AppColors.dashboardBg.withValues(alpha: 0.96),
        border: Border(
          right: BorderSide(color: AppColors.white.withValues(alpha: 0.12), width: 1.0),
        ),
      ),
      child: Column(
        children: [
          // App Logo & Title
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.45),
                        blurRadius: 14,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Icon(Icons.bolt, color: AppColors.nearBlack, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppConstants.appName,
                        style: TextStyle(
                          color: AppColors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                          letterSpacing: -0.3,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        engine.localDeviceName,
                        style: TextStyle(color: AppColors.primaryAccent, fontSize: 11, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Device status indicator pill
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.cardBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: engine.isReceivingPaused
                    ? Colors.orange.withValues(alpha: 0.4)
                    : AppColors.white.withValues(alpha: 0.14),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: engine.isReceivingPaused ? Colors.orange : AppColors.primary,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: (engine.isReceivingPaused ? Colors.orange : AppColors.primary)
                            .withValues(alpha: 0.6),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    engine.isReceivingPaused
                        ? 'Receiving Paused'
                        : '${engine.pairedDevices.length} Paired Device(s)',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.white),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Navigation Links
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              itemCount: navItems.length,
              itemBuilder: (context, index) {
                final item = navItems[index];
                final isSelected = _selectedIndex == index;

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        setState(() => _selectedIndex = index);
                        if (isDrawer) {
                          Navigator.pop(context);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: isSelected ? AppColors.primary.withValues(alpha: 0.18) : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          border: isSelected
                              ? Border.all(color: AppColors.primary.withValues(alpha: 0.4), width: 1)
                              : null,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isSelected ? item.activeIcon : item.icon,
                              size: 19,
                              color: isSelected ? AppColors.primaryAccent : AppColors.secondaryText,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                item.title,
                                style: TextStyle(
                                  color: isSelected ? AppColors.white : AppColors.secondaryText,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            if (index == 4 && engine.receivedItems.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.primary,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '${engine.receivedItems.length}',
                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.nearBlack),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // Bottom Theme & Version Area
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: AppColors.white.withValues(alpha: 0.08)),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: widget.onToggleTheme,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            widget.isDarkMode ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                            color: AppColors.secondaryText,
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              widget.isDarkMode ? 'Dark Forest' : 'Light Mode',
                              style: TextStyle(fontSize: 11, color: AppColors.secondaryText),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Text(
                  'v${updateService.currentVersion}',
                  style: TextStyle(fontSize: 10, color: AppColors.secondaryText),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
