import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/services/transfer_engine.dart';
import '../../core/utils/format_utils.dart';
import '../../core/constants.dart';
import '../core/widgets/hover_card.dart';

class DashboardView extends StatefulWidget {
  final Function(int navIndex) onNavigate;

  const DashboardView({
    super.key,
    required this.onNavigate,
  });

  @override
  State<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<DashboardView> {
  final TextEditingController _deviceNameController = TextEditingController();
  bool _isEditingName = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final engine = context.read<TransferEngine>();
        _deviceNameController.text = engine.localDeviceName;
      }
    });
  }

  @override
  void dispose() {
    _deviceNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<TransferEngine>();

    if (!_isEditingName && _deviceNameController.text != engine.localDeviceName) {
      _deviceNameController.text = engine.localDeviceName;
    }

    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: Device Identity & Connection Card
            _buildDeviceStatusCard(context, engine),
            const SizedBox(height: 20),

            // Section: Name Your Device (Requirement 6)
            _buildNameYourDeviceCard(context, engine),
            const SizedBox(height: 28),

            // Section: Primary Actions (Core Modules)
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
      decoration: BoxDecoration(
        gradient: AppColors.heroGlassGradient,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppColors.white.withValues(alpha: 0.18), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: AppColors.dashboardBg.withValues(alpha: 0.45),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.25),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.white.withValues(alpha: 0.22)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Icon(Icons.bolt, color: AppColors.white, size: 26),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            engine.localDeviceName,
                            style: TextStyle(
                              color: AppColors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.4,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'IP: ${engine.localIp} • Port: ${engine.localPort} • Session Code: ${engine.currentPairingSession?.numericCode ?? "---"}',
                            style: TextStyle(color: AppColors.secondaryText, fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: AppColors.white.withValues(alpha: 0.2)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Color(0xFF34D399),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Color(0xFF34D399),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text('Ready to Share', style: TextStyle(color: AppColors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          // Stats row with 4 frosted navy glass rounded square cards
          Row(
            children: [
              Expanded(child: _statItem('Paired Devices', '${engine.pairedDevices.length}')),
              const SizedBox(width: 10),
              Expanded(child: _statItem('Network Status', engine.isReceivingPaused ? 'Paused' : 'Active')),
              const SizedBox(width: 10),
              Expanded(child: _statItem('History Records', '${engine.historyRecords.length}')),
              const SizedBox(width: 10),
              Expanded(child: _statItem('Pairing Code', engine.currentPairingSession?.numericCode ?? '---')),
            ],
          ),
        ],
      ),
    );
  }

  // Name Your Device Card (Requirement 6)
  Widget _buildNameYourDeviceCard(BuildContext context, TransferEngine engine) {
    return HoverCard(
      borderRadius: BorderRadius.circular(20),
      padding: const EdgeInsets.all(20),
      liftOffset: 2.0,
      scale: 1.008,
      color: AppColors.cardBg,
      borderColor: AppColors.white.withValues(alpha: 0.14),
      hoverBorderColor: AppColors.primaryAccent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.edit_note, color: AppColors.primaryAccent, size: 22),
                  SizedBox(width: 8),
                  Text(
                    'Name Your Device',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.white),
                  ),
                ],
              ),
              if (engine.isCustomDeviceNameSaved)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle, color: Color(0xFF10B981), size: 14),
                      SizedBox(width: 4),
                      Text('Saved to Session', style: TextStyle(color: Color(0xFF10B981), fontSize: 11, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Set a friendly name (e.g. "Abhijeet\'s Laptop" or "Workstation Lab") displayed to paired devices.',
            style: TextStyle(color: AppColors.secondaryText, fontSize: 12),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _deviceNameController,
                  style: TextStyle(color: AppColors.white, fontSize: 14, fontWeight: FontWeight.w600),
                  decoration: InputDecoration(
                    hintText: 'Enter custom device name...',
                    hintStyle: TextStyle(color: AppColors.white.withValues(alpha: 0.38)),
                    prefixIcon: Icon(Icons.laptop_chromebook, color: AppColors.primaryAccent, size: 20),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: AppColors.white.withValues(alpha: 0.15)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: AppColors.white.withValues(alpha: 0.15)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: AppColors.primaryAccent, width: 1.5),
                    ),
                    filled: true,
                    fillColor: AppColors.cardBg,
                  ),
                  onChanged: (val) {
                    setState(() => _isEditingName = true);
                  },
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.nearBlack,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.save, size: 16),
                label: const Text('Save', style: TextStyle(fontWeight: FontWeight.bold)),
                onPressed: () async {
                  final name = _deviceNameController.text.trim();
                  if (name.isNotEmpty) {
                    await engine.setCustomDeviceName(name);
                    setState(() => _isEditingName = false);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Device name updated to "$name" and persisted across sessions.')),
                      );
                    }
                  }
                },
              ),
              if (engine.isCustomDeviceNameSaved) ...[
                const SizedBox(width: 8),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.secondaryText,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  ),
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Reset'),
                  onPressed: () async {
                    await engine.resetCustomDeviceName();
                    setState(() {
                      _isEditingName = false;
                      _deviceNameController.text = engine.localDeviceName;
                    });
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Device name reset to default.')),
                      );
                    }
                  },
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _statItem(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.cardBg.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.white.withValues(alpha: 0.12), width: 1.0),
      ),
      child: Column(
        children: [
          Text(value, style: TextStyle(color: AppColors.primaryAccent, fontWeight: FontWeight.w900, fontSize: 17)),
          const SizedBox(height: 3),
          Text(label, style: TextStyle(color: AppColors.secondaryText, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildActionGrid(BuildContext context) {
    final actions = [
      (
        title: 'PDF Studio',
        subtitle: 'Arrange screenshots into structured multi-page PDF',
        icon: Icons.picture_as_pdf,
        color: const Color(0xFFEF4444),
        navIndex: 1,
      ),
      (
        title: 'Device Pairing',
        subtitle: 'Session-based 6-digit numeric & QR pairing',
        icon: Icons.qr_code_2,
        color: const Color(0xFF10B981),
        navIndex: 2,
      ),
      (
        title: 'Send Files',
        subtitle: 'Direct transfer to paired devices',
        icon: Icons.send_rounded,
        color: AppColors.primaryAccent,
        navIndex: 3,
      ),
      (
        title: 'Received Items',
        subtitle: 'View & download verified inbound files',
        icon: Icons.move_to_inbox,
        color: const Color(0xFF0D9488),
        navIndex: 4,
      ),
      (
        title: 'Screenshot Sessions',
        subtitle: 'Session manager with persistent workspaces',
        icon: Icons.collections,
        color: const Color(0xFF8B5CF6),
        navIndex: 5,
      ),
      (
        title: 'PDF Tools',
        subtitle: 'Universal Converter, merge, split, compress',
        icon: Icons.build_circle_outlined,
        color: const Color(0xFFEC4899),
        navIndex: 6,
      ),
      (
        title: 'Universal Clipboard',
        subtitle: 'Instant sync text across devices',
        icon: Icons.content_paste_go,
        color: const Color(0xFFF59E0B),
        navIndex: 7,
      ),
      (
        title: 'HISTORY',
        subtitle: 'Persistent log of sent & received files',
        icon: Icons.history,
        color: const Color(0xFF14B8A6),
        navIndex: 8,
      ),
      (
        title: 'Settings & Security',
        subtitle: 'Download paths, auto-save & security mode',
        icon: Icons.lock_outline,
        color: const Color(0xFFE11D48),
        navIndex: 9,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = constraints.maxWidth >= 1000
            ? 5
            : constraints.maxWidth >= 750
                ? 3
                : constraints.maxWidth >= 480
                    ? 2
                    : 1;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            childAspectRatio: 1.45,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
          ),
          itemCount: actions.length,
          itemBuilder: (context, i) {
            final a = actions[i];
            return HoverCard(
              onTap: () => widget.onNavigate(a.navIndex),
              borderRadius: BorderRadius.circular(18),
              padding: const EdgeInsets.all(14),
              liftOffset: 3.5,
              scale: 1.025,
              color: AppColors.cardBg,
              hoverColor: AppColors.surfaceElevated,
              borderColor: AppColors.white.withValues(alpha: 0.12),
              hoverBorderColor: AppColors.primaryAccent,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: a.color.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(a.icon, color: a.color, size: 20),
                      ),
                      Icon(Icons.arrow_forward, size: 14, color: AppColors.white.withValues(alpha: 0.3)),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        a.title,
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: AppColors.white),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        a.subtitle,
                        style: TextStyle(color: AppColors.secondaryText, fontSize: 10.5),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildActiveTransfersWidget(BuildContext context, TransferEngine engine) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: engine.activeTransfers.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final t = engine.activeTransfers[index];
        return HoverCard(
          borderRadius: BorderRadius.circular(16),
          padding: const EdgeInsets.all(16),
          liftOffset: 2.0,
          scale: 1.01,
          color: AppColors.cardBg,
          borderColor: AppColors.white.withValues(alpha: 0.12),
          hoverBorderColor: AppColors.primaryAccent,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.sync, color: AppColors.primaryAccent, size: 18),
                      const SizedBox(width: 8),
                      Text(t.fileName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    ],
                  ),
                  Text('${(t.progress * 100).round()}%', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryAccent)),
                ],
              ),
              const SizedBox(height: 10),
              LinearProgressIndicator(
                value: t.progress,
                backgroundColor: AppColors.white.withValues(alpha: 0.08),
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.primaryAccent),
                minHeight: 6,
                borderRadius: BorderRadius.circular(4),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Peer: ${t.peerDeviceName}', style: TextStyle(fontSize: 11, color: AppColors.secondaryText)),
                  Text(
                    '${FormatUtils.formatBytes((t.fileSizeBytes * t.progress).round())} / ${FormatUtils.formatBytes(t.fileSizeBytes)}',
                    style: TextStyle(fontSize: 11, color: AppColors.secondaryText),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRecentActivityWidget(BuildContext context, TransferEngine engine) {
    if (engine.historyRecords.isEmpty) {
      return Card(
        elevation: 0,
        color: AppColors.cardBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: AppColors.white.withValues(alpha: 0.12)),
        ),
        child: Padding(
          padding: EdgeInsets.all(28),
          child: Center(
            child: Column(
              children: [
                Icon(Icons.history_toggle_off, size: 36, color: AppColors.secondaryText),
                SizedBox(height: 8),
                Text('No recent transfers recorded. Real file transfers will appear here.', style: TextStyle(color: AppColors.secondaryText, fontSize: 12)),
              ],
            ),
          ),
        ),
      );
    }

    final recent = engine.historyRecords.take(5).toList();
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: recent.length,
      separatorBuilder: (_, _) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final record = recent[index];
        final isCompleted = record.status.toLowerCase() == 'completed';
        return HoverCard(
          borderRadius: BorderRadius.circular(12),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          liftOffset: 1.5,
          scale: 1.008,
          color: AppColors.cardBg,
          borderColor: AppColors.white.withValues(alpha: 0.08),
          hoverBorderColor: AppColors.primaryAccent,
          child: Row(
            children: [
              Icon(
                record.isIncoming ? Icons.arrow_downward : Icons.arrow_upward,
                color: isCompleted ? const Color(0xFF10B981) : Colors.redAccent,
                size: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      record.fileName,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${record.isIncoming ? "From" : "To"}: ${record.isIncoming ? record.senderName : record.recipientName} • ${FormatUtils.formatBytes(record.fileSize)}',
                      style: TextStyle(fontSize: 10.5, color: AppColors.secondaryText),
                    ),
                  ],
                ),
              ),
              Text(
                FormatUtils.formatDateTime(record.timestamp),
                style: TextStyle(fontSize: 10.5, color: AppColors.secondaryText),
              ),
            ],
          ),
        );
      },
    );
  }
}
