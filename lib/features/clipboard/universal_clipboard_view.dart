import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../data/services/transfer_engine.dart';
import '../../core/constants.dart';

class UniversalClipboardView extends StatefulWidget {
  const UniversalClipboardView({super.key});

  @override
  State<UniversalClipboardView> createState() => _UniversalClipboardViewState();
}

class _UniversalClipboardViewState extends State<UniversalClipboardView> {
  String _clipboardText = '';
  String? _selectedDeviceId;
  bool _isReading = false;

  Future<void> _readClipboard() async {
    setState(() => _isReading = true);
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      setState(() {
        _clipboardText = data?.text ?? '';
        _isReading = false;
      });
      if (_clipboardText.isEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Clipboard is currently empty.')),
        );
      }
    } catch (e) {
      setState(() => _isReading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error accessing clipboard: $e')),
        );
      }
    }
  }

  void _sendClipboardContent() {
    final engine = context.read<TransferEngine>();
    if (_clipboardText.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please paste or enter text before sending.')),
      );
      return;
    }
    if (_selectedDeviceId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a recipient device.')),
      );
      return;
    }

    final dev = engine.pairedDevices.firstWhere((d) => d.id == _selectedDeviceId);
    final bytes = Uint8List.fromList(_clipboardText.codeUnits);

    engine.sendFileToDevice(
      fileName: 'Clipboard_Message_${DateTime.now().millisecondsSinceEpoch}.txt',
      bytes: bytes,
      recipient: dev,
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Clipboard text sent to ${dev.name}.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<TransferEngine>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Universal Smart Clipboard', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Security Notice
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.security, color: AppColors.primary, size: 24),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Clipboard Sharing requires your explicit approval for every transmission. Background surveillance of sensitive data or passwords is strictly disabled.',
                      style: TextStyle(fontSize: 12, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Actions: Paste from Desktop / Mobile Clipboard
            Row(
              children: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
                  icon: _isReading
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.paste, size: 18),
                  label: const Text('Paste from System Clipboard'),
                  onPressed: _isReading ? null : _readClipboard,
                ),
                const SizedBox(width: 12),
                if (_clipboardText.isNotEmpty)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.clear, size: 18),
                    label: const Text('Clear Preview'),
                    onPressed: () => setState(() => _clipboardText = ''),
                  ),
              ],
            ),
            const SizedBox(height: 20),

            // Text Preview / Edit Box
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.15)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Content Preview:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: TextEditingController(text: _clipboardText),
                      maxLines: 8,
                      decoration: const InputDecoration(
                        hintText: 'Clipboard contents (code snippets, terminal text, links, notes) will appear here...',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (val) => _clipboardText = val,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Recipient Device
            const Text('SEND TO PAIRED DEVICE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey)),
            const SizedBox(height: 8),

            if (engine.pairedDevices.isEmpty)
              const Text('No paired devices. Please pair a device first.')
            else
              DropdownButtonFormField<String>(
                initialValue: _selectedDeviceId,
                hint: const Text('Select Paired Device'),
                decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                items: engine.pairedDevices
                    .map((d) => DropdownMenuItem(value: d.id, child: Text('${d.name} (${d.ip})')))
                    .toList(),
                onChanged: (val) => setState(() => _selectedDeviceId = val),
              ),
            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.secondary, foregroundColor: Colors.white),
                icon: const Icon(Icons.send),
                label: const Text('Send Clipboard to Selected Device', style: TextStyle(fontWeight: FontWeight.bold)),
                onPressed: (_clipboardText.isNotEmpty && _selectedDeviceId != null) ? _sendClipboardContent : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
