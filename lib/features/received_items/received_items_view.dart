import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/services/file_actions.dart';
import '../../core/widgets/demo_mode_notice.dart';
import 'package:provider/provider.dart';
import '../../data/services/transfer_engine.dart';
import '../../data/models/received_item_model.dart';
import '../../data/models/device_model.dart';
import '../../core/utils/file_utils.dart';
import '../../core/utils/format_utils.dart';
import '../../core/constants.dart';
import '../../core/widgets/hover_card.dart';

/// QuickShare Studio — Received Items & Background Inbox
/// Every file received from another device is permanently stored here and can be downloaded later.
/// Preserves original file name, format, and contents across app sessions.
class ReceivedItemsView extends StatefulWidget {
  final VoidCallback? onOpenSettings;

  const ReceivedItemsView({super.key, this.onOpenSettings});

  @override
  State<ReceivedItemsView> createState() => _ReceivedItemsViewState();
}

class _ReceivedItemsViewState extends State<ReceivedItemsView> {
  ReceivedFileType? _selectedFilter;

  // -------------------------------------------------------------
  // Send PDF Simulation Dialog
  // -------------------------------------------------------------
  void _showSendPdfFromPairedDeviceDialog(BuildContext context, TransferEngine engine) {
    if (engine.pairedDevices.isEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.charcoalSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: AppColors.subtleBorder),
          ),
          title: Row(
            children: [
              Icon(Icons.phone_android, color: AppColors.primaryAccent),
              SizedBox(width: 10),
              Text(
                'No Paired Devices',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: AppColors.primaryText,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: Text(
            'To send a PDF from a paired device, you need at least one connected phone or lab PC.\n\nWould you like to instantly connect a test paired device now?',
            style: TextStyle(fontFamily: 'Poppins', color: AppColors.secondaryText),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: TextStyle(fontFamily: 'Poppins', color: AppColors.secondaryText)),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryAccent,
                foregroundColor: AppColors.nearBlack,
              ),
              icon: const Icon(Icons.link, size: 16),
              label: const Text('Pair Sample Phone', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.bold)),
              onPressed: () async {
                await engine.simulateInstantPair(deviceName: 'Pixel 8 Pro', platform: 'Android');
                if (ctx.mounted) Navigator.pop(ctx);
                if (context.mounted) {
                  _showSendPdfFromPairedDeviceDialog(context, engine);
                }
              },
            ),
          ],
        ),
      );
      return;
    }

    var selectedDevice = engine.pairedDevices.first;
    final nameController = TextEditingController(text: 'Lab_Report_${selectedDevice.name.replaceAll(RegExp(r'\s+'), '_')}.pdf');
    var selectedPreset = 'lab_report';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppColors.charcoalSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: AppColors.subtleBorder),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.picture_as_pdf, color: Color(0xFFEF4444), size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Send PDF from Paired Device',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: AppColors.primaryText,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Inbound transmission to Received Items',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 11,
                        color: AppColors.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Choose Paired Sender Device:',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    color: AppColors.primaryText,
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<DeviceModel>(
                  initialValue: selectedDevice,
                  dropdownColor: AppColors.cardBg,
                  decoration: InputDecoration(
                    prefixIcon: Icon(Icons.devices, color: AppColors.primaryAccent, size: 18),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                  items: engine.pairedDevices
                      .map((d) => DropdownMenuItem(
                            value: d,
                            child: Text(
                              d.name,
                              style: TextStyle(fontFamily: 'Poppins', color: AppColors.primaryText),
                            ),
                          ))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setDialogState(() {
                        selectedDevice = val;
                        nameController.text = 'Lab_Report_${val.name.replaceAll(RegExp(r'\s+'), '_')}.pdf';
                      });
                    }
                  },
                ),
                const SizedBox(height: 16),
                Text(
                  'PDF Document Type:',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    color: AppColors.primaryText,
                  ),
                ),
                const SizedBox(height: 8),
                InkWell(
                  onTap: () => setDialogState(() => selectedPreset = 'lab_report'),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: selectedPreset == 'lab_report'
                          ? AppColors.primaryAccent.withValues(alpha: 0.15)
                          : AppColors.cardBg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: selectedPreset == 'lab_report'
                            ? AppColors.primaryAccent
                            : AppColors.subtleBorder,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          selectedPreset == 'lab_report' ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                          color: selectedPreset == 'lab_report' ? AppColors.primaryAccent : AppColors.secondaryText,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Generated Lab Experiment PDF',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 13,
                                  color: AppColors.primaryText,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Vector-rendered lab report with headers & checksum',
                                style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: AppColors.secondaryText),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (engine.activeSessionPdf != null) ...[
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () => setDialogState(() => selectedPreset = 'session_pdf'),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: selectedPreset == 'session_pdf'
                            ? AppColors.primaryAccent.withValues(alpha: 0.15)
                            : AppColors.cardBg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: selectedPreset == 'session_pdf'
                              ? AppColors.primaryAccent
                              : AppColors.subtleBorder,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            selectedPreset == 'session_pdf' ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                            color: selectedPreset == 'session_pdf' ? AppColors.primaryAccent : AppColors.secondaryText,
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Active Session PDF (${engine.activeSessionPdf!.fileName})',
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 13,
                                    color: AppColors.primaryText,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${engine.activeSessionPdf!.pageCount} pages • ${FormatUtils.formatBytes(engine.activeSessionPdf!.fileSizeBytes)}',
                                  style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: AppColors.secondaryText),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: nameController,
                  style: TextStyle(fontFamily: 'Poppins', color: AppColors.primaryText, fontSize: 13),
                  decoration: InputDecoration(
                    labelText: 'Incoming PDF File Name',
                    prefixIcon: const Icon(Icons.description, color: Color(0xFFEF4444), size: 18),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: TextStyle(fontFamily: 'Poppins', color: AppColors.secondaryText)),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryAccent,
                foregroundColor: AppColors.nearBlack,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.download_for_offline, size: 18),
              label: const Text('Receive PDF Now', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.bold)),
              onPressed: () async {
                final fname = FileUtils.formatPdfFilename(nameController.text.trim());
                Uint8List? customBytes;
                if (selectedPreset == 'session_pdf' && engine.activeSessionPdf != null) {
                  customBytes = engine.activeSessionPdf!.bytes;
                }
                Navigator.pop(ctx);
                await engine.sendPdfFromDevice(
                  senderDevice: selectedDevice,
                  fileName: fname,
                  bytes: customBytes,
                );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Received $fname from ${selectedDevice.name}! Added to Received Items.'),
                      backgroundColor: AppColors.charcoalSurface,
                    ),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------
  // Send Text Dialog
  // -------------------------------------------------------------
  void _showSendTextDialog(BuildContext context, TransferEngine engine) {
    if (engine.pairedDevices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No paired devices available. Pair a device first.')),
      );
      return;
    }

    final textController = TextEditingController();
    var selectedDevice = engine.pairedDevices.first;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppColors.charcoalSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: AppColors.subtleBorder),
          ),
          title: Row(
            children: [
              Icon(Icons.text_fields, color: AppColors.primaryAccent),
              SizedBox(width: 8),
              Text(
                'Send Text Snippet to Paired Device',
                style: TextStyle(fontFamily: 'Poppins', color: AppColors.primaryText, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Send notes, URLs, or code to a connected smartphone or computer:',
                style: TextStyle(fontFamily: 'Poppins', color: AppColors.secondaryText, fontSize: 12),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<DeviceModel>(
                initialValue: selectedDevice,
                dropdownColor: AppColors.cardBg,
                decoration: const InputDecoration(labelText: 'Recipient Device', border: OutlineInputBorder()),
                items: engine.pairedDevices
                    .map((d) => DropdownMenuItem(value: d, child: Text(d.name, style: TextStyle(color: AppColors.primaryText))))
                    .toList(),
                onChanged: (val) {
                  if (val != null) setDialogState(() => selectedDevice = val);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: textController,
                maxLines: 4,
                style: TextStyle(color: AppColors.white, fontFamily: 'Poppins', fontSize: 13),
                decoration: const InputDecoration(
                  labelText: 'Text or Code to Send',
                  hintText: 'e.g. Meeting at 4 PM in Lab 3.',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: TextStyle(fontFamily: 'Poppins', color: AppColors.secondaryText)),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryAccent,
                foregroundColor: AppColors.nearBlack,
              ),
              icon: const Icon(Icons.send_rounded, size: 16),
              label: const Text('Send Text', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.bold)),
              onPressed: () {
                if (textController.text.trim().isNotEmpty) {
                  engine.sendTextToDevice(text: textController.text.trim(), recipient: selectedDevice);
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Text sent to ${selectedDevice.name}!')),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------
  // Change Download Path Dialog
  // -------------------------------------------------------------
  void _editDownloadPath(BuildContext context, TransferEngine engine) {
    final controller = TextEditingController(text: engine.downloadDirectory);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.charcoalSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: AppColors.subtleBorder),
        ),
        title: Text(
          'Change Download Storage Directory',
          style: TextStyle(fontFamily: 'Poppins', color: AppColors.primaryText, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Files received automatically from trusted devices will be saved to this folder:',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: AppColors.secondaryText),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              style: TextStyle(color: AppColors.white, fontFamily: 'Poppins', fontSize: 13),
              decoration: InputDecoration(
                labelText: 'Download Folder Path',
                prefixIcon: Icon(Icons.folder_open, color: AppColors.primaryAccent),
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(fontFamily: 'Poppins', color: AppColors.secondaryText)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryAccent,
              foregroundColor: AppColors.nearBlack,
            ),
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                engine.updateDownloadDirectory(controller.text.trim());
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Download directory updated to ${controller.text.trim()}')),
                );
              }
            },
            child: const Text('Save Path', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // Download or Save to Device Action
  // -------------------------------------------------------------
  Future<void> _downloadOrSaveItem(BuildContext context, ReceivedItemModel item, TransferEngine engine) async {
    final bytes = item.bytes.isNotEmpty ? item.bytes : engine.fileDataStore[item.fileName];
    if (bytes == null || bytes.isEmpty) {
      // Large received files go straight to disk and are not kept in memory.
      final message = item.savedToPath.isNotEmpty
          ? 'Already saved to ${item.savedToPath}.'
          : 'File contents are no longer available.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      return;
    }
    final String message;
    try {
      message = await FileActions.save(bytes, item.fileName, directory: engine.downloadDirectory);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save: $e')));
      }
      return;
    }
    await engine.downloadOrSaveReceivedItem(item);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.charcoalSurface,
          content: Row(
            children: [
              Icon(Icons.check_circle_rounded, color: AppColors.primaryAccent, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '$message (${FormatUtils.formatBytes(item.fileSizeBytes)}).',
                  style: TextStyle(fontFamily: 'Poppins', color: AppColors.primaryText, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  // -------------------------------------------------------------
  // Preview / Open Item Dialog
  // -------------------------------------------------------------
  void _previewItem(BuildContext context, ReceivedItemModel item, TransferEngine engine) {
    if (item.bytes.isEmpty && item.savedToPath.isNotEmpty && (engine.fileDataStore[item.fileName]?.isEmpty ?? true)) {
      FileActions.runWithSnackBar(context, () => FileActions.openSaved(item.savedToPath));
      return;
    }
    if (item.fileType == ReceivedFileType.pdf && item.bytes.isNotEmpty) {
      FileActions.runWithSnackBar(context, () => FileActions.open(item.bytes, item.fileName));
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.charcoalSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: AppColors.subtleBorder),
        ),
        title: Row(
          children: [
            Icon(_getFileIcon(item.fileType), color: _getFileColor(item.fileType), size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                item.fileName,
                style: TextStyle(fontFamily: 'Poppins', color: AppColors.primaryText, fontWeight: FontWeight.bold, fontSize: 15),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (item.fileType == ReceivedFileType.text && item.textContent != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.cardBg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.subtleBorder),
                  ),
                  child: SelectableText(
                    item.textContent!,
                    style: TextStyle(fontSize: 13, fontFamily: 'monospace', color: AppColors.primaryText),
                  ),
                ),
              ] else if (item.fileType == ReceivedFileType.image && item.bytes.isNotEmpty) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(item.bytes, height: 260, fit: BoxFit.contain, cacheHeight: 600),
                ),
              ] else ...[
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Icon(_getFileIcon(item.fileType), size: 70, color: _getFileColor(item.fileType)),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              _buildDetailRow('File Size', FormatUtils.formatBytes(item.fileSizeBytes)),
              _buildDetailRow('Sender Device', item.senderDeviceName),
              _buildDetailRow('Received At', '${item.receivedAt.hour.toString().padLeft(2, '0')}:${item.receivedAt.minute.toString().padLeft(2, '0')} • ${item.receivedAt.day}/${item.receivedAt.month}/${item.receivedAt.year}'),
              _buildDetailRow('Storage Path', item.savedToPath),
              if (item.sha256.isNotEmpty)
                _buildDetailRow('SHA-256', item.sha256.length > 20 ? '${item.sha256.substring(0, 16)}...' : item.sha256),
            ],
          ),
        ),
        actions: [
          if (item.fileType == ReceivedFileType.text && item.textContent != null)
            OutlinedButton.icon(
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('Copy Text', style: TextStyle(fontFamily: 'Poppins')),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: item.textContent!));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Copied text to clipboard!')),
                );
              },
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Close', style: TextStyle(fontFamily: 'Poppins', color: AppColors.secondaryText)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryAccent,
              foregroundColor: AppColors.nearBlack,
            ),
            icon: const Icon(Icons.download_rounded, size: 16),
            label: const Text('Download / Save to device', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.bold)),
            onPressed: () {
              Navigator.pop(ctx);
              _downloadOrSaveItem(context, item, engine);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: TextStyle(fontFamily: 'Poppins', fontSize: 11.5, color: AppColors.secondaryText, fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontFamily: 'Poppins', fontSize: 11.5, color: AppColors.primaryText, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  IconData _getFileIcon(ReceivedFileType type) {
    switch (type) {
      case ReceivedFileType.pdf:
        return Icons.picture_as_pdf;
      case ReceivedFileType.image:
        return Icons.image_rounded;
      case ReceivedFileType.text:
        return Icons.text_snippet_rounded;
      case ReceivedFileType.document:
        return Icons.description_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
  }

  Color _getFileColor(ReceivedFileType type) {
    switch (type) {
      case ReceivedFileType.pdf:
        return const Color(0xFFEF4444);
      case ReceivedFileType.image:
        return AppColors.primaryAccent;
      case ReceivedFileType.text:
        return AppColors.primaryAccent;
      case ReceivedFileType.document:
        return const Color(0xFFFBBF24);
      default:
        return AppColors.primaryAccent;
    }
  }

  // -------------------------------------------------------------
  // Build Main Screen
  // -------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final engine = context.watch<TransferEngine>();

    final filteredItems = _selectedFilter == null
        ? engine.receivedItems
        : engine.receivedItems.where((i) => i.fileType == _selectedFilter).toList();

    return Scaffold(
      backgroundColor: AppColors.dashboardBg,
      appBar: AppBar(
        backgroundColor: AppColors.charcoalSurface,
        elevation: 0,
        title: Text(
          'Received Files & Background Inbox',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w700,
            color: AppColors.primaryText,
          ),
        ),
        actions: [
          // Send / Receive PDF from Paired Device shortcut
          IconButton(
            icon: const Icon(Icons.picture_as_pdf, color: Color(0xFFEF4444)),
            tooltip: 'Send PDF from Paired Device',
            onPressed: () => _showSendPdfFromPairedDeviceDialog(context, engine),
          ),
          // Send text shortcut
          IconButton(
            icon: Icon(Icons.chat_bubble_outline, color: AppColors.primaryAccent),
            tooltip: 'Send Text to Paired Device',
            onPressed: () => _showSendTextDialog(context, engine),
          ),
          if (engine.receivedItems.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined, color: Color(0xFFEF4444)),
              tooltip: 'Clear All Received Records',
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: AppColors.charcoalSurface,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    title: Text('Clear Received Records?', style: TextStyle(fontFamily: 'Poppins', color: AppColors.primaryText)),
                    content: Text(
                      'Are you sure you want to clear the received records list? Files on disk will remain preserved.',
                      style: TextStyle(fontFamily: 'Poppins', color: AppColors.secondaryText),
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: TextStyle(fontFamily: 'Poppins', color: AppColors.secondaryText))),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444), foregroundColor: AppColors.white),
                        onPressed: () {
                          Navigator.pop(ctx);
                          engine.clearAllReceivedItems();
                        },
                        child: const Text('Clear All', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                );
              },
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status & Storage Destination Card
            _buildStatusBanner(context, engine),
            const SizedBox(height: 20),
            const DemoModeNotice(),

            // Category Filter Chips
            _buildFilterChips(engine),
            const SizedBox(height: 18),

            // Received Items List
            if (filteredItems.isEmpty)
              _buildEmptyState(context, engine)
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: filteredItems.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final item = filteredItems[index];
                  return _buildReceivedItemCard(context, item, engine);
                },
              ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------
  // Status & Storage Destination Banner
  // -------------------------------------------------------------
  Widget _buildStatusBanner(BuildContext context, TransferEngine engine) {
    return HoverCard(
      borderRadius: BorderRadius.circular(18),
      padding: const EdgeInsets.all(20),
      liftOffset: 1.5,
      scale: 1.008,
      color: AppColors.charcoalSurface,
      borderColor: AppColors.subtleBorder,
      hoverBorderColor: AppColors.primaryAccent.withValues(alpha: 0.6),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: engine.isReceivingPaused
                      ? Colors.orange.withValues(alpha: 0.15)
                      : AppColors.primaryAccent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: engine.isReceivingPaused
                      ? Colors.orange.withValues(alpha: 0.4)
                      : AppColors.primaryAccent.withValues(alpha: 0.3),
                  ),
                ),
                child: Icon(
                  engine.isReceivingPaused ? Icons.pause_circle_outline : Icons.cloud_download_rounded,
                  color: engine.isReceivingPaused ? Colors.orange : AppColors.primaryAccent,
                  size: 26,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        Text(
                          engine.isReceivingPaused ? 'Background Receiving: PAUSED' : 'Background Receiving: ACTIVE',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: engine.isReceivingPaused ? Colors.orange : AppColors.primaryText,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.cardBg,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.subtleBorder),
                          ),
                          child: Text(
                            '${engine.pairedDevices.length} Trusted Devices',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primaryAccent,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Target Destination: ${engine.downloadDirectory}',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11.5,
                        color: AppColors.secondaryText,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: engine.isReceivingPaused ? AppColors.primaryAccent : Colors.orange,
                      side: BorderSide(color: engine.isReceivingPaused ? AppColors.primaryAccent : Colors.orange),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                    icon: Icon(engine.isReceivingPaused ? Icons.play_arrow_rounded : Icons.pause_rounded, size: 16),
                    label: Text(
                      engine.isReceivingPaused ? 'Resume' : 'Pause Receiving',
                      style: const TextStyle(fontFamily: 'Poppins', fontSize: 11.5),
                    ),
                    onPressed: () => engine.togglePauseReceiving(),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryAccent,
                      foregroundColor: AppColors.nearBlack,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                    icon: const Icon(Icons.edit_location_alt_rounded, size: 16),
                    label: const Text('Change Path', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.bold, fontSize: 11.5)),
                    onPressed: () => _editDownloadPath(context, engine),
                  ),
                ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // Filter Chips
  // -------------------------------------------------------------
  Widget _buildFilterChips(TransferEngine engine) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilterChip(
          label: Text('All (${engine.receivedItems.length})', style: const TextStyle(fontFamily: 'Poppins', fontSize: 11.5)),
          selected: _selectedFilter == null,
          selectedColor: AppColors.primaryAccent,
          backgroundColor: AppColors.cardBg,
          checkmarkColor: AppColors.nearBlack,
          labelStyle: TextStyle(
            fontFamily: 'Poppins',
            color: _selectedFilter == null ? AppColors.nearBlack : AppColors.secondaryText,
            fontWeight: _selectedFilter == null ? FontWeight.bold : FontWeight.normal,
          ),
          onSelected: (_) => setState(() => _selectedFilter = null),
        ),
        FilterChip(
          avatar: const Icon(Icons.picture_as_pdf, size: 15, color: Color(0xFFEF4444)),
          label: Text('PDFs (${engine.receivedItems.where((i) => i.fileType == ReceivedFileType.pdf).length})', style: const TextStyle(fontFamily: 'Poppins', fontSize: 11.5)),
          selected: _selectedFilter == ReceivedFileType.pdf,
          selectedColor: AppColors.primaryAccent,
          backgroundColor: AppColors.cardBg,
          checkmarkColor: AppColors.nearBlack,
          labelStyle: TextStyle(
            fontFamily: 'Poppins',
            color: _selectedFilter == ReceivedFileType.pdf ? AppColors.nearBlack : AppColors.secondaryText,
            fontWeight: _selectedFilter == ReceivedFileType.pdf ? FontWeight.bold : FontWeight.normal,
          ),
          onSelected: (_) => setState(() => _selectedFilter = ReceivedFileType.pdf),
        ),
        FilterChip(
          avatar: Icon(Icons.image, size: 15, color: AppColors.primaryAccent),
          label: Text('Images (${engine.receivedItems.where((i) => i.fileType == ReceivedFileType.image).length})', style: const TextStyle(fontFamily: 'Poppins', fontSize: 11.5)),
          selected: _selectedFilter == ReceivedFileType.image,
          selectedColor: AppColors.primaryAccent,
          backgroundColor: AppColors.cardBg,
          checkmarkColor: AppColors.nearBlack,
          labelStyle: TextStyle(
            fontFamily: 'Poppins',
            color: _selectedFilter == ReceivedFileType.image ? AppColors.nearBlack : AppColors.secondaryText,
            fontWeight: _selectedFilter == ReceivedFileType.image ? FontWeight.bold : FontWeight.normal,
          ),
          onSelected: (_) => setState(() => _selectedFilter = ReceivedFileType.image),
        ),
        FilterChip(
          avatar: Icon(Icons.text_snippet, size: 15, color: AppColors.primaryAccent),
          label: Text('Text (${engine.receivedItems.where((i) => i.fileType == ReceivedFileType.text).length})', style: const TextStyle(fontFamily: 'Poppins', fontSize: 11.5)),
          selected: _selectedFilter == ReceivedFileType.text,
          selectedColor: AppColors.primaryAccent,
          backgroundColor: AppColors.cardBg,
          checkmarkColor: AppColors.nearBlack,
          labelStyle: TextStyle(
            fontFamily: 'Poppins',
            color: _selectedFilter == ReceivedFileType.text ? AppColors.nearBlack : AppColors.secondaryText,
            fontWeight: _selectedFilter == ReceivedFileType.text ? FontWeight.bold : FontWeight.normal,
          ),
          onSelected: (_) => setState(() => _selectedFilter = ReceivedFileType.text),
        ),
      ],
    );
  }

  // -------------------------------------------------------------
  // Empty State
  // -------------------------------------------------------------
  Widget _buildEmptyState(BuildContext context, TransferEngine engine) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.subtleBorder),
      ),
      child: Center(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.charcoalSurface,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.subtleBorder),
              ),
              child: Icon(Icons.inbox_rounded, size: 40, color: AppColors.primaryAccent),
            ),
            const SizedBox(height: 14),
            Text(
              'No files received in this category',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: AppColors.primaryText,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Files received from paired smartphones, laptops, and tablets are stored here permanently and can be downloaded anytime.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12,
                color: AppColors.secondaryText,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryAccent,
                foregroundColor: AppColors.nearBlack,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              ),
              icon: const Icon(Icons.picture_as_pdf, size: 16),
              label: const Text('Send PDF from Paired Device', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.bold)),
              onPressed: () => _showSendPdfFromPairedDeviceDialog(context, engine),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------
  // Received Item Card
  // -------------------------------------------------------------
  Widget _buildReceivedItemCard(BuildContext context, ReceivedItemModel item, TransferEngine engine) {
    final fileColor = _getFileColor(item.fileType);
    final fileIcon = _getFileIcon(item.fileType);

    return HoverCard(
      borderRadius: BorderRadius.circular(16),
      liftOffset: 1.5,
      scale: 1.008,
      padding: const EdgeInsets.all(16),
      color: AppColors.cardBg,
      borderColor: AppColors.subtleBorder,
      hoverBorderColor: fileColor.withValues(alpha: 0.6),
      child: Row(
        children: [
          // File Icon Avatar
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: fileColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: fileColor.withValues(alpha: 0.3)),
            ),
            child: Icon(fileIcon, color: fileColor, size: 22),
          ),
          const SizedBox(width: 14),

          // File Information (Name, Sender, Size, Date, Path)
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.fileName,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.bold,
                          fontSize: 13.5,
                          color: AppColors.primaryText,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.charcoalSurface,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppColors.subtleBorder),
                      ),
                      child: Text(
                        'SAVED',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          color: AppColors.primaryAccent,
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                if (item.fileType == ReceivedFileType.text && item.textContent != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      '"${item.textContent}"',
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 11.5, fontStyle: FontStyle.italic, color: AppColors.secondaryText),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                Text(
                  'From: ${item.senderDeviceName} • ${FormatUtils.formatBytes(item.fileSizeBytes)} • ${item.receivedAt.hour.toString().padLeft(2, '0')}:${item.receivedAt.minute.toString().padLeft(2, '0')}',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 11.5, color: AppColors.secondaryText),
                ),
                const SizedBox(height: 2),
                Text(
                  'Path: ${item.savedToPath}',
                  style: TextStyle(fontFamily: 'monospace', fontSize: 10.5, color: AppColors.secondaryText),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),

          // Action Buttons: Open, Download / Save to device, Delete
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (item.fileType == ReceivedFileType.text && item.textContent != null)
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.secondaryText,
                    side: BorderSide(color: AppColors.subtleBorder),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.copy, size: 14),
                  label: const Text('Copy', style: TextStyle(fontFamily: 'Poppins', fontSize: 11)),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: item.textContent!));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Copied text to clipboard!')),
                    );
                  },
                ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.secondaryText,
                  side: BorderSide(color: AppColors.subtleBorder),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.visibility, size: 14),
                label: const Text('Open / See', style: TextStyle(fontFamily: 'Poppins', fontSize: 11)),
                onPressed: () => _previewItem(context, item, engine),
              ),
              // Prominent Download / Save to device button
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryAccent,
                  foregroundColor: AppColors.nearBlack,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  elevation: 0,
                ),
                icon: const Icon(Icons.download_rounded, size: 15),
                label: const Text(
                  'Download',
                  style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 11.5),
                ),
                onPressed: () => _downloadOrSaveItem(context, item, engine),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Color(0xFFEF4444), size: 18),
                tooltip: 'Delete Record',
                onPressed: () => engine.removeReceivedItem(item.id),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
