import 'dart:io' show File;
import 'widgets/connection_settings_section.dart';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/services/transfer_engine.dart';
import '../../data/services/app_update_service.dart';
import '../../data/models/device_model.dart';
import '../../data/models/transfer_item.dart';
import '../../data/models/device_profile.dart';
import '../../data/services/device_profile_service.dart';
import '../onboarding/models/predefined_avatar.dart';
import '../onboarding/onboarding_screen.dart';
import 'widgets/edit_profile_dialog.dart';
import '../../core/utils/format_utils.dart';
import '../../core/constants.dart';
import '../../core/widgets/hover_card.dart';
import '../../core/services/theme_service.dart';

class SecuritySettingsView extends StatefulWidget {
  const SecuritySettingsView({super.key});

  @override
  State<SecuritySettingsView> createState() => _SecuritySettingsViewState();
}

class _SecuritySettingsViewState extends State<SecuritySettingsView> {
  // Appearance Preferences
  // Mirrors the app-wide theme (ThemeService keeps AppColors.isDark in sync and rebuilds the tree).
  bool get _isDarkMode => AppColors.isDark;
  bool _isLiquidGlassEnabled = true;

  // Notification Preferences
  bool _notifyIncomingTransfers = true;
  bool _notifyCompletedFailedTransfers = true;

  // Clipboard Privacy Preferences
  bool _clipboardSendOnTapOnly = true;
  String _clipboardClearPolicy = 'Never';

  // Storage and Path
  late final TextEditingController _downloadPathController;
  late final TextEditingController _deviceNameController;
  bool _showReleaseNotes = false;
  DeviceProfile? _deviceProfile;

