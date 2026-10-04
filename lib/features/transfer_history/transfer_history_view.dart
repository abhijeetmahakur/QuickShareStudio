import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/services/file_actions.dart';
import 'package:provider/provider.dart';
import '../../core/constants.dart';
import '../../core/utils/format_utils.dart';
import '../../core/widgets/hover_card.dart';
import '../../data/models/history_record.dart';
import '../../data/services/transfer_engine.dart';

class TransferHistoryView extends StatefulWidget {
  const TransferHistoryView({super.key});

  @override
  State<TransferHistoryView> createState() => _TransferHistoryViewState();
}

class _TransferHistoryViewState extends State<TransferHistoryView> {
  String _searchQuery = '';
  String _statusFilter = 'All';
  String _directionFilter = 'All';

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<TransferEngine>();

    final filtered = engine.historyRecords.where((r) {
      final matchesSearch = r.fileName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          r.recipientName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          r.senderName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          (r.sessionName != null && r.sessionName!.toLowerCase().contains(_searchQuery.toLowerCase()));

      final matchesStatus = _statusFilter == 'All' || r.status.toLowerCase() == _statusFilter.toLowerCase();

      final matchesDirection = _directionFilter == 'All' ||
          (_directionFilter == 'Sent' && !r.isIncoming) ||
          (_directionFilter == 'Received' && r.isIncoming);

      return matchesSearch && matchesStatus && matchesDirection;
    }).toList();

    final sentCount = engine.historyRecords.where((r) => !r.isIncoming).length;
    final receivedCount = engine.historyRecords.where((r) => r.isIncoming).length;

