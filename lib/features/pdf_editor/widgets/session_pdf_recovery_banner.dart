import '../../../core/constants.dart';
import 'package:flutter/material.dart';
import '../../../core/services/file_actions.dart';
import 'package:provider/provider.dart';
import '../../../data/services/transfer_engine.dart';
import '../../../core/utils/format_utils.dart';
import 'session_pdf_dialog.dart';

class SessionPdfRecoveryBanner extends StatelessWidget {
  const SessionPdfRecoveryBanner({super.key});

  static Color get panelBg => AppColors.charcoalSurface;
  static Color get cardBg => AppColors.cardBg;
  static Color get limeAccent => AppColors.primaryAccent;
  static Color get softGray => AppColors.secondaryText;
  static Color get primaryWhite => AppColors.primaryText;
  static const Color darkText = AppColors.nearBlack;
  static Color get subtleBorder => AppColors.subtleBorder;
  static Color get subtleBorderLight => AppColors.subtleBorderLight;

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<TransferEngine>();
    final pdf = engine.activeSessionPdf;

    if (pdf == null) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: subtleBorderLight),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: limeAccent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.picture_as_pdf_rounded, color: limeAccent, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      pdf.isRecovered ? 'Recovered Session PDF' : 'Session PDF Ready',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: primaryWhite,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: limeAccent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: limeAccent.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        '${pdf.pageCount} pgs • ${FormatUtils.formatBytes(pdf.fileSizeBytes)}',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: limeAccent,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  pdf.fileName,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: softGray,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: limeAccent,
              foregroundColor: darkText,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              textStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.bold),
            ),
            icon: const Icon(Icons.send_to_mobile_rounded, size: 14, color: darkText),
            label: const Text('Continue Sending'),
            onPressed: () {
              SessionPdfDialog.show(
                context,
                sessionPdf: pdf,
              );
            },
          ),
          const SizedBox(width: 6),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: primaryWhite,
              side: BorderSide(color: subtleBorderLight),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              textStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 12),
            ),
            onPressed: () => FileActions.runWithSnackBar(
              context,
              () => FileActions.save(pdf.bytes, pdf.fileName, directory: engine.downloadDirectory),
            ),
            child: const Text('Save'),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: Icon(Icons.close, size: 18, color: softGray),
            tooltip: 'Discard',
            onPressed: () => engine.clearSessionPdf(),
          ),
        ],
      ),
    );
  }
}
