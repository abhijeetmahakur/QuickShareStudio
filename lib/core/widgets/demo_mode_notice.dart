import 'package:flutter/material.dart';
import '../../data/services/cross_device_transfer_service.dart';
import '../constants.dart';

/// Shown on pairing/sending screens when the local network transfer service is not running
/// (always the case in the browser-based desktop app). Without it, pairing and transfers
/// are simulated, so the user must not mistake them for real ones.
class DemoModeNotice extends StatelessWidget {
  const DemoModeNotice({super.key});

  @override
  Widget build(BuildContext context) {
    if (CrossDeviceTransferService().isServerRunning) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: AppColors.warning, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Demo mode: this version cannot reach other devices yet. Pairing and transfers '
              'are simulated on this computer and no file leaves it. To move a file now, '
              'use Save or Share and send it another way.',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 12.5, color: AppColors.primaryText, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
