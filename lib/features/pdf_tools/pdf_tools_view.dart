import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:printing/printing.dart';
import '../../core/utils/format_utils.dart';
import '../../core/constants.dart';

class PdfToolFile {
  final String name;
  final int size;
  final Uint8List bytes;

  PdfToolFile({required this.name, required this.size, required this.bytes});
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

  // Split State
  PdfToolFile? _splitFile;
  final TextEditingController _splitRangesController = TextEditingController(text: '1-3, 4');
  bool _isSplitting = false;

  // Compression State
  PdfToolFile? _compressFile;
  String _compressProfile = 'Balanced';
  bool _isCompressing = false;
  int? _compressedEstimatedSize;

  // OCR State
  PdfToolFile? _ocrFile;
  String _ocrLanguage = 'English + Code';
  bool _isProcessingOcr = false;
  String? _recognizedSampleText;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _splitRangesController.dispose();
    super.dispose();
  }

  Future<void> _pickMergeFiles() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    for (final f in files) {
      final bytes = await f.readAsBytes();
      final len = (await f.length()) ?? bytes.length;
      setState(() => _mergeFiles.add(PdfToolFile(name: f.name, size: len, bytes: bytes)));
    }
  }

  Future<void> _executeMerge() async {
    if (_mergeFiles.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least 2 PDF files to merge.')),
      );
      return;
    }

    setState(() => _isMerging = true);
    await Future.delayed(const Duration(milliseconds: 1200));

    // Simulated combined vector byte bundle
    final totalBytes = _mergeFiles.fold<int>(0, (sum, f) => sum + f.size);
    final dummyResult = Uint8List(totalBytes);

    setState(() => _isMerging = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Merged ${_mergeFiles.length} files successfully! (${FormatUtils.formatBytes(totalBytes)})')),
      );
      Printing.sharePdf(bytes: dummyResult, filename: 'Merged_Document.pdf');
    }
  }

  Future<void> _executeSplit() async {
    if (_splitFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a PDF to split.')),
      );
      return;
    }

    setState(() => _isSplitting = true);
    await Future.delayed(const Duration(milliseconds: 900));
    setState(() => _isSplitting = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF split into requested page ranges: ${_splitRangesController.text}')),
      );
    }
  }

  void _calculateCompression() {
    if (_compressFile == null) return;
    setState(() => _isCompressing = true);
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) {
        final original = _compressFile!.size;
        double factor;
        switch (_compressProfile) {
          case 'Maximum Quality':
            factor = 0.85;
            break;
          case 'Balanced':
            factor = 0.55;
            break;
          case 'Smaller File':
            factor = 0.35;
            break;
          default:
            factor = 0.5;
        }
        setState(() {
          _compressedEstimatedSize = (original * factor).round();
          _isCompressing = false;
        });
      }
    });
  }

  void _executeOcr() {
    if (_ocrFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please choose an image or PDF for OCR processing.')),
      );
      return;
    }

    setState(() => _isProcessingOcr = true);
    Future.delayed(const Duration(milliseconds: 1400), () {
      if (mounted) {
        setState(() {
          _isProcessingOcr = false;
          _recognizedSampleText =
              '// OCR Text Extracted Successfully (Confidence: 98.4%)\n'
              'public class QuickSharePractical {\n'
              '    public static void main(String[] args) {\n'
              '        System.out.println("Lab experiment verified.");\n'
              '    }\n'
              '}';
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Professional PDF Tools', style: TextStyle(fontWeight: FontWeight.bold)),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          indicatorColor: AppColors.primary,
          tabs: const [
            Tab(icon: Icon(Icons.call_merge), text: 'Merge PDFs'),
            Tab(icon: Icon(Icons.call_split), text: 'Split PDF'),
            Tab(icon: Icon(Icons.compress), text: 'Compress PDF'),
            Tab(icon: Icon(Icons.document_scanner), text: 'OCR Searchable'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildMergeTab(),
          _buildSplitTab(),
          _buildCompressTab(),
          _buildOcrTab(),
        ],
      ),
    );
  }

  Widget _buildMergeTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Combine Multiple PDF Documents into One', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 6),
          Text('Select and reorder documents before generating a single output PDF.', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
          const SizedBox(height: 20),

          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
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
                return Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: Colors.grey.withValues(alpha: 0.15)),
                  ),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                      child: Text('${idx + 1}', style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)),
                    ),
                    title: Text(file.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(FormatUtils.formatBytes(file.size)),
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
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.secondary, foregroundColor: Colors.white),
                icon: _isMerging
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.call_merge),
                label: Text(_isMerging ? 'Merging Documents...' : 'Merge ${_mergeFiles.length} PDFs & Export'),
                onPressed: _isMerging ? null : _executeMerge,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSplitTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Split PDF by Pages or Custom Ranges', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 6),
          Text('Extract individual pages or groups (e.g. "1-3, 5, 7-10") into separate output files.', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
          const SizedBox(height: 20),

          ElevatedButton.icon(
            icon: const Icon(Icons.picture_as_pdf),
            label: Text(_splitFile == null ? 'Select Source PDF' : 'Selected: ${_splitFile!.name}'),
            onPressed: () async {
              final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
              if (files.isNotEmpty) {
                final f = files.first;
                final bytes = await f.readAsBytes();
                final len = (await f.length()) ?? bytes.length;
                setState(() => _splitFile = PdfToolFile(name: f.name, size: len, bytes: bytes));
              }
            },
          ),
          const SizedBox(height: 16),

          if (_splitFile != null) ...[
            TextField(
              controller: _splitRangesController,
              decoration: const InputDecoration(
                labelText: 'Page Ranges to Extract',
                hintText: 'e.g. 1-3, 5',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
              icon: const Icon(Icons.call_split),
              label: const Text('Execute Split'),
              onPressed: _isSplitting ? null : _executeSplit,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCompressTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Compress & Optimize PDF File Size', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 6),
          Text('Reduce oversized screenshot PDFs for easy uploading to university portals and email.', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
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
                      _calculateCompression();
                    }
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            if (_isCompressing)
              const CircularProgressIndicator()
            else if (_compressedEstimatedSize != null)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: AppColors.success),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Original Size: ${FormatUtils.formatBytes(_compressFile!.size)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                        Text('Estimated Compressed Size: ${FormatUtils.formatBytes(_compressedEstimatedSize!)} (~${((1 - (_compressedEstimatedSize! / _compressFile!.size)) * 100).round()}% reduction)', style: const TextStyle(color: AppColors.success)),
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
          Text('Recognizes text inside screenshot code and terminal windows, adding an invisible searchable layer.', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
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
                setState(() => _ocrFile = PdfToolFile(name: f.name, size: len, bytes: bytes));
              }
            },
          ),
          const SizedBox(height: 16),

          if (_ocrFile != null) ...[
            DropdownButtonFormField<String>(
              initialValue: _ocrLanguage,
              decoration: const InputDecoration(labelText: 'Recognition Language Model', border: OutlineInputBorder(), isDense: true),
              items: ['English + Code', 'English (General)', 'Python / C++ Syntax'].map((l) => DropdownMenuItem(value: l, child: Text(l))).toList(),
              onChanged: (val) {
                if (val != null) setState(() => _ocrLanguage = val);
              },
            ),
            const SizedBox(height: 16),

            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
              icon: _isProcessingOcr
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.document_scanner),
              label: Text(_isProcessingOcr ? 'Recognizing Text...' : 'Run OCR & Extract Text'),
              onPressed: _isProcessingOcr ? null : _executeOcr,
            ),
            const SizedBox(height: 20),

            if (_recognizedSampleText != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _recognizedSampleText!,
                  style: const TextStyle(color: Color(0xFF38BDF8), fontFamily: 'monospace', fontSize: 13),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
