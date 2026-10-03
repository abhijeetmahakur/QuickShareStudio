import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/services/transfer_engine.dart';
import '../../core/utils/format_utils.dart';
import '../../core/constants.dart';

class DashboardView extends StatelessWidget {
  final Function(int navIndex) onNavigate;

  const DashboardView({
    super.key,
    required this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<TransferEngine>();

    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: Device Identity & Connection Card
            _buildDeviceStatusCard(context, engine),
            const SizedBox(height: 28),

            // Section: Primary Actions (10 Core Modules)
            const Text(
              'PRIMARY ACTIONS & WORKSPACE',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 14),
            _buildActionGrid(context),
            const SizedBox(height: 28),

            // Active Transfers Live Widget (if any)
            if (engine.activeTransfers.isNotEmpty) ...[
              const Text(
                'ACTIVE TRANSFERS',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              _buildActiveTransfersWidget(context, engine),
              const SizedBox(height: 28),
            ],

            // Recent Transfer Activity
            const Text(
              'RECENT FILE EXCHANGES',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            _buildRecentActivityWidget(context, engine),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceStatusCard(BuildContext context, TransferEngine engine) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF4F46E5), Color(0xFF6366F1), Color(0xFF06B6D4)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4F46E5).withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.share, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        engine.localDeviceName,
                        style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'IP: ${engine.localIp} • Port: ${engine.localPort} • Online',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13),
                      ),
                    ],
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFF4ADE80), shape: BoxShape.circle)),
                    const SizedBox(width: 8),
                    const Text('Ready to Share', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Divider(color: Colors.white.withValues(alpha: 0.2), height: 1),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _statItem('Paired Devices', '${engine.pairedDevices.length}'),
              _statItem('Nearby Detected', '${engine.nearbyDiscoveredDevices.length}'),
              _statItem('Completed Transfers', '${engine.historyRecords.length}'),
              _statItem('Pairing Code', engine.currentPairingSession?.numericCode ?? '---'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statItem(String label, String value) {
    return Column(
      children: [
        Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 11)),
      ],
    );
  }

  Widget _buildActionGrid(BuildContext context) {
    final actions = [
      (
        title: 'Create PDF',
        subtitle: 'Multi-page studio & 7 layouts',
        icon: Icons.picture_as_pdf,
        color: const Color(0xFF6366F1),
        navIndex: 1,
      ),
      (
        title: 'Connect Device',
        subtitle: 'QR code & 6-digit code pairing',
        icon: Icons.qr_code_scanner,
        color: const Color(0xFF06B6D4),
        navIndex: 2,
      ),
      (
        title: 'Nearby Devices',
        subtitle: 'Auto-discover on local network',
        icon: Icons.wifi_find,
        color: const Color(0xFF10B981),
        navIndex: 3,
      ),
      (
        title: 'Send Files',
        subtitle: 'Transfer to one or multiple devices',
        icon: Icons.send_rounded,
        color: const Color(0xFF3B82F6),
        navIndex: 4,
      ),
      (
        title: 'Screenshot Sessions',
        subtitle: 'Organize lab screenshots & notes',
        icon: Icons.collections,
        color: const Color(0xFF8B5CF6),
        navIndex: 5,
      ),
      (
        title: 'PDF Tools',
        subtitle: 'Merge, split, compress, OCR',
        icon: Icons.build_circle_outlined,
        color: const Color(0xFFEC4899),
        navIndex: 6,
      ),
      (
        title: 'Universal Clipboard',
        subtitle: 'Smart sync text & images',
        icon: Icons.content_paste_go,
        color: const Color(0xFFF59E0B),
        navIndex: 7,
      ),
      (
        title: 'Transfer History',
        subtitle: 'Inspect logs, verify & resend',
        icon: Icons.history,
        color: const Color(0xFF14B8A6),
        navIndex: 8,
      ),
      (
        title: 'Saved Templates',
        subtitle: 'Lab presets & contact sheets',
        icon: Icons.dashboard_customize_outlined,
        color: const Color(0xFF64748B),
        navIndex: 9,
      ),
      (
        title: 'Settings & Security',
        subtitle: 'App PIN lock, private transfer',
        icon: Icons.lock_outline,
        color: const Color(0xFFE11D48),
        navIndex: 10,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = constraints.maxWidth >= 1000
            ? 5
            : constraints.maxWidth >= 750
                ? 4
                : constraints.maxWidth >= 480
                    ? 3
                    : 2;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            childAspectRatio: 1.35,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
          ),
          itemCount: actions.length,
          itemBuilder: (context, i) {
            final a = actions[i];
            return InkWell(
              onTap: () => onNavigate(a.navIndex),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.15)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.02),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: a.color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(a.icon, color: a.color, size: 20),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      a.title,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    const SizedBox(height: 2),
                    Expanded(
                      child: Text(
                        a.subtitle,
                        style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildActiveTransfersWidget(BuildContext context, TransferEngine engine) {
    return Column(
      children: [
        for (final t in engine.activeTransfers.take(3))
          Card(
            elevation: 0,
            margin: const EdgeInsets.only(bottom: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: Colors.grey.withValues(alpha: 0.15)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  const Icon(Icons.sync, color: AppColors.primary),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t.fileName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        const SizedBox(height: 4),
                        LinearProgressIndicator(
                          value: t.progress,
                          backgroundColor: Colors.grey.withValues(alpha: 0.15),
                          valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    '${(t.progress * 100).round()}%',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildRecentActivityWidget(BuildContext context, TransferEngine engine) {
    if (engine.historyRecords.isEmpty) {
      return Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: Colors.grey.withValues(alpha: 0.15)),
        ),
        child: const Padding(
          padding: EdgeInsets.all(28),
          child: Center(child: Text('No transfers yet. Connect a device or export a PDF to begin.')),
        ),
      );
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.15)),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: engine.historyRecords.take(4).length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, idx) {
          final r = engine.historyRecords[idx];
          return ListTile(
            leading: const Icon(Icons.check_circle, color: AppColors.success),
            title: Text(r.fileName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            subtitle: Text('Sent to ${r.recipientName} • ${FormatUtils.formatBytes(r.fileSize)}'),
            trailing: Text(
              FormatUtils.formatTime(r.timestamp),
              style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
            ),
          );
        },
      ),
    );
  }
}
