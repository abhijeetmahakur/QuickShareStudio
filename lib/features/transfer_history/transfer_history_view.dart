import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/services/transfer_engine.dart';
import '../../core/utils/format_utils.dart';
import '../../core/constants.dart';

class TransferHistoryView extends StatefulWidget {
  const TransferHistoryView({super.key});

  @override
  State<TransferHistoryView> createState() => _TransferHistoryViewState();
}

class _TransferHistoryViewState extends State<TransferHistoryView> {
  String _searchQuery = '';
  String _statusFilter = 'All';

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<TransferEngine>();

    final filtered = engine.historyRecords.where((r) {
      final matchesSearch = r.fileName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          r.recipientName.toLowerCase().contains(_searchQuery.toLowerCase());
      final matchesFilter = _statusFilter == 'All' || r.status.toLowerCase() == _statusFilter.toLowerCase();
      return matchesSearch && matchesFilter;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transfer History & Log', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          if (engine.historyRecords.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: 'Clear History',
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Clear Transfer History?'),
                    content: const Text('This will delete all local transfer logs. Original files remain untouched.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                        onPressed: () {
                          engine.clearHistory();
                          Navigator.pop(ctx);
                        },
                        child: const Text('Clear All'),
                      ),
                    ],
                  ),
                );
              },
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Search & Filter Controls
            Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search by file name or device...',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (val) => setState(() => _searchQuery = val),
                  ),
                ),
                const SizedBox(width: 16),
                DropdownButton<String>(
                  value: _statusFilter,
                  items: ['All', 'Completed', 'Failed', 'Cancelled']
                      .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                      .toList(),
                  onChanged: (val) => setState(() => _statusFilter = val!),
                ),
              ],
            ),
            const SizedBox(height: 20),

            if (filtered.isEmpty)
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(color: Colors.grey.withValues(alpha: 0.15)),
                ),
                child: const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(Icons.history_toggle_off, size: 40, color: Colors.grey),
                        SizedBox(height: 12),
                        Text('No transfer history matching criteria.'),
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
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, idx) {
                  final record = filtered[idx];
                  return Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(color: Colors.grey.withValues(alpha: 0.15)),
                    ),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: record.status == 'completed'
                            ? AppColors.success.withValues(alpha: 0.1)
                            : AppColors.error.withValues(alpha: 0.1),
                        child: Icon(
                          record.isIncoming ? Icons.arrow_downward : Icons.arrow_upward,
                          color: record.status == 'completed' ? AppColors.success : AppColors.error,
                        ),
                      ),
                      title: Text(record.fileName, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(
                        'To: ${record.recipientName} • ${FormatUtils.formatBytes(record.fileSize)} • ${FormatUtils.formatDateTime(record.timestamp)}',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: record.status == 'completed'
                                  ? AppColors.success.withValues(alpha: 0.1)
                                  : AppColors.error.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              record.status.toUpperCase(),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: record.status == 'completed' ? AppColors.success : AppColors.error,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.replay, size: 18),
                            tooltip: 'Resend',
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Resending ${record.fileName}...')),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