  @override
  void initState() {
    super.initState();
    final engine = context.read<TransferEngine>();
    _downloadPathController = TextEditingController(
      text: engine.downloadDirectory,
    );
    _deviceNameController = TextEditingController(text: engine.localDeviceName);
    _loadPreferences();
    _loadDeviceProfile();
  }

  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _isLiquidGlassEnabled =
            prefs.getBool('appearance_liquid_glass') ?? true;
        _notifyIncomingTransfers =
            prefs.getBool('notify_incoming_transfers') ?? true;
        _notifyCompletedFailedTransfers =
            prefs.getBool('notify_completed_failed') ?? true;
        _clipboardSendOnTapOnly =
            prefs.getBool('clipboard_send_on_tap_only') ?? true;
        _clipboardClearPolicy =
            prefs.getString('clipboard_clear_policy') ?? 'Never';
      });
    } catch (_) {}
  }

  Future<void> _saveBoolPref(String key, bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
    } catch (_) {}
  }

  Future<void> _saveStringPref(String key, String value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, value);
    } catch (_) {}
  }

  Future<void> _loadDeviceProfile() async {
    final p = await DeviceProfileService().loadProfile();
    if (mounted) {
      setState(() => _deviceProfile = p);
    }
  }

  @override
  void dispose() {
    _downloadPathController.dispose();
    _deviceNameController.dispose();
    super.dispose();
  }

  Future<void> _browseFolder() async {
    try {
      final selected = await FilePicker.getDirectoryPath();
      if (selected != null && selected.isNotEmpty) {
        setState(() {
          _downloadPathController.text = selected;
        });
        if (mounted) {
          context.read<TransferEngine>().updateDownloadDirectory(selected);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Download directory updated to: $selected')),
          );
        }
      }
    } catch (_) {
      _showManualPathDialog();
    }
  }

  void _showManualPathDialog() {
    final controller = TextEditingController(
      text: _downloadPathController.text,
    );
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.charcoalSurface,
        title: Row(
          children: [
            Icon(Icons.folder_special, color: AppColors.primaryAccent),
            SizedBox(width: 8),
            Text('Set Download Folder Path'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter destination directory path on your computer where incoming files and folders will be saved:',
              style: TextStyle(fontSize: 13, color: AppColors.secondaryText),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Folder Path',
                hintText: r'C:\Users\you\Downloads\QuickShare',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.folder_open),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryAccent,
              foregroundColor: AppColors.nearBlack,
            ),
            onPressed: () {
              final newPath = controller.text.trim();
              if (newPath.isNotEmpty) {
                setState(() => _downloadPathController.text = newPath);
                context.read<TransferEngine>().updateDownloadDirectory(newPath);
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Download path changed to: $newPath')),
                );
              }
            },
            child: const Text('Save Path'),
          ),
        ],
      ),
    );
  }

  void _confirmClearHistory(BuildContext context, TransferEngine engine) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.charcoalSurface,
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red),
            SizedBox(width: 8),
            Text('Clear Transfer History?'),
          ],
        ),
        content: const Text(
          'This will permanently delete all transfer history logs and recorded exchanges. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: AppColors.white,
            ),
            onPressed: () {
              engine.clearHistory();
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'All transfer history and logs have been cleared.',
                  ),
                ),
              );
            },
            child: const Text('Confirm Clear'),
          ),
        ],
      ),
    );
  }

  void _confirmClearReceivedFiles(BuildContext context, TransferEngine engine) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.charcoalSurface,
        title: const Row(
          children: [
            Icon(Icons.delete_forever_rounded, color: Colors.red),
            SizedBox(width: 8),
            Text('Clear Received Files?'),
          ],
        ),
        content: const Text(
          'This will permanently delete all received files and cached downloads stored in the application. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: AppColors.white,
            ),
            onPressed: () {
              engine.clearReceivedItems();
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'All received files stored in the app have been cleared.',
                  ),
                ),
              );
            },
            child: const Text('Confirm Delete'),
          ),
        ],
      ),
    );
  }

  void _confirmRemoveDevice(
    BuildContext context,
    TransferEngine engine,
    DeviceModel dev,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.charcoalSurface,
        title: const Text('Remove Paired Device?'),
        content: Text(
          'Are you sure you want to remove "${dev.name}" from your paired-device list?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: AppColors.white,
            ),
            onPressed: () {
              engine.removePairedDevice(dev.id);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Device "${dev.name}" removed from paired devices.',
                  ),
                ),
              );
            },
            child: const Text('Remove Device'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<TransferEngine>();
    final updateService = context.watch<AppUpdateService>();

    if (_downloadPathController.text != engine.downloadDirectory &&
        !_downloadPathController.selection.isValid) {
      _downloadPathController.text = engine.downloadDirectory;
    }

    if (_deviceNameController.text != engine.localDeviceName &&
        !_deviceNameController.selection.isValid) {
      _deviceNameController.text = engine.localDeviceName;
    }

    // Storage computations
    final int receivedBytes = engine.receivedItems.fold(
      0,
      (sum, item) => sum + item.fileSizeBytes,
    );
    final int incompleteBytes = engine.activeTransfers
        .where((t) => t.status != TransferStatus.completed)
        .fold(0, (sum, t) => sum + t.fileSizeBytes);
    final int incompleteCount = engine.activeTransfers
        .where((t) => t.status != TransferStatus.completed)
        .length;

    return Scaffold(
      backgroundColor: AppColors.dashboardBg,
      appBar: AppBar(
        backgroundColor: AppColors.dashboardBg,
        surfaceTintColor: Colors.transparent,
        title: Text(
          'Settings & Privacy',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: AppColors.primaryText,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // -------------------------------------------------------------
            // SECTION 1: APPEARANCE
            // -------------------------------------------------------------
            Text(
              'APPEARANCE',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: AppColors.secondaryText,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 12),
            HoverCard(
              borderRadius: BorderRadius.circular(16),
              padding: const EdgeInsets.all(18),
              color: AppColors.charcoalSurface,
              borderColor: AppColors.white.withValues(alpha: 0.12),
              hoverBorderColor: AppColors.primaryAccent,
              child: Column(
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: Icon(
                      _isDarkMode
                          ? Icons.dark_mode_rounded
                          : Icons.light_mode_rounded,
                      color: AppColors.primaryAccent,
                    ),
                    title: Text(
                      _isDarkMode
                          ? 'Dark Mode (Enabled)'
                          : 'Light Mode (Enabled)',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      _isDarkMode
                          ? 'Deep charcoal & lime theme active'
                          : 'Clean high-contrast daytime theme active',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.secondaryText,
                      ),
                    ),
                    value: _isDarkMode,
                    onChanged: (val) {
                      ThemeService().setThemeMode(
                        val ? ThemeMode.dark : ThemeMode.light,
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            val
                                ? 'Dark Mode activated'
                                : 'Light Mode activated',
                          ),
                        ),
                      );
                    },
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: Icon(
                      Icons.blur_on_rounded,
                      color: AppColors.primaryAccent,
                    ),
                    title: const Text(
                      'Liquid Glass Visual Effect',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      'Renders translucent frosted glass acrylics, ambient glows, and backdrop blurs',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.secondaryText,
                      ),
                    ),
                    value: _isLiquidGlassEnabled,
                    onChanged: (val) {
                      setState(() => _isLiquidGlassEnabled = val);
                      _saveBoolPref('appearance_liquid_glass', val);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            val
                                ? 'Liquid Glass effect enabled'
                                : 'Liquid Glass effect disabled',
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Application Updates & Device Maintenance (Required by Widget Tests)
            _buildUpdatesSection(context, updateService, engine),
            const SizedBox(height: 24),

            // Connections: auto-accept, default method, internet & Bluetooth
            const ConnectionSettingsSection(),
            const SizedBox(height: 24),

            // -------------------------------------------------------------
            // SECTION 2: TRANSFERS AND STORAGE
            // -------------------------------------------------------------
            Text(
              'TRANSFERS AND STORAGE',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: AppColors.secondaryText,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 12),
            HoverCard(
              borderRadius: BorderRadius.circular(16),
              padding: const EdgeInsets.all(20),
              color: AppColors.charcoalSurface,
              borderColor: AppColors.white.withValues(alpha: 0.12),
              hoverBorderColor: AppColors.primaryAccent,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Storage breakdown badges
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.dashboardBg,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppColors.white.withValues(alpha: 0.08),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.folder_shared_rounded,
                                    color: AppColors.primaryAccent,
                                    size: 18,
                                  ),
                                  SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      'Received Files Storage',
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: AppColors.secondaryText,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                FormatUtils.formatBytes(receivedBytes),
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primaryText,
                                ),
                              ),
                              Text(
                                '${engine.receivedItems.length} stored files',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.secondaryText,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.dashboardBg,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppColors.white.withValues(alpha: 0.08),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.hourglass_top_rounded,
                                    color: Colors.amber,
                                    size: 18,
                                  ),
                                  SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      'Incomplete Transfers',
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: AppColors.secondaryText,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                FormatUtils.formatBytes(incompleteBytes),
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primaryText,
                                ),
                              ),
                              Text(
                                '$incompleteCount paused/interrupted',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.secondaryText,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // Clear actions
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primaryAccent,
                        ),
                        icon: const Icon(
                          Icons.cleaning_services_outlined,
                          size: 16,
                        ),
                        label: const Text(
                          'Clear Temporary Chunks & Interrupted Transfers',
                        ),
                        onPressed: () {
                          engine.clearIncompleteTransfers();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Temporary chunks and incomplete transfer files cleared.',
                              ),
                            ),
                          );
                        },
                      ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.redAccent,
                        ),
                        icon: const Icon(Icons.delete_sweep_rounded, size: 16),
                        label: const Text('Clear Transfer History & Logs'),
                        onPressed: () => _confirmClearHistory(context, engine),
                      ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.redAccent,
                        ),
                        icon: const Icon(Icons.folder_delete_rounded, size: 16),
                        label: const Text('Clear Stored Received Files'),
                        onPressed: () =>
                            _confirmClearReceivedFiles(context, engine),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Divider(),
                  const SizedBox(height: 14),

                  // Destination Folder Header (Required by Widget Tests)
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.primaryAccent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.folder_special,
                          color: AppColors.primaryAccent,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Destination Folder for Inbound Downloads',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Files, lab PDFs, and documents received from paired devices are saved here',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.secondaryText,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Editable path row with Browse & Apply
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final pathField = TextField(
                          controller: _downloadPathController,
                          decoration: InputDecoration(
                            labelText: 'Active Download Directory Path',
                            hintText: r'C:\Users\you\Downloads\QuickShare',
                            prefixIcon: Icon(
                              Icons.folder_open,
                              color: AppColors.primaryAccent,
                            ),
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              tooltip: 'Clear Path',
                              onPressed: () => _downloadPathController.clear(),
                            ),
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                          onSubmitted: (val) {
                            if (val.trim().isNotEmpty) {
                              engine.updateDownloadDirectory(val.trim());
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Download directory saved: ${val.trim()}',
                                  ),
                                ),
                              );
                            }
                          },
                        );
                      final saveButton = ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryAccent,
                          foregroundColor: AppColors.nearBlack,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                        ),
                        icon: const Icon(Icons.check, size: 18),
                        label: const Text('Save Path'),
                        onPressed: () {
                          final val = _downloadPathController.text.trim();
                          if (val.isNotEmpty) {
                            engine.updateDownloadDirectory(val);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Download path updated to: $val'),
                              ),
                            );
                          }
                        },
                      );
                      final browseButton = OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 14,
                          ),
                        ),
                        icon: const Icon(
                          Icons.folder_shared_outlined,
                          size: 18,
                        ),
                        label: const Text('Browse...'),
                        onPressed: _browseFolder,
                      );
                      // Narrow windows: stack the buttons under the path field.
                      if (constraints.maxWidth < 560) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            pathField,
                            const SizedBox(height: 10),
                            Wrap(spacing: 8, runSpacing: 8, children: [saveButton, browseButton]),
                          ],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(child: pathField),
                          const SizedBox(width: 10),
                          saveButton,
                          const SizedBox(width: 8),
                          browseButton,
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 14),

                  // Quick presets
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'Quick Presets:',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppColors.secondaryText,
                        ),
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.download, size: 14),
                        label: const Text(
                          'Downloads Folder',
                          style: TextStyle(fontSize: 11),
                        ),
                        onPressed: () {
                          const p = r'C:\Users\Abhijeet\Downloads\QuickShare';
                          _downloadPathController.text = p;
                          engine.updateDownloadDirectory(p);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Set download directory to Downloads\\QuickShare',
                              ),
                            ),
                          );
                        },
                      ),
                      ActionChip(
                        avatar: const Icon(
                          Icons.description_outlined,
                          size: 14,
                        ),
                        label: const Text(
                          'Documents Folder',
                          style: TextStyle(fontSize: 11),
                        ),
                        onPressed: () {
                          const p = r'C:\Users\Abhijeet\Documents\QuickShare';
                          _downloadPathController.text = p;
                          engine.updateDownloadDirectory(p);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Set download directory to Documents\\QuickShare',
                              ),
                            ),
                          );
                        },
                      ),
                      ActionChip(
                        avatar: const Icon(
                          Icons.desktop_windows_outlined,
                          size: 14,
                        ),
                        label: const Text(
                          'Desktop Folder',
                          style: TextStyle(fontSize: 11),
                        ),
                        onPressed: () {
                          const p =
                              r'C:\Users\Abhijeet\Desktop\QuickShare_Received';
                          _downloadPathController.text = p;
                          engine.updateDownloadDirectory(p);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Set download directory to Desktop\\QuickShare_Received',
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // -------------------------------------------------------------
            // SECTION 3: NOTIFICATIONS
            // -------------------------------------------------------------
            Text(
              'NOTIFICATIONS',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: AppColors.secondaryText,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 12),
            HoverCard(
              borderRadius: BorderRadius.circular(16),
              padding: const EdgeInsets.all(18),
              color: AppColors.charcoalSurface,
              borderColor: AppColors.white.withValues(alpha: 0.12),
              hoverBorderColor: AppColors.primaryAccent,
              child: Column(
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: Icon(
                      Icons.notifications_active_rounded,
                      color: AppColors.primaryAccent,
                    ),
                    title: const Text(
                      'Incoming Transfer Notifications',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      'Receive instant visual banners and alerts when a paired device initiates a transfer',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.secondaryText,
                      ),
                    ),
                    value: _notifyIncomingTransfers,
                    onChanged: (val) {
                      setState(() => _notifyIncomingTransfers = val);
                      _saveBoolPref('notify_incoming_transfers', val);
                    },
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: Icon(
                      Icons.check_circle_outline_rounded,
                      color: AppColors.primaryAccent,
                    ),
                    title: const Text(
                      'Completed & Failed Transfer Notifications',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      'Alert when long-running file transfers, PDFs, or batch exchanges complete or encounter an error',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.secondaryText,
                      ),
                    ),
                    value: _notifyCompletedFailedTransfers,
                    onChanged: (val) {
                      setState(() => _notifyCompletedFailedTransfers = val);
                      _saveBoolPref('notify_completed_failed', val);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // -------------------------------------------------------------
            // SECTION 4: DEVICES
            // -------------------------------------------------------------
            Text(
              'DEVICES',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: AppColors.secondaryText,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 12),
            HoverCard(
              borderRadius: BorderRadius.circular(16),
              padding: const EdgeInsets.all(20),
              color: AppColors.charcoalSurface,
              borderColor: AppColors.white.withValues(alpha: 0.12),
              hoverBorderColor: AppColors.primaryAccent,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Device Name Shown to Paired Devices:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _deviceNameController,
                          decoration: InputDecoration(
                            hintText: 'e.g. Lab_Workstation_Alpha',
                            prefixIcon: Icon(
                              Icons.badge_outlined,
                              color: AppColors.primaryAccent,
                            ),
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryAccent,
                          foregroundColor: AppColors.nearBlack,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                        ),
                        onPressed: () {
                          final name = _deviceNameController.text.trim();
                          if (name.isNotEmpty) {
                            engine.setCustomDeviceName(name);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Device name updated to: $name'),
                              ),
                            );
                          }
                        },
                        child: const Text('Save Name'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Divider(),
                  const SizedBox(height: 12),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          'PAIRED DEVICES LIST',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: AppColors.secondaryText,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          '${engine.pairedDevices.length} device(s) connected',
                          textAlign: TextAlign.end,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.secondaryText,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  if (engine.pairedDevices.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.dashboardBg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: AppColors.white.withValues(alpha: 0.08),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.devices_other_rounded,
                            size: 18,
                            color: AppColors.secondaryText,
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'No paired devices connected currently.',
                              style: TextStyle(
                                color: AppColors.secondaryText,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: engine.pairedDevices.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        final dev = engine.pairedDevices[i];
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.dashboardBg,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: AppColors.white.withValues(alpha: 0.08),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                dev.deviceType == DeviceType.mobile
                                    ? Icons.phone_android_rounded
                                    : dev.deviceType == DeviceType.tablet
                                    ? Icons.tablet_mac_rounded
                                    : Icons.laptop_chromebook_rounded,
                                color: AppColors.primaryAccent,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      dev.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                    Text(
                                      'IP: ${dev.ip} · Port: ${dev.port}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: AppColors.secondaryText,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.delete_outline_rounded,
                                  color: Colors.redAccent,
                                  size: 20,
                                ),
                                tooltip: 'Remove Device',
                                onPressed: () =>
                                    _confirmRemoveDevice(context, engine, dev),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // -------------------------------------------------------------
            // SECTION 5: CLIPBOARD PRIVACY
            // -------------------------------------------------------------
            Text(
              'CLIPBOARD PRIVACY',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: AppColors.secondaryText,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 12),
            HoverCard(
              borderRadius: BorderRadius.circular(16),
              padding: const EdgeInsets.all(18),
              color: AppColors.charcoalSurface,
              borderColor: AppColors.white.withValues(alpha: 0.12),
              hoverBorderColor: AppColors.primaryAccent,
              child: Column(
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: Icon(
                      Icons.send_rounded,
                      color: AppColors.primaryAccent,
                    ),
                    title: const Text(
                      'Send Clipboard Content Only When I Tap Send',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      'Prevents automatic background synchronization of clipboard text and sensitive passwords',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.secondaryText,
                      ),
                    ),
                    value: _clipboardSendOnTapOnly,
                    onChanged: (val) {
                      setState(() => _clipboardSendOnTapOnly = val);
                      _saveBoolPref('clipboard_send_on_tap_only', val);
                    },
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final description = Row(
                          children: [
                            Icon(
                              Icons.timer_outlined,
                              color: AppColors.primaryAccent,
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Clear Copied Clipboard Content',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    'Automatically flush clipboard memory after specified period',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.secondaryText,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                        final policyDropdown = DropdownButton<String>(
                          value: _clipboardClearPolicy,
                          items: const [
                            DropdownMenuItem(
                              value: 'Never',
                              child: Text('Never'),
                            ),
                            DropdownMenuItem(
                              value: 'After 1 minute',
                              child: Text('After 1 minute'),
                            ),
                            DropdownMenuItem(
                              value: 'After 5 minutes',
                              child: Text('After 5 minutes'),
                            ),
                            DropdownMenuItem(
                              value: 'On app close',
                              child: Text('On app close'),
                            ),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setState(() => _clipboardClearPolicy = val);
                              _saveStringPref('clipboard_clear_policy', val);
                            }
                          },
                        );

                        if (constraints.maxWidth < 640) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: constraints.maxWidth,
                                child: description,
                              ),
                              Align(
                                alignment: Alignment.centerRight,
                                child: policyDropdown,
                              ),
                            ],
                          );
                        }

                        return Row(
                          children: [
                            Expanded(child: description),
                            policyDropdown,
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            // -------------------------------------------------------------
            // SECTION 7: DEVICE PROFILE & PERSONALIZATION (Required by Widget Tests)
            // -------------------------------------------------------------
            _buildDeviceProfileSection(context, engine),
          ],
        ),
      ),
    );
  }

  Widget _buildUpdatesSection(
    BuildContext context,
    AppUpdateService updateService,
    TransferEngine engine,
  ) {
    final update = updateService.latestUpdate;
    final isProcessing =
        updateService.status == UpdateStatus.downloading ||
        updateService.status == UpdateStatus.verifying ||
        updateService.status == UpdateStatus.staging;
    final hasUpdate = update != null && update.isNewerVersion;

    String lastCheckedStr = 'Never';
    if (updateService.lastCheckedTime != null) {
      final dt = updateService.lastCheckedTime!;
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      lastCheckedStr =
          '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} at $h:$m';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'UPDATES & DEVICE MAINTENANCE',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13,
            color: AppColors.secondaryText,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: 12),
        HoverCard(
          borderRadius: BorderRadius.circular(16),
          padding: const EdgeInsets.all(20),
          liftOffset: 2.0,
          color: AppColors.charcoalSurface,
          borderColor: hasUpdate
              ? AppColors.primaryAccent.withValues(alpha: 0.4)
              : AppColors.white.withValues(alpha: 0.12),
          hoverBorderColor: AppColors.primaryAccent,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final statusIcon = Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.primaryAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      hasUpdate
                          ? Icons.system_update_rounded
                          : Icons.check_circle_rounded,
                      color: AppColors.primaryAccent,
                      size: 24,
                    ),
                  );
                  final versionDetails = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            'Current Version: v${updateService.currentVersion}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: AppColors.primaryText,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: hasUpdate
                                  ? Colors.orange.withValues(alpha: 0.15)
                                  : AppColors.primaryAccent.withValues(
                                      alpha: 0.15,
                                    ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              hasUpdate ? 'Update Available' : 'Up to Date',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                                color: hasUpdate
                                    ? Colors.orange
                                    : AppColors.primaryAccent,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        hasUpdate
                            ? 'Latest available: v${update.version} · ${FormatUtils.formatBytes(update.packageSizeBytes)}'
                            : 'You are running the latest stable build',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.secondaryText,
                        ),
                      ),
                    ],
                  );
                  final checkUpdatesButton = ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.cardBg,
                      foregroundColor: AppColors.primaryText,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: updateService.status == UpdateStatus.checking
                        ? SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.white,
                            ),
                          )
                        : const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text(
                      'Check for Updates',
                      style: TextStyle(fontSize: 12),
                    ),
                    onPressed:
                        (isProcessing ||
                            updateService.status == UpdateStatus.checking)
                        ? null
                        : () async {
                            await updateService.checkForUpdates(
                              userInitiated: true,
                            );
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    updateService.latestUpdate != null &&
                                            updateService
                                                .latestUpdate!
                                                .isNewerVersion
                                        ? 'New version v${updateService.latestUpdate!.version} found!'
                                        : 'QuickShare is up to date (v${updateService.currentVersion}).',
                                  ),
                                ),
                              );
                            }
                          },
                  );

                  if (constraints.maxWidth < 560) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            statusIcon,
                            const SizedBox(width: 14),
                            Expanded(child: versionDetails),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerRight,
                          child: checkUpdatesButton,
                        ),
                      ],
                    );
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      statusIcon,
                      const SizedBox(width: 14),
                      Expanded(child: versionDetails),
                      checkUpdatesButton,
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),

              if (hasUpdate) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.cardBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.primaryAccent.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Update to v${update.version}',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primaryText,
                            ),
                          ),
                          Text(
                            FormatUtils.formatBytes(update.packageSizeBytes),
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.secondaryText,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        update.description,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.secondaryText,
                        ),
                      ),
                      const SizedBox(height: 10),

                      InkWell(
                        onTap: () => setState(
                          () => _showReleaseNotes = !_showReleaseNotes,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _showReleaseNotes
                                  ? 'Hide Release Notes'
                                  : 'View Details',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.primaryAccent,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Icon(
                              _showReleaseNotes
                                  ? Icons.keyboard_arrow_up
                                  : Icons.keyboard_arrow_down,
                              size: 16,
                              color: AppColors.primaryAccent,
                            ),
                          ],
                        ),
                      ),

                      if (_showReleaseNotes) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: update.releaseNotes.map((note) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 2,
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '• ',
                                      style: TextStyle(
                                        color: AppColors.primaryAccent,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(
                                        note,
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          color: AppColors.secondaryText,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),

                      if (isProcessing) ...[
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  updateService.statusMessage,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.secondaryText,
                                  ),
                                ),
                                Text(
                                  '${(updateService.updateProgress * 100).toInt()}%',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.primaryAccent,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: LinearProgressIndicator(
                                value: updateService.updateProgress,
                                backgroundColor: AppColors.white.withValues(
                                  alpha: 0.1,
                                ),
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  AppColors.primaryAccent,
                                ),
                                minHeight: 6,
                              ),
                            ),
                          ],
                        ),
                      ] else ...[
                        Row(
                          children: [
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primaryAccent,
                                foregroundColor: AppColors.nearBlack,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              icon: const Icon(
                                Icons.download_rounded,
                                size: 16,
                              ),
                              label: const Text(
                                'Update Now',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              onPressed: () {
                                updateService.startUpdateNow(
                                  engine: engine,
                                  onComplete: () {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'QuickShare Studio updated to v${updateService.currentVersion}!',
                                        ),
                                      ),
                                    );
                                  },
                                  onError: (err) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Update Error: $err'),
                                        backgroundColor: Colors.red,
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                            const SizedBox(width: 12),
                            OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              onPressed: updateService.isUpdatePostponed
                                  ? null
                                  : () => updateService.postponeUpdate(),
                              child: Text(
                                updateService.isUpdatePostponed
                                    ? 'Update Postponed'
                                    : 'Update Later',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.charcoalSurface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.verified_outlined,
                        color: AppColors.primaryAccent,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Your application is up to date (version ${updateService.currentVersion}). No new updates available.',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: AppColors.secondaryText,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              LayoutBuilder(
                builder: (context, constraints) {
                  final lastChecked = Text(
                    'Last checked: $lastCheckedStr',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AppColors.secondaryText,
                    ),
                  );
                  final autoCheck = Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          'Automatically check for updates',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primaryText,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Switch(
                        value: updateService.autoCheckUpdates,
                        onChanged: (val) =>
                            updateService.setAutoCheckUpdates(val),
                      ),
                    ],
                  );

                  if (constraints.maxWidth < 560) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        lastChecked,
                        const SizedBox(height: 8),
                        autoCheck,
                      ],
                    );
                  }

                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [lastChecked, autoCheck],
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDeviceProfileSection(
    BuildContext context,
    TransferEngine engine,
  ) {
    final profile = _deviceProfile;
    final avatarId = profile?.avatarId ?? 'laptop';
    final avatar = PredefinedAvatar.findById(avatarId);
    final hasCustomAvatar =
        profile?.isCustomAvatar == true &&
        profile?.customAvatarPath != null &&
        profile!.customAvatarPath!.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'DEVICE PROFILE & IDENTITY',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13,
            color: AppColors.secondaryText,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: 12),
        Card(
          elevation: 0,
          color: AppColors.charcoalSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: AppColors.white.withValues(alpha: 0.12)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppColors.limeGreen.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.limeGreen, width: 2),
                  ),
                  child: Center(
                    child: hasCustomAvatar && !kIsWeb
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(28),
                            child: Image.file(
                              File(profile.customAvatarPath!),
                              width: 52,
                              height: 52,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  Icon(
                                    avatar.icon,
                                    size: 28,
                                    color: AppColors.limeGreen,
                                  ),
                            ),
                          )
                        : Icon(
                            avatar.icon,
                            size: 28,
                            color: AppColors.limeGreen,
                          ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              engine.localDeviceName,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: AppColors.white,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.limeGreen.withValues(
                                alpha: 0.15,
                              ),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: AppColors.limeGreen.withValues(
                                  alpha: 0.3,
                                ),
                              ),
                            ),
                            child: Text(
                              (profile?.platform ?? 'DEVICE').toUpperCase(),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: AppColors.limeGreen,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Avatar: ${hasCustomAvatar ? "Custom Photo" : avatar.label} · ID: ${profile != null && profile.id.length >= 8 ? profile.id.substring(0, 8) : "local"}',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.secondaryText,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // Flexible so the buttons wrap instead of overflowing on narrow screens.
                Flexible(
                  child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.limeGreen,
                        foregroundColor: AppColors.nearBlack,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.edit_rounded, size: 16),
                      label: const Text(
                        'Edit Profile',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      onPressed: () {
                        if (profile != null) {
                          showDialog(
                            context: context,
                            builder: (ctx) => EditProfileDialog(
                              initialProfile: profile,
                              onSaved: _loadDeviceProfile,
                            ),
                          );
                        }
                      },
                    ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.softGray,
                        side: BorderSide(color: AppColors.glassBorder),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.restart_alt_rounded, size: 16),
                      label: const Text('Reset Setup'),
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Reset Onboarding Setup?'),
                            content: const Text(
                              'This will reset your device first-time setup state so you can experience initial onboarding flow again.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('Cancel'),
                              ),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.limeGreen,
                                  foregroundColor: AppColors.nearBlack,
                                ),
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('Reset & Launch Setup'),
                              ),
                            ],
                          ),
                        );
                        if (confirm == true && context.mounted) {
                          await DeviceProfileService().resetOnboarding();
                          await _loadDeviceProfile();
                          if (context.mounted) {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => OnboardingScreen(
                                  onComplete: () {
                                    Navigator.of(context).pop();
                                    _loadDeviceProfile();
                                  },
                                ),
                              ),
                            );
                          }
                        }
                      },
                    ),
                  ],
                ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
