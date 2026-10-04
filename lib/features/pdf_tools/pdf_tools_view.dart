import '../../core/services/ocr_service.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:archive/archive.dart';
import 'package:image/image.dart' as img;
import 'package:file_picker/file_picker.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:provider/provider.dart';
import '../../core/services/file_actions.dart';
import '../../core/services/pdf_pages.dart';
import '../../core/utils/format_utils.dart';
import '../../core/utils/file_utils.dart';
import '../../core/constants.dart';
import '../../data/services/transfer_engine.dart';
import '../../core/widgets/hover_card.dart';
import 'services/file_converter_service.dart';
import 'services/folder_picker.dart';

class PdfToolFile {
  final String name;
  final int size;
  final Uint8List bytes;
  final int pageCount;

  PdfToolFile({
    required this.name,
    required this.size,
    required this.bytes,
    this.pageCount = 1,
  });
}

class SplitOutputConfig {
  final TextEditingController nameController;
  final TextEditingController pagesController;
  final Set<int> selectedPages;

  SplitOutputConfig({
    required String initialName,
    required String initialPages,
    Set<int>? selectedPages,
  })  : nameController = TextEditingController(text: initialName),
        pagesController = TextEditingController(text: initialPages),
        selectedPages = selectedPages ?? {};

  void dispose() {
    nameController.dispose();
    pagesController.dispose();
  }
}

class GeneratedSplitResult {
  final String name;
  final Uint8List bytes;
  final String pagesDescription;

  GeneratedSplitResult({
    required this.name,
    required this.bytes,
    required this.pagesDescription,
  });
}

enum ConversionItemStatus {
  ready,
  converting,
  completed,
  error,
}

class ConverterQueueItem {
  final String id;
  final String fileName;
  /// Sub-folder inside an added folder ("week1/"), kept when downloading results as a ZIP.
  final String relativeDir;
  final Uint8List bytes;
  final int sizeBytes;
  final String fileType;
  ConversionFormat selectedFormat;
  final TextEditingController outputNameController;
  ConversionItemStatus status;
  double progress;
  String? statusMessage;
  ConversionResult? result;
  String? errorMessage;

  ConverterQueueItem({
    required this.id,
    required this.fileName,
    this.relativeDir = '',
    required this.bytes,
    required this.sizeBytes,
    required this.fileType,
    required this.selectedFormat,
    required String initialOutputName,
    this.status = ConversionItemStatus.ready,
    this.progress = 0.0,
    this.statusMessage = 'Ready',
    this.result,
    this.errorMessage,
  }) : outputNameController = TextEditingController(text: initialOutputName);

  void dispose() {
    outputNameController.dispose();
  }
}

class PdfToolsView extends StatefulWidget {
  const PdfToolsView({super.key});

  @override
  State<PdfToolsView> createState() => _PdfToolsViewState();
}

