import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants.dart';
import '../../core/utils/format_utils.dart';
import '../../data/models/app_update_info.dart';
import '../../data/services/app_update_service.dart';
import '../../data/services/transfer_engine.dart';

String _plainReleaseText(String text) => text
    .replaceAll(RegExp(r'^\s{0,3}#{1,6}\s*', multiLine: true), '')
    .replaceAll(RegExp(r'^\s*[-*+]\s+', multiLine: true), '')
    .replaceAll(RegExp(r'[*_`]'), '')
    .trim();

String _updateDescription(AppUpdateInfo update) {
  if (RegExp(r'^#{1,6}\s+.+$').hasMatch(update.description.trim())) {
    return 'Bug fixes and improvements.';
  }
  final description = _plainReleaseText(update.description);
  return description.isEmpty ? 'A new version is ready to install.' : description;
}

class UpdateDialog extends StatefulWidget {
  final AppUpdateInfo update;

  const UpdateDialog({
    super.key,
    required this.update,
  });

  static Future<void> show(BuildContext context, AppUpdateInfo update) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => UpdateDialog(update: update),
    );
  }

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool _showDetails = false;

  void _handleUpdateNow(AppUpdateService updateService, TransferEngine engine) {
    updateService.startUpdateNow(
      engine: engine,
      onComplete: () {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('QuickShare Studio successfully updated to v${updateService.currentVersion}!'),
              backgroundColor: AppColors.cardBg,
            ),
          );
        }
      },
      onError: (err) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Update Error: $err'),
              backgroundColor: Colors.red.shade900,
            ),
          );
        }
      },
    );
  }

  void _handleUpdateLater(AppUpdateService updateService) {
    updateService.postponeUpdate();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final updateService = context.watch<AppUpdateService>();
    final engine = context.watch<TransferEngine>();
    final update = widget.update;
    final isProcessing = updateService.status == UpdateStatus.downloading ||
        updateService.status == UpdateStatus.verifying ||
        updateService.status == UpdateStatus.staging;
    final isApplied = updateService.status == UpdateStatus.applied;
    final isFailed = updateService.status == UpdateStatus.failed;
    final warningMessage = (updateService.errorMessage ?? '').trim();
    final screenSize = MediaQuery.sizeOf(context);
    final isCompact = screenSize.width < 600;
    // Versions below the minimum supported one cannot postpone.
    final mandatory = update.isBelowMinimum;

    return Dialog(
      insetPadding: EdgeInsets.symmetric(horizontal: isCompact ? 16 : 40, vertical: 24),
      backgroundColor: AppColors.cardBg,
      elevation: 24,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: AppColors.white.withValues(alpha: 0.16), width: 1.2),
      ),
      child: Container(
        constraints: BoxConstraints(maxWidth: 520, maxHeight: screenSize.height - 48),
        child: SingleChildScrollView(
          padding: EdgeInsets.all(isCompact ? 18 : 26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
            // Header: Update Icon & Title
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.4),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(Icons.system_update_alt_rounded, color: AppColors.nearBlack, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SOFTWARE UPDATE AVAILABLE',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.3,
                          color: AppColors.secondary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Update available v${update.version}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        update.title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: AppColors.white,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!isProcessing && !mandatory)
                  IconButton(
                    icon: Icon(Icons.close, size: 20, color: AppColors.secondaryText),
                    tooltip: 'Postpone',
                    onPressed: () => _handleUpdateLater(updateService),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            Divider(color: AppColors.overlay.withValues(alpha: 0.12), height: 1),
            const SizedBox(height: 18),

            // Version Pill & Metadata
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.cardBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.white.withValues(alpha: 0.1)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      'v${update.currentVersion} → v${update.version}',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Size: ${FormatUtils.formatBytes(update.packageSizeBytes)} • SHA-256 Verified',
                      style: TextStyle(fontSize: 11.5, color: AppColors.secondaryText),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Short Description
            Text(
              _updateDescription(update),
              style: TextStyle(fontSize: 13, color: AppColors.secondaryText, height: 1.4),
            ),
            const SizedBox(height: 12),

            // Expandable "View Details"
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => setState(() => _showDetails = !_showDetails),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(
                      _showDetails ? Icons.expand_less : Icons.expand_more,
                      size: 18,
                      color: AppColors.primaryAccent,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _showDetails ? 'Hide Details' : 'View Details',
                      style: TextStyle(
                        color: AppColors.primaryAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            if (_showDetails) ...[
              const SizedBox(height: 8),
              Container(
                constraints: const BoxConstraints(maxHeight: 140),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.dashboardBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.white.withValues(alpha: 0.08)),
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: update.releaseNotes.length,
                  itemBuilder: (context, idx) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('• ', style: TextStyle(color: AppColors.primaryAccent, fontWeight: FontWeight.bold)),
                          Expanded(
                            child: Text(
                              _plainReleaseText(update.releaseNotes[idx]),
                              style: TextStyle(fontSize: 11.5, color: AppColors.secondaryText),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
            const SizedBox(height: 16),

            // Progress / Status Area
            if (isProcessing) ...[
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        updateService.statusMessage,
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.secondaryText),
                      ),
                      Text(
                        '${(updateService.updateProgress * 100).toInt()}%',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: updateService.updateProgress,
                      backgroundColor: AppColors.white.withValues(alpha: 0.1),
                      valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                      minHeight: 6,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ] else if (isApplied) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.check_circle, color: Color(0xFF10B981), size: 20),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Update Applied! User settings and history are fully intact.',
                        style: TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 12.5),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ] else if (isFailed) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.error_outline, color: Colors.redAccent, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        warningMessage.isNotEmpty ? warningMessage : 'Update could not be completed.',
                        style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Action Buttons
            if (mandatory) ...[
              Text(
                'This version (v${update.currentVersion}) is no longer supported. Update to keep sharing files with other devices.',
                style: TextStyle(fontSize: 12.5, color: AppColors.warning, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
            ],
            if (updateService.status == UpdateStatus.readyToRestart) ...[
              Text(
                updateService.statusMessage,
                style: TextStyle(fontSize: 12.5, color: AppColors.success),
              ),
              const SizedBox(height: 12),
            ],
            if (isApplied)
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: AppColors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.check, size: 18),
                label: const Text('Continue with New Version', style: TextStyle(fontWeight: FontWeight.bold)),
                onPressed: () => Navigator.of(context).pop(),
              )
            else if (!isProcessing)
              Row(
                children: [
                  if (!mandatory) Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        side: BorderSide(color: AppColors.white.withValues(alpha: 0.2)),
                      ),
                      onPressed: () => _handleUpdateLater(updateService),
                      child: Text('Update Later', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.white)),
                    ),
                  ),
                  if (!mandatory) const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.nearBlack,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 3,
                      ),
                      icon: const Icon(Icons.download_rounded, size: 18),
                      label: const Text('Update Now', style: TextStyle(fontWeight: FontWeight.bold)),
                      onPressed: () => _handleUpdateNow(updateService, engine),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
