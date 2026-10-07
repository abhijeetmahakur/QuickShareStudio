import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/services/clipboard_image_service.dart';
import '../../core/utils/format_utils.dart';
import '../../core/widgets/demo_mode_notice.dart';
import 'package:provider/provider.dart';
import '../../data/models/device_model.dart';
import '../../data/services/transfer_engine.dart';
import '../../core/constants.dart';
import '../../core/widgets/hover_card.dart';

class UniversalClipboardView extends StatefulWidget {
  const UniversalClipboardView({super.key});

  @override
  State<UniversalClipboardView> createState() => _UniversalClipboardViewState();
}

class _UniversalClipboardViewState extends State<UniversalClipboardView> {
  late final TextEditingController _textController;
  final Set<String> _selectedDeviceIds = {};
  bool _isReading = false;
  bool _isSending = false;
  final Map<String, String> _deliveryStatuses = {};

  /// A screenshot or copied picture (PNG). When set it is sent instead of the text.
  Uint8List? _image;

  // False while another section of the dashboard is showing.
  bool _isVisible = true;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController();
    HardwareKeyboard.instance.addHandler(_handleKeyboard);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyboard);
    _textController.dispose();
    super.dispose();
  }

  /// Ctrl+V outside the text box pastes whatever is on the clipboard: an image or text.
  /// (Inside the text box, Ctrl+V / Ctrl+C / Ctrl+X are the normal text shortcuts.)
  bool _handleKeyboard(KeyEvent event) {
    if (kIsWeb || !_isVisible || !mounted || event is! KeyDownEvent) return false;
    if (event.logicalKey != LogicalKeyboardKey.keyV) return false;
    final keys = HardwareKeyboard.instance;
    if (!(keys.isControlPressed || keys.isMetaPressed) || keys.isAltPressed) return false;
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return false;
    final focus = FocusManager.instance.primaryFocus;
    if (focus?.context?.findAncestorWidgetOfExactType<EditableText>() != null) return false;
    if (!_isReading) unawaited(_readClipboard());
    return true;
  }

  Future<void> _readClipboard() async {
    setState(() => _isReading = true);
    try {
      // A screenshot on the clipboard has no text, so look for an image first.
      final image = await ClipboardImageService.readImageBytes();
      if (image != null) {
        setState(() {
          _image = image;
          _isReading = false;
          _deliveryStatuses.clear();
        });
        return;
      }
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text ?? '';
      setState(() {
        _image = null;
        _textController.text = text;
        _isReading = false;
      });
      if (text.isEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.cardBg,
            content: Text(
              'Clipboard is currently empty.',
              style: TextStyle(fontFamily: 'Poppins', color: AppColors.secondaryText),
            ),
          ),
        );
      }
    } catch (e) {
      setState(() => _isReading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.cardBg,
            content: Text(
              'Error accessing clipboard: $e',
              style: TextStyle(fontFamily: 'Poppins', color: AppColors.error),
            ),
          ),
        );
      }
    }
  }

  Future<void> _sendClipboardContent() async {
    final engine = context.read<TransferEngine>();
    final content = _textController.text; // Preserve exact indentation, code formatting, and spaces
    final image = _image;
    final what = image != null ? 'image' : 'text';
    if (image == null && content.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.cardBg,
          content: Text(
            'Please paste or enter text before sending.',
            style: TextStyle(fontFamily: 'Poppins', color: AppColors.primaryText),
          ),
        ),
      );
      return;
    }
    if (_selectedDeviceIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.cardBg,
          content: Text(
            'Please select at least one recipient device.',
            style: TextStyle(fontFamily: 'Poppins', color: AppColors.primaryText),
          ),
        ),
      );
      return;
    }

    setState(() {
      _isSending = true;
      _deliveryStatuses.clear();
    });

    // Exact UTF-8 byte encoding guarantees 100% preservation of code, symbols, indentations, and emojis
    final bytes = image ?? Uint8List.fromList(utf8.encode(content));
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final fileName = image != null ? 'Clipboard_Image_$timestamp.png' : 'Clipboard_Snippet_$timestamp.txt';
    final List<String> succeededNames = [];
    final List<String> failedNames = [];

    for (final devId in _selectedDeviceIds) {
      final dev = engine.pairedDevices.where((d) => d.id == devId).firstOrNull;
      if (dev == null) {
        failedNames.add('Unknown Device');
        _deliveryStatuses[devId] = 'Failed: Disconnected';
        continue;
      }

      try {
        _deliveryStatuses[devId] = 'Sending...';
        setState(() {});

        final transfer = await engine.sendFileToDevice(
          fileName: fileName,
          bytes: bytes,
          recipient: dev,
        );
        if (!await engine.waitForTransfer(transfer.transferId)) {
          final failed = engine.activeTransfers.where((t) => t.transferId == transfer.transferId);
          throw failed.isNotEmpty && failed.first.errorMessage != null ? failed.first.errorMessage! : 'Transfer failed';
        }

        succeededNames.add(dev.name);
        _deliveryStatuses[devId] = 'Sent successfully';
      } catch (e) {
        failedNames.add(dev.name);
        _deliveryStatuses[devId] = 'Failed: $e';
      }
    }

    if (mounted) {
      setState(() => _isSending = false);

      if (succeededNames.length == 1 && failedNames.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.charcoalSurface,
            content: Row(
              children: [
                Icon(Icons.check_circle_rounded, color: AppColors.primaryAccent, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Clipboard $what sent to ${succeededNames.first}.',
                    style: TextStyle(fontFamily: 'Poppins', color: AppColors.primaryText, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        );
      } else if (succeededNames.isNotEmpty && failedNames.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.charcoalSurface,
            content: Row(
              children: [
                Icon(Icons.check_circle_rounded, color: AppColors.primaryAccent, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Clipboard $what sent to all ${succeededNames.length} selected devices.',
                    style: TextStyle(fontFamily: 'Poppins', color: AppColors.primaryText, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        );
      } else if (succeededNames.isNotEmpty && failedNames.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.surfaceElevated,
            content: Text(
              'Sent to ${succeededNames.join(", ")}, but failed for: ${failedNames.join(", ")}',
              style: TextStyle(fontFamily: 'Poppins', color: AppColors.warning),
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.surfaceElevated,
            content: Text(
              'Failed to send clipboard $what to: ${failedNames.join(", ")}',
              style: TextStyle(fontFamily: 'Poppins', color: AppColors.error),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    _isVisible = TickerMode.valuesOf(context).enabled;
    final engine = context.watch<TransferEngine>();

    // Auto-select first paired device if none currently selected
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
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
                const DemoModeNotice(),
                // Security Notice Banner
                Container(
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
                          'Clipboard Sharing requires your explicit approval for every transmission. Text and code formatting are preserved '
                          'with high fidelity; copied images and screenshots are sent as PNG. Press Ctrl+V on this page to paste.',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 12,
                            height: 1.45,
                            color: AppColors.secondaryText,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Actions: Paste from Desktop / Mobile Clipboard
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
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.nearBlack),
                            )
                          : const Icon(Icons.paste_rounded, size: 18),
                      label: const Text(
                        'Paste from System Clipboard',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      onPressed: _isReading ? null : _readClipboard,
                    ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        foregroundColor: AppColors.primaryText,
                        side: BorderSide(color: AppColors.subtleBorderLight),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: Icon(Icons.clear_rounded, size: 18, color: AppColors.secondaryText),
                      label: Text(
                        'Clear Preview',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w500,
                          fontSize: 13,
                          color: AppColors.primaryText,
                        ),
                      ),
                      onPressed: () {
                        setState(() {
                          _textController.clear();
                          _image = null;
                          _deliveryStatuses.clear();
                        });
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                // Text / Code Preview & Edit Box
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
                              _image != null ? 'Image Preview (sent as PNG):' : 'Content Preview (Text & Code Formatting Preserved):',
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
                            _image != null
                                ? FormatUtils.formatBytes(_image!.length)
                                : '${_textController.text.length} chars · ${_textController.text.split("\n").length} lines',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 11.5,
                              color: AppColors.secondaryText,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (_image != null) ...[
                        Container(
                          key: const Key('clipboard_image_preview'),
                          width: double.infinity,
                          constraints: const BoxConstraints(maxHeight: 260),
                          decoration: BoxDecoration(
                            color: AppColors.dashboardBg,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.subtleBorderLight),
                          ),
                          padding: const EdgeInsets.all(8),
                          child: Image.memory(_image!, fit: BoxFit.contain, gaplessPlayback: true),
                        ),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          style: TextButton.styleFrom(foregroundColor: AppColors.secondaryText),
                          icon: const Icon(Icons.text_fields_rounded, size: 16),
                          label: const Text('Remove image and type text instead', style: TextStyle(fontFamily: 'Poppins', fontSize: 12)),
                          onPressed: () => setState(() => _image = null),
                        ),
                      ] else
                      TextField(
                        controller: _textController,
                        maxLines: 10,
                        cursorColor: AppColors.primaryAccent,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 13,
                          height: 1.5,
                          color: AppColors.primaryText,
                        ),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: AppColors.dashboardBg,
                          hintText: 'Enter or paste code, terminal logs, links, notes, or snippets here...',
                          hintStyle: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 12.5,
                            color: AppColors.mutedText,
                          ),
                          contentPadding: const EdgeInsets.all(14),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: AppColors.subtleBorderLight),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: AppColors.primaryAccent, width: 1.5),
                          ),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Multi-Device Recipient Selection
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'SEND TO PAIRED DEVICES',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        color: AppColors.secondaryText,
                        letterSpacing: 1.0,
                      ),
                    ),
                    if (engine.pairedDevices.length > 1)
                      Row(
                        children: [
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.primaryAccent,
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            ),
                            icon: Icon(Icons.select_all_rounded, size: 16, color: AppColors.primaryAccent),
                            label: Text(
                              'Select All',
                              style: TextStyle(fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primaryAccent),
                            ),
                            onPressed: () {
                              setState(() {
                                _selectedDeviceIds.clear();
                                _selectedDeviceIds.addAll(engine.pairedDevices.map((d) => d.id));
                              });
                            },
                          ),
                          const SizedBox(width: 4),
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.secondaryText,
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            ),
                            icon: Icon(Icons.deselect_rounded, size: 16, color: AppColors.secondaryText),
                            label: Text(
                              'Clear',
                              style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: AppColors.secondaryText),
                            ),
                            onPressed: () {
                              setState(() => _selectedDeviceIds.clear());
                            },
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
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'No paired devices connected. Please pair a device first.',
                            style: TextStyle(fontFamily: 'Poppins', color: AppColors.secondaryText, fontSize: 12.5),
                          ),
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
                          color: isSelected
                              ? AppColors.primaryAccent.withValues(alpha: 0.08)
                              : AppColors.cardBg,
                          borderColor: isSelected
                              ? AppColors.primaryAccent
                              : AppColors.subtleBorder,
                          hoverBorderColor: AppColors.primaryAccent,
                          onTap: () {
                            setState(() {
                              if (isSelected) {
                                _selectedDeviceIds.remove(d.id);
                              } else {
                                _selectedDeviceIds.add(d.id);
                              }
                            });
                          },
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
                                onChanged: (val) {
                                  setState(() {
                                    if (val == true) {
                                      _selectedDeviceIds.add(d.id);
                                    } else {
                                      _selectedDeviceIds.remove(d.id);
                                    }
                                  });
                                },
                              ),
                              Icon(
                                d.deviceType == DeviceType.mobile
                                    ? Icons.phone_android_rounded
                                    : d.deviceType == DeviceType.tablet
                                        ? Icons.tablet_mac_rounded
                                        : Icons.laptop_chromebook_rounded,
                                color: isSelected ? AppColors.primaryAccent : AppColors.secondaryText,
                                size: 22,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      d.name,
                                      style: TextStyle(
                                        fontFamily: 'Poppins',
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13.5,
                                        color: isSelected ? AppColors.primaryAccent : AppColors.primaryText,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'IP: ${d.ip} · ${d.isOnline ? "Online" : "Offline"}',
                                      style: TextStyle(
                                        fontFamily: 'Poppins',
                                        fontSize: 11.5,
                                        color: AppColors.secondaryText,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (status != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: status.contains('success')
                                        ? AppColors.primaryAccent.withValues(alpha: 0.15)
                                        : status.contains('Failed')
                                            ? AppColors.error.withValues(alpha: 0.15)
                                            : AppColors.softGray.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: status.contains('success')
                                          ? AppColors.primaryAccent.withValues(alpha: 0.35)
                                          : status.contains('Failed')
                                              ? AppColors.error.withValues(alpha: 0.35)
                                              : AppColors.softGray.withValues(alpha: 0.3),
                                    ),
                                  ),
                                  child: Text(
                                    status,
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: status.contains('success')
                                          ? AppColors.primaryAccent
                                          : status.contains('Failed')
                                              ? AppColors.error
                                              : AppColors.primaryText,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                const SizedBox(height: 20),

                // Main Send Action Button
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
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.nearBlack),
                          )
                        : const Icon(Icons.send_rounded, size: 20),
                    label: Text(
                      _selectedDeviceIds.length <= 1
                          ? 'Send Clipboard to Selected Device'
                          : 'Send Clipboard to Selected Devices (${_selectedDeviceIds.length})',
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    onPressed: ((_image != null || _textController.text.trim().isNotEmpty) &&
                            _selectedDeviceIds.isNotEmpty &&
                            !_isSending)
                        ? _sendClipboardContent
                        : null,
                  ),
                ),
              ],
            ),
          ),
        );
      }
    }
