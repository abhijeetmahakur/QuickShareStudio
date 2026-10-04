import 'dart:ui';
import 'package:flutter/material.dart';
import '../../core/constants.dart';
import '../../core/utils/format_utils.dart';
import '../../data/models/incoming_transfer_request.dart';
import '../../data/models/transfer_item.dart';
import '../../data/services/transfer_engine.dart';

class IncomingTransferModal extends StatefulWidget {
  final IncomingTransferRequest request;
  final TransferEngine engine;
  final VoidCallback onDismiss;

  const IncomingTransferModal({
    super.key,
    required this.request,
    required this.engine,
    required this.onDismiss,
  });

  @override
  State<IncomingTransferModal> createState() => _IncomingTransferModalState();
}

class _IncomingTransferModalState extends State<IncomingTransferModal> {
  bool _isAccepted = false;

  TransferItem? get _activeTransfer {
    try {
      return widget.engine.activeTransfers.firstWhere((t) => t.transferId == widget.request.requestId);
    } catch (_) {
      return null;
    }
  }

  void _handleAccept() {
    setState(() => _isAccepted = true);
    widget.engine.acceptIncomingTransfer(widget.request.requestId, fallbackRequest: widget.request);
  }

  void _handleReject() {
    widget.engine.rejectIncomingTransfer(widget.request.requestId);
    widget.onDismiss();
  }

  @override
  Widget build(BuildContext context) {
    final transfer = _activeTransfer;
    final isDone = transfer?.status == TransferStatus.completed;

    return Center(
      child: Material(
        color: Colors.transparent,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              width: 480,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.cardBg.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: AppColors.white.withValues(alpha: 0.16),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 32,
                    offset: const Offset(0, 12),
                  ),
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.18),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.18),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.25),
                              blurRadius: 10,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Icon(Icons.downloading_rounded, color: AppColors.primary, size: 24),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isDone ? 'TRANSFER COMPLETED' : _isAccepted ? 'RECEIVING FILE' : 'INCOMING FILE TRANSFER',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.2,
                                color: AppColors.secondary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              isDone
                                  ? 'Saved to Destination Folder'
                                  : _isAccepted
                                      ? 'Receiving data from paired sender'
                                      : 'Transfer request from ${widget.request.senderDeviceName}',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: AppColors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close, size: 20, color: AppColors.secondaryText),
                        onPressed: () {
                          if (!_isAccepted) {
                            _handleReject();
                          } else {
                            widget.onDismiss();
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Divider(color: AppColors.overlay.withValues(alpha: 0.12), height: 1),
                  const SizedBox(height: 18),

                  // Sender Device
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.cardBg,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.white.withValues(alpha: 0.10)),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                          child: Icon(
                            widget.request.senderDeviceName.contains('PC') || widget.request.senderDeviceName.contains('Laptop')
                                ? Icons.laptop
                                : Icons.phone_android,
                            color: AppColors.primary,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      widget.request.senderDeviceName,
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.white),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppColors.success.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      'PAIRED PEER',
                                      style: TextStyle(color: AppColors.success, fontSize: 9.5, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '${widget.request.connectionType} • Session Active',
                                style: TextStyle(fontSize: 11, color: AppColors.secondaryText),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // File Information Card
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.cardBg,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.white.withValues(alpha: 0.10)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: widget.request.fileName.endsWith('.pdf')
                                ? Colors.redAccent.withValues(alpha: 0.18)
                                : widget.request.fileName.endsWith('.png') || widget.request.fileName.endsWith('.jpg')
                                    ? AppColors.primary.withValues(alpha: 0.18)
                                    : AppColors.secondary.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            widget.request.fileName.endsWith('.pdf')
                                ? Icons.picture_as_pdf
                                : widget.request.fileName.endsWith('.png') || widget.request.fileName.endsWith('.jpg')
                                    ? Icons.image
                                    : Icons.insert_drive_file,
                            color: widget.request.fileName.endsWith('.pdf')
                                ? Colors.redAccent
                                : AppColors.primaryLight,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.request.fileName,
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.white),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 3),
                              Row(
                                children: [
                                  Text(
                                    FormatUtils.formatBytes(widget.request.fileSizeBytes),
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.secondaryText),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'SHA: ${widget.request.sha256.length > 10 ? widget.request.sha256.substring(0, 10) : widget.request.sha256}...',
                                    style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: AppColors.secondaryText),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Progress Bar if in Transferring State
                  if (_isAccepted) ...[
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              isDone
                                  ? 'Transfer Complete (100%)'
                                  : 'Transferring ${((transfer?.progress ?? 0.0) * 100).toStringAsFixed(1)}%',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: isDone ? AppColors.success : AppColors.secondary,
                              ),
                            ),
                            Text(
                              isDone ? 'Auto-Saved' : '${FormatUtils.formatBytes((transfer?.speedBytesPerSec ?? 0.0).round())}/s',
                              style: TextStyle(fontSize: 11, color: AppColors.secondaryText),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: isDone ? 1.0 : (transfer?.progress ?? 0.0),
                            minHeight: 8,
                            backgroundColor: AppColors.cardBg,
                            color: isDone ? AppColors.success : AppColors.primary,
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ],

                  // Actions Buttons
                  if (!isDone && !_isAccepted)
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.error,
                              side: BorderSide(color: AppColors.error.withValues(alpha: 0.4)),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            icon: const Icon(Icons.close, size: 18),
                            label: const Text('Reject Transfer', style: TextStyle(fontWeight: FontWeight.bold)),
                            onPressed: _handleReject,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: AppColors.onLimeText,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              elevation: 4,
                            ),
                            icon: const Icon(Icons.file_download, size: 18),
                            label: const Text('Accept Transfer', style: TextStyle(fontWeight: FontWeight.bold)),
                            onPressed: _handleAccept,
                          ),
                        ),
                      ],
                    )
                  else if (isDone)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.success,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        icon: const Icon(Icons.check_circle, size: 18),
                        label: const Text('Done & Open Inbox', style: TextStyle(fontWeight: FontWeight.bold)),
                        onPressed: widget.onDismiss,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
