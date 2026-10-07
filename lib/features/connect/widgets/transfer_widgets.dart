import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants.dart';
import '../../../core/design/tokens.dart';
import '../../../core/utils/format_utils.dart';
import '../../../data/models/transfer_item.dart';
import '../../../data/services/transfer_engine.dart';
import '../../../transfer/transfer_method.dart';

/// "LAN" / "Internet" / "Bluetooth" pill.
class MethodBadge extends StatelessWidget {
  const MethodBadge(this.method, {super.key, this.relayed = false, this.compact = false});
  final TransferMethod method;
  final bool relayed;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = switch (method) {
      TransferMethod.lan => AppColors.limeGreen,
      TransferMethod.internet => const Color(0xFF60A5FA),
      TransferMethod.bluetooth => const Color(0xFFA78BFA),
    };
    final label = method == TransferMethod.internet
        ? (relayed ? 'Relay' : 'Direct')
        : method.badge;
    return Semantics(
      label: method == TransferMethod.internet
          ? 'Connected over the internet via ${relayed ? 'a relay' : 'a direct connection'}'
          : 'Connected by ${method.description}',
      excludeSemantics: true,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: compact ? 6 : Space.s, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(Radii.chip),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(method.icon, size: compact ? 11 : 13, color: color),
          const SizedBox(width: Space.xs),
          Text(label, style: TextStyle(fontFamily: 'Poppins', fontSize: compact ? 10 : 11, fontWeight: FontWeight.w700, color: color)),
        ]),
      ),
    );
  }
}

/// The 4-digit code both devices show for the same connection.
class VerificationCodeChip extends StatelessWidget {
  const VerificationCodeChip(this.code, {super.key});
  final String code;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Both devices show the same 4 digits when nobody is listening in. If they differ, disconnect.',
      child: Semantics(
        label: 'Verification code ${code.split('').join(' ')}. Check that the other device shows the same.',
        excludeSemantics: true,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: Space.s, vertical: 3),
          decoration: BoxDecoration(
            color: AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(Radii.chip),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.verified_user_outlined, size: 13, color: AppColors.secondaryText),
            const SizedBox(width: Space.xs),
            Text('Verify $code',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                    color: AppColors.primaryText,
                    fontFeatures: const [FontFeature.tabularFigures()])),
          ]),
        ),
      ),
    );
  }
}

String _statusText(TransferItem t) {
  switch (t.status) {
    case TransferStatus.queued:
      return t.errorMessage ?? 'Waiting...';
    case TransferStatus.transferring:
      final speed = t.speedBytesPerSec > 0 ? FormatUtils.formatSpeed(t.speedBytesPerSec) : '';
      final eta = t.eta != null ? ' · ${FormatUtils.formatDuration(t.eta!)} left' : '';
      return '${(t.progress * 100).floor()}%${speed.isEmpty ? '' : ' · $speed'}$eta';
    case TransferStatus.paused:
      return t.errorMessage ?? 'Connection lost.';
    case TransferStatus.completed:
      return t.isSender ? 'Delivered and verified' : 'Received and verified';
    case TransferStatus.failed:
      return t.errorMessage ?? 'Failed.';
    case TransferStatus.cancelled:
      return t.errorMessage ?? 'Cancelled.';
  }
}

/// One transfer with progress, speed, ETA and the actions that make sense for its state.
class TransferProgressTile extends StatelessWidget {
  const TransferProgressTile({super.key, required this.item, required this.engine});
  final TransferItem item;
  final TransferEngine engine;

  @override
  Widget build(BuildContext context) {
    final t = item;
    final active = t.status == TransferStatus.transferring || t.status == TransferStatus.queued;
    final color = switch (t.status) {
      TransferStatus.completed => AppColors.success,
      TransferStatus.failed => AppColors.error,
      TransferStatus.paused => AppColors.warning,
      TransferStatus.cancelled => AppColors.mutedText,
      _ => AppColors.limeGreen,
    };
    final direction = t.isSender ? 'To ${t.peerDeviceName}' : 'From ${t.peerDeviceName}';
    return Semantics(
      container: true,
      label: '${t.isSender ? 'Sending' : 'Receiving'} ${t.fileName}, $direction, ${_statusText(t)}',
      child: Container(
        padding: const EdgeInsets.all(Space.m),
        decoration: BoxDecoration(
          color: AppColors.cardBg,
          borderRadius: BorderRadius.circular(Radii.control),
          border: Border.all(color: AppColors.subtleBorder),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(t.isSender ? Icons.north_east_rounded : Icons.south_west_rounded, size: 18, color: color),
            const SizedBox(width: Space.s),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t.fileName, style: TextStyles.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text('$direction · ${FormatUtils.formatBytes(t.fileSizeBytes)}', style: TextStyles.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
              ]),
            ),
            if (t.method != null) ...[
              const SizedBox(width: Space.s),
              MethodBadge(t.method!, compact: true, relayed: t.relayed),
            ],
          ]),
          const SizedBox(height: Space.s),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: t.status == TransferStatus.completed ? 1 : t.progress.clamp(0.0, 1.0)),
            duration: const Duration(milliseconds: 250),
            builder: (_, value, _) => ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: t.status == TransferStatus.queued ? null : value,
                minHeight: 6,
                backgroundColor: AppColors.surfaceElevated,
                color: color,
                semanticsLabel: 'Transfer progress',
                semanticsValue: '${(value * 100).round()}%',
              ),
            ),
          ),
          const SizedBox(height: Space.s),
          Row(children: [
            Expanded(
              child: Text(_statusText(t),
                  style: TextStyles.caption.copyWith(
                      color: t.status == TransferStatus.failed || t.status == TransferStatus.paused ? color : null)),
            ),
            // Resuming is the sender's move; the receiver just waits (or cancels).
            if (t.status == TransferStatus.paused && t.resumable && t.isSender)
              _Action('Resume', Icons.play_arrow_rounded, () => engine.resumeTransfer(t.transferId)),
            if ((t.status == TransferStatus.paused || t.status == TransferStatus.failed) && t.isSender)
              _Action('Retry', Icons.refresh_rounded, () => engine.retryTransfer(t.transferId)),
            if (active || t.status == TransferStatus.paused)
              _Action('Cancel', Icons.close_rounded, () => engine.cancelTransfer(t.transferId)),
            if (!active && t.status != TransferStatus.paused)
              _Action('Dismiss', Icons.done_rounded, () => engine.removeTransfer(t.transferId)),
          ]),
        ]),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action(this.label, this.icon, this.onTap);
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primaryText,
        minimumSize: const Size(minTapTarget, minTapTarget),
        padding: const EdgeInsets.symmetric(horizontal: Space.s),
      ),
      icon: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}
