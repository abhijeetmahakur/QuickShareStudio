import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../../data/services/transfer_engine.dart';
import '../../data/models/device_model.dart';
import '../../data/models/transfer_item.dart';
import '../../core/utils/format_utils.dart';
import '../../core/constants.dart';

class SelectedFileItem {
  final String name;
  final int size;
  final Uint8List bytes;

  SelectedFileItem({
    required this.name,
    required this.size,
    required this.bytes,
  });
}

class SendFilesView extends StatefulWidget {
  final Uint8List? preloadedBytes;
  final String? preloadedName;

  const SendFilesView({
    super.key,
    this.preloadedBytes,
    this.preloadedName,
  });

  @override
  State<SendFilesView> createState() => _SendFilesViewState();
}

class _SendFilesViewState extends State<SendFilesView> {
  final List<SelectedFileItem> _selectedFiles = [];
  final Set<String> _selectedDeviceIds = {};
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    if (widget.preloadedBytes != null && widget.preloadedName != null) {
      _selectedFiles.add(
        SelectedFileItem(
          name: widget.preloadedName!,
          size: widget.preloadedBytes!.length,
          bytes: widget.preloadedBytes!,
        ),
      );
    }
  }

  Future<void> _pickFiles() async {
    try {
      final files = await FilePicker.pickFiles();
      if (files.isNotEmpty) {
        for (final f in files) {
          final bytes = await f.readAsBytes();
          final len = (await f.length()) ?? bytes.length;
          setState(() {
            _selectedFiles.add(SelectedFileItem(name: f.name, size: len, bytes: bytes));
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error picking files: $e')));
      }
    }
  }

  Future<void> _startTransfer() async {
    final engine = context.read<TransferEngine>();
    if (_selectedFiles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select at least one file.')));
      return;
    }
    if (_selectedDeviceIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select at least one recipient device.')));
      return;
    }

    final targetDevices = engine.pairedDevices.where((d) => _selectedDeviceIds.contains(d.id)).toList();

    setState(() => _isSending = true);

    for (final file in _selectedFiles) {
      await engine.sendFileToMultipleRecipients(
        fileName: file.name,
        bytes: file.bytes,
        recipients: targetDevices,
      );
    }

    setState(() => _isSending = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Started transfer of ${_selectedFiles.length} file(s) to ${targetDevices.length} recipient(s).')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<TransferEngine>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Send Files & Multi-Device Transfer', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Step 1: Select Files
            const Text(
              '1. SELECT FILES OR SCREENSHOTS TO TRANSFER',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 12),

            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.15)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    InkWell(
                      onTap: _pickFiles,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.primary.withValues(alpha: 0.25), style: BorderStyle.solid),
                        ),
                        child: const Column(
                          children: [
                            Icon(Icons.upload_file, size: 36, color: AppColors.primary),
                            SizedBox(height: 8),
                            Text('Click to Pick Files, Screenshots, or PDFs', style: TextStyle(fontWeight: FontWeight.bold)),
                            SizedBox(height: 4),
                            Text('Photos, Lab PDFs, code archives, plain text documents supported', style: TextStyle(fontSize: 12, color: Colors.grey)),
                          ],
                        ),
                      ),
                    ),

                    if (_selectedFiles.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text('Selected Files Queue:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      ),
                      const SizedBox(height: 8),
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _selectedFiles.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, idx) {
                          final f = _selectedFiles[idx];
                          return ListTile(
                            dense: true,
                            leading: const Icon(Icons.insert_drive_file, color: AppColors.primary),
                            title: Text(f.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text(FormatUtils.formatBytes(f.size)),
                            trailing: IconButton(
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () => setState(() => _selectedFiles.removeAt(idx)),
                            ),
                          );
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Step 2: Choose Recipient(s)
            const Text(
              '2. SELECT RECIPIENT DEVICE(S)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 12),

            if (engine.pairedDevices.isEmpty)
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(color: Colors.grey.withValues(alpha: 0.15)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: AppColors.warning),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text('No trusted devices paired yet. Pair with a device using QR code or 6-digit code first.'),
                      ),
                      ElevatedButton(
                        onPressed: () => Navigator.pushNamed(context, '/pairing'),
                        child: const Text('Pair Device'),
                      ),
                    ],
                  ),
                ),
              )
            else
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.15)),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: engine.pairedDevices.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final dev = engine.pairedDevices[index];
                    final isChecked = _selectedDeviceIds.contains(dev.id);

                    return CheckboxListTile(
                      value: isChecked,
                      onChanged: (val) {
                        setState(() {
                          if (val == true) {
                            _selectedDeviceIds.add(dev.id);
                          } else {
                            _selectedDeviceIds.remove(dev.id);
                          }
                        });
                      },
                      secondary: CircleAvatar(
                        backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                        child: Icon(
                          dev.deviceType == DeviceType.mobile ? Icons.phone_android : Icons.computer,
                          color: AppColors.primary,
                        ),
                      ),
                      title: Text(dev.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('${dev.ip}:${dev.port} • Trusted'),
                    );
                  },
                ),
              ),

            const SizedBox(height: 24),

            // Send Action
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.send_rounded),
                label: Text(
                  _selectedDeviceIds.length > 1
                      ? 'Send to ${_selectedDeviceIds.length} Recipients'
                      : 'Send File to Recipient',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                onPressed: (_selectedFiles.isNotEmpty && _selectedDeviceIds.isNotEmpty && !_isSending)
                    ? _startTransfer
                    : null,
              ),
            ),

            const SizedBox(height: 32),

            // Active Transfers Progress Section
            if (engine.activeTransfers.isNotEmpty) ...[
              const Text(
                'ACTIVE TRANSFERS & INTERRUPTION RECOVERY',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: engine.activeTransfers.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, idx) {
                  final t = engine.activeTransfers[idx];
                  return Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(color: Colors.grey.withValues(alpha: 0.15)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(t.fileName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: t.status == TransferStatus.completed
                                      ? AppColors.success.withValues(alpha: 0.15)
                                      : t.status == TransferStatus.transferring
                                          ? AppColors.primary.withValues(alpha: 0.15)
                                          : AppColors.warning.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  t.status.name.toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: t.status == TransferStatus.completed
                                        ? AppColors.success
                                        : t.status == TransferStatus.transferring
                                            ? AppColors.primary
                                            : AppColors.warning,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Recipient: ${t.peerDeviceName} • ${FormatUtils.formatBytes(t.fileSizeBytes)} • SHA: ${t.sha256.substring(0, 8)}',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                          ),
                          const SizedBox(height: 10),
                          LinearProgressIndicator(
                            value: t.progress,
                            backgroundColor: Colors.grey.withValues(alpha: 0.15),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              t.status == TransferStatus.completed ? AppColors.success : AppColors.primary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '${(t.progress * 100).toStringAsFixed(1)}% (${t.transferredChunks}/${t.totalChunks} chunks) • ${FormatUtils.formatSpeed(t.speedBytesPerSec)}',
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                              ),
                              Row(
                                children: [
                                  if (t.status == TransferStatus.transferring)
                                    IconButton(
                                      icon: const Icon(Icons.pause, size: 18),
                                      tooltip: 'Pause Transfer',
                                      onPressed: () => engine.pauseTransfer(t.transferId),
                                    )
                                  else if (t.status == TransferStatus.paused)
                                    IconButton(
                                      icon: const Icon(Icons.play_arrow, size: 18),
                                      tooltip: 'Resume Transfer',
                                      onPressed: () => engine.resumeTransfer(t.transferId),
                                    ),
                                  if (t.status != TransferStatus.completed)
                                    IconButton(
                                      icon: const Icon(Icons.cancel_outlined, size: 18, color: Colors.red),
                                      tooltip: 'Cancel Transfer',
                                      onPressed: () => engine.cancelTransfer(t.transferId),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}
