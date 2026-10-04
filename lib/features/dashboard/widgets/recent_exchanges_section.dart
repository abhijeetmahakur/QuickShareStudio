import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../core/constants.dart';
import '../../../core/utils/file_utils.dart';
import '../../../core/utils/format_utils.dart';
import '../../../data/models/history_record.dart';
import '../../../data/services/transfer_engine.dart';

/// RECENT FILE EXCHANGES: the latest transfer history records.
class RecentExchangesSection extends StatelessWidget {
  const RecentExchangesSection({super.key});

  static const int maxRows = 5;

  static String _statusLabel(String status) =>
      status.isEmpty ? status : status[0].toUpperCase() + status.substring(1);

  @override
  Widget build(BuildContext context) {
    // Live: newest transfer history records from the engine.
    TransferEngine? engine;
    try {
      engine = context.watch<TransferEngine>();
    } catch (_) {}
    final records = engine?.historyRecords.take(maxRows).toList() ?? const <HistoryRecord>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Heading
        Text(
          'RECENT FILE EXCHANGES',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 12.0,
            fontWeight: FontWeight.w700,
            color: AppColors.secondaryText,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: 14.0),

        // Upper portion of rounded dark card with horizontal scroll safeguard
        LayoutBuilder(
          builder: (context, constraints) {
            final double contentWidth = constraints.maxWidth < 620.0 ? 620.0 : constraints.maxWidth;
            return Container(
              decoration: BoxDecoration(
                color: AppColors.charcoalSurface, // #171717
                borderRadius: BorderRadius.vertical(top: Radius.circular(18.0)),
                border: Border(
                  top: BorderSide(color: AppColors.subtleBorder, width: 1.0),
                  left: BorderSide(color: AppColors.subtleBorder, width: 1.0),
                  right: BorderSide(color: AppColors.subtleBorder, width: 1.0),
                ),
              ),
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(18.0)),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: contentWidth,
                    child: Column(
                      children: [
                    // Header row (table columns)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 14.0),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 4,
                            child: Text(
                              'FILE NAME',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 11.0,
                                fontWeight: FontWeight.w600,
                                color: AppColors.secondaryText,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Text(
                              'DEVICE / RECIPIENT',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 11.0,
                                fontWeight: FontWeight.w600,
                                color: AppColors.secondaryText,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              'SIZE',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 11.0,
                                fontWeight: FontWeight.w600,
                                color: AppColors.secondaryText,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              'STATUS',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 11.0,
                                fontWeight: FontWeight.w600,
                                color: AppColors.secondaryText,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              'TIME',
                              textAlign: TextAlign.end,
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 11.0,
                                fontWeight: FontWeight.w600,
                                color: AppColors.secondaryText,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    Divider(color: AppColors.surfaceElevated, height: 1.0),

                    if (records.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 18.0),
                        child: Text(
                          'No file exchanges yet. Sent and received files will appear here.',
                          style: TextStyle(fontFamily: 'Poppins', fontSize: 12.5, color: AppColors.secondaryText),
                        ),
                      ),
                    for (var i = 0; i < records.length; i++) ...[
                      if (i > 0) Divider(color: AppColors.surfaceElevated, height: 1.0),
                      _buildExchangeRow(
                        icon: FileUtils.isPdfFilename(records[i].fileName)
                            ? Icons.picture_as_pdf_rounded
                            : FileUtils.isImageFilename(records[i].fileName)
                                ? Icons.image_outlined
                                : Icons.insert_drive_file_outlined,
                        iconColor: AppColors.white,
                        fileName: records[i].fileName,
                        device: records[i].isIncoming ? records[i].senderName : records[i].recipientName,
                        size: FormatUtils.formatBytes(records[i].fileSize),
                        status: _statusLabel(records[i].status),
                        time: DateFormat('h:mm a').format(records[i].timestamp),
                      ),
                    ],

                    // Subtle bottom gradient fade to indicate upper portion
                    Container(
                      height: 20.0,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Color(0x00171717),
                            Color(0x55171717),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    ),
      ],
    );
  }

  Widget _buildExchangeRow({
    required IconData icon,
    required Color iconColor,
    required String fileName,
    required String device,
    required String size,
    required String status,
    required String time,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Row(
              children: [
                Icon(icon, size: 16.0, color: iconColor),
                const SizedBox(width: 8.0),
                Expanded(
                  child: Text(
                    fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12.0,
                      fontWeight: FontWeight.w500,
                      color: AppColors.primaryText,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              device,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12.0,
                fontWeight: FontWeight.w400,
                color: AppColors.secondaryText,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              size,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12.0,
                fontWeight: FontWeight.w400,
                color: AppColors.secondaryText,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6.0,
                  height: 6.0,
                  decoration: BoxDecoration(
                    color: AppColors.statusIndicator,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6.0),
                Flexible(
                  child: Text(
                    status,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: AppColors.primaryText,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              time,
              textAlign: TextAlign.end,
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 11.5,
                fontWeight: FontWeight.w400,
                color: Color(0xFF777777),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
