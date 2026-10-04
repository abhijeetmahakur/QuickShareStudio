import '../../../core/constants.dart';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/services/file_actions.dart';
import '../../../data/models/pdf_project.dart';
import '../../../data/models/session_pdf.dart';
import '../../../data/services/transfer_engine.dart';
import 'session_pdf_dialog.dart';
import '../services/pdf_export_service.dart';
import '../../../core/utils/file_utils.dart';
import '../../../core/utils/format_utils.dart';

class ExportDialog extends StatefulWidget {
  final PdfProject project;
  final String? initialFileName;
  final Function(String fileName)? onFileNameChanged;
  final Function(Uint8List pdfBytes, String fileName)? onSendToDevice;

  // Official Dark Lime Design Palette Tokens
  static Color get dialogBg => AppColors.charcoalSurface;
  static Color get cardBg => AppColors.cardBg;
  static Color get limeAccent => AppColors.primaryAccent;
  static Color get softGray => AppColors.secondaryText;
  static Color get primaryWhite => AppColors.primaryText;
  static const Color darkText = AppColors.nearBlack;
  static Color get subtleBorder => AppColors.subtleBorder;
  static Color get subtleBorderLight => AppColors.subtleBorderLight;

  const ExportDialog({
    super.key,
    required this.project,
    this.initialFileName,
    this.onFileNameChanged,
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
  bool _isSuccessStatus = false;
  bool _nameSavedFeedback = false;
  Timer? _feedbackTimer;
  String? _validationError;

  @override
  void initState() {
    super.initState();
    final engine = context.read<TransferEngine>();

    // Choose candidate filename
    String candidate = 'QuickShare_Document.pdf';
    final saved = engine.savedDocumentName;
    if (widget.initialFileName != null && widget.initialFileName!.trim().isNotEmpty) {
      candidate = widget.initialFileName!;
    } else if (saved != null && saved.isNotEmpty) {
      candidate = saved;
    } else if (widget.project.title.isNotEmpty && widget.project.title != 'Untitled_Lab_Document') {
      candidate = widget.project.title;
    }

    final formattedName = FileUtils.formatPdfFilename(candidate);
    _nameController = TextEditingController(text: formattedName);
  }

  @override
  void dispose() {
    _feedbackTimer?.cancel();
    _nameController.dispose();
    super.dispose();
  }

  String _validateAndGetFileName() {
    final raw = _nameController.text.trim();
    if (raw.isEmpty) {
      setState(() {
        _validationError = 'Filename cannot be empty.';
      });
      return 'QuickShare_Document.pdf';
    }
    final sanitized = FileUtils.formatPdfFilename(raw);
    setState(() {
      _validationError = null;
      _nameController.text = sanitized;
    });
    return sanitized;
  }

  void _saveDocumentName(TransferEngine engine) {
    final sanitized = _validateAndGetFileName();
    engine.saveDocumentName(sanitized);
    widget.onFileNameChanged?.call(sanitized);

    setState(() {
      _nameSavedFeedback = true;
      _statusMessage = 'Filename saved as "$sanitized"';
      _isSuccessStatus = true;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Document name saved as "$sanitized"',
          style: TextStyle(fontFamily: 'Poppins', color: AppColors.white),
        ),
        backgroundColor: ExportDialog.cardBg,
        duration: const Duration(seconds: 2),
      ),
    );

    _feedbackTimer?.cancel();
    _feedbackTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() => _nameSavedFeedback = false);
      }
    });
  }

  Future<Uint8List?> _renderPdf() async {
    setState(() {
      _isExporting = true;
      _statusMessage = 'Rendering vector PDF pages...';
      _isSuccessStatus = false;
    });

    try {
      final bytes = await PdfExportService.generatePdf(
        project: widget.project,
        includeOcrLayer: _includeOcr,
      );

      setState(() {
        _generatedBytes = bytes;
        _isExporting = false;
        _statusMessage = 'PDF generated successfully (${FormatUtils.formatBytes(bytes.length)})';
        _isSuccessStatus = true;
      });
      return bytes;
    } catch (e) {
      setState(() {
        _isExporting = false;
        _statusMessage = 'Error generating PDF: $e';
        _isSuccessStatus = false;
      });
      return null;
    }
  }

  /// Renders the PDF if needed, then runs [action] and reports its outcome in the status box.
  Future<void> _runFileAction(
    TransferEngine engine,
    Future<String> Function(Uint8List bytes, String fileName) action,
  ) async {
    final validName = _validateAndGetFileName();
    engine.saveDocumentName(validName);
    widget.onFileNameChanged?.call(validName);

    var bytes = _generatedBytes;
    bytes ??= await _renderPdf();
    if (bytes == null) return;

    try {
      final message = await action(bytes, validName);
      if (!mounted) return;
      setState(() {
        _statusMessage = message;
        _isSuccessStatus = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Failed: $e';
        _isSuccessStatus = false;
      });
    }
  }

  Future<void> _savePdfToDisk(TransferEngine engine) => _runFileAction(
        engine,
        (bytes, name) => FileActions.save(bytes, name, directory: engine.downloadDirectory),
      );

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<TransferEngine>();

    return AlertDialog(
      backgroundColor: ExportDialog.dialogBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: ExportDialog.subtleBorderLight),
      ),
      title: Row(
        children: [
          Icon(Icons.picture_as_pdf_rounded, color: ExportDialog.limeAccent, size: 22),
          SizedBox(width: 10),
          Text(
            'Export & Share PDF Document',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.bold,
              fontSize: 17,
              color: ExportDialog.primaryWhite,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Editable Document Filename with Save button
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: TextField(
                    controller: _nameController,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      color: ExportDialog.primaryWhite,
                      fontSize: 13,
                    ),
                    decoration: InputDecoration(
                      labelText: 'PDF File Name',
                      labelStyle: TextStyle(color: ExportDialog.softGray, fontSize: 12),
                      hintText: 'e.g. QuickShare_Document.pdf',
                      hintStyle: TextStyle(color: AppColors.mutedText, fontSize: 12),
                      filled: true,
                      fillColor: ExportDialog.cardBg,
                      errorText: _validationError,
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(8)),
                        borderSide: BorderSide(color: ExportDialog.subtleBorderLight),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(8)),
                        borderSide: BorderSide(color: ExportDialog.limeAccent),
                      ),
                      prefixIcon: Icon(Icons.description_outlined, color: ExportDialog.softGray, size: 18),
                      suffixIcon: _nameSavedFeedback
                          ? Icon(Icons.check_circle_rounded, color: ExportDialog.limeAccent, size: 20)
                          : null,
                    ),
                    onChanged: (val) {
                      if (_validationError != null) {
                        setState(() => _validationError = null);
                      }
                      widget.onFileNameChanged?.call(val);
                    },
                    onSubmitted: (_) => _saveDocumentName(engine),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ExportDialog.cardBg,
                    foregroundColor: ExportDialog.limeAccent,
                    side: BorderSide(color: ExportDialog.limeAccent),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: Icon(Icons.save_rounded, size: 18, color: ExportDialog.limeAccent),
                  label: const Text(
                    'Save Name',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                  onPressed: () => _saveDocumentName(engine),
                ),
              ],
            ),
            if (engine.savedDocumentName != null && engine.savedDocumentName!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Persistent Document Name: ${engine.savedDocumentName!}',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: ExportDialog.softGray),
              ),
            ],
            const SizedBox(height: 14),

            // Summary info card
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: ExportDialog.cardBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: ExportDialog.subtleBorderLight),
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
              title: Text(
                'Add Searchable Text Layer',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: ExportDialog.primaryWhite),
              ),
              subtitle: Text(
                "Embeds each image's caption or file name as invisible, searchable text",
                style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: ExportDialog.softGray),
              ),
              value: _includeOcr,
              activeThumbColor: ExportDialog.limeAccent,
              activeTrackColor: ExportDialog.limeAccent.withValues(alpha: 0.4),
              inactiveThumbColor: ExportDialog.softGray,
              inactiveTrackColor: ExportDialog.subtleBorder,
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
              Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(ExportDialog.limeAccent),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  _statusMessage ?? 'Processing...',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: ExportDialog.softGray),
                ),
              ),
            ] else if (_statusMessage != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: _isSuccessStatus
                      ? ExportDialog.limeAccent.withValues(alpha: 0.1)
                      : const Color(0xFFF87171).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: _isSuccessStatus
                        ? ExportDialog.limeAccent.withValues(alpha: 0.3)
                        : const Color(0xFFF87171).withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _isSuccessStatus ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                      size: 16,
                      color: _isSuccessStatus ? ExportDialog.limeAccent : const Color(0xFFF87171),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _statusMessage!,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 12,
                          color: _isSuccessStatus ? ExportDialog.limeAccent : const Color(0xFFF87171),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Close', style: TextStyle(fontFamily: 'Poppins', color: ExportDialog.softGray)),
        ),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: ExportDialog.primaryWhite,
            side: BorderSide(color: ExportDialog.subtleBorderLight),
          ),
          icon: const Icon(Icons.print_outlined, size: 17),
          label: const Text('Print / Preview', style: TextStyle(fontFamily: 'Poppins')),
          onPressed: () => _runFileAction(engine, FileActions.open),
        ),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: ExportDialog.limeAccent,
            side: BorderSide(color: ExportDialog.limeAccent),
          ),
          icon: Icon(Icons.save_alt_rounded, size: 17, color: ExportDialog.limeAccent),
          label: const Text('Save to Disk', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.bold)),
          onPressed: () => _savePdfToDisk(engine),
        ),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: ExportDialog.limeAccent,
            foregroundColor: ExportDialog.darkText,
            elevation: 0,
          ),
          icon: const Icon(Icons.share_rounded, size: 17, color: ExportDialog.darkText),
          label: const Text(
            'Share PDF',
            style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.bold),
          ),
          onPressed: () => _runFileAction(
            engine,
            (bytes, name) => FileActions.share(bytes, name, directory: engine.downloadDirectory),
          ),
        ),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: ExportDialog.cardBg,
            foregroundColor: ExportDialog.limeAccent,
            side: BorderSide(color: ExportDialog.subtleBorderLight),
          ),
          icon: Icon(Icons.send_to_mobile_rounded, size: 17, color: ExportDialog.limeAccent),
          label: const Text('Send to Device', style: TextStyle(fontFamily: 'Poppins')),
          onPressed: () async {
            final validName = _validateAndGetFileName();
            engine.saveDocumentName(validName);
            widget.onFileNameChanged?.call(validName);
            if (_generatedBytes == null) {
              await _renderPdf();
            }
            if (_generatedBytes != null && context.mounted) {
              final pdf = SessionPdf(
                sessionName: widget.project.title,
                fileName: validName,
                bytes: _generatedBytes!,
                pageCount: widget.project.pages.length,
                screenshotCount: widget.project.totalImageCount,
                paperFormatDescription: widget.project.pages.isNotEmpty
                    ? '${widget.project.pages.first.geometry.paperSize.name.toUpperCase()} ${widget.project.pages.first.geometry.isLandscape ? "Landscape" : "Portrait"}'
                    : 'A4 Portrait',
              );
              Navigator.pop(context);
              SessionPdfDialog.show(context, sessionPdf: pdf);
            }
          },
        ),
      ],
    );
  }

  Widget _infoItem(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: ExportDialog.primaryWhite,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 11,
            color: ExportDialog.softGray,
          ),
        ),
      ],
    );
  }
}