class _PdfToolsViewState extends State<PdfToolsView> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Merge State
  final List<PdfToolFile> _mergeFiles = [];
  bool _isMerging = false;
  Uint8List? _lastMergedBytes;
  String? _lastMergedName;

  // Multi-Output Split State (Image 4)
  PdfToolFile? _splitFile;
  int _outputPdfCount = 3;
  final List<SplitOutputConfig> _splitConfigs = [];
  bool _isSplitting = false;
  final List<GeneratedSplitResult> _splitResults = [];
  final TextEditingController _sourcePdfNameController = TextEditingController();
  final TextEditingController _batchPrefixController = TextEditingController(text: 'Split_Doc');

  // Compression State
  PdfToolFile? _compressFile;
  String _compressProfile = 'Balanced';
  bool _isCompressing = false;
  Uint8List? _compressedBytes;
  int? _compressedEstimatedSize;

  // OCR State
  PdfToolFile? _ocrFile;
  String _ocrLanguage = OcrService.languages.keys.first;
  bool _isProcessingOcr = false;
  String? _ocrProgress;
  OcrResult? _ocrResult;
  String? _ocrError;

  // Multi-File Converter Queue State
  final List<ConverterQueueItem> _converterQueue = [];
  bool _isConvertingBatch = false;
  String? _converterFolderName;

  @override
  void dispose() {
    _tabController.dispose();
    for (final item in _converterQueue) {
      item.dispose();
    }
    for (final c in _splitConfigs) {
      c.dispose();
    }
    _sourcePdfNameController.dispose();
    _batchPrefixController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _initSplitConfigs();
  }

  void _initSplitConfigs() {
    for (final c in _splitConfigs) {
      c.dispose();
    }
    _splitConfigs.clear();

    final defaults = [
      (name: 'pdf1.pdf', pages: '1, 2, 5'),
      (name: 'pdf2.pdf', pages: '3, 4'),
      (name: 'pdf3.pdf', pages: '3'),
    ];

    for (int i = 0; i < _outputPdfCount; i++) {
      final def = i < defaults.length ? defaults[i] : (name: 'pdf${i + 1}.pdf', pages: '${i + 1}');
      final config = SplitOutputConfig(
        initialName: def.name,
        initialPages: def.pages,
      );
      _parsePagesIntoSet(config);
      _splitConfigs.add(config);
    }
  }

  void _applyBatchPrefix(String prefix) {
    final clean = prefix.trim().isEmpty ? 'Split_Doc' : prefix.trim();
    for (int i = 0; i < _splitConfigs.length; i++) {
      _splitConfigs[i].nameController.text = '${clean}_Part_${i + 1}.pdf';
    }
    setState(() {});
  }

  Future<void> _loadSampleSourcePdf() async {
    final pdfDoc = pw.Document();
    for (int p = 1; p <= 5; p++) {
      pdfDoc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (ctx) => pw.Center(
            child: pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: [
                pw.Text('Laboratory Document Page $p', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 12),
                pw.Text('QuickShare Multi-Page Laboratory Sample PDF for Splitting'),
                pw.SizedBox(height: 8),
                pw.Text('Page $p of 5 • Fully Valid Printable Document'),
              ],
            ),
          ),
        ),
      );
    }
    final bytes = await pdfDoc.save();
    const name = 'Computer_Networks_Lab_Manual.pdf';
    _sourcePdfNameController.text = name;
    _batchPrefixController.text = 'Networks_Unit';
    setState(() {
      _splitFile = PdfToolFile(name: name, size: bytes.length, bytes: bytes, pageCount: 5);
      _splitResults.clear();
      _applyBatchPrefix('Networks_Unit');
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Loaded 5-page sample document: "$name"')),
      );
    }
  }

  void _loadActiveSessionPdf() {
    final engine = context.read<TransferEngine>();
    final sessionPdf = engine.activeSessionPdf;
    if (sessionPdf == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No active Session PDF available. Create one in PDF Studio first or load sample.')),
      );
      return;
    }
    _sourcePdfNameController.text = sessionPdf.name;
    final base = sessionPdf.name.replaceAll('.pdf', '');
    _batchPrefixController.text = base;
    setState(() {
      _splitFile = PdfToolFile(
        name: sessionPdf.name,
        size: sessionPdf.bytes.length,
        bytes: sessionPdf.bytes,
        pageCount: sessionPdf.pageCount,
      );
      _splitResults.clear();
      _applyBatchPrefix(base);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Loaded Active Session PDF: "${sessionPdf.name}"')),
    );
  }

  void _renameSplitResult(int index) {
    final current = _splitResults[index];
    final controller = TextEditingController(text: current.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename Split PDF Document'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'File Name',
            hintText: 'e.g. Unit1_Theory.pdf',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.drive_file_rename_outline),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: AppColors.onLimeText),
            onPressed: () {
              final newName = controller.text.trim();
              if (newName.isNotEmpty) {
                final validated = newName.toLowerCase().endsWith('.pdf') ? newName : '$newName.pdf';
                setState(() {
                  _splitResults[index] = GeneratedSplitResult(
                    name: validated,
                    bytes: current.bytes,
                    pagesDescription: current.pagesDescription,
                  );
                });
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Renamed split PDF to "$validated"')),
                );
              }
            },
            child: const Text('Save Name'),
          ),
        ],
      ),
    );
  }

  void _updateSplitCount(int count) {
    if (count < 1 || count > 12) return;
    setState(() {
      _outputPdfCount = count;
      while (_splitConfigs.length < count) {
        final idx = _splitConfigs.length + 1;
        final prefix = _batchPrefixController.text.trim().isEmpty ? 'pdf' : _batchPrefixController.text.trim();
        final config = SplitOutputConfig(
          initialName: '${prefix}_$idx.pdf',
          initialPages: '$idx',
        );
        _parsePagesIntoSet(config);
        _splitConfigs.add(config);
      }
      while (_splitConfigs.length > count) {
        _splitConfigs.removeLast().dispose();
      }
    });
  }

  void _parsePagesIntoSet(SplitOutputConfig config) {
    config.selectedPages.clear();
    final parts = config.pagesController.text.split(RegExp(r'[,;\s]+'));
    for (final p in parts) {
      if (p.trim().isEmpty) continue;
      if (p.contains('-')) {
        final rangeParts = p.split('-');
        if (rangeParts.length == 2) {
          final start = int.tryParse(rangeParts[0].trim());
          final end = int.tryParse(rangeParts[1].trim());
          if (start != null && end != null && start <= end) {
            for (int pg = start; pg <= end; pg++) {
              config.selectedPages.add(pg);
            }
          }
        }
      } else {
        final pg = int.tryParse(p.trim());
        if (pg != null && pg > 0) {
          config.selectedPages.add(pg);
        }
      }
    }
  }

  void _togglePageInConfig(SplitOutputConfig config, int page) {
    setState(() {
      if (config.selectedPages.contains(page)) {
        config.selectedPages.remove(page);
      } else {
        config.selectedPages.add(page);
      }
      final sorted = config.selectedPages.toList()..sort();
      config.pagesController.text = sorted.join(', ');
    });
  }

  Future<void> _pickMergeFiles() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    final unreadable = <String>[];
    for (final f in files) {
      final bytes = await f.readAsBytes();
      final len = (await f.length()) ?? bytes.length;
      try {
        final pageCount = await PdfPages.pageCount(bytes);
        if (!mounted) return;
        setState(() => _mergeFiles.add(PdfToolFile(name: f.name, size: len, bytes: bytes, pageCount: pageCount)));
      } catch (_) {
        unreadable.add(f.name);
      }
    }
    if (unreadable.isNotEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Skipped unreadable or damaged PDF: ${unreadable.join(', ')}')),
      );
    }
  }

  /// Concatenates the selected PDFs page-for-page. Throws if any file cannot be read.
  Future<Uint8List> _buildMergedPdf(List<PdfToolFile> files) =>
      PdfPages.merge([for (final f in files) f.bytes]);

  Future<void> _executeMerge() async {
    if (_mergeFiles.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least 2 PDF files to merge.')),
      );
      return;
    }

    setState(() => _isMerging = true);

    try {
      final validPdfBytes = await _buildMergedPdf(_mergeFiles);

      setState(() {
        _isMerging = false;
        _lastMergedBytes = validPdfBytes;
        _lastMergedName = 'Merged_Submission_${DateTime.now().millisecondsSinceEpoch % 10000}.pdf';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Merged ${_mergeFiles.length} files successfully! (${FormatUtils.formatBytes(validPdfBytes.length)})'),
            action: SnackBarAction(
              label: 'Download',
              onPressed: () {
                FileActions.runWithSnackBar(context, () => FileActions.save(validPdfBytes, _lastMergedName!, directory: context.read<TransferEngine>().downloadDirectory));
              },
            ),
          ),
        );
      }
    } catch (e) {
      setState(() => _isMerging = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error merging PDFs: $e')),
        );
      }
    }
  }

  Future<void> _pickSplitSourcePdf() async {
    final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
    if (files.isEmpty) return;
    final f = files.first;
    final bytes = await f.readAsBytes();
    final len = (await f.length()) ?? bytes.length;
    final int pageCount;
    try {
      pageCount = await PdfPages.pageCount(bytes);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"${f.name}" is not a readable PDF.')),
        );
      }
      return;
    }
    if (!mounted) return;

    final baseName = f.name.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');
    _sourcePdfNameController.text = f.name;
    _batchPrefixController.text = baseName;

    setState(() {
      _splitFile = PdfToolFile(name: f.name, size: len, bytes: bytes, pageCount: pageCount);
      _splitResults.clear();
      _applyBatchPrefix(baseName);
    });
  }

  Future<void> _executeMultiSplit() async {
    if (_splitFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a source PDF to split.')),
      );
      return;
    }

    setState(() => _isSplitting = true);
    _splitResults.clear();

    try {
      final totalPages = _splitFile!.pageCount;

      // Validate every part before producing anything.
      final partPages = <List<int>>[];
      for (int i = 0; i < _splitConfigs.length; i++) {
        final config = _splitConfigs[i];
        _parsePagesIntoSet(config);
        final pages = config.selectedPages.toList()..sort();
        if (pages.isEmpty) {
          throw _SplitInputError('Part ${i + 1}: enter the pages to include (e.g. 1-3, 5).');
        }
        final missing = pages.where((p) => p < 1 || p > totalPages).toList();
        if (missing.isNotEmpty) {
          throw _SplitInputError(
            'Part ${i + 1}: page ${missing.join(', ')} does not exist — "${_splitFile!.name}" has $totalPages pages.',
          );
        }
        partPages.add(pages);
      }

      for (int i = 0; i < _splitConfigs.length; i++) {
        final config = _splitConfigs[i];
        final targetPages = partPages[i];
        final outBytes = await PdfPages.extractPages(_splitFile!.bytes, targetPages);
        String outName = config.nameController.text.trim();
        if (!outName.toLowerCase().endsWith('.pdf')) {
          outName += '.pdf';
        }

        _splitResults.add(GeneratedSplitResult(
          name: outName,
          bytes: outBytes,
          pagesDescription: targetPages.join(', '),
        ));
      }

      setState(() => _isSplitting = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Successfully generated ${_splitResults.length} split PDF documents!')),
        );
      }
    } catch (e) {
      _splitResults.clear();
      setState(() => _isSplitting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e is _SplitInputError ? e.message : 'Error splitting PDF: $e')),
        );
      }
    }
  }

  Future<void> _executeCompression() async {
    if (_compressFile == null) return;
    setState(() => _isCompressing = true);

    try {
      double dpi = 100;
      switch (_compressProfile) {
        case 'Maximum Quality':
          dpi = 150;
          break;
        case 'Balanced':
          dpi = 100;
          break;
        case 'Smaller File':
          dpi = 72;
          break;
      }

      // Re-render each page and store it as a JPEG at the chosen DPI (PNG pages are
      // lossless and usually made the "compressed" file larger than the original).
      final quality = dpi >= 150 ? 85 : (dpi >= 100 ? 75 : 60);
      final doc = pw.Document();
      var pageTotal = 0;
      await for (final page in Printing.raster(_compressFile!.bytes, dpi: dpi)) {
        final rgba = await page.toImage().then((im) => im.toByteData());
        final decoded = img.Image.fromBytes(
          width: page.width,
          height: page.height,
          bytes: rgba!.buffer,
          numChannels: 4,
        );
        final jpg = img.encodeJpg(decoded, quality: quality);
        doc.addPage(
          pw.Page(
            // Raster size is in pixels at [dpi]; PDF pages are measured in points (1/72 in).
            pageFormat: PdfPageFormat(page.width * 72 / dpi, page.height * 72 / dpi),
            margin: pw.EdgeInsets.zero,
            build: (pw.Context ctx) => pw.FullPage(
              ignoreMargins: true,
              child: pw.Image(pw.MemoryImage(jpg), fit: pw.BoxFit.fill),
            ),
          ),
        );
        pageTotal++;
      }
      if (pageTotal == 0) {
        throw Exception('could not read any pages from "${_compressFile!.name}"');
      }

      final compressed = await doc.save();

      setState(() {
        _isCompressing = false;
        _compressedBytes = compressed;
        _compressedEstimatedSize = compressed.length;
      });

      if (mounted) {
        final original = _compressFile!.size;
        final message = compressed.length < original
            ? 'Compressed PDF ready: ${FormatUtils.formatBytes(original)} → ${FormatUtils.formatBytes(compressed.length)}'
            : 'This PDF is already compact — the result (${FormatUtils.formatBytes(compressed.length)}) is not smaller '
                'than the original (${FormatUtils.formatBytes(original)}). Try "Smaller File".';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (e) {
      setState(() => _isCompressing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Compression failed: $e')));
      }
    }
  }

  Future<void> _executeOcr() async {
    if (_ocrFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please choose an image or PDF for OCR processing.')),
      );
      return;
    }

    setState(() {
      _isProcessingOcr = true;
      _ocrResult = null;
      _ocrError = null;
      _ocrProgress = 'Preparing pages…';
    });

    try {
      final file = _ocrFile!;
      final images = <Uint8List>[];
      if (file.name.toLowerCase().endsWith('.pdf')) {
        await for (final page in Printing.raster(file.bytes, dpi: 200)) {
          images.add(await page.toPng());
        }
        if (images.isEmpty) throw Exception('no pages found in this PDF');
      } else {
        images.add(file.bytes);
      }
      if (mounted) setState(() => _ocrProgress = 'Loading OCR engine (first run downloads it)…');

      final result = await OcrService.recognize(
        images,
        OcrService.languages[_ocrLanguage]!,
        onProgress: (done, total) {
          if (mounted) setState(() => _ocrProgress = 'Recognized page $done of $total');
        },
      );
      if (!mounted) return;
      setState(() {
        _isProcessingOcr = false;
        _ocrResult = result;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isProcessingOcr = false;
        _ocrError = 'OCR failed: $e';
      });
    }
  }

  String get _ocrBaseName => (_ocrFile?.name ?? 'ocr').replaceAll(RegExp(r'\.[^.]+$'), '');

  Future<void> _saveOcrText() => FileActions.runWithSnackBar(
        context,
        () => FileActions.save(
          Uint8List.fromList(utf8.encode(_ocrResult!.text)),
          '${_ocrBaseName}_text.txt',
          directory: context.read<TransferEngine>().downloadDirectory,
        ),
      );

  Future<void> _saveSearchablePdf() => FileActions.runWithSnackBar(context, () async {
        final pages = _ocrResult!.pdfPages;
        final bytes = pages.length == 1 ? pages.first : await PdfPages.merge(pages);
        if (!mounted) return 'Cancelled';
        return FileActions.save(
          bytes,
          '${_ocrBaseName}_searchable.pdf',
          directory: context.read<TransferEngine>().downloadDirectory,
        );
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.dashboardBg,
      appBar: AppBar(
        backgroundColor: AppColors.dashboardBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Professional PDF Tools',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w700,
            color: AppColors.white,
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.limeGreen,
          unselectedLabelColor: AppColors.softGray,
          indicatorColor: AppColors.limeGreen,
          indicatorSize: TabBarIndicatorSize.label,
          dividerColor: AppColors.subtleBorder,
          isScrollable: true,
          tabs: const [
            Tab(icon: Icon(Icons.transform_rounded), text: 'File Converter'),
            Tab(icon: Icon(Icons.call_merge_rounded), text: 'Merge PDFs'),
            Tab(icon: Icon(Icons.call_split_rounded), text: 'Split PDF'),
            Tab(icon: Icon(Icons.compress_rounded), text: 'Compress PDF'),
            Tab(icon: Icon(Icons.document_scanner_rounded), text: 'OCR Searchable'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildConverterTab(),
          _buildMergeTab(),
          _buildSplitTab(),
          _buildCompressTab(),
          _buildOcrTab(),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // UNIVERSAL FILE CONVERTER TAB (Multi-File Queue)
  // -------------------------------------------------------------
  static List<ConversionFormat> _getSupportedFormatsForFile(String fileName) =>
      ConversionFormats.targetsFor(fileName);

  static String _getCleanBaseName(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.tar.gz')) return fileName.substring(0, fileName.length - 7);
    final lastDot = fileName.lastIndexOf('.');
    if (lastDot <= 0) return fileName;
    return fileName.substring(0, lastDot);
  }

  static String _getDefaultOutputFileName(String fileName, ConversionFormat format) {
    final base = _getCleanBaseName(fileName);
    return '$base${format.outputExtension}';
  }

  static String _detectFileTypeLabel(String fileName) => ConversionFormats.detect(fileName).label;

  static IconData _getFileIcon(String fileName) {
    switch (ConversionFormats.detect(fileName)) {
      case SourceKind.pdf:
        return Icons.picture_as_pdf_rounded;
      case SourceKind.docx:
      case SourceKind.doc:
      case SourceKind.odt:
      case SourceKind.rtf:
        return Icons.description_rounded;
      case SourceKind.xlsx:
      case SourceKind.ods:
      case SourceKind.csv:
      case SourceKind.tsv:
        return Icons.table_chart_rounded;
      case SourceKind.pptx:
      case SourceKind.odp:
        return Icons.slideshow_rounded;
      case SourceKind.text:
      case SourceKind.markdown:
        return Icons.text_snippet_rounded;
      case SourceKind.html:
      case SourceKind.code:
      case SourceKind.json:
      case SourceKind.xml:
        return Icons.code_rounded;
      case SourceKind.image:
      case SourceKind.svg:
        return Icons.image_rounded;
      case SourceKind.stl:
      case SourceKind.obj:
      case SourceKind.threeMf:
        return Icons.view_in_ar_rounded;
      case SourceKind.zip:
      case SourceKind.tar:
      case SourceKind.tarGz:
      case SourceKind.gzip:
        return Icons.folder_zip_rounded;
      case SourceKind.other:
        return Icons.insert_drive_file_rounded;
    }
  }

  static Color _getFileColor(String fileName) {
    switch (ConversionFormats.detect(fileName)) {
      case SourceKind.pdf:
        return const Color(0xFFEF4444);
      case SourceKind.docx:
      case SourceKind.doc:
      case SourceKind.odt:
      case SourceKind.rtf:
        return const Color(0xFF3B82F6);
      case SourceKind.xlsx:
      case SourceKind.ods:
      case SourceKind.csv:
      case SourceKind.tsv:
        return const Color(0xFF10B981);
      case SourceKind.pptx:
      case SourceKind.odp:
        return const Color(0xFFF97316);
      case SourceKind.image:
      case SourceKind.svg:
        return const Color(0xFFA855F7);
      case SourceKind.html:
      case SourceKind.code:
      case SourceKind.json:
      case SourceKind.xml:
        return const Color(0xFF06B6D4);
      case SourceKind.stl:
      case SourceKind.obj:
      case SourceKind.threeMf:
        return const Color(0xFFF59E0B);
      default:
        return AppColors.secondaryText;
    }
  }

  void _addConverterFile(String fileName, Uint8List bytes, {String relativeDir = ''}) {
    final targets = _getSupportedFormatsForFile(fileName);
    final format = targets.first;
    _converterQueue.add(ConverterQueueItem(
      id: '${DateTime.now().microsecondsSinceEpoch}_${_converterQueue.length}_$fileName',
      fileName: fileName,
      relativeDir: relativeDir,
      bytes: bytes,
      sizeBytes: bytes.length,
      fileType: _detectFileTypeLabel(fileName),
      selectedFormat: format,
      initialOutputName: _getDefaultOutputFileName(fileName, format),
    ));
  }

  void _showConverterMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.surfaceElevated,
        content: Text(
          message,
          style: TextStyle(fontFamily: 'Poppins', color: isError ? AppColors.error : AppColors.primaryText),
        ),
      ),
    );
  }

  Future<void> _pickConverterFiles() async {
    try {
      final res = await FilePicker.pickFiles(type: FileType.any);
      if (res.isEmpty) return;
      for (final f in res) {
        _addConverterFile(f.name, await f.readAsBytes());
      }
      setState(() {});
    } catch (e) {
      _showConverterMessage('Error selecting files: $e', isError: true);
    }
  }

  Future<void> _pickConverterFolder() async {
    try {
      final folder = await FolderPicker.pick();
      if (folder == null) return;
      if (folder.files.isEmpty) {
        _showConverterMessage('"${folder.name}" has no files to convert.');
        return;
      }
      _converterFolderName = folder.name;
      for (final f in folder.files) {
        final slash = f.relativePath.lastIndexOf('/');
        _addConverterFile(f.name, f.bytes, relativeDir: slash == -1 ? '' : f.relativePath.substring(0, slash + 1));
      }
      setState(() {});
      final zipOnly = folder.files
          .where((f) => _getSupportedFormatsForFile(f.name).first == ConversionFormat.zip)
          .length;
      _showConverterMessage(
        'Added ${folder.files.length} file(s) from "${folder.name}".'
        '${zipOnly > 0 ? ' $zipOnly file(s) (video, audio, apps…) can only be packed into ZIP.' : ''}'
        '${folder.skippedTooLarge.isNotEmpty ? ' Skipped ${folder.skippedTooLarge.length} file(s) over 150 MB.' : ''}',
      );
    } catch (e) {
      _showConverterMessage('Error reading folder: $e', isError: true);
    }
  }

  /// Formats offered by "Convert all to": every format at least one queued file supports.
  List<ConversionFormat> get _bulkFormats {
    final seen = <ConversionFormat>{};
    for (final item in _converterQueue) {
      seen.addAll(_getSupportedFormatsForFile(item.fileName));
    }
    return ConversionFormat.values.where(seen.contains).toList();
  }

  void _setFormatForAll(ConversionFormat format) {
    var changed = 0;
    setState(() {
      for (final item in _converterQueue) {
        if (item.status == ConversionItemStatus.converting) continue;
        if (!_getSupportedFormatsForFile(item.fileName).contains(format)) continue;
        _applyFormat(item, format);
        changed++;
      }
    });
    final skipped = _converterQueue.length - changed;
    _showConverterMessage(
      'Set $changed file(s) to ${format.label}.${skipped > 0 ? ' $skipped file(s) can\'t become ${format.outputExtension} and kept their format.' : ''}',
    );
  }

  void _applyFormat(ConverterQueueItem item, ConversionFormat format) {
    item.selectedFormat = format;
    final currentText = item.outputNameController.text.trim();
    final base = currentText.isEmpty ? _getCleanBaseName(item.fileName) : _getCleanBaseName(currentText);
    item.outputNameController.text = '$base${format.outputExtension}';
    if (item.status == ConversionItemStatus.completed || item.status == ConversionItemStatus.error) {
      item.status = ConversionItemStatus.ready;
      item.progress = 0.0;
      item.statusMessage = 'Ready';
      item.result = null;
      item.errorMessage = null;
    }
  }

  void _removeFile(ConverterQueueItem item) {
    setState(() {
      item.dispose();
      _converterQueue.remove(item);
    });
  }

  void _clearAllFiles() {
    setState(() {
      for (final item in _converterQueue) {
        item.dispose();
      }
      _converterQueue.clear();
      _converterFolderName = null;
    });
  }

  Future<void> _showFormatPicker(ConverterQueueItem item) async {
    final availableFormats = _getSupportedFormatsForFile(item.fileName);
    if (availableFormats.isEmpty) return;

    final selected = await showDialog<ConversionFormat>(
      context: context,
      builder: (ctx) {
        return SearchableFormatPickerDialog(
          fileName: item.fileName,
          currentFormat: item.selectedFormat,
          availableFormats: availableFormats,
        );
      },
    );

    if (selected != null && selected != item.selectedFormat) {
      setState(() => _applyFormat(item, selected));
    }
  }

  Future<void> _convertItem(ConverterQueueItem item) async {
    if (item.status == ConversionItemStatus.converting) return;

    setState(() {
      item.status = ConversionItemStatus.converting;
      item.progress = 0.05;
      item.statusMessage = 'Starting conversion...';
      item.errorMessage = null;
      item.result = null;
    });

    try {
      final result = await FileConverterService.convert(
        format: item.selectedFormat,
        inputFileName: item.fileName,
        inputBytes: item.bytes,
        onProgress: (progress, status) {
          if (mounted) {
            setState(() {
              item.progress = progress;
              item.statusMessage = status;
            });
          }
        },
      );

      if (mounted) {
        setState(() {
          item.status = ConversionItemStatus.completed;
          item.progress = 1.0;
          item.statusMessage = 'Completed';
          item.result = result;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          item.status = ConversionItemStatus.error;
          item.progress = 0.0;
          item.statusMessage = 'Failed';
          item.errorMessage = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
        });
      }
    }
  }

  Future<void> _convertAllReadyFiles() async {
    final readyItems = _converterQueue.where((item) {
      return item.status == ConversionItemStatus.ready ||
             item.status == ConversionItemStatus.error;
    }).toList();

    if (readyItems.isEmpty) return;

    setState(() {
      _isConvertingBatch = true;
    });

    for (final item in readyItems) {
      if (!mounted) break;
      await _convertItem(item);
    }

    if (mounted) {
      setState(() {
        _isConvertingBatch = false;
      });

      final successCount = readyItems.where((i) => i.status == ConversionItemStatus.completed).length;
      final failCount = readyItems.where((i) => i.status == ConversionItemStatus.error).length;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.cardBg,
          content: Text(
            failCount == 0
                ? 'All $successCount file(s) converted successfully!'
                : 'Converted $successCount file(s), $failCount failed.',
            style: TextStyle(
              fontFamily: 'Poppins',
              color: failCount == 0 ? AppColors.limeGreen : AppColors.error,
            ),
          ),
        ),
      );
    }
  }

  String _outputNameFor(ConverterQueueItem item) {
    var name = item.outputNameController.text.trim();
    if (name.isEmpty) {
      name = _getDefaultOutputFileName(item.fileName, item.selectedFormat);
    }
    name = FileUtils.sanitizeFilename(name);
    if (!name.toLowerCase().endsWith(item.selectedFormat.outputExtension.toLowerCase())) {
      name = '$name${item.selectedFormat.outputExtension}';
    }
    return name;
  }

  Future<void> _saveConvertedFile(ConverterQueueItem item) async {
    if (item.result == null) return;
    final name = _outputNameFor(item);
    try {
      await FilePicker.saveFile(
        fileName: name,
        bytes: item.result!.outputBytes,
        mimeType: item.selectedFormat.mimeType,
        dialogTitle: 'Save converted file',
      );
      _showConverterMessage('Saved "$name"');
    } catch (e) {
      _showConverterMessage('Error saving file: $e', isError: true);
    }
  }

  /// Downloads every converted file as one ZIP, keeping the original sub-folder layout.
  Future<void> _saveAllConvertedFiles() async {
    final completed = _converterQueue
        .where((i) => i.status == ConversionItemStatus.completed && i.result != null)
        .toList();
    if (completed.isEmpty) return;

    final archive = Archive();
    final used = <String>{};
    for (final item in completed) {
      final name = _outputNameFor(item);
      final dot = name.indexOf('.', 1);
      var path = '${item.relativeDir}$name';
      // Two inputs can map to the same output name (a.docx and a.odt -> a.pdf).
      for (var n = 2; !used.add(path.toLowerCase()); n++) {
        path = dot > 0
            ? '${item.relativeDir}${name.substring(0, dot)} ($n)${name.substring(dot)}'
            : '${item.relativeDir}$name ($n)';
      }
      archive.addFile(ArchiveFile.bytes(path, item.result!.outputBytes));
    }
    final zipName = '${FileUtils.sanitizeFilename(_converterFolderName ?? 'QuickShare')}_converted.zip';
    try {
      await FilePicker.saveFile(
        fileName: zipName,
        bytes: ZipEncoder().encodeBytes(archive),
        mimeType: 'application/zip',
        dialogTitle: 'Save all converted files',
      );
      _showConverterMessage('Saved ${completed.length} converted file(s) in "$zipName"');
    } catch (e) {
      _showConverterMessage('Error saving ZIP: $e', isError: true);
    }
  }

  Widget _buildConverterTab() {
    final readyCount = _converterQueue
        .where((i) => i.status == ConversionItemStatus.ready || i.status == ConversionItemStatus.error)
        .length;
    final completedCount = _converterQueue
        .where((i) => i.status == ConversionItemStatus.completed)
        .length;
    final totalBytes = _converterQueue.fold<int>(0, (sum, i) => sum + i.sizeBytes);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row with Heading, Subtitle and Top Actions
          _buildConverterHeader(readyCount, completedCount, totalBytes),
          const SizedBox(height: 24),

          // Main Converter Body: Empty State or File Queue
          if (_converterQueue.isEmpty)
            _buildEmptyQueueState()
          else ...[
            _buildConverterQueueList(),
            const SizedBox(height: 24),
            _buildConverterBottomActionBar(readyCount, completedCount),
          ],
        ],
      ),
    );
  }

  Widget _buildConverterHeader(int readyCount, int completedCount, int totalBytes) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 650;

        final titleSection = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.limeGreen.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.limeGreen.withValues(alpha: 0.25)),
              ),
              child: Icon(Icons.transform_rounded, color: AppColors.limeGreen, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'File Converter',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700,
                      fontSize: 22,
                      color: AppColors.white,
                      letterSpacing: -0.3,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Batch convert files or whole folders offline: documents, spreadsheets, slides, images, code, 3D models and archives.',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12.5,
                      color: AppColors.softGray,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );

        final actionButtons = Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.limeGreen,
                foregroundColor: AppColors.nearBlack,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.add_rounded, size: 20, color: AppColors.nearBlack),
              label: const Text(
                'Add Files',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: AppColors.nearBlack,
                ),
              ),
              onPressed: _isConvertingBatch ? null : _pickConverterFiles,
            ),
            _buildAddFolderButton(),
            if (_converterQueue.isNotEmpty) _buildBulkFormatMenu(),
            if (_converterQueue.isNotEmpty)
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.softGray,
                  side: BorderSide(color: AppColors.subtleBorder),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                label: const Text(
                  'Clear All',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 13),
                ),
                onPressed: _isConvertingBatch ? null : _clearAllFiles,
              ),
          ],
        );

        if (isCompact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              titleSection,
              const SizedBox(height: 16),
              actionButtons,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: titleSection),
            const SizedBox(width: 16),
            actionButtons,
          ],
        );
      },
    );
  }

  Widget _buildAddFolderButton() {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.limeGreen,
        side: BorderSide(color: AppColors.limeGreen.withValues(alpha: 0.6)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      icon: const Icon(Icons.drive_folder_upload_rounded, size: 19),
      label: const Text(
        'Add Folder',
        style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 13),
      ),
      onPressed: _isConvertingBatch ? null : _pickConverterFolder,
    );
  }

  Widget _buildBulkFormatMenu() {
    final formats = _bulkFormats;
    return PopupMenuButton<ConversionFormat>(
      key: const Key('convert_all_to_menu'),
      enabled: !_isConvertingBatch && formats.isNotEmpty,
      tooltip: 'Set one output format for every file that supports it',
      color: AppColors.charcoalSurface,
      constraints: const BoxConstraints(maxHeight: 420, minWidth: 240),
      onSelected: _setFormatForAll,
      itemBuilder: (context) => [
        for (final f in formats)
          PopupMenuItem<ConversionFormat>(
            value: f,
            child: Row(
              children: [
                Expanded(
                  child: Text(f.label, style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: AppColors.primaryText)),
                ),
                Text(
                  '${_converterQueue.where((i) => _getSupportedFormatsForFile(i.fileName).contains(f)).length}/${_converterQueue.length}',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: AppColors.secondaryText),
                ),
              ],
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.subtleBorderLight),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.swap_horiz_rounded, size: 18, color: AppColors.limeGreen),
            const SizedBox(width: 8),
            Text(
              'Convert all to…',
              style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.primaryText),
            ),
            Icon(Icons.arrow_drop_down_rounded, color: AppColors.secondaryText),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyQueueState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.subtleBorder, width: 1.2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.limeGreen.withValues(alpha: 0.1),
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.limeGreen.withValues(alpha: 0.25)),
            ),
            child: Icon(
              Icons.upload_file_rounded,
              color: AppColors.limeGreen,
              size: 42,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'No files selected for conversion',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: AppColors.white,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Text(
              'Add files or a whole folder. Each file gets a sensible default output (usually PDF), and you can switch any file — or all of them at once — to another format. Everything runs offline on this device.',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12.5,
                color: AppColors.softGray,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 22),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.limeGreen,
              foregroundColor: AppColors.nearBlack,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.add_rounded, size: 20, color: AppColors.nearBlack),
            label: const Text(
              'Add Files to Convert',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                fontSize: 13.5,
                color: AppColors.nearBlack,
              ),
            ),
            onPressed: _pickConverterFiles,
          ),
          const SizedBox(height: 10),
          _buildAddFolderButton(),
          const SizedBox(height: 24),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [for (final line in ConversionFormats.supportedSummary) _SupportedFormatPill(line)],
          ),
        ],
      ),
    );
  }

  Widget _buildConverterQueueList() {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _converterQueue.length,
      separatorBuilder: (context, index) => const SizedBox(height: 14),
      itemBuilder: (context, index) {
        final item = _converterQueue[index];
        return _buildQueueItemCard(item);
      },
    );
  }

  Widget _buildQueueItemCard(ConverterQueueItem item) {
    final fileColor = _getFileColor(item.fileName);
    final fileIcon = _getFileIcon(item.fileName);
    final isConverting = item.status == ConversionItemStatus.converting;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: item.status == ConversionItemStatus.completed
              ? AppColors.limeGreen.withValues(alpha: 0.35)
              : item.status == ConversionItemStatus.error
                  ? AppColors.error.withValues(alpha: 0.35)
                  : AppColors.subtleBorder,
          width: 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: File icon, name, badges, status pill, and remove button
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: fileColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: fileColor.withValues(alpha: 0.3)),
                ),
                child: Icon(fileIcon, color: fileColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.fileName,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: AppColors.white,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (item.relativeDir.isNotEmpty)
                      Text(
                        item.relativeDir,
                        style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: AppColors.mutedText),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceElevated,
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            item.fileType,
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 10.5,
                              color: AppColors.softGray,
                            ),
                          ),
                        ),
                        Text(
                          FormatUtils.formatBytes(item.sizeBytes),
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 11,
                            color: AppColors.softGray,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // Status Pill
              _buildItemStatusPill(item),
              const SizedBox(width: 8),
              // Remove Button
              IconButton(
                icon: Icon(Icons.close_rounded, color: AppColors.softGray, size: 20),
                tooltip: 'Remove from selection',
                onPressed: isConverting ? null : () => _removeFile(item),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Divider(color: AppColors.subtleBorder, height: 1),
          const SizedBox(height: 14),

          // Row 2: Target Format Picker & Output Filename Customization
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 540;

              final formatSelector = InkWell(
                onTap: isConverting ? null : () => _showFormatPicker(item),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.subtleBorder),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Icon(Icons.swap_horiz_rounded, size: 16, color: AppColors.limeGreen),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                item.selectedFormat.label,
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.white,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.arrow_drop_down_rounded, color: AppColors.softGray, size: 22),
                    ],
                  ),
                ),
              );

              final filenameField = TextField(
                controller: item.outputNameController,
                enabled: !isConverting,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12.5,
                  color: AppColors.white,
                ),
                cursorColor: AppColors.limeGreen,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'e.g. converted_file${item.selectedFormat.outputExtension}',
                  hintStyle: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    color: AppColors.softGray,
                  ),
                  prefixIcon: Icon(Icons.edit_note_rounded, size: 18, color: AppColors.softGray),
                  suffixText: item.selectedFormat.outputExtension,
                  suffixStyle: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: AppColors.limeGreen,
                  ),
                  filled: true,
                  fillColor: AppColors.surfaceElevated,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: AppColors.subtleBorder),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: AppColors.subtleBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: AppColors.limeGreen, width: 1.2),
                  ),
                ),
              );

              if (isWide) {
                return Row(
                  children: [
                    Expanded(
                      flex: 4,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Output Format',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 11,
                              color: AppColors.softGray,
                            ),
                          ),
                          const SizedBox(height: 4),
                          formatSelector,
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      flex: 5,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Output Filename',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 11,
                              color: AppColors.softGray,
                            ),
                          ),
                          const SizedBox(height: 4),
                          filenameField,
                        ],
                      ),
                    ),
                  ],
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Output Format',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 11,
                      color: AppColors.softGray,
                    ),
                  ),
                  const SizedBox(height: 4),
                  formatSelector,
                  const SizedBox(height: 10),
                  Text(
                    'Output Filename',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 11,
                      color: AppColors.softGray,
                    ),
                  ),
                  const SizedBox(height: 4),
                  filenameField,
                ],
              );
            },
          ),

          // Row 3: Dynamic Status Banner / Progress / Success / Error / Actions
          if (item.status == ConversionItemStatus.converting) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.limeGreen.withValues(alpha: 0.25)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          item.statusMessage ?? 'Converting...',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 12,
                            color: AppColors.white,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '${(item.progress * 100).toInt()}%',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppColors.limeGreen,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: item.progress,
                    backgroundColor: AppColors.dashboardBg,
                    valueColor: AlwaysStoppedAnimation<Color>(AppColors.limeGreen),
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ],
              ),
            ),
          ] else if (item.status == ConversionItemStatus.error) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline_rounded, color: AppColors.error, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item.errorMessage ?? 'Conversion failed. Please try again.',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 11.5,
                        color: AppColors.error,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.error,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.refresh_rounded, size: 15),
                    label: const Text('Retry', style: TextStyle(fontFamily: 'Poppins', fontSize: 11.5)),
                    onPressed: () => _convertItem(item),
                  ),
                ],
              ),
            ),
          ] else if (item.status == ConversionItemStatus.completed && item.result != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.limeGreen.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.limeGreen.withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle_rounded, color: AppColors.limeGreen, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Ready: ${FormatUtils.formatBytes(item.result!.outputBytes.length)} • ${item.result!.details}',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.white,
                          ),
                        ),
                        if (item.result!.hasWarnings && item.result!.warningMessage != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            item.result!.warningMessage!,
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 10.5,
                              color: AppColors.warning,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.limeGreen,
                      foregroundColor: AppColors.nearBlack,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.download_rounded, size: 16, color: AppColors.nearBlack),
                    label: const Text(
                      'Save / Download',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: AppColors.nearBlack,
                      ),
                    ),
                    onPressed: () => _saveConvertedFile(item),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildItemStatusPill(ConverterQueueItem item) {
    switch (item.status) {
      case ConversionItemStatus.ready:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.subtleBorder),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.schedule_rounded, size: 12, color: AppColors.softGray),
              SizedBox(width: 5),
              Text(
                'Ready',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: AppColors.softGray),
              ),
            ],
          ),
        );
      case ConversionItemStatus.converting:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.limeGreen.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.limeGreen.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 11,
                height: 11,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.limeGreen),
              ),
              const SizedBox(width: 6),
              Text(
                '${(item.progress * 100).toInt()}%',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: AppColors.limeGreen,
                ),
              ),
            ],
          ),
        );
      case ConversionItemStatus.completed:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.limeGreen.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.limeGreen.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle_rounded, size: 13, color: AppColors.limeGreen),
              SizedBox(width: 5),
              Text(
                'Success',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: AppColors.limeGreen,
                ),
              ),
            ],
          ),
        );
      case ConversionItemStatus.error:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.error.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded, size: 13, color: AppColors.error),
              SizedBox(width: 5),
              Text(
                'Failed',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: AppColors.error,
                ),
              ),
            ],
          ),
        );
    }
  }

  Widget _buildConverterBottomActionBar(int readyCount, int completedCount) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.subtleBorder),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 600;

          final statsText = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_converterQueue.length} files in queue',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: AppColors.white,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '$readyCount ready to convert • $completedCount completed',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  color: AppColors.softGray,
                ),
              ),
            ],
          );

          final buttons = Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (completedCount > 1)
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.limeGreen,
                    side: BorderSide(color: AppColors.limeGreen.withValues(alpha: 0.4)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.folder_zip_rounded, size: 18),
                  label: const Text(
                    'Download All (.zip)',
                    style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  onPressed: _saveAllConvertedFiles,
                ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.limeGreen,
                  foregroundColor: AppColors.nearBlack,
                  disabledBackgroundColor: AppColors.subtleBorder,
                  disabledForegroundColor: AppColors.softGray,
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: _isConvertingBatch
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.nearBlack),
                      )
                    : const Icon(Icons.play_arrow_rounded, size: 20, color: AppColors.nearBlack),
                label: Text(
                  _isConvertingBatch
                      ? 'Converting Files...'
                      : readyCount > 0
                          ? 'Convert ($readyCount Files)'
                          : 'All Files Converted',
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                    color: AppColors.nearBlack,
                  ),
                ),
                onPressed: (readyCount > 0 && !_isConvertingBatch) ? _convertAllReadyFiles : null,
              ),
            ],
          );

          if (isCompact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                statsText,
                const SizedBox(height: 14),
                buttons,
              ],
            );
          }

          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              statsText,
              buttons,
            ],
          );
        },
      ),
    );
  }

  Widget _buildMergeTab() {
    final engine = context.read<TransferEngine>();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Combine Multiple PDF Documents into One', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 6),
          Text('Select and reorder documents before generating a 100% valid, openable combined PDF.', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
          const SizedBox(height: 20),

          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: AppColors.onLimeText),
            icon: const Icon(Icons.add),
            label: const Text('Select PDF Files to Merge'),
            onPressed: _pickMergeFiles,
          ),
          const SizedBox(height: 16),

          if (_mergeFiles.isNotEmpty) ...[
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _mergeFiles.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, idx) {
                final file = _mergeFiles[idx];
                return HoverCard(
                  borderRadius: BorderRadius.circular(8),
                  liftOffset: 3.0,
                  scale: 1.012,
                  hoverBorderColor: AppColors.primary,
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                      child: Text('${idx + 1}', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)),
                    ),
                    title: Text(file.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('${FormatUtils.formatBytes(file.size)} • ~${file.pageCount} page(s)'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (idx > 0)
                          IconButton(
                            icon: const Icon(Icons.arrow_upward, size: 18),
                            onPressed: () {
                              setState(() {
                                final item = _mergeFiles.removeAt(idx);
                                _mergeFiles.insert(idx - 1, item);
                              });
                            },
                          ),
                        if (idx < _mergeFiles.length - 1)
                          IconButton(
                            icon: const Icon(Icons.arrow_downward, size: 18),
                            onPressed: () {
                              setState(() {
                                final item = _mergeFiles.removeAt(idx);
                                _mergeFiles.insert(idx + 1, item);
                              });
                            },
                          ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.red, size: 18),
                          onPressed: () => setState(() => _mergeFiles.removeAt(idx)),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.secondary, foregroundColor: AppColors.onLimeText),
                icon: _isMerging
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: AppColors.onLimeText, strokeWidth: 2))
                    : const Icon(Icons.call_merge),
                label: Text(_isMerging ? 'Merging Documents into Standard PDF...' : 'Merge ${_mergeFiles.length} PDFs & Export'),
                onPressed: _isMerging ? null : _executeMerge,
              ),
            ),
          ],

          if (_lastMergedBytes != null && _lastMergedName != null) ...[
            const SizedBox(height: 24),
            HoverCard(
              padding: const EdgeInsets.all(16),
              borderRadius: BorderRadius.circular(10),
              liftOffset: 2.5,
              scale: 1.01,
              color: AppColors.success.withValues(alpha: 0.1),
              borderColor: AppColors.success.withValues(alpha: 0.3),
              hoverBorderColor: AppColors.success,
              child: Row(
                children: [
                  Icon(Icons.check_circle, color: AppColors.success, size: 28),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Merged PDF Ready: $_lastMergedName', style: const TextStyle(fontWeight: FontWeight.bold)),
                        Text('Size: ${FormatUtils.formatBytes(_lastMergedBytes!.length)} • 100% Valid Standard PDF', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                      ],
                    ),
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton.icon(
                        icon: const Icon(Icons.visibility, size: 16),
                        label: const Text('Preview'),
                        onPressed: () => FileActions.runWithSnackBar(context, () => FileActions.open(_lastMergedBytes!, _lastMergedName!)),
                      ),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.download, size: 16),
                        label: const Text('Download'),
                        onPressed: () => FileActions.runWithSnackBar(context, () => FileActions.save(_lastMergedBytes!, _lastMergedName!, directory: engine.downloadDirectory)),
                      ),
                      if (engine.pairedDevices.isNotEmpty)
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: AppColors.onLimeText),
                          icon: const Icon(Icons.send_rounded, size: 16),
                          label: const Text('Send to Paired Device'),
                          onPressed: () {
                            engine.sendFileToMultipleRecipients(
                              fileName: _lastMergedName!,
                              bytes: _lastMergedBytes!,
                              recipients: engine.pairedDevices,
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Sent $_lastMergedName to ${engine.pairedDevices.length} device(s)!')),
                            );
                          },
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // Multi-Output Split Tab (Fourth Image)
  Widget _buildSplitTab() {
    final engine = context.read<TransferEngine>();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Multi-Output PDF Splitter', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 6),
          Text(
            'Split a single source PDF into multiple custom PDFs with individual names and chosen pages (e.g. pdf1: 1, 2, 5 | pdf2: 3, 4 | pdf3: 3).',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
          ),
          const SizedBox(height: 20),

          // Source PDF Selection and Renaming (Audio 2 requirement)
          HoverCard(
            borderRadius: BorderRadius.circular(12),
            padding: const EdgeInsets.all(16),
            liftOffset: 2.5,
            hoverBorderColor: AppColors.primary,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.picture_as_pdf, color: AppColors.primary, size: 24),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('1. Source Document to Split', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          Text('Select or customize the name of the PDF you are splitting', style: TextStyle(fontSize: 12, color: Colors.grey)),
                        ],
                      ),
                    ),
                    if (_splitFile != null)
                      OutlinedButton.icon(
                        icon: const Icon(Icons.swap_horiz, size: 16),
                        label: const Text('Change File'),
                        onPressed: _pickSplitSourcePdf,
                      ),
                  ],
                ),
                const SizedBox(height: 14),

                if (_splitFile == null) ...[
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: AppColors.onLimeText,
                        ),
                        icon: const Icon(Icons.file_open, size: 18),
                        label: const Text('Select PDF from Computer...'),
                        onPressed: _pickSplitSourcePdf,
                      ),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                        label: const Text('Use Active Session PDF'),
                        onPressed: _loadActiveSessionPdf,
                      ),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.science_outlined, size: 18),
                        label: const Text('Load 5-Page Sample Lab PDF'),
                        onPressed: _loadSampleSourcePdf,
                      ),
                    ],
                  ),
                ] else ...[
                  // Editable Source PDF Name Field
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _sourcePdfNameController,
                          decoration: InputDecoration(
                            labelText: 'Name of the PDF You Are Splitting (Editable)',
                            hintText: 'e.g. Computer_Networks_Lab_Manual.pdf',
                            prefixIcon: Icon(Icons.drive_file_rename_outline, color: AppColors.primary),
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          onChanged: (val) {
                            if (val.trim().isNotEmpty && _splitFile != null) {
                              setState(() {
                                _splitFile = PdfToolFile(
                                  name: val.trim(),
                                  size: _splitFile!.size,
                                  bytes: _splitFile!.bytes,
                                  pageCount: _splitFile!.pageCount,
                                );
                              });
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                        ),
                        child: Text(
                          '${_splitFile!.pageCount} Pages • ${FormatUtils.formatBytes(_splitFile!.size)}',
                          style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Batch Rename / Prefix row
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _batchPrefixController,
                          decoration: InputDecoration(
                            labelText: 'Auto-Prefix for Target Split Documents',
                            hintText: 'e.g. Unit_01 or Lab_Manual',
                            prefixIcon: Icon(Icons.auto_awesome, size: 18, color: AppColors.secondary),
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.secondary,
                          foregroundColor: AppColors.onLimeText,
                        ),
                        icon: const Icon(Icons.done_all, size: 16),
                        label: const Text('Apply Prefix to All'),
                        onPressed: () => _applyBatchPrefix(_batchPrefixController.text),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),

          if (_splitFile != null) ...[
            // Output Count Selector
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.15)),
              ),
              child: Row(
                children: [
                  Icon(Icons.pie_chart_outline, color: AppColors.primary),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Number of Target PDFs to Create', style: TextStyle(fontWeight: FontWeight.bold)),
                        Text('Configure how many separate PDF documents to produce', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: _outputPdfCount > 1 ? () => _updateSplitCount(_outputPdfCount - 1) : null,
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '$_outputPdfCount PDFs',
                          style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary, fontSize: 14),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed: _outputPdfCount < 10 ? () => _updateSplitCount(_outputPdfCount + 1) : null,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Individual PDF Configurations
            const Text(
              'CONFIGURE EACH OUTPUT PDF (NAME & PAGES):',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),

            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _splitConfigs.length,
              separatorBuilder: (_, _) => const SizedBox(height: 14),
              itemBuilder: (context, idx) {
                final config = _splitConfigs[idx];
                final maxPages = _splitFile?.pageCount ?? 5;

                return Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(color: AppColors.primary.withValues(alpha: 0.2)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 14,
                              backgroundColor: AppColors.primary,
                              child: Text('${idx + 1}', style: TextStyle(color: AppColors.nearBlack, fontSize: 12, fontWeight: FontWeight.bold)),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller: config.nameController,
                                decoration: InputDecoration(
                                  labelText: 'PDF #${idx + 1} File Name',
                                  hintText: 'e.g. pdf${idx + 1}.pdf',
                                  isDense: true,
                                  border: const OutlineInputBorder(),
                                  prefixIcon: const Icon(Icons.edit, size: 16),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: config.pagesController,
                                onChanged: (_) => setState(() => _parsePagesIntoSet(config)),
                                decoration: const InputDecoration(
                                  labelText: 'Pages to Extract (from Source)',
                                  hintText: 'e.g. 1, 2, 5 or 3-4',
                                  isDense: true,
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.pages, size: 16),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // Quick page toggle chips
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            const Text('Quick Select:', style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
                            for (int pg = 1; pg <= maxPages; pg++)
                              FilterChip(
                                label: Text('Page $pg', style: const TextStyle(fontSize: 11)),
                                selected: config.selectedPages.contains(pg),
                                selectedColor: AppColors.primary,
                                checkmarkColor: AppColors.white,
                                labelStyle: TextStyle(
                                  color: config.selectedPages.contains(pg) ? AppColors.white : null,
                                  fontWeight: FontWeight.w600,
                                ),
                                onSelected: (_) => _togglePageInConfig(config, pg),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),

            const SizedBox(height: 24),

            // Execute Button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: AppColors.onLimeText),
                icon: _isSplitting
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: AppColors.onLimeText, strokeWidth: 2))
                    : const Icon(Icons.call_split),
                label: Text(_isSplitting ? 'Generating Valid Split PDFs...' : 'Execute Multi-PDF Split (${_splitConfigs.length} Documents)'),
                onPressed: _isSplitting ? null : _executeMultiSplit,
              ),
            ),
          ],

          // Split Results Cards
          if (_splitResults.isNotEmpty) ...[
            const SizedBox(height: 32),
            Text(
              'GENERATED SPLIT DOCUMENTS (READY TO DOWNLOAD & OPEN):',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.success),
            ),
            const SizedBox(height: 12),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _splitResults.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, idx) {
                final item = _splitResults[idx];
                return Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(color: AppColors.success.withValues(alpha: 0.3)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Icon(Icons.picture_as_pdf, color: AppColors.success, size: 28),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                              const SizedBox(height: 2),
                              Text('Pages: [${item.pagesDescription}] • ${FormatUtils.formatBytes(item.bytes.length)} • Standard PDF', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                            ],
                          ),
                        ),
                        Wrap(
                          spacing: 8,
                          children: [
                            OutlinedButton.icon(
                              icon: const Icon(Icons.drive_file_rename_outline, size: 14),
                              label: const Text('Rename'),
                              onPressed: () => _renameSplitResult(idx),
                            ),
                            OutlinedButton.icon(
                              icon: const Icon(Icons.visibility, size: 14),
                              label: const Text('Preview'),
                              onPressed: () => FileActions.runWithSnackBar(context, () => FileActions.open(item.bytes, item.name)),
                            ),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: AppColors.onLimeText),
                              icon: const Icon(Icons.download, size: 14),
                              label: const Text('Download'),
                              onPressed: () => FileActions.runWithSnackBar(context, () => FileActions.save(item.bytes, item.name, directory: engine.downloadDirectory)),
                            ),
                            if (engine.pairedDevices.isNotEmpty)
                              IconButton(
                                icon: Icon(Icons.send_rounded, color: AppColors.secondary, size: 20),
                                tooltip: 'Send to Paired Device',
                                onPressed: () {
                                  engine.sendFileToMultipleRecipients(
                                    fileName: item.name,
                                    bytes: item.bytes,
                                    recipients: engine.pairedDevices,
                                  );
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Sent ${item.name} to paired devices!')),
                                  );
                                },
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCompressTab() {
    final engine = context.read<TransferEngine>();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Compress & Optimize PDF File Size', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 6),
          Text('Reduce oversized screenshot PDFs into fully compliant, openable standard PDFs for easy submission.', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
          const SizedBox(height: 20),

          ElevatedButton.icon(
            icon: const Icon(Icons.upload_file),
            label: Text(_compressFile == null ? 'Select PDF to Compress' : 'File: ${_compressFile!.name} (${FormatUtils.formatBytes(_compressFile!.size)})'),
            onPressed: () async {
              final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
              if (files.isNotEmpty) {
                final f = files.first;
                final bytes = await f.readAsBytes();
                final len = (await f.length()) ?? bytes.length;
                setState(() {
                  _compressFile = PdfToolFile(name: f.name, size: len, bytes: bytes);
                  _compressedEstimatedSize = null;
                  _compressedBytes = null;
                });
              }
            },
          ),
          const SizedBox(height: 20),

          if (_compressFile != null) ...[
            const Text('SELECT COMPRESSION PROFILE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: ['Maximum Quality', 'Balanced', 'Smaller File'].map((profile) {
                return ChoiceChip(
                  label: Text(profile),
                  selected: _compressProfile == profile,
                  onSelected: (val) {
                    if (val) {
                      setState(() => _compressProfile = profile);
                    }
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: AppColors.onLimeText),
                icon: _isCompressing
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: AppColors.onLimeText, strokeWidth: 2))
                    : const Icon(Icons.compress),
                label: Text(_isCompressing ? 'Compressing & Validating Standard PDF...' : 'Compress PDF Now'),
                onPressed: _isCompressing ? null : _executeCompression,
              ),
            ),
            const SizedBox(height: 20),

            if (_compressedBytes != null && _compressedEstimatedSize != null)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, color: AppColors.success, size: 28),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Original Size: ${FormatUtils.formatBytes(_compressFile!.size)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                          Text(
                            _compressedEstimatedSize! < _compressFile!.size
                                ? 'Optimized Size: ${FormatUtils.formatBytes(_compressedEstimatedSize!)} (~${((1 - (_compressedEstimatedSize! / _compressFile!.size)) * 100).round()}% smaller)'
                                : 'Result: ${FormatUtils.formatBytes(_compressedEstimatedSize!)} — not smaller than the original',
                            style: TextStyle(color: AppColors.success, fontWeight: FontWeight.bold),
                          ),
                          const Text('Verified Standard-Compliant PDF (Opens seamlessly)', style: TextStyle(fontSize: 11, color: Colors.grey)),
                        ],
                      ),
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        OutlinedButton.icon(
                          icon: const Icon(Icons.visibility, size: 14),
                          label: const Text('Preview'),
                          onPressed: () => FileActions.runWithSnackBar(context, () => FileActions.open(_compressedBytes!, 'Compressed_${_compressFile!.name}')),
                        ),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: AppColors.onLimeText),
                          icon: const Icon(Icons.download, size: 14),
                          label: const Text('Download'),
                          onPressed: () => FileActions.runWithSnackBar(context, () => FileActions.save(_compressedBytes!, 'Compressed_${_compressFile!.name}', directory: engine.downloadDirectory)),
                        ),
                        if (engine.pairedDevices.isNotEmpty)
                          IconButton(
                            icon: Icon(Icons.send_rounded, color: AppColors.secondary, size: 20),
                            tooltip: 'Send to Paired Device',
                            onPressed: () {
                              engine.sendFileToMultipleRecipients(
                                fileName: 'Compressed_${_compressFile!.name}',
                                bytes: _compressedBytes!,
                                recipients: engine.pairedDevices,
                              );
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Sent compressed PDF to paired devices!')),
                              );
                            },
                          ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildOcrTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Optical Character Recognition (Searchable PDF)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 6),
          Text(
            'Recognizes text in screenshots and scanned PDFs, and can save a searchable PDF. '
            'The OCR engine is downloaded on first use, so an internet connection is needed.',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
          ),
          const SizedBox(height: 20),

          ElevatedButton.icon(
            icon: const Icon(Icons.image_search),
            label: Text(_ocrFile == null ? 'Select Screenshot Image or PDF' : 'Selected: ${_ocrFile!.name}'),
            onPressed: () async {
              final files = await FilePicker.pickFiles(
                type: FileType.custom,
                allowedExtensions: ['png', 'jpg', 'jpeg', 'pdf'],
              );
              if (files.isNotEmpty) {
                final f = files.first;
                final bytes = await f.readAsBytes();
                final len = (await f.length()) ?? bytes.length;
                setState(() {
                  _ocrFile = PdfToolFile(name: f.name, size: len, bytes: bytes);
                  _ocrResult = null;
                  _ocrError = null;
                });
              }
            },
          ),
          const SizedBox(height: 16),

          if (_ocrFile != null) ...[
            DropdownButtonFormField<String>(
              initialValue: _ocrLanguage,
              decoration: const InputDecoration(labelText: 'Recognition Language Model', border: OutlineInputBorder(), isDense: true),
              items: OcrService.languages.keys.map((l) => DropdownMenuItem(value: l, child: Text(l))).toList(),
              onChanged: (val) {
                if (val != null) setState(() => _ocrLanguage = val);
              },
            ),
            const SizedBox(height: 16),

            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: AppColors.onLimeText),
              icon: _isProcessingOcr
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onLimeText))
                  : const Icon(Icons.document_scanner),
              label: Text(_isProcessingOcr ? 'Recognizing Text...' : 'Run OCR & Extract Text'),
              onPressed: _isProcessingOcr ? null : _executeOcr,
            ),
            const SizedBox(height: 20),

            if (_isProcessingOcr && _ocrProgress != null)
              Text(_ocrProgress!, style: TextStyle(color: AppColors.secondaryText, fontSize: 12)),
            if (_ocrError != null)
              Text(_ocrError!, style: TextStyle(color: AppColors.error, fontSize: 13)),
            if (_ocrResult != null) ...[
              Text(
                _ocrResult!.text.trim().isEmpty
                    ? 'No text was found.'
                    : 'Recognized text · confidence ${_ocrResult!.confidence.round()}%',
                style: TextStyle(color: AppColors.secondaryText, fontSize: 12, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxHeight: 360),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.cardBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.white.withValues(alpha: 0.12)),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    _ocrResult!.text,
                    style: TextStyle(color: AppColors.secondary, fontFamily: 'monospace', fontSize: 13),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('Copy Text'),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: _ocrResult!.text));
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Text copied')));
                      }
                    },
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.text_snippet_outlined, size: 16),
                    label: const Text('Save as .txt'),
                    onPressed: _saveOcrText,
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: AppColors.onLimeText),
                    icon: const Icon(Icons.picture_as_pdf, size: 16),
                    label: const Text('Save Searchable PDF'),
                    onPressed: _saveSearchablePdf,
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _SupportedFormatPill extends StatelessWidget {
  final String label;
  const _SupportedFormatPill(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.subtleBorder),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 11,
          color: AppColors.softGray,
        ),
      ),
    );
  }
}

