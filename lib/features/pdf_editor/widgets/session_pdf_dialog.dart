import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../core/services/file_actions.dart';
import '../../../core/widgets/demo_mode_notice.dart';
import '../../../data/models/device_model.dart';
import '../../../data/models/session_pdf.dart';
import '../../../data/models/transfer_item.dart';
import '../../../data/services/transfer_engine.dart';
import '../../../core/utils/file_utils.dart';
import '../../../core/utils/format_utils.dart';
import '../../../core/constants.dart';

enum SessionPdfStep {
  ready,
  selectDevice,
  pairing,
  transferring,
  completed,
  interrupted,
}

class SessionPdfDialog extends StatefulWidget {
  final SessionPdf sessionPdf;
  final bool autoSendImmediately;
  final VoidCallback? onDismiss;

  const SessionPdfDialog({
    super.key,
    required this.sessionPdf,
    this.autoSendImmediately = false,
    this.onDismiss,
  });

  static Future<void> show(
    BuildContext context, {
    required SessionPdf sessionPdf,
    bool autoSendImmediately = false,
    VoidCallback? onDismiss,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => SessionPdfDialog(
        sessionPdf: sessionPdf,
        autoSendImmediately: autoSendImmediately,
        onDismiss: onDismiss,
      ),
    );
  }

  @override
  State<SessionPdfDialog> createState() => _SessionPdfDialogState();
}

