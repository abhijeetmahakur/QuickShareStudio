import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import '../../../data/models/pdf_project.dart';
import '../services/pdf_export_service.dart';
import '../../../core/utils/file_utils.dart';
import '../../../core/utils/format_utils.dart';
import '../../../core/constants.dart';

class ExportDialog extends StatefulWidget {
  final PdfProject project;
  final Function(Uint8List pdfBytes, String fileName)? onSendToDevice;

  const ExportDialog({
    super.key,
    required this.project,
    this.onSendToDevice,
  });

  @override
  State<ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<ExportDialog> {
  late TextEditingController _nameController;
  bool _includeOcr = false;
  bool _isExporting = false;
  Uint8List? _generatedBytes;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    final smartName = FileUtils.generateSmartPdfName(widget.project.title);
    _nameController = TextEditingController(text: smartName);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _renderPdf() async {
    setState(() {
      _isExporting = true;
      _statusMessage = 'Rendering vector PDF pages...';
    });

    try {
      final bytes = await PdfExportService.generatePdf(
        project: widget.project,
        includeOcrLayer: _includeOcr,
      );

      setState(() {
        _generatedBytes = bytes;
        _isExporting = false;
        _statusMessage = 'PDF successfully generated (${FormatUtils.formatBytes(bytes.length)})';
      });
    } catch (e) {
      setState(() {
        _isExporting = false;
        _statusMessage = 'Error generating PDF: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final sanitizedName = FileUtils.sanitizeFilename(_nameController.text);

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.picture_as_pdf, color: AppColors.primary),
          SizedBox(width: 8),
          Text('Export & Share PDF Document'),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Document Filename',
                hintText: 'e.g. Java_Practical_01.pdf',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.description_outlined),
              ),
            ),
            const SizedBox(height: 12),

            // Summary info
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _infoItem('Pages', '${widget.project.pages.length}'),
                  _infoItem('Total Images', '${widget.project.totalImageCount}'),
                  _infoItem(
                    'Paper Size',
                    widget.project.pages.isNotEmpty
                        ? widget.project.pages.first.geometry.paperSize.name.toUpperCase()
                        : 'A4',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // OCR Searchable Text Layer Option
            SwitchListTile(
              title: const Text('Add Searchable OCR Text Layer', style: TextStyle(fontSize: 13)),
              subtitle: const Text('Embeds invisible searchable text into the PDF', style: TextStyle(fontSize: 11)),
              value: _includeOcr,
              onChanged: (val) {
                setState(() {
                  _includeOcr = val;
                  _generatedBytes = null; // Re-render needed
                });
              },
              contentPadding: EdgeInsets.zero,
            ),

            if (_isExporting) ...[
              const SizedBox(height: 16),
              const Center(child: CircularProgressIndicator()),
              const SizedBox(height: 8),
              Center(child: Text(_statusMessage ?? 'Processing...', style: const TextStyle(fontSize: 12))),
            ] else if (_statusMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                _statusMessage!,
                style: TextStyle(
                  fontSize: 12,
                  color: _generatedBytes != null ? AppColors.success : AppColors.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        ElevatedButton.icon(
          icon: const Icon(Icons.print_outlined, size: 18),
          label: const Text('Print / Preview'),
          onPressed: () async {
            if (_generatedBytes == null) {
              await _renderPdf();
            }
            if (_generatedBytes != null) {
              await Printing.layoutPdf(
                onLayout: (format) async => _generatedBytes!,
                name: sanitizedName,
              );
            }
          },
        ),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
          icon: const Icon(Icons.share, size: 18),
          label: const Text('Save / Share File'),
          onPressed: () async {
            if (_generatedBytes == null) {
              await _renderPdf();
            }
            if (_generatedBytes != null) {
              await Printing.sharePdf(
                bytes: _generatedBytes!,
                filename: sanitizedName.endsWith('.pdf') ? sanitizedName : '$sanitizedName.pdf',
              );
            }
          },
        ),
        if (widget.onSendToDevice != null)
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.secondary, foregroundColor: Colors.white),
            icon: const Icon(Icons.send_to_mobile, size: 18),
            label: const Text('Send to Device'),
            onPressed: () async {
              if (_generatedBytes == null) {
                await _renderPdf();
              }
              if (_generatedBytes != null) {
                widget.onSendToDevice!(_generatedBytes!, sanitizedName);
                if (context.mounted) Navigator.pop(context);
              }
            },
          ),
      ],
    );
  }

  Widget _infoItem(String label, String value) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }
}