class SearchableFormatPickerDialog extends StatefulWidget {
  final String fileName;
  final ConversionFormat currentFormat;
  final List<ConversionFormat> availableFormats;

  const SearchableFormatPickerDialog({
    super.key,
    required this.fileName,
    required this.currentFormat,
    required this.availableFormats,
  });

  @override
  State<SearchableFormatPickerDialog> createState() => _SearchableFormatPickerDialogState();
}

class _SearchableFormatPickerDialogState extends State<SearchableFormatPickerDialog> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _getCategoryForFormat(ConversionFormat format) => format.category;

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case 'Documents':
        return Icons.description_rounded;
      case 'Spreadsheets & Data':
        return Icons.table_chart_rounded;
      case 'Images':
        return Icons.image_rounded;
      case '3D Models':
        return Icons.view_in_ar_rounded;
      case 'Archives':
        return Icons.folder_zip_rounded;
      default:
        return Icons.folder_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    final filtered = widget.availableFormats.where((format) {
      if (query.isEmpty) return true;
      return format.label.toLowerCase().contains(query) ||
          format.outputExtension.toLowerCase().contains(query);
    }).toList();

    final categories = <String, List<ConversionFormat>>{};
    for (final format in filtered) {
      final cat = _getCategoryForFormat(format);
      categories.putIfAbsent(cat, () => []).add(format);
    }

    return Dialog(
      backgroundColor: AppColors.charcoalSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppColors.subtleBorder),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 520),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.limeGreen.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.swap_horiz_rounded, color: AppColors.limeGreen, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Select Output Format',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            color: AppColors.white,
                          ),
                        ),
                        Text(
                          'Compatible with ${widget.fileName}',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 11.5,
                            color: AppColors.softGray,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: AppColors.softGray, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Search Input
              TextField(
                controller: _searchController,
                autofocus: true,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: AppColors.white,
                  fontSize: 13,
                ),
                cursorColor: AppColors.limeGreen,
                decoration: InputDecoration(
                  hintText: 'Search formats (e.g. PDF, Word, PNG, STL, ZIP)...',
                  hintStyle: TextStyle(
                    fontFamily: 'Poppins',
                    color: AppColors.softGray,
                    fontSize: 12.5,
                  ),
                  prefixIcon: Icon(Icons.search_rounded, color: AppColors.limeGreen, size: 18),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.clear_rounded, color: AppColors.softGray, size: 16),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {});
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: AppColors.cardBg,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: AppColors.subtleBorder),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: AppColors.subtleBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: AppColors.limeGreen, width: 1.5),
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 14),

              // Grouped Format List
              Flexible(
                child: filtered.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.search_off_rounded, color: AppColors.softGray.withValues(alpha: 0.5), size: 36),
                              const SizedBox(height: 8),
                              Text(
                                'No formats match "${_searchController.text.trim()}"',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 12.5,
                                  color: AppColors.softGray,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView(
                        shrinkWrap: true,
                        children: [
                          for (final entry in categories.entries) ...[
                            Padding(
                              padding: const EdgeInsets.only(top: 8, bottom: 6),
                              child: Row(
                                children: [
                                  Icon(_getCategoryIcon(entry.key), size: 14, color: AppColors.limeGreen),
                                  const SizedBox(width: 6),
                                  Text(
                                    entry.key.toUpperCase(),
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.7,
                                      color: AppColors.softGray,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Divider(
                                      color: AppColors.subtleBorder.withValues(alpha: 0.6),
                                      thickness: 0.8,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            for (final format in entry.value) ...[
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: InkWell(
                                  onTap: () => Navigator.of(context).pop(format),
                                  borderRadius: BorderRadius.circular(10),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                    decoration: BoxDecoration(
                                      color: format == widget.currentFormat
                                          ? AppColors.limeGreen.withValues(alpha: 0.12)
                                          : AppColors.cardBg,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: format == widget.currentFormat
                                            ? AppColors.limeGreen
                                            : AppColors.subtleBorder,
                                        width: format == widget.currentFormat ? 1.5 : 1.0,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          format == widget.currentFormat
                                              ? Icons.check_circle_rounded
                                              : Icons.radio_button_unchecked_rounded,
                                          color: format == widget.currentFormat
                                              ? AppColors.limeGreen
                                              : AppColors.softGray,
                                          size: 18,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            format.label,
                                            style: TextStyle(
                                              fontFamily: 'Poppins',
                                              fontSize: 13,
                                              fontWeight: format == widget.currentFormat
                                                  ? FontWeight.w600
                                                  : FontWeight.w400,
                                              color: format == widget.currentFormat
                                                  ? AppColors.primaryText
                                                  : AppColors.secondaryText,
                                            ),
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: format == widget.currentFormat
                                                ? AppColors.limeGreen.withValues(alpha: 0.2)
                                                : AppColors.surfaceElevated,
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            format.outputExtension.toUpperCase(),
                                            style: TextStyle(
                                              fontFamily: 'Poppins',
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: format == widget.currentFormat
                                                  ? AppColors.limeGreen
                                                  : AppColors.softGray,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SplitInputError implements Exception {
  final String message;
  _SplitInputError(this.message);
}
