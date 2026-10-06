import 'package:flutter/material.dart';

import '../../../core/constants.dart';
import '../../../core/design/tokens.dart';
import '../../../transfer/connect_flow.dart';

/// Single status line while connecting ("Connecting...") and clear error card with a single
/// "Retry" button when all connection methods fail.
class ConnectStatusPanel extends StatelessWidget {
  const ConnectStatusPanel({
    super.key,
    required this.state,
    required this.onRetry,
  });

  final ConnectFlowState state;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: switch (state.phase) {
        ConnectPhase.connecting ||
        ConnectPhase.searchingLan ||
        ConnectPhase.tryingInternet => _busy(),
        ConnectPhase.failed => _failed(),
        _ => const SizedBox.shrink(),
      },
    );
  }

  Widget _busy() {
    return Semantics(
      key: const ValueKey('connecting'),
      liveRegion: true,
      label: 'Connecting...',
      child: Container(
        margin: const EdgeInsets.only(bottom: Space.l),
        padding: const EdgeInsets.symmetric(
          horizontal: Space.m,
          vertical: Space.m,
        ),
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(Radii.control),
          border: Border.all(color: AppColors.subtleBorder),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.limeGreen,
              ),
            ),
            const SizedBox(width: Space.m),
            Expanded(
              child: Text(
                'Connecting...',
                style: TextStyles.label.copyWith(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w500,
                  color: AppColors.primaryText,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _failed() {
    return Semantics(
      key: const ValueKey('failed'),
      liveRegion: true,
      child: Container(
        margin: const EdgeInsets.only(bottom: Space.l),
        padding: const EdgeInsets.all(Space.l),
        decoration: BoxDecoration(
          color: AppColors.errorContainer,
          borderRadius: BorderRadius.circular(Radii.control),
          border: Border.all(color: AppColors.warning.withValues(alpha: 0.45)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  color: AppColors.warning,
                  size: 20,
                ),
                const SizedBox(width: Space.s),
                Expanded(
                  child: Text(
                    state.statusText,
                    style: TextStyles.body.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.primaryText,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.m),
            ElevatedButton.icon(
              onPressed: onRetry,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.limeGreen,
                foregroundColor: AppColors.nearBlack,
                elevation: 0,
                minimumSize: const Size(0, minTapTarget),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(Radii.control),
                ),
              ),
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text(
                'Retry',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
