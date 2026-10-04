import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import '../../../core/constants.dart';
import '../../../data/services/transfer_engine.dart';
import 'statistic_card.dart';

/// Large rounded rectangular header panel for QuickShare Studio.
/// Charcoal surface (#171717), lime green accents, no blue gradients.
/// Displays live device status and 4 metric cards from [TransferEngine].
class DashboardHeader extends StatelessWidget {
  const DashboardHeader({super.key});

  @override
  Widget build(BuildContext context) {
    // Watch the engine so the pairing code, device info and counts update live
    // (e.g. after "Regenerate 6-Digit Code" on the pairing screen).
    TransferEngine? engine;
    try {
      engine = context.watch<TransferEngine>();
    } catch (_) {}

    final completedCount = engine?.historyRecords.where((r) => r.status == 'completed').length ?? 0;
    final stats = [
      StatisticCard(value: '${engine?.pairedDevices.length ?? 0}', label: 'Paired Devices'),
      StatisticCard(value: '${engine?.receivedItems.length ?? 0}', label: 'Received Items'),
      StatisticCard(value: '$completedCount', label: 'Completed'),
      StatisticCard(
        value: engine?.currentPairingSession?.numericCode ?? '---',
        label: 'Pairing Code',
        isAccent: true,
      ),
    ];
    final subtitle = engine == null
        ? 'Local device'
        : '${engine.localDeviceName} · IP: ${engine.localIp} · Port: ${engine.localPort}';
    final isReady = engine == null || !engine.isReceivingPaused;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 680;
        final isVeryNarrow = constraints.maxWidth < 460;
        final isCompact = constraints.maxWidth < 300;

        return Container(
          padding: EdgeInsets.all(isNarrow ? 18.0 : 24.0),
          decoration: BoxDecoration(
            color: AppColors.charcoalSurface, // #171717
            borderRadius: BorderRadius.circular(20.0),
            border: Border.all(color: AppColors.subtleBorder, width: 1.0),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top row: Lightning icon, heading + subtitle, status pill
              if (isVeryNarrow)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildLightningIcon(),
                    const SizedBox(height: 10.0),
                    _buildStatusPill(isReady, compact: true),
                    const SizedBox(height: 14.0),
                    _buildHeadingAndSubtitle(subtitle),
                  ],
                )
              else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildLightningIcon(),
                    const SizedBox(width: 16.0),
                    Expanded(child: _buildHeadingAndSubtitle(subtitle)),
                    const SizedBox(width: 12.0),
                    _buildStatusPill(isReady),
                  ],
                ),

              const SizedBox(height: 24.0),

              // Bottom statistics row / grid (4 cards)
              if (constraints.maxWidth >= 720)
                Row(
                  children: [
                    for (var i = 0; i < stats.length; i++) ...[
                      if (i > 0) const SizedBox(width: 12.0),
                      Expanded(child: stats[i]),
                    ],
                  ],
                )
              else if (isCompact)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < stats.length; i++) ...[
                      if (i > 0) const SizedBox(height: 12.0),
                      stats[i],
                    ],
                  ],
                )
              else
                Column(
                  children: [
                    Row(
                      children: [
                        Expanded(child: stats[0]),
                        const SizedBox(width: 12.0),
                        Expanded(child: stats[1]),
                      ],
                    ),
                    const SizedBox(height: 12.0),
                    Row(
                      children: [
                        Expanded(child: stats[2]),
                        const SizedBox(width: 12.0),
                        Expanded(child: stats[3]),
                      ],
                    ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLightningIcon() {
    return Container(
      width: 44.0,
      height: 44.0,
      decoration: BoxDecoration(
        color: const Color(0x1AD5FF40), // Translucent lime-green
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(
          color: AppColors.primaryAccent.withValues(alpha: 0.35),
          width: 1.0,
        ),
      ),
      child: Icon(
        Icons.bolt_rounded,
        color: AppColors.primaryAccent,
        size: 24.0,
      ),
    );
  }

  Widget _buildHeadingAndSubtitle(String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Own Your Transfers, Shape Your Workflow',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 20.0,
            fontWeight: FontWeight.w700,
            color: AppColors.primaryText,
            letterSpacing: -0.3,
            height: 1.25,
          ),
        ),
        SizedBox(height: 5.0),
        Text(
          subtitle,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 12.5,
            fontWeight: FontWeight.w400,
            color: AppColors.secondaryText,
            height: 1.3,
          ),
        ),
      ],
    );
  }

  Widget _buildStatusPill(bool isReady, {bool compact = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
      decoration: BoxDecoration(
        color: AppColors.dashboardBg,
        borderRadius: BorderRadius.circular(20.0),
        border: Border.all(color: AppColors.subtleBorder, width: 1.0),
      ),
      child: Row(
        mainAxisSize: compact ? MainAxisSize.max : MainAxisSize.min,
        children: [
          Container(
            width: 8.0,
            height: 8.0,
            decoration: BoxDecoration(
              color: AppColors.statusIndicator,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.statusIndicator.withValues(alpha: 0.6),
                  blurRadius: 6.0,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8.0),
          if (compact)
            Expanded(child: _StatusLabel(isReady))
          else
            _StatusLabel(isReady),
        ],
      ),
    );
  }
}

class _StatusLabel extends StatelessWidget {
  final bool isReady;
  const _StatusLabel(this.isReady);

  @override
  Widget build(BuildContext context) {
    return Text(
      isReady ? 'Ready to Share' : 'Receiving Paused',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontFamily: 'Poppins',
        fontSize: 12.0,
        fontWeight: FontWeight.w500,
        color: AppColors.primaryText,
      ),
    );
  }
}
