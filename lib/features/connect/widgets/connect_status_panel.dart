import 'package:flutter/material.dart';

import '../../../core/constants.dart';
import '../../../core/design/tokens.dart';
import '../../../transfer/connect_flow.dart';
import '../../../transfer/transfer_method.dart';

/// Progress and outcome of "connect with a code": "Looking on your network..." ->
/// "Trying over internet...", and when nothing worked the three ways forward.
class ConnectStatusPanel extends StatelessWidget {
  const ConnectStatusPanel({
    super.key,
    required this.state,
    required this.onCancel,
    required this.onTryInternet,
    required this.onUseBluetooth,
    required this.onRetry,
    this.bluetoothAvailable = false,
    this.bluetoothUnavailableReason,
  });

  final ConnectFlowState state;
  final VoidCallback onCancel;
  final VoidCallback onTryInternet;
  final VoidCallback onUseBluetooth;
  final VoidCallback onRetry;
  final bool bluetoothAvailable;
  final String? bluetoothUnavailableReason;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: switch (state.phase) {
        ConnectPhase.searchingLan || ConnectPhase.tryingInternet => _busy(),
        ConnectPhase.failed => _failed(),
        _ => const SizedBox.shrink(),
      },
    );
  }

  Widget _busy() {
    final internet = state.phase == ConnectPhase.tryingInternet;
    return Semantics(
      key: ValueKey(state.phase),
      liveRegion: true,
      label: state.statusText,
      child: Container(
        margin: const EdgeInsets.only(bottom: Space.l),
        padding: const EdgeInsets.all(Space.m),
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(Radii.control),
        ),
        child: Row(children: [
          SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.limeGreen)),
          const SizedBox(width: Space.m),
          Icon(internet ? TransferMethod.internet.icon : TransferMethod.lan.icon, size: 16, color: AppColors.secondaryText),
          const SizedBox(width: Space.s),
          Expanded(child: Text(state.statusText, style: TextStyles.label)),
          TextButton(
            onPressed: onCancel,
            style: TextButton.styleFrom(minimumSize: const Size(minTapTarget, minTapTarget), foregroundColor: AppColors.primaryText),
            child: const Text('Cancel', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
          ),
        ]),
      ),
    );
  }

  Widget _failed() {
    final showOptions = state.showsOptions;
    final offline = state.failure == ConnectFailure.noInternet;
    return Semantics(
      key: const ValueKey('failed'),
      liveRegion: true,
      child: Container(
        margin: const EdgeInsets.only(bottom: Space.l),
        padding: const EdgeInsets.all(Space.l),
        decoration: BoxDecoration(
          color: AppColors.warningContainer,
          borderRadius: BorderRadius.circular(Radii.control),
          border: Border.all(color: AppColors.warning.withValues(alpha: 0.45)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(offline ? Icons.wifi_off_rounded : Icons.travel_explore_rounded, color: AppColors.warning, size: 20),
            const SizedBox(width: Space.s),
            Expanded(
              child: Text(
                showOptions ? ConnectFlowState.lanNotFoundMessage : (state.detail ?? 'Could not connect.'),
                style: TextStyles.body.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ]),
          if (showOptions && state.detail != null) ...[
            const SizedBox(height: Space.s),
            Padding(
              padding: const EdgeInsets.only(left: 28),
              child: Text(state.detail!, style: TextStyles.caption),
            ),
          ],
          if (showOptions || state.failure == ConnectFailure.wrongCode || state.failure == ConnectFailure.noRoute) ...[
            const SizedBox(height: Space.m),
            Wrap(spacing: Space.s, runSpacing: Space.s, children: [
              _button('Try over internet', Icons.public_rounded, offline ? null : onTryInternet,
                  tooltip: offline ? 'No internet connection' : null),
              _button('Use Bluetooth', Icons.bluetooth_rounded, bluetoothAvailable ? onUseBluetooth : null,
                  tooltip: bluetoothAvailable ? null : bluetoothUnavailableReason),
              _button('Retry', Icons.refresh_rounded, onRetry, primary: true),
            ]),
          ],
        ]),
      ),
    );
  }

  Widget _button(String label, IconData icon, VoidCallback? onTap, {bool primary = false, String? tooltip}) {
    final button = primary
        ? ElevatedButton.icon(
            onPressed: onTap,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.limeGreen,
              foregroundColor: AppColors.nearBlack,
              elevation: 0,
              minimumSize: const Size(0, minTapTarget),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.control)),
            ),
            icon: Icon(icon, size: 16),
            label: Text(label, style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 12.5)),
          )
        : OutlinedButton.icon(
            onPressed: onTap,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primaryText,
              side: BorderSide(color: AppColors.subtleBorderLight),
              minimumSize: const Size(0, minTapTarget),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.control)),
            ),
            icon: Icon(icon, size: 16),
            label: Text(label, style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 12.5)),
          );
    return tooltip == null ? button : Tooltip(message: tooltip, child: button);
  }
}
