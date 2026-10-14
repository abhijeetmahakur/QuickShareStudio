import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/widgets/demo_mode_notice.dart';
import 'package:provider/provider.dart';
import '../../data/models/device_model.dart';
import '../../data/services/transfer_engine.dart';
import '../../core/constants.dart';
import '../../core/widgets/hover_card.dart';
import '../../core/services/platform_clipboard_service.dart';
import '../../core/services/clipboard_image_service.dart';
import '../../data/models/screenshot_item.dart';

// ---------------------------------------------------------------------------
// Data models
// ---------------------------------------------------------------------------

class _HistoryEntry {
  final DateTime timestamp;
  final String label;
  final ClipboardContentType type;
  final String? text;
  final Uint8List? imageBytes;
  final String? imageMime;
  final List<String>? filePaths;

  _HistoryEntry({
    required this.timestamp,
    required this.label,
    required this.type,
    this.text,
    this.imageBytes,
    this.imageMime,
    this.filePaths,
  });
}

// ---------------------------------------------------------------------------
// Main widget
// ---------------------------------------------------------------------------

class UniversalClipboardView extends StatefulWidget {
  const UniversalClipboardView({super.key});

  @override
  State<UniversalClipboardView> createState() => _UniversalClipboardViewState();
}

class _UniversalClipboardViewState extends State<UniversalClipboardView>
    with SingleTickerProviderStateMixin {
  late final TextEditingController _textController;
  late final TabController _tabController;
  final Set<String> _selectedDeviceIds = {};

  // States
  bool _isReading = false;
  bool _isSending = false;
  bool _isReadingImage = false;
  bool _isCopyingToClipboard = false;
  final Map<String, String> _deliveryStatuses = {};

  // Image clipboard state
  ScreenshotItem? _pastedImage;
  String? _imageStatusMessage;
  bool _imageOpSuccess = false;

  // File clipboard state
  List<String> _clipboardFiles = [];
  String? _fileStatusMessage;

  // History
  final List<_HistoryEntry> _history = [];
  static const int _maxHistory = 20;
  bool _historyEnabled = true;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _textController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Text clipboard operations
  // ---------------------------------------------------------------------------

  Future<void> _readClipboard() async {
    setState(() => _isReading = true);
    try {
      final result = await PlatformClipboardService.instance.read();
      if (result.type == ClipboardContentType.text && result.text != null) {
        setState(() {
          _textController.text = result.text!;
          _isReading = false;
        });
        if (_historyEnabled) _addHistory(result);
      } else if (result.type == ClipboardContentType.image) {
        setState(() => _isReading = false);
        _showSnackBar('Image detected — switch to the Image tab to paste it.', isInfo: true);
      } else if (result.type == ClipboardContentType.files) {
        setState(() => _isReading = false);
        _showSnackBar('Files detected — switch to the Files tab to see them.', isInfo: true);
      } else {
        setState(() {
          _textController.text = '';
          _isReading = false;
        });
        if (result.errorMessage != null) {
          _showSnackBar(result.errorMessage!, isError: true);
        } else {
          _showSnackBar('Clipboard is currently empty.', isInfo: true);
        }
      }
    } catch (e) {
      setState(() => _isReading = false);
      _showSnackBar('Error accessing clipboard: $e', isError: true);
    }
  }

  Future<void> _copyTextToClipboard() async {
    final text = _textController.text;
    if (text.trim().isEmpty) {
      _showSnackBar('Nothing to copy.', isInfo: true);
      return;
    }
    setState(() => _isCopyingToClipboard = true);
    try {
      final result = await PlatformClipboardService.instance.writeText(text);
      if (result.success) {
        _showSnackBar('Text copied to system clipboard ✓');
        if (_historyEnabled) {
          _addHistory(ClipboardReadResult(type: ClipboardContentType.text, text: text));
        }
      } else {
        _showSnackBar(result.errorMessage ?? 'Copy failed.', isError: true);
      }
    } finally {
      setState(() => _isCopyingToClipboard = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Image clipboard operations
  // ---------------------------------------------------------------------------

  Future<void> _pasteImageFromClipboard() async {
    setState(() {
      _isReadingImage = true;
      _imageStatusMessage = null;
      _pastedImage = null;
    });
    try {
      final img = await ClipboardImageService.readPastedImage();
      if (img != null) {
        setState(() {
          _pastedImage = img;
          _isReadingImage = false;
          _imageOpSuccess = true;
          _imageStatusMessage = 'Image pasted: ${img.name}';
        });
        if (_historyEnabled) {
          _history.insert(0, _HistoryEntry(
            timestamp: DateTime.now(),
            label: img.name,
            type: ClipboardContentType.image,
            imageBytes: img.bytes,
          ));
          if (_history.length > _maxHistory) _history.removeLast();
        }
      } else {
        setState(() {
          _isReadingImage = false;
          _imageOpSuccess = false;
          _imageStatusMessage = _getNoImageMessage();
        });
      }
    } catch (e) {
      setState(() {
        _isReadingImage = false;
        _imageOpSuccess = false;
        _imageStatusMessage = 'Error reading clipboard image: $e';
      });
    }
  }

  String _getNoImageMessage() {
    if (kIsWeb) return 'No image found in clipboard. Try Ctrl+V with an image source focused.';
    if (!kIsWeb && Platform.isLinux) {
      final env = PlatformClipboardService.instance.linuxEnvironment;
      if (env?.isWayland == true) {
        return 'No image in clipboard. On Wayland, copy an image from an app first. '
            'Note: if the source app is closed, Wayland may clear the clipboard.';
      }
      return 'No image in clipboard. Copy an image (e.g. in a browser or image viewer) then try again.';
    }
    return 'No image found in clipboard. Copy an image first.';
  }

  Future<void> _copyImageToClipboard() async {
    if (_pastedImage == null) return;
    setState(() => _isCopyingToClipboard = true);
    try {
      final ok = await ClipboardImageService.writeImageToClipboard(
        _pastedImage!.bytes,
        mime: 'image/png',
      );
      if (ok) {
        _showSnackBar('Image copied to system clipboard as PNG ✓');
      } else {
        _showSnackBar(
          'Image clipboard not supported on this platform. '
          'Use "Send to Device" to transfer the image instead.',
          isError: true,
        );
      }
    } finally {
      setState(() => _isCopyingToClipboard = false);
    }
  }

  Future<void> _sendImageToDevices() async {
    if (_pastedImage == null) {
      _showSnackBar('Paste an image first.', isInfo: true);
      return;
    }
    if (_selectedDeviceIds.isEmpty) {
      _showSnackBar('Select at least one device.', isInfo: true);
      return;
    }
    final engine = context.read<TransferEngine>();
    setState(() {
      _isSending = true;
      _deliveryStatuses.clear();
    });
    final img = _pastedImage!;
    for (final devId in _selectedDeviceIds) {
      final dev = engine.pairedDevices.where((d) => d.id == devId).firstOrNull;
      if (dev == null) { _deliveryStatuses[devId] = 'Failed: Disconnected'; continue; }
      try {
        _deliveryStatuses[devId] = 'Sending...';
        setState(() {});
        final transfer = await engine.sendFileToDevice(
          fileName: img.name,
          bytes: img.bytes,
          recipient: dev,
        );
        if (!await engine.waitForTransfer(transfer.transferId)) {
          throw 'Transfer failed';
        }
        _deliveryStatuses[devId] = 'Sent ✓';
      } catch (e) {
        _deliveryStatuses[devId] = 'Failed: $e';
      }
    }
    if (mounted) setState(() => _isSending = false);
    _showSnackBar('Image sent to ${_selectedDeviceIds.length} device(s).');
  }

  // ---------------------------------------------------------------------------
  // File clipboard operations
  // ---------------------------------------------------------------------------

  Future<void> _readFilesFromClipboard() async {
    setState(() => _fileStatusMessage = null);
    try {
      final result = await PlatformClipboardService.instance.read();
      if (result.type == ClipboardContentType.files && result.filePaths != null) {
        setState(() {
          _clipboardFiles = result.filePaths!;
          _fileStatusMessage = '${result.filePaths!.length} file(s) from clipboard';
        });
      } else {
        setState(() {
          _clipboardFiles = [];
          _fileStatusMessage = _getNoFilesMessage();
        });
      }
    } catch (e) {
      setState(() {
        _clipboardFiles = [];
        _fileStatusMessage = 'Error reading clipboard files: $e';
      });
    }
  }

  String _getNoFilesMessage() {
    if (!kIsWeb && Platform.isLinux) {
      return 'No files in clipboard. Copy files in a file manager (Nautilus/Dolphin) then try again.';
    }
    return 'No files in clipboard. Copy files from a file manager first.';
  }

  Future<void> _copyFilesToClipboard(List<String> paths) async {
    if (paths.isEmpty) return;
    final result = await PlatformClipboardService.instance.writeFilePaths(paths);
    if (result.success) {
      _showSnackBar('${paths.length} file(s) copied to clipboard ✓');
    } else {
      _showSnackBar(result.errorMessage ?? 'File clipboard write failed.', isError: true);
    }
  }

  Future<void> _sendFilesToDevices(List<String> paths) async {
    if (paths.isEmpty || _selectedDeviceIds.isEmpty) return;
    final engine = context.read<TransferEngine>();
    setState(() {
      _isSending = true;
      _deliveryStatuses.clear();
    });
    for (final devId in _selectedDeviceIds) {
      final dev = engine.pairedDevices.where((d) => d.id == devId).firstOrNull;
      if (dev == null) { _deliveryStatuses[devId] = 'Failed: Disconnected'; continue; }
      for (final path in paths) {
        try {
          final file = File(path);
          final bytes = await file.readAsBytes();
          final name = path.split(Platform.pathSeparator).last;
          _deliveryStatuses[devId] = 'Sending $name...';
          setState(() {});
          final transfer = await engine.sendFileToDevice(
            fileName: name,
            bytes: bytes,
            recipient: dev,
          );
          await engine.waitForTransfer(transfer.transferId);
          _deliveryStatuses[devId] = 'Sent ✓';
        } catch (e) {
          _deliveryStatuses[devId] = 'Failed: $e';
        }
      }
    }
    if (mounted) setState(() => _isSending = false);
    _showSnackBar('Files sent to ${_selectedDeviceIds.length} device(s).');
  }

  // ---------------------------------------------------------------------------
  // Cross-device text send
  // ---------------------------------------------------------------------------

  Future<void> _sendClipboardContent() async {
    final engine = context.read<TransferEngine>();
    final content = _textController.text;
    if (content.trim().isEmpty) {
      _showSnackBar('Paste or enter text before sending.', isInfo: true);
      return;
    }
    if (_selectedDeviceIds.isEmpty) {
      _showSnackBar('Select at least one recipient device.', isInfo: true);
      return;
    }

    setState(() {
      _isSending = true;
      _deliveryStatuses.clear();
    });

    final bytes = Uint8List.fromList(utf8.encode(content));
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final List<String> succeededNames = [];
    final List<String> failedNames = [];

    for (final devId in _selectedDeviceIds) {
      final dev = engine.pairedDevices.where((d) => d.id == devId).firstOrNull;
      if (dev == null) {
        failedNames.add('Unknown');
        _deliveryStatuses[devId] = 'Failed: Disconnected';
        continue;
      }

      try {
        _deliveryStatuses[devId] = 'Sending...';
        setState(() {});

        final transfer = await engine.sendFileToDevice(
          fileName: 'Clipboard_Snippet_$timestamp.txt',
          bytes: bytes,
          recipient: dev,
        );
        if (!await engine.waitForTransfer(transfer.transferId)) {
          final failed = engine.activeTransfers.where((t) => t.transferId == transfer.transferId);
          throw failed.isNotEmpty && failed.first.errorMessage != null
              ? failed.first.errorMessage!
              : 'Transfer failed';
        }

        succeededNames.add(dev.name);
        _deliveryStatuses[devId] = 'Sent ✓';
      } catch (e) {
        failedNames.add(dev.name);
        _deliveryStatuses[devId] = 'Failed: $e';
      }
    }

    if (mounted) {
      setState(() => _isSending = false);
      if (succeededNames.isNotEmpty && failedNames.isEmpty) {
        _showSnackBar('Clipboard text sent to ${succeededNames.join(", ")}.');
      } else if (succeededNames.isNotEmpty) {
        _showSnackBar(
          'Sent to ${succeededNames.join(", ")}, failed: ${failedNames.join(", ")}',
          isError: true,
        );
      } else {
        _showSnackBar('Failed: ${failedNames.join(", ")}', isError: true);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // History helpers
  // ---------------------------------------------------------------------------

  void _addHistory(ClipboardReadResult result) {
    String label;
    if (result.type == ClipboardContentType.text) {
      final t = result.text ?? '';
      label = t.length > 40 ? '${t.substring(0, 40)}…' : t;
    } else if (result.type == ClipboardContentType.image) {
      label = 'Image (${result.imageMime ?? "unknown"})';
    } else if (result.type == ClipboardContentType.files) {
      label = '${result.filePaths?.length ?? 0} file(s)';
    } else {
      label = 'Unknown content';
    }
    _history.insert(0, _HistoryEntry(
      timestamp: DateTime.now(),
      label: label,
      type: result.type,
      text: result.text,
      imageBytes: result.imageBytes,
      imageMime: result.imageMime,
      filePaths: result.filePaths,
    ));
    if (_history.length > _maxHistory) _history.removeLast();
    setState(() {});
  }

  void _restoreHistory(_HistoryEntry entry) {
    if (entry.type == ClipboardContentType.text && entry.text != null) {
      _textController.text = entry.text!;
      _tabController.animateTo(0);
      setState(() {});
    } else if (entry.type == ClipboardContentType.image && entry.imageBytes != null) {
      // Restore to image tab
      _tabController.animateTo(1);
      setState(() {
        _pastedImage = ScreenshotItem(
          name: entry.label,
          bytes: entry.imageBytes!,
          sha256: '',
          width: 0,
          height: 0,
          aspectRatio: 1,
        );
      });
    } else if (entry.type == ClipboardContentType.files && entry.filePaths != null) {
      // Restore to files tab
      _tabController.animateTo(2);
      setState(() {
        _clipboardFiles = List<String>.from(entry.filePaths!);
      });
    }
  }

  // ---------------------------------------------------------------------------
  // UI helpers
  // ---------------------------------------------------------------------------

  void _showSnackBar(String message, {bool isError = false, bool isInfo = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: isError
            ? AppColors.error.withValues(alpha: 0.12)
            : isInfo
                ? AppColors.cardBg
                : AppColors.charcoalSurface,
        content: Row(
          children: [
            Icon(
              isError
                  ? Icons.error_outline_rounded
                  : isInfo
                      ? Icons.info_outline_rounded
                      : Icons.check_circle_rounded,
              color: isError
                  ? AppColors.error
                  : isInfo
                      ? AppColors.secondaryText
                      : AppColors.primaryAccent,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12.5,
                  color: AppColors.primaryText,
                ),
              ),
            ),
          ],
        ),
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<TransferEngine>();

    if (_selectedDeviceIds.isEmpty && engine.pairedDevices.isNotEmpty) {
      _selectedDeviceIds.add(engine.pairedDevices.first.id);
    }

    return Scaffold(
      backgroundColor: AppColors.dashboardBg,
      appBar: AppBar(
        backgroundColor: AppColors.dashboardBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Universal Smart Clipboard',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w700,
            color: AppColors.primaryText,
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          labelStyle: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 12.5),
          unselectedLabelStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 12),
          labelColor: AppColors.primaryAccent,
          unselectedLabelColor: AppColors.secondaryText,
          indicatorColor: AppColors.primaryAccent,
          indicatorSize: TabBarIndicatorSize.label,
          tabs: const [
            Tab(icon: Icon(Icons.text_fields_rounded, size: 18), text: 'Text'),
            Tab(icon: Icon(Icons.image_rounded, size: 18), text: 'Image'),
            Tab(icon: Icon(Icons.folder_open_rounded, size: 18), text: 'Files'),
            Tab(icon: Icon(Icons.history_rounded, size: 18), text: 'History'),
          ],
        ),
      ),
      body: Column(
        children: [
          // Linux clipboard environment notice
          if (!kIsWeb && Platform.isLinux) _buildLinuxEnvBanner(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildTextTab(engine),
                _buildImageTab(engine),
                _buildFilesTab(engine),
                _buildHistoryTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Linux environment banner
  // ---------------------------------------------------------------------------

  Widget _buildLinuxEnvBanner() {
    final env = PlatformClipboardService.instance.linuxEnvironment;
    if (env == null) return const SizedBox.shrink();
    final hasNative = env.hasNativeClipboard;
    return Container(
      color: hasNative
          ? AppColors.primaryAccent.withValues(alpha: 0.06)
          : AppColors.warning.withValues(alpha: 0.08),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: [
          Icon(
            hasNative ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
            color: hasNative ? AppColors.primaryAccent : AppColors.warning,
            size: 16,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              hasNative
                  ? 'Linux ${env.description}: Image & file clipboard ready'
                  : 'Linux ${env.description}: Native clipboard unavailable — text only. '
                    'Ensure GTK3 is installed and the app has clipboard access.',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 11.5,
                color: hasNative ? AppColors.primaryAccent : AppColors.warning,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Text Tab
  // ---------------------------------------------------------------------------

  Widget _buildTextTab(TransferEngine engine) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const DemoModeNotice(),
          _buildSecurityBanner(),
          const SizedBox(height: 20),

          // Action buttons
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryAccent,
                  foregroundColor: AppColors.nearBlack,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: _isReading
                    ? const SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.nearBlack))
                    : const Icon(Icons.paste_rounded, size: 18),
                label: const Text('Paste from System Clipboard',
                    style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 13)),
                onPressed: _isReading ? null : _readClipboard,
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  foregroundColor: AppColors.primaryText,
                  side: BorderSide(color: AppColors.subtleBorderLight),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: Icon(Icons.copy_rounded, size: 18, color: AppColors.secondaryText),
                label: const Text('Copy to Clipboard',
                    style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w500, fontSize: 13)),
                onPressed: _isCopyingToClipboard ? null : _copyTextToClipboard,
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  foregroundColor: AppColors.primaryText,
                  side: BorderSide(color: AppColors.subtleBorderLight),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: Icon(Icons.clear_rounded, size: 18, color: AppColors.secondaryText),
                label: const Text('Clear Preview',
                    style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w500, fontSize: 13)),
                onPressed: () => setState(() {
                  _textController.clear();
                  _deliveryStatuses.clear();
                }),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // Text editor
          HoverCard(
            borderRadius: BorderRadius.circular(14),
            padding: const EdgeInsets.all(16),
            color: AppColors.cardBg,
            borderColor: AppColors.subtleBorder,
            hoverBorderColor: AppColors.primaryAccent,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        'Content Preview (Text & Code Formatting Preserved):',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w600,
                          fontSize: 12.5,
                          color: AppColors.primaryText,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${_textController.text.length} chars · ${_textController.text.split("\n").length} lines',
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 11.5, color: AppColors.secondaryText),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _textController,
                  maxLines: 10,
                  cursorColor: AppColors.primaryAccent,
                  style: TextStyle(fontFamily: 'monospace', fontSize: 13, height: 1.5, color: AppColors.primaryText),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: AppColors.dashboardBg,
                    hintText: 'Enter or paste code, terminal logs, links, notes, or snippets here...',
                    hintStyle: TextStyle(fontFamily: 'Poppins', fontSize: 12.5, color: AppColors.mutedText),
                    contentPadding: const EdgeInsets.all(14),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: AppColors.subtleBorderLight)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: AppColors.primaryAccent, width: 1.5)),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          _buildDeviceSelector(engine),
          const SizedBox(height: 20),

          // Send button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryAccent,
                foregroundColor: AppColors.nearBlack,
                disabledBackgroundColor: AppColors.surfaceElevated,
                disabledForegroundColor: AppColors.mutedText,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: _isSending
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.nearBlack))
                  : const Icon(Icons.send_rounded, size: 20),
              label: Text(
                _selectedDeviceIds.length <= 1
                    ? 'Send Clipboard to Selected Device'
                    : 'Send Clipboard to ${_selectedDeviceIds.length} Devices',
                style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 14),
              ),
              onPressed: (_textController.text.trim().isNotEmpty &&
                      _selectedDeviceIds.isNotEmpty &&
                      !_isSending)
                  ? _sendClipboardContent
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Image Tab
  // ---------------------------------------------------------------------------

  Widget _buildImageTab(TransferEngine engine) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Capability info
          _buildCapabilityBanner(
            icon: Icons.image_rounded,
            text: PlatformClipboardService.instance.supportsImageClipboard
                ? 'Native image clipboard ready — supports PNG, JPEG, GIF, WebP, BMP, TIFF'
                : 'Native image clipboard unavailable on this platform. Use the web build for image paste.',
            isAvailable: PlatformClipboardService.instance.supportsImageClipboard || kIsWeb,
          ),
          const SizedBox(height: 20),

          // Action buttons
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryAccent,
                  foregroundColor: AppColors.nearBlack,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: _isReadingImage
                    ? const SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.nearBlack))
                    : const Icon(Icons.paste_rounded, size: 18),
                label: const Text('Paste Image from Clipboard',
                    style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 13)),
                onPressed: _isReadingImage ? null : _pasteImageFromClipboard,
              ),
              if (_pastedImage != null) ...[
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    foregroundColor: AppColors.primaryText,
                    side: BorderSide(color: AppColors.subtleBorderLight),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: Icon(Icons.copy_rounded, size: 18, color: AppColors.secondaryText),
                  label: const Text('Copy Image to Clipboard',
                      style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w500, fontSize: 13)),
                  onPressed: _isCopyingToClipboard ? null : _copyImageToClipboard,
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),

          // Status message
          if (_imageStatusMessage != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _imageOpSuccess
                    ? AppColors.primaryAccent.withValues(alpha: 0.08)
                    : AppColors.cardBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _imageOpSuccess ? AppColors.primaryAccent.withValues(alpha: 0.3) : AppColors.subtleBorder,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _imageOpSuccess ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                    color: _imageOpSuccess ? AppColors.primaryAccent : AppColors.secondaryText,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _imageStatusMessage!,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12.5,
                        color: _imageOpSuccess ? AppColors.primaryAccent : AppColors.secondaryText,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 16),

          // Image preview
          if (_pastedImage != null) ...[
            HoverCard(
              borderRadius: BorderRadius.circular(14),
              padding: const EdgeInsets.all(12),
              color: AppColors.cardBg,
              borderColor: AppColors.primaryAccent.withValues(alpha: 0.3),
              hoverBorderColor: AppColors.primaryAccent,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.image_rounded, color: AppColors.primaryAccent, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _pastedImage!.name,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: AppColors.primaryText,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '${(_pastedImage!.bytes.length / 1024).toStringAsFixed(1)} KB',
                        style: TextStyle(fontFamily: 'Poppins', fontSize: 11.5, color: AppColors.secondaryText),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(
                      _pastedImage!.bytes,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) => Container(
                        height: 120,
                        alignment: Alignment.center,
                        color: AppColors.surfaceElevated,
                        child: Text('Preview unavailable',
                            style: TextStyle(color: AppColors.mutedText, fontFamily: 'Poppins')),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _buildDeviceSelector(engine),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryAccent,
                  foregroundColor: AppColors.nearBlack,
                  disabledBackgroundColor: AppColors.surfaceElevated,
                  disabledForegroundColor: AppColors.mutedText,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: _isSending
                    ? const SizedBox(width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.nearBlack))
                    : const Icon(Icons.send_rounded, size: 20),
                label: const Text('Send Image to Device',
                    style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 14)),
                onPressed: (_pastedImage != null && _selectedDeviceIds.isNotEmpty && !_isSending)
                    ? _sendImageToDevices
                    : null,
              ),
            ),
          ] else
            _buildEmptyImageState(),
        ],
      ),
    );
  }

  Widget _buildEmptyImageState() {
    return Container(
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.subtleBorder),
      ),
      child: Column(
        children: [
          Icon(Icons.image_search_rounded, color: AppColors.mutedText, size: 48),
          const SizedBox(height: 16),
          Text(
            'No image in clipboard',
            style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600,
                fontSize: 16, color: AppColors.secondaryText),
          ),
          const SizedBox(height: 8),
          Text(
            'Copy a screenshot, photo, or any image, then tap "Paste Image from Clipboard".',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 12.5, color: AppColors.mutedText, height: 1.5),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Files Tab
  // ---------------------------------------------------------------------------

  Widget _buildFilesTab(TransferEngine engine) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCapabilityBanner(
            icon: Icons.folder_open_rounded,
            text: PlatformClipboardService.instance.supportsFileClipboard
                ? 'File clipboard ready — copy files from your file manager and paste here'
                : 'Native file clipboard not available. Use the Transfer tab to send files directly.',
            isAvailable: PlatformClipboardService.instance.supportsFileClipboard,
          ),
          const SizedBox(height: 20),

          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryAccent,
                  foregroundColor: AppColors.nearBlack,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.paste_rounded, size: 18),
                label: const Text('Paste Files from Clipboard',
                    style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 13)),
                onPressed: _readFilesFromClipboard,
              ),
            ],
          ),
          const SizedBox(height: 16),

          if (_fileStatusMessage != null)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: AppColors.cardBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.subtleBorder),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, color: AppColors.secondaryText, size: 18),
                  const SizedBox(width: 10),
                  Expanded(child: Text(_fileStatusMessage!,
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 12.5, color: AppColors.secondaryText))),
                ],
              ),
            ),

          if (_clipboardFiles.isEmpty)
            Container(
              padding: const EdgeInsets.all(40),
              decoration: BoxDecoration(
                color: AppColors.cardBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.subtleBorder),
              ),
              child: Column(
                children: [
                  Icon(Icons.folder_copy_rounded, color: AppColors.mutedText, size: 48),
                  const SizedBox(height: 16),
                  Text('No files in clipboard', style: TextStyle(fontFamily: 'Poppins',
                      fontWeight: FontWeight.w600, fontSize: 16, color: AppColors.secondaryText)),
                  const SizedBox(height: 8),
                  Text(
                    'Copy files in your file manager (Nautilus, Dolphin, Explorer) then tap "Paste Files from Clipboard".',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 12.5, color: AppColors.mutedText, height: 1.5),
                    textAlign: TextAlign.center,
                  ),
                  if (!kIsWeb && Platform.isLinux) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Linux: Copy files with Ctrl+C in Nautilus or Dolphin.\n'
                      'Wayland note: clipboard may clear when the source app is closed.',
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 11.5, color: AppColors.mutedText, height: 1.5),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            )
          else ...[
            Column(
              children: _clipboardFiles.map((path) {
                final name = path.split(Platform.pathSeparator).last;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: HoverCard(
                    borderRadius: BorderRadius.circular(12),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    color: AppColors.cardBg,
                    borderColor: AppColors.subtleBorder,
                    hoverBorderColor: AppColors.primaryAccent,
                    child: Row(
                      children: [
                        Icon(Icons.insert_drive_file_rounded, color: AppColors.primaryAccent, size: 22),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name, style: TextStyle(fontFamily: 'Poppins',
                                  fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.primaryText)),
                              Text(path, style: TextStyle(fontFamily: 'Poppins',
                                  fontSize: 11, color: AppColors.mutedText),
                                overflow: TextOverflow.ellipsis),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.copy_rounded, size: 18, color: AppColors.secondaryText),
                          tooltip: 'Copy path',
                          onPressed: () => Clipboard.setData(ClipboardData(text: path)),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            _buildDeviceSelector(engine),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primaryAccent,
                        side: BorderSide(color: AppColors.primaryAccent),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      label: const Text(
                        'Copy to Clipboard',
                        style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                      onPressed: _clipboardFiles.isNotEmpty
                          ? () => _copyFilesToClipboard(_clipboardFiles)
                          : null,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryAccent,
                        foregroundColor: AppColors.nearBlack,
                        disabledBackgroundColor: AppColors.surfaceElevated,
                        disabledForegroundColor: AppColors.mutedText,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: _isSending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.nearBlack),
                            )
                          : const Icon(Icons.send_rounded, size: 18),
                      label: Text(
                        'Send ${_clipboardFiles.length} File(s)',
                        style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                      onPressed: (_clipboardFiles.isNotEmpty && _selectedDeviceIds.isNotEmpty && !_isSending)
                          ? () => _sendFilesToDevices(_clipboardFiles)
                          : null,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // History Tab
  // ---------------------------------------------------------------------------

  Widget _buildHistoryTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('CLIPBOARD HISTORY',
                  style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                      fontSize: 12, color: AppColors.secondaryText, letterSpacing: 1.0)),
              Row(
                children: [
                  Switch(
                    value: _historyEnabled,
                    activeThumbColor: AppColors.primaryAccent,
                    activeTrackColor: AppColors.primaryAccent.withValues(alpha: 0.5),
                    onChanged: (v) => setState(() => _historyEnabled = v),
                  ),
                  const SizedBox(width: 4),
                  Text(_historyEnabled ? 'Enabled' : 'Disabled',
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: AppColors.secondaryText)),
                  if (_history.isNotEmpty) ...[
                    const SizedBox(width: 12),
                    TextButton.icon(
                      style: TextButton.styleFrom(foregroundColor: AppColors.error,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
                      icon: Icon(Icons.delete_sweep_rounded, size: 16, color: AppColors.error),
                      label: Text('Clear', style: TextStyle(fontFamily: 'Poppins',
                          fontSize: 12, color: AppColors.error)),
                      onPressed: () => setState(() => _history.clear()),
                    ),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'History is stored locally in memory only and cleared when the app closes. '
            'Enable history to track recently read clipboard items.',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 11.5, color: AppColors.mutedText, height: 1.45),
          ),
          const SizedBox(height: 16),

          if (_history.isEmpty)
            Container(
              padding: const EdgeInsets.all(40),
              decoration: BoxDecoration(
                color: AppColors.cardBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.subtleBorder),
              ),
              child: Column(
                children: [
                  Icon(Icons.history_rounded, color: AppColors.mutedText, size: 48),
                  const SizedBox(height: 16),
                  Text('No history yet', style: TextStyle(fontFamily: 'Poppins',
                      fontWeight: FontWeight.w600, fontSize: 16, color: AppColors.secondaryText)),
                  const SizedBox(height: 8),
                  Text('Paste text or images to build clipboard history.',
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 12.5, color: AppColors.mutedText)),
                ],
              ),
            )
          else
            Column(
              children: _history.asMap().entries.map((entry) {
                final e = entry.value;
                final icon = e.type == ClipboardContentType.image
                    ? Icons.image_rounded
                    : e.type == ClipboardContentType.files
                        ? Icons.folder_rounded
                        : Icons.text_fields_rounded;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: HoverCard(
                    borderRadius: BorderRadius.circular(12),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    color: AppColors.cardBg,
                    borderColor: AppColors.subtleBorder,
                    hoverBorderColor: AppColors.primaryAccent,
                    onTap: () => _restoreHistory(e),
                    child: Row(
                      children: [
                        Icon(icon, color: AppColors.primaryAccent, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(e.label, style: TextStyle(fontFamily: 'Poppins',
                                  fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.primaryText),
                                overflow: TextOverflow.ellipsis),
                              Text(
                                '${e.type.name} · ${_formatTime(e.timestamp)}',
                                style: TextStyle(fontFamily: 'Poppins', fontSize: 11.5, color: AppColors.mutedText),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.restore_rounded, color: AppColors.secondaryText, size: 18),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  String _formatTime(DateTime t) {
    final now = DateTime.now();
    final diff = now.difference(t);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }

  // ---------------------------------------------------------------------------
  // Shared widgets
  // ---------------------------------------------------------------------------

  Widget _buildSecurityBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.subtleBorder),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primaryAccent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.security_rounded, color: AppColors.primaryAccent, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              'Clipboard Sharing requires your explicit approval for every transmission. '
              'Content is never sent automatically. History is stored in memory only.',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 12, height: 1.45, color: AppColors.secondaryText),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCapabilityBanner({required IconData icon, required String text, required bool isAvailable}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isAvailable
            ? AppColors.primaryAccent.withValues(alpha: 0.06)
            : AppColors.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isAvailable
              ? AppColors.primaryAccent.withValues(alpha: 0.2)
              : AppColors.warning.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: isAvailable ? AppColors.primaryAccent : AppColors.warning, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  color: isAvailable ? AppColors.primaryAccent : AppColors.warning,
                  height: 1.45,
                )),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceSelector(TransferEngine engine) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('SEND TO PAIRED DEVICES',
                style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                    fontSize: 12, color: AppColors.secondaryText, letterSpacing: 1.0)),
            if (engine.pairedDevices.length > 1)
              Row(
                children: [
                  TextButton(
                    style: TextButton.styleFrom(foregroundColor: AppColors.primaryAccent,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
                    onPressed: () => setState(() {
                      _selectedDeviceIds.clear();
                      _selectedDeviceIds.addAll(engine.pairedDevices.map((d) => d.id));
                    }),
                    child: Text('All', style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
                        fontWeight: FontWeight.w600, color: AppColors.primaryAccent)),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(foregroundColor: AppColors.secondaryText,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
                    onPressed: () => setState(() => _selectedDeviceIds.clear()),
                    child: Text('None', style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
                        color: AppColors.secondaryText)),
                  ),
                ],
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (engine.pairedDevices.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.cardBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.subtleBorder),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, color: AppColors.secondaryText, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('No paired devices. Pair a device in the Connect tab first.',
                      style: TextStyle(fontFamily: 'Poppins', color: AppColors.secondaryText, fontSize: 12.5)),
                ),
              ],
            ),
          )
        else
          Column(
            children: engine.pairedDevices.map((d) {
              final isSelected = _selectedDeviceIds.contains(d.id);
              final status = _deliveryStatuses[d.id];
              return Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: HoverCard(
                  borderRadius: BorderRadius.circular(12),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  color: isSelected ? AppColors.primaryAccent.withValues(alpha: 0.08) : AppColors.cardBg,
                  borderColor: isSelected ? AppColors.primaryAccent : AppColors.subtleBorder,
                  hoverBorderColor: AppColors.primaryAccent,
                  onTap: () => setState(() {
                    if (isSelected) {
                      _selectedDeviceIds.remove(d.id);
                    } else {
                      _selectedDeviceIds.add(d.id);
                    }
                  }),
                  child: Row(
                    children: [
                      Checkbox(
                        value: isSelected,
                        activeColor: AppColors.primaryAccent,
                        checkColor: AppColors.nearBlack,
                        side: BorderSide(
                          color: isSelected ? AppColors.primaryAccent : AppColors.mutedText,
                          width: 1.5,
                        ),
                        onChanged: (val) => setState(() {
                          if (val == true) {
                            _selectedDeviceIds.add(d.id);
                          } else {
                            _selectedDeviceIds.remove(d.id);
                          }
                        }),
                      ),
                      Icon(
                        d.deviceType == DeviceType.mobile ? Icons.phone_android_rounded
                            : d.deviceType == DeviceType.tablet ? Icons.tablet_mac_rounded
                            : Icons.laptop_chromebook_rounded,
                        color: isSelected ? AppColors.primaryAccent : AppColors.secondaryText,
                        size: 22,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(d.name, style: TextStyle(fontFamily: 'Poppins',
                                fontWeight: FontWeight.w600, fontSize: 13.5,
                                color: isSelected ? AppColors.primaryAccent : AppColors.primaryText)),
                            Text('IP: ${d.ip} · ${d.isOnline ? "Online" : "Offline"}',
                                style: TextStyle(fontFamily: 'Poppins', fontSize: 11.5, color: AppColors.secondaryText)),
                          ],
                        ),
                      ),
                      if (status != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                          decoration: BoxDecoration(
                            color: status.contains('✓')
                                ? AppColors.primaryAccent.withValues(alpha: 0.15)
                                : status.contains('Failed')
                                    ? AppColors.error.withValues(alpha: 0.15)
                                    : AppColors.softGray.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: status.contains('✓')
                                  ? AppColors.primaryAccent.withValues(alpha: 0.35)
                                  : status.contains('Failed')
                                      ? AppColors.error.withValues(alpha: 0.35)
                                      : AppColors.softGray.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Text(status, style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: status.contains('✓')
                                ? AppColors.primaryAccent
                                : status.contains('Failed')
                                    ? AppColors.error
                                    : AppColors.primaryText,
                          )),
                        ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
      ],
    );
  }
}