class _SessionPdfDialogState extends State<SessionPdfDialog> with SingleTickerProviderStateMixin {
  late SessionPdfStep _currentStep;
  late TextEditingController _fileNameController;
  late String _activeFileName;
  final Set<String> _selectedDeviceIds = {};
  TransferItem? _currentTransfer;
  StreamSubscription? _transferSub;
  late AnimationController _pulseController;
  TransferEngine? _engine;
  bool _isTransferring = false;
  bool _nameSaved = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );

    final engine = context.read<TransferEngine>();
    
    // Determine active filename: engine saved document name, or sessionPdf fileName
    final savedName = engine.savedDocumentName;
    _activeFileName = (savedName != null && savedName.isNotEmpty)
        ? savedName
        : widget.sessionPdf.fileName;
    _activeFileName = FileUtils.formatPdfFilename(_activeFileName);
    _fileNameController = TextEditingController(text: _activeFileName);

    // Auto-save session PDF in engine so it is not lost
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        engine.setSessionPdf(widget.sessionPdf.copyWith(fileName: _activeFileName));
      }
    });

    if (widget.autoSendImmediately) {
      if (engine.pairedDevices.isEmpty) {
        _currentStep = SessionPdfStep.pairing;
        _pulseController.repeat(reverse: true);
      } else {
        _currentStep = SessionPdfStep.selectDevice;
        if (engine.pairedDevices.length == 1) {
          _selectedDeviceIds.add(engine.pairedDevices.first.id);
        }
      }
    } else {
      _currentStep = SessionPdfStep.ready;
    }
  }

  void _saveFileName(TransferEngine engine) {
    final sanitized = FileUtils.formatPdfFilename(_fileNameController.text);
    setState(() {
      _activeFileName = sanitized;
      _fileNameController.text = sanitized;
      _nameSaved = true;
    });

    engine.saveDocumentName(sanitized);
    engine.setSessionPdf(widget.sessionPdf.copyWith(fileName: sanitized));

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Document name saved as "$sanitized"'),
        duration: const Duration(seconds: 2),
      ),
    );

    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _nameSaved = false);
    });
  }

  Future<void> _runFileAction(Future<String> Function(Uint8List bytes, String fileName) action) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final message = await action(widget.sessionPdf.bytes, _activeFileName);
      messenger.showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 4)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  Future<void> _savePdfToDisk(TransferEngine engine) {
    _saveFileName(engine);
    return _runFileAction(
      (bytes, name) => FileActions.save(bytes, name, directory: engine.downloadDirectory),
    );
  }

  void _onSendToDeviceClicked() {
    final engine = _engine ?? context.read<TransferEngine>();
    if (engine.pairedDevices.isEmpty) {
      _pulseController.repeat(reverse: true);
      setState(() {
        _currentStep = SessionPdfStep.pairing;
      });
    } else {
      _pulseController.stop();
      setState(() {
        _currentStep = SessionPdfStep.selectDevice;
        if (engine.pairedDevices.length == 1) {
          _selectedDeviceIds.add(engine.pairedDevices.first.id);
        }
      });
    }
  }

  Future<void> _startTransfer(List<DeviceModel> recipients) async {
    _pulseController.stop();
    final engine = _engine ?? context.read<TransferEngine>();
    if (recipients.isEmpty || !mounted) return;

    setState(() {
      _currentStep = SessionPdfStep.transferring;
      _isTransferring = true;
    });

    const resolvedConnection = 'Direct Local Network';

    if (recipients.length == 1) {
      final t = await engine.sendFileToDevice(
        fileName: _activeFileName,
        bytes: widget.sessionPdf.bytes,
        recipient: recipients.first,
        sessionName: widget.sessionPdf.sessionName,
        pageCount: widget.sessionPdf.pageCount,
        connectionType: resolvedConnection,
      );
      if (mounted) {
        setState(() {
          _currentTransfer = t;
        });
      }
    } else {
      final list = await engine.sendFileToMultipleRecipients(
        fileName: _activeFileName,
        bytes: widget.sessionPdf.bytes,
        recipients: recipients,
        sessionName: widget.sessionPdf.sessionName,
        pageCount: widget.sessionPdf.pageCount,
        connectionType: resolvedConnection,
      );
      if (mounted && list.isNotEmpty) {
        setState(() {
          _currentTransfer = list.first;
        });
      }
    }
  }

  Future<void> _simulateInterruption() async {
    final engine = _engine ?? context.read<TransferEngine>();
    if (_currentTransfer != null) {
      engine.simulateTransferInterruption(_currentTransfer!.transferId);
      if (mounted) {
        setState(() {
          _currentStep = SessionPdfStep.interrupted;
          _isTransferring = false;
        });
      }
    }
  }

  void _resumeTransfer() {
    final engine = _engine ?? context.read<TransferEngine>();
    if (_currentTransfer != null) {
      engine.resumeTransfer(_currentTransfer!.transferId);
      if (mounted) {
        setState(() {
          _currentStep = SessionPdfStep.transferring;
          _isTransferring = true;
        });
      }
    }
  }

  Future<void> _retryTransfer() async {
    final engine = _engine ?? context.read<TransferEngine>();
    if (_currentTransfer != null) {
      final newTransfer = await engine.retryTransfer(_currentTransfer!.transferId);
      if (mounted) {
        setState(() {
          if (newTransfer != null) {
            _currentTransfer = newTransfer;
          }
          _currentStep = SessionPdfStep.transferring;
          _isTransferring = true;
        });
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final engine = context.read<TransferEngine>();
    if (_engine != engine) {
      _engine?.removeListener(_onEngineStateChanged);
      _engine = engine;
      _engine!.addListener(_onEngineStateChanged);
    }
  }

  @override
  void dispose() {
    _fileNameController.dispose();
    _engine?.removeListener(_onEngineStateChanged);
    _pulseController.dispose();
    _transferSub?.cancel();
    super.dispose();
  }

  void _onEngineStateChanged() {
    if (!mounted || _engine == null) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _engine == null) return;

      if (_currentStep == SessionPdfStep.pairing && _engine!.pairedDevices.isNotEmpty && !_isTransferring) {
        final target = _engine!.pairedDevices.last;
        _startTransfer([target]);
        return;
      }

      if (_currentStep == SessionPdfStep.transferring && _currentTransfer != null) {
        final active = _engine!.activeTransfers.firstWhere(
          (t) => t.transferId == _currentTransfer!.transferId,
          orElse: () => _currentTransfer!,
        );
        if (active.status == TransferStatus.completed && _currentStep != SessionPdfStep.completed) {
          setState(() {
            _currentStep = SessionPdfStep.completed;
            _isTransferring = false;
          });
        } else if ((active.status == TransferStatus.failed || active.status == TransferStatus.paused) && _currentStep != SessionPdfStep.interrupted) {
          setState(() {
            _currentStep = SessionPdfStep.interrupted;
            _isTransferring = false;
          });
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<TransferEngine>();

    return Dialog(
      backgroundColor: AppColors.cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: AppColors.white.withValues(alpha: 0.14)),
      ),
      elevation: 16,
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildDialogHeader(),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Sending steps are simulated without the network service; say so.
                    if (_currentStep != SessionPdfStep.ready) const DemoModeNotice(),
                    _buildCurrentStepContent(engine),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDialogHeader() {
    String title;
    IconData icon;
    Color iconColor;

    switch (_currentStep) {
      case SessionPdfStep.ready:
        title = 'Session PDF Ready';
        icon = Icons.picture_as_pdf;
        iconColor = AppColors.primary;
        break;
      case SessionPdfStep.selectDevice:
        title = 'Send Session PDF';
        icon = Icons.send_to_mobile;
        iconColor = AppColors.secondary;
        break;
      case SessionPdfStep.pairing:
        title = 'Pair Device to Send';
        icon = Icons.qr_code_scanner;
        iconColor = AppColors.primary;
        break;
      case SessionPdfStep.transferring:
        title = 'Sending Session PDF';
        icon = Icons.wifi_tethering;
        iconColor = AppColors.primary;
        break;
      case SessionPdfStep.completed:
        title = 'PDF Sent Successfully';
        icon = Icons.check_circle_outline;
        iconColor = AppColors.success;
        break;
      case SessionPdfStep.interrupted:
        title = 'Transfer Interrupted';
        icon = Icons.warning_amber_rounded;
        iconColor = AppColors.warning;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        border: Border(bottom: BorderSide(color: AppColors.white.withValues(alpha: 0.12))),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: iconColor.withValues(alpha: 0.12),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            tooltip: 'Close',
            onPressed: () {
              widget.onDismiss?.call();
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentStepContent(TransferEngine engine) {
    switch (_currentStep) {
      case SessionPdfStep.ready:
        return _buildReadyStep(engine);
      case SessionPdfStep.selectDevice:
        return _buildSelectDeviceStep(engine);
      case SessionPdfStep.pairing:
        return _buildPairingStep(engine);
      case SessionPdfStep.transferring:
        return _buildTransferringStep(engine);
      case SessionPdfStep.completed:
        return _buildCompletedStep(engine);
      case SessionPdfStep.interrupted:
        return _buildInterruptedStep();
    }
  }

  // -------------------------------------------------------------
  // STEP 1: SESSION PDF READY (Section 5 & 74)
  // -------------------------------------------------------------
  Widget _buildReadyStep(TransferEngine engine) {
    final pdf = widget.sessionPdf;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Editable Filename with prominent Save button
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.cardBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.white.withValues(alpha: 0.12)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Document File Name',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.secondaryText),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _fileNameController,
                      decoration: InputDecoration(
                        hintText: 'e.g. Lab_Report.pdf',
                        border: const OutlineInputBorder(),
                        isDense: true,
                        prefixIcon: const Icon(Icons.description_outlined, size: 20),
                        suffixIcon: _nameSaved
                            ? Icon(Icons.check_circle, color: AppColors.success, size: 18)
                            : null,
                      ),
                      onSubmitted: (_) => _saveFileName(engine),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.onLimeText,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    ),
                    icon: const Icon(Icons.save, size: 16),
                    label: const Text('Save', style: TextStyle(fontWeight: FontWeight.bold)),
                    onPressed: () => _saveFileName(engine),
                  ),
                ],
              ),
              if (engine.savedDocumentName != null && engine.savedDocumentName!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  'Saved across sessions: ${engine.savedDocumentName!}',
                  style: TextStyle(fontSize: 11, color: AppColors.primary),
                ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _badge('${pdf.screenshotCount} screenshots', Icons.photo_library_outlined),
                  _badge('${pdf.pageCount} ${pdf.pageCount == 1 ? 'page' : 'pages'}', Icons.pages_outlined),
                  _badge(pdf.paperFormatDescription, Icons.aspect_ratio),
                  _badge(FormatUtils.formatBytes(pdf.fileSizeBytes), Icons.data_usage),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Primary Action: Send to Device
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.onLimeText,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            elevation: 2,
          ),
          icon: const Icon(Icons.send_to_mobile, size: 20),
          label: const Text(
            'Send to Paired Device',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          onPressed: _onSendToDeviceClicked,
        ),
        const SizedBox(height: 10),

        // Secondary Actions: Save PDF & Open PDF
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.download_outlined, size: 18),
                label: const Text('Save PDF'),
                onPressed: () => _savePdfToDisk(engine),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('Open PDF'),
                onPressed: () {
                  _saveFileName(engine);
                  _runFileAction(FileActions.open);
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  // -------------------------------------------------------------
  // STEP 2: DEVICE SELECTION
  // -------------------------------------------------------------
  Widget _buildSelectDeviceStep(TransferEngine engine) {
    final pdf = widget.sessionPdf;
    final devices = engine.pairedDevices;

    if (devices.length == 1) {
      final dev = devices.first;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Sending to:',
            style: TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.cardBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.3), width: 1.5),
            ),
            child: Row(
              children: [
                _deviceIcon(dev.deviceType),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(dev.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 2),
                      Text(
                        'Connected • Paired Session Active',
                        style: TextStyle(fontSize: 11, color: AppColors.success, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    _activeFileName,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${pdf.pageCount} pgs • ${FormatUtils.formatBytes(pdf.fileSizeBytes)}',
                  style: TextStyle(fontSize: 12, color: AppColors.secondaryText),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => setState(() => _currentStep = SessionPdfStep.ready),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.onLimeText,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  icon: const Icon(Icons.send, size: 18),
                  label: const Text('Send Now', style: TextStyle(fontWeight: FontWeight.bold)),
                  onPressed: () => _startTransfer([dev]),
                ),
              ),
            ],
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Choose paired device:',
          style: TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 10),
        for (final dev in devices) ...[
          CheckboxListTile(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            tileColor: _selectedDeviceIds.contains(dev.id)
                ? AppColors.primary.withValues(alpha: 0.08)
                : AppColors.cardBg,
            value: _selectedDeviceIds.contains(dev.id),
            onChanged: (val) {
              setState(() {
                if (val == true) {
                  _selectedDeviceIds.add(dev.id);
                } else {
                  _selectedDeviceIds.remove(dev.id);
                }
              });
            },
            secondary: _deviceIcon(dev.deviceType),
            title: Text(dev.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            subtitle: Text('Connected • Paired Session Active', style: TextStyle(fontSize: 11, color: AppColors.success)),
            controlAffinity: ListTileControlAffinity.trailing,
          ),
          const SizedBox(height: 6),
        ],
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton(
              onPressed: () {
                setState(() {
                  _selectedDeviceIds.clear();
                  _selectedDeviceIds.addAll(devices.map((d) => d.id));
                });
              },
              child: const Text('Select All', style: TextStyle(fontSize: 12)),
            ),
            Text(
              '$_activeFileName (${FormatUtils.formatBytes(pdf.fileSizeBytes)})',
              style: TextStyle(fontSize: 11, color: AppColors.secondaryText),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => setState(() => _currentStep = SessionPdfStep.ready),
                child: const Text('Cancel'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.onLimeText,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                icon: const Icon(Icons.send, size: 18),
                label: Text(
                  _selectedDeviceIds.length > 1
                      ? 'Send to Selected (${_selectedDeviceIds.length})'
                      : 'Send PDF',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                onPressed: _selectedDeviceIds.isNotEmpty
                    ? () {
                        final chosen = devices.where((d) => _selectedDeviceIds.contains(d.id)).toList();
                        _startTransfer(chosen);
                      }
                    : null,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // -------------------------------------------------------------
  // STEP 3: PAIRING SCREEN (No timers, no bluetooth, no zero-install)
  // -------------------------------------------------------------
  Widget _buildPairingStep(TransferEngine engine) {
    final session = engine.currentPairingSession;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Text(
          'Connect Paired Device',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 6),
        Text(
          'Scan this QR code or enter the session code on your other device to connect and transfer the PDF.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: AppColors.secondaryText),
        ),
        const SizedBox(height: 14),

        // QR Code Container
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white, // QR codes need a white quiet zone in every theme
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: QrImageView(
            data: session?.qrPayload ?? 'quickshare://${engine.localIp}:${engine.localPort}/pair?code=${session?.code}',
            version: QrVersions.auto,
            size: 160.0,
            backgroundColor: Colors.white,
          ),
        ),
        const SizedBox(height: 14),

        Text(
          'SESSION PAIRING CODE',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
            color: AppColors.secondaryText,
          ),
        ),
        const SizedBox(height: 6),

        // Formatted Numeric Code Display
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
          ),
          child: Text(
            session?.formattedCode ?? '--- ---',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              letterSpacing: 4,
              fontFamily: 'monospace',
              color: AppColors.primary,
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Active Session Indicator
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FadeTransition(
              opacity: _pulseController,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'Session Active • Waiting for connection...',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.secondaryText),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        TextButton(
          onPressed: () => setState(() => _currentStep = SessionPdfStep.ready),
          child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
        ),
      ],
    );
  }

  // -------------------------------------------------------------
  // STEP 4: TRANSFERRING PROGRESS
  // -------------------------------------------------------------
  Widget _buildTransferringStep(TransferEngine engine) {
    final transfer = engine.activeTransfers.firstWhere(
      (t) => t.transferId == _currentTransfer?.transferId,
      orElse: () => _currentTransfer ?? engine.activeTransfers.first,
    );

    final progressPct = (transfer.progress * 100).round();
    final bytesSent = (transfer.fileSizeBytes * transfer.progress).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.picture_as_pdf, color: AppColors.primary, size: 24),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                transfer.fileName,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ),
            Text(
              '$progressPct%',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: AppColors.primary),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Progress bar
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: transfer.progress,
            minHeight: 12,
            backgroundColor: AppColors.white.withValues(alpha: 0.1),
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
          ),
        ),
        const SizedBox(height: 10),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${FormatUtils.formatBytes(bytesSent)} / ${FormatUtils.formatBytes(transfer.fileSizeBytes)}',
              style: TextStyle(fontSize: 12, color: AppColors.secondaryText),
            ),
            Text(
              FormatUtils.formatSpeed(transfer.speedBytesPerSec),
              style: TextStyle(fontSize: 12, color: AppColors.secondaryText),
            ),
          ],
        ),
        const SizedBox(height: 16),

        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.cardBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.white.withValues(alpha: 0.1)),
          ),
          child: Row(
            children: [
              Icon(Icons.devices, size: 24, color: AppColors.secondary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('To:', style: TextStyle(fontSize: 11, color: AppColors.secondaryText)),
                    Text(transfer.peerDeviceName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Direct Transfer\nIn Progress',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: AppColors.success),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () {
                  engine.cancelTransfer(transfer.transferId);
                  setState(() => _currentStep = SessionPdfStep.ready);
                },
                child: const Text('Cancel Transfer'),
              ),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              icon: const Icon(Icons.flash_off, size: 14),
              label: const Text('Test Interrupt', style: TextStyle(fontSize: 11)),
              onPressed: _simulateInterruption,
            ),
          ],
        ),
      ],
    );
  }

  // -------------------------------------------------------------
  // STEP 5: TRANSFER COMPLETED
  // -------------------------------------------------------------
  Widget _buildCompletedStep(TransferEngine engine) {
    final pdf = widget.sessionPdf;
    final recipientName = _currentTransfer?.peerDeviceName ?? 'Connected Device';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        CircleAvatar(
          radius: 28,
          backgroundColor: AppColors.successContainer,
          child: Icon(Icons.check, color: AppColors.success, size: 36),
        ),
        const SizedBox(height: 14),
        Text(
          _activeFileName,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 6),
        Text(
          'Sent to: $recipientName',
          style: TextStyle(fontSize: 13, color: AppColors.white.withValues(alpha: 0.7), fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          '${FormatUtils.formatBytes(pdf.fileSizeBytes)} • ${pdf.pageCount} ${pdf.pageCount == 1 ? 'page' : 'pages'}',
          style: TextStyle(fontSize: 12, color: AppColors.secondaryText),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.success.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle, size: 14, color: AppColors.success),
              SizedBox(width: 6),
              Text(
                'Transfer Complete',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.success),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.cardBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.history_rounded, size: 14, color: AppColors.primary),
              SizedBox(width: 6),
              Text(
                'Recorded in HISTORY',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.white),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: () => _runFileAction(FileActions.open),
                child: const Text('Open PDF'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.onLimeText,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: () {
                  widget.onDismiss?.call();
                  Navigator.pop(context);
                },
                child: const Text('Done', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // -------------------------------------------------------------
  // STEP 6: FAILED / INTERRUPTED TRANSFER
  // -------------------------------------------------------------
  Widget _buildInterruptedStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        CircleAvatar(
          radius: 28,
          backgroundColor: AppColors.errorContainer,
          child: Icon(Icons.wifi_off, color: AppColors.error, size: 32),
        ),
        const SizedBox(height: 14),
        Text(
          _activeFileName,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 8),
        Text(
          'The connection was interrupted.',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.error),
        ),
        const SizedBox(height: 4),
        Text(
          'Your PDF has not been lost. You can resume from the last valid chunk.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: AppColors.secondaryText),
        ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 360;

            final cancelButton = SizedBox(
              height: 44,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () => setState(() => _currentStep = SessionPdfStep.ready),
                child: const Text(
                  'Cancel',
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13),
                ),
              ),
            );

            final retryButton = SizedBox(
              height: 44,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: _retryTransfer,
                child: const Text(
                  'Retry',
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13),
                ),
              ),
            );

            final resumeButton = SizedBox(
              height: 44,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.onLimeText,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: _resumeTransfer,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.play_arrow, size: 16),
                    SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        'Resume',
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            );

            if (isNarrow) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  resumeButton,
                  const SizedBox(height: 8),
                  retryButton,
                  const SizedBox(height: 8),
                  cancelButton,
                ],
              );
            }

            return Row(
              children: [
                Expanded(child: cancelButton),
                const SizedBox(width: 8),
                Expanded(child: retryButton),
                const SizedBox(width: 8),
                Expanded(child: resumeButton),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _badge(String text, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColors.secondaryText),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.secondaryText)),
        ],
      ),
    );
  }

  Widget _deviceIcon(DeviceType type) {
    IconData icon;
    switch (type) {
      case DeviceType.desktop:
        icon = Icons.computer;
        break;
      case DeviceType.mobile:
        icon = Icons.smartphone;
        break;
      case DeviceType.tablet:
        icon = Icons.tablet_mac;
        break;
      case DeviceType.browser:
        icon = Icons.language;
        break;
    }
    return CircleAvatar(
      radius: 18,
      backgroundColor: AppColors.primary.withValues(alpha: 0.1),
      child: Icon(icon, color: AppColors.primary, size: 18),
    );
  }
}