    return Scaffold(
      backgroundColor: AppColors.dashboardBg,
      appBar: AppBar(
        backgroundColor: AppColors.dashboardBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'HISTORY',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
            color: AppColors.primaryText,
          ),
        ),
        actions: [
          if (engine.historyRecords.isNotEmpty)
            IconButton(
              icon: Icon(Icons.delete_sweep_outlined, color: AppColors.secondaryText),
              tooltip: 'Clear History Log',
              onPressed: () => _confirmClearHistory(context, engine),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header stats
            Row(
              children: [
                _buildStatBadge(
                  label: 'Total Transfers',
                  value: '${engine.historyRecords.length}',
                  icon: Icons.swap_horiz_rounded,
                  color: AppColors.primaryAccent,
                ),
                const SizedBox(width: 12),
                _buildStatBadge(
                  label: 'Sent',
                  value: '$sentCount',
                  icon: Icons.arrow_upward_rounded,
                  color: AppColors.primaryAccent,
                ),
                const SizedBox(width: 12),
                _buildStatBadge(
                  label: 'Received',
                  value: '$receivedCount',
                  icon: Icons.arrow_downward_rounded,
                  color: AppColors.softGray,
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Search & Filter Controls
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 300,
                  child: TextField(
                    cursorColor: AppColors.primaryAccent,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 13,
                      color: AppColors.primaryText,
                    ),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: AppColors.charcoalSurface,
                      prefixIcon: Icon(Icons.search, size: 20, color: AppColors.secondaryText),
                      hintText: 'Search file, device, session...',
                      hintStyle: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12.5,
                        color: AppColors.secondaryText,
                      ),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: AppColors.subtleBorder),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: AppColors.primaryAccent, width: 1.5),
                      ),
                    ),
                    onChanged: (val) => setState(() => _searchQuery = val),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.charcoalSurface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.subtleBorder),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _directionFilter,
                      dropdownColor: AppColors.cardBg,
                      icon: Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.primaryAccent, size: 18),
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: AppColors.primaryText,
                      ),
                      items: ['All', 'Sent', 'Received']
                          .map((d) => DropdownMenuItem(value: d, child: Text('Direction: $d')))
                          .toList(),
                      onChanged: (val) => setState(() => _directionFilter = val!),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.charcoalSurface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.subtleBorder),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _statusFilter,
                      dropdownColor: AppColors.cardBg,
                      icon: Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.primaryAccent, size: 18),
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: AppColors.primaryText,
                      ),
                      items: ['All', 'Completed', 'Failed', 'Cancelled']
                          .map((s) => DropdownMenuItem(value: s, child: Text('Status: $s')))
                          .toList(),
                      onChanged: (val) => setState(() => _statusFilter = val!),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            if (filtered.isEmpty)
              Container(
                decoration: BoxDecoration(
                  color: AppColors.cardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.subtleBorder),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(40),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(
                          Icons.history_toggle_off_rounded,
                          size: 48,
                          color: AppColors.secondaryText.withValues(alpha: 0.5),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'No history records matching criteria.',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            color: AppColors.primaryText,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          engine.historyRecords.isEmpty
                              ? 'Transfers sent or received will appear here automatically.'
                              : 'Try changing your search term or filter options.',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            color: AppColors.secondaryText,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: filtered.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, idx) {
                  final record = filtered[idx];

                  return HoverCard(
                    borderRadius: BorderRadius.circular(14),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    liftOffset: 2.0,
                    scale: 1.01,
                    color: AppColors.cardBg,
                    borderColor: AppColors.subtleBorder,
                    hoverBorderColor: AppColors.primaryAccent,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Direction Avatar
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: record.isIncoming
                              ? AppColors.white.withValues(alpha: 0.10)
                              : AppColors.primaryAccent.withValues(alpha: 0.15),
                          child: Icon(
                            record.isIncoming ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                            color: record.isIncoming ? AppColors.white : AppColors.primaryAccent,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 14),

                        // File info & Details
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      record.fileName,
                                      style: TextStyle(
                                        fontFamily: 'Poppins',
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                        color: AppColors.primaryText,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  // Direction tag
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: record.isIncoming
                                          ? AppColors.white.withValues(alpha: 0.10)
                                          : AppColors.primaryAccent.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      record.isIncoming ? 'RECEIVED' : 'SENT',
                                      style: TextStyle(
                                        fontFamily: 'Poppins',
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w700,
                                        color: record.isIncoming ? AppColors.white : AppColors.primaryAccent,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  // Downloadable tag
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppColors.primaryAccent.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: AppColors.primaryAccent.withValues(alpha: 0.25)),
                                    ),
                                    child: Text(
                                      'DOWNLOADABLE',
                                      style: TextStyle(
                                        fontFamily: 'Poppins',
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.primaryAccent,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 5),
                              Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(
                                    FormatUtils.formatBytes(record.fileSize),
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.primaryText,
                                    ),
                                  ),
                                  Text('•', style: TextStyle(color: AppColors.secondaryText)),
                                  Text(
                                    record.isIncoming
                                        ? 'From: ${record.senderName.isNotEmpty ? record.senderName : "Remote Device"}'
                                        : 'To: ${record.recipientName.isNotEmpty ? record.recipientName : "Paired Device"}',
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 11.5,
                                      color: AppColors.secondaryText,
                                    ),
                                  ),
                                  Text('•', style: TextStyle(color: AppColors.secondaryText)),
                                  Text(
                                    FormatUtils.formatDateTime(record.timestamp),
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 11,
                                      color: AppColors.secondaryText,
                                    ),
                                  ),
                                  if (record.sessionName != null && record.sessionName!.isNotEmpty) ...[
                                    Text('•', style: TextStyle(color: AppColors.secondaryText)),
                                    Text(
                                      'Session: ${record.sessionName}',
                                      style: TextStyle(
                                        fontFamily: 'Poppins',
                                        fontSize: 11,
                                        color: AppColors.primaryAccent,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),

                        // Status badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: record.status == 'completed'
                                ? AppColors.primaryAccent.withValues(alpha: 0.12)
                                : AppColors.error.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: record.status == 'completed'
                                  ? AppColors.primaryAccent.withValues(alpha: 0.35)
                                  : AppColors.error.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Text(
                            record.status.toUpperCase(),
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: record.status == 'completed' ? AppColors.primaryAccent : AppColors.error,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),

                        // Action buttons
                        IconButton(
                          icon: Icon(Icons.info_outline_rounded, size: 19, color: AppColors.secondaryText),
                          tooltip: 'View Transfer Details',
                          onPressed: () => _showRecordDetails(context, record, true),
                        ),
                        IconButton(
                          icon: Icon(Icons.download_rounded, size: 19, color: AppColors.primaryAccent),
                          tooltip: 'Download Recorded File',
                          onPressed: () => _openOrDownloadFile(context, engine, record),
                        ),
                        IconButton(
                          icon: Icon(Icons.replay_rounded, size: 19, color: AppColors.softGray),
                          tooltip: 'Resend to Paired Device',
                          onPressed: () => _resendRecord(context, engine, record),
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatBadge({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.subtleBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 10,
                  color: AppColors.secondaryText,
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showRecordDetails(BuildContext context, HistoryRecord record, bool isAvailable) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.charcoalSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: AppColors.subtleBorder),
        ),
        title: Row(
          children: [
            Icon(
              record.isIncoming ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
              color: record.isIncoming ? AppColors.white : AppColors.primaryAccent,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Transfer Details',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                  color: AppColors.primaryText,
                ),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDetailRow('File Name', record.fileName),
                _buildDetailRow('Direction', record.isIncoming ? 'Incoming (Received)' : 'Outgoing (Sent)'),
                _buildDetailRow('Status', record.status.toUpperCase()),
                _buildDetailRow('File Size', '${FormatUtils.formatBytes(record.fileSize)} (${record.fileSize} bytes)'),
                _buildDetailRow('Sender', record.senderName.isNotEmpty ? record.senderName : 'Local App'),
                _buildDetailRow('Recipient', record.recipientName.isNotEmpty ? record.recipientName : 'Remote Device'),
                _buildDetailRow('Date & Time', record.timestamp.toLocal().toString()),
                _buildDetailRow('Connection', record.connectionType),
                if (record.sessionName != null && record.sessionName!.isNotEmpty)
                  _buildDetailRow('Session', record.sessionName!),
                if (record.pageCount != null)
                  _buildDetailRow('Pages', '${record.pageCount}'),
                _buildDetailRow(
                  'Cache Status',
                  isAvailable ? 'Available locally for download/resend' : 'Original file purged (metadata only)',
                  highlightColor: isAvailable ? AppColors.primaryAccent : Colors.amber,
                ),
                const SizedBox(height: 12),
                Text(
                  'SHA-256 Verification Hash:',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.secondaryText,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.dashboardBg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.subtleBorder),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: SelectableText(
                          record.sha256.isNotEmpty ? record.sha256 : 'N/A',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            color: AppColors.primaryAccent,
                          ),
                        ),
                      ),
                      if (record.sha256.isNotEmpty)
                        IconButton(
                          icon: Icon(Icons.copy, size: 16, color: AppColors.secondaryText),
                          tooltip: 'Copy Hash',
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: record.sha256));
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                backgroundColor: AppColors.charcoalSurface,
                                content: Text('SHA-256 hash copied to clipboard!'),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryAccent,
              foregroundColor: AppColors.nearBlack,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {Color? highlightColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12,
                color: AppColors.secondaryText,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: highlightColor ?? AppColors.primaryText,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openOrDownloadFile(BuildContext context, TransferEngine engine, HistoryRecord record) async {
    final bytes = engine.getFileBytes(record);
    if (bytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.charcoalSurface,
          content: Text('Original file contents are no longer available in cache.'),
        ),
      );
      return;
    }

    try {
      final message = await FileActions.save(bytes, record.fileName, directory: engine.downloadDirectory);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.charcoalSurface,
            content: Text(message),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.errorContainer,
            content: Text('Could not open file: $e'),
          ),
        );
      }
    }
  }

  void _resendRecord(BuildContext context, TransferEngine engine, HistoryRecord record) async {
    if (engine.pairedDevices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.charcoalSurface,
          content: Text('No paired device available. Please pair a device first.'),
        ),
      );
      return;
    }

    try {
      await engine.resendRecord(record);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.charcoalSurface,
            content: Text('Resending "${record.fileName}" to ${engine.pairedDevices.first.name}...'),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.errorContainer,
            content: Text('Failed to resend: $e'),
          ),
        );
      }
    }
  }

  void _confirmClearHistory(BuildContext context, TransferEngine engine) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.charcoalSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: AppColors.subtleBorder),
        ),
        title: Text(
          'Clear Transfer History?',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w700,
            color: AppColors.primaryText,
          ),
        ),
        content: Text(
          'This will clear all local transfer log entries. Original file contents and active sessions will not be deleted.',
          style: TextStyle(
            fontFamily: 'Poppins',
            color: AppColors.secondaryText,
          ),
        ),
        actions: [
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primaryText,
              side: BorderSide(color: AppColors.subtleBorderLight),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(fontFamily: 'Poppins')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: AppColors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              engine.clearHistory();
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: AppColors.charcoalSurface,
                  content: Text('Transfer history cleared.'),
                ),
              );
            },
            child: const Text('Clear All', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}
