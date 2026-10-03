import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../data/models/pdf_project.dart';
import '../../data/models/screenshot_item.dart';
import 'widgets/page_preview_canvas.dart';
import 'widgets/page_thumbnails_bar.dart';
import 'widgets/layout_settings_panel.dart';
import 'widgets/export_dialog.dart';
import '../../core/utils/sample_screenshot_generator.dart';
import '../../core/constants.dart';

class PdfEditorView extends StatefulWidget {
  final PdfProject? initialProject;
  final Function(List<ScreenshotItem> images)? onSendCollectionToDevice;

  const PdfEditorView({
    super.key,
    this.initialProject,
    this.onSendCollectionToDevice,
  });

  @override
  State<PdfEditorView> createState() => _PdfEditorViewState();
}

class _PdfEditorViewState extends State<PdfEditorView> {
  late PdfProject _project;
  int _currentPageIndex = 0;
  double _zoomScale = 1.0;
  bool _showPrintableGuides = true;
  bool _showSafeGuides = true;
  PageBackgroundStyle _bgStyle = PageBackgroundStyle.white;

  // Undo / Redo stack
  final List<List<PdfPageModel>> _undoStack = [];
  final List<List<PdfPageModel>> _redoStack = [];

  @override
  void initState() {
    super.initState();
    _project = widget.initialProject ?? PdfProject(title: 'Java_Lab_Screenshots');
  }

  void _saveUndoState() {
    _undoStack.add(_project.pages.map((p) => p.copyWith()).toList());
    _redoStack.clear();
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    _redoStack.add(_project.pages.map((p) => p.copyWith()).toList());
    setState(() {
      _project.pages = _undoStack.removeLast();
      if (_currentPageIndex >= _project.pages.length) {
        _currentPageIndex = _project.pages.length - 1;
      }
    });
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    _undoStack.add(_project.pages.map((p) => p.copyWith()).toList());
    setState(() {
      _project.pages = _redoStack.removeLast();
      if (_currentPageIndex >= _project.pages.length) {
        _currentPageIndex = _project.pages.length - 1;
      }
    });
  }

  PdfPageModel get _currentPage {
    if (_project.pages.isEmpty) {
      _project.pages = [PdfPageModel(pageNumber: 1)];
      _currentPageIndex = 0;
    }
    final index = _currentPageIndex.clamp(0, _project.pages.length - 1);
    return _project.pages[index];
  }

  void _addImages(List<ScreenshotItem> newImages) {
    if (newImages.isEmpty) return;
    _saveUndoState();

    // Check for duplicate images across the project
    final existingHashes = <String>{};
    for (final page in _project.pages) {
      for (final img in page.images) {
        existingHashes.add(img.sha256);
      }
    }

    final duplicates = newImages.where((img) => existingHashes.contains(img.sha256)).toList();
    if (duplicates.isNotEmpty) {
      _showDuplicateWarning(duplicates, () {
        _performAddImages(newImages);
      });
      return;
    }

    _performAddImages(newImages);
  }

  void _performAddImages(List<ScreenshotItem> imagesToAdd) {
    setState(() {
      if (_project.autoContinuePages) {
        // Collect all images and auto-distribute
        final allImages = <ScreenshotItem>[];
        for (final p in _project.pages) {
          allImages.addAll(p.images);
        }
        allImages.addAll(imagesToAdd);

        _project.autoDistributeScreenshots(
          allImages,
          defaultPreset: _currentPage.presetType,
          defaultGeometry: _currentPage.geometry,
          defaultFitMode: _currentPage.fitMode,
          defaultCaptions: _currentPage.showCaptions,
        );
      } else {
        // Just append to current page
        _currentPage.images.addAll(imagesToAdd);
      }
    });
  }

  void _showDuplicateWarning(List<ScreenshotItem> duplicates, VoidCallback onKeepBoth) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.warning),
            SizedBox(width: 8),
            Text('Duplicate Screenshot Detected'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Found ${duplicates.length} image(s) identical to screenshots already in this document (matching SHA-256 cryptographic hash):',
            ),
            const SizedBox(height: 8),
            for (final d in duplicates.take(3))
              Text('• ${d.name} (${d.sha256.substring(0, 8)}...)', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            const Text('What would you like to do?'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Skip Duplicate'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(context);
              onKeepBoth();
            },
            child: const Text('Keep Both'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickImageFiles() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['png', 'jpg', 'jpeg', 'webp', 'bmp'],
      );

      if (files.isNotEmpty) {
        final imported = <ScreenshotItem>[];
        for (final f in files) {
          final bytes = await f.readAsBytes();
          imported.add(
            ScreenshotItem(
              name: f.name,
              bytes: bytes,
              caption: f.name.replaceAll(RegExp(r'\.[^.]+$'), ''),
            ),
          );
        }
        _addImages(imported);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error selecting images: $e')));
      }
    }
  }

  Future<void> _importSampleLabScreenshots() async {
    final samples = await SampleScreenshotGenerator.generateLabSamples();
    _addImages(samples);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Imported 6 realistic lab screenshots (Java, Terminal, Python, etc.)')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 960;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.picture_as_pdf, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(
              _project.title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
        actions: [
          // Undo / Redo
          IconButton(
            icon: const Icon(Icons.undo),
            tooltip: 'Undo',
            onPressed: _undoStack.isNotEmpty ? _undo : null,
          ),
          IconButton(
            icon: const Icon(Icons.redo),
            tooltip: 'Redo',
            onPressed: _redoStack.isNotEmpty ? _redo : null,
          ),
          const SizedBox(width: 8),

          // Import Sample Lab Screenshots Action
          OutlinedButton.icon(
            icon: const Icon(Icons.science_outlined, size: 16),
            label: const Text('Load Lab Samples', style: TextStyle(fontSize: 12)),
            onPressed: _importSampleLabScreenshots,
          ),
          const SizedBox(width: 8),

          // Add Screenshots
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.add_photo_alternate, size: 18),
            label: const Text('Add Images'),
            onPressed: _pickImageFiles,
          ),
          const SizedBox(width: 8),

          // Export & Print PDF
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.secondary,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.download, size: 18),
            label: const Text('Export PDF'),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => ExportDialog(
                  project: _project,
                  onSendToDevice: (bytes, name) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Prepared $name for device transmission.')),
                    );
                  },
                ),
              );
            },
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: isDesktop ? _buildDesktopLayout() : _buildMobileLayout(),
    );
  }

  Widget _buildDesktopLayout() {
    return Row(
      children: [
        // Left: Page Thumbnails & Document Navigation
        PageThumbnailsBar(
          pages: _project.pages,
          selectedPageIndex: _currentPageIndex,
          onSelectPage: (idx) => setState(() => _currentPageIndex = idx),
          onAddPage: () {
            _saveUndoState();
            setState(() {
              final newPageNum = _project.pages.length + 1;
              _project.pages.add(
                PdfPageModel(
                  pageNumber: newPageNum,
                  presetType: _currentPage.presetType,
                  geometry: _currentPage.geometry,
                ),
              );
              _currentPageIndex = _project.pages.length - 1;
            });
          },
          onDuplicatePage: (idx) {
            _saveUndoState();
            setState(() {
              final target = _project.pages[idx];
              final duplicated = target.copyWith(pageNumber: _project.pages.length + 1);
              _project.pages.insert(idx + 1, duplicated);
              _reindexPages();
              _currentPageIndex = idx + 1;
            });
          },
          onDeletePage: (idx) {
            if (_project.pages.length <= 1) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Cannot delete the only page.')),
              );
              return;
            }
            _saveUndoState();
            setState(() {
              _project.pages.removeAt(idx);
              _reindexPages();
              if (_currentPageIndex >= _project.pages.length) {
                _currentPageIndex = _project.pages.length - 1;
              }
            });
          },
          onReorderPage: (oldIdx, newIdx) {
            _saveUndoState();
            setState(() {
              final item = _project.pages.removeAt(oldIdx);
              _project.pages.insert(newIdx, item);
              _reindexPages();
              _currentPageIndex = newIdx;
            });
          },
        ),

        // Center: Xerox-Ready Live Preview & Canvas Floating Toolbar
        Expanded(
          child: Column(
            children: [
              // Zoom & Guide Toolbar
              _buildCanvasToolbar(),

              // Canvas Preview
              Expanded(
                child: Container(
                  color: const Color(0xFF0B0F19), // Neutral dark workspace backdrop
                  child: PagePreviewCanvas(
                    page: _currentPage,
                    totalPages: _project.pages.length,
                    zoomScale: _zoomScale,
                    showPrintableGuides: _showPrintableGuides,
                    showSafeMarginGuides: _showSafeGuides,
                    backgroundStyle: _bgStyle,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Right: Layout & Page Settings Panel
        LayoutSettingsPanel(
          page: _currentPage,
          autoContinue: _project.autoContinuePages,
          onPresetChanged: (preset) {
            _saveUndoState();
            setState(() {
              _currentPage = _currentPage.copyWith(presetType: preset);
              if (_project.autoContinuePages) {
                final allImages = <ScreenshotItem>[];
                for (final p in _project.pages) {
                  allImages.addAll(p.images);
                }
                _project.autoDistributeScreenshots(
                  allImages,
                  defaultPreset: preset,
                  defaultGeometry: _currentPage.geometry,
                );
              }
            });
          },
          onPaperSizeChanged: (size) {
            _saveUndoState();
            setState(() {
              _currentPage = _currentPage.copyWith(
                geometry: _currentPage.geometry.copyWith(paperSize: size),
              );
            });
          },
          onOrientationChanged: (isLand) {
            _saveUndoState();
            setState(() {
              _currentPage = _currentPage.copyWith(
                geometry: _currentPage.geometry.copyWith(isLandscape: isLand),
              );
            });
          },
          onMarginChanged: (m) {
            _saveUndoState();
            setState(() {
              _currentPage = _currentPage.copyWith(
                geometry: _currentPage.geometry.copyWith(marginPoints: m),
              );
            });
          },
          onSpacingChanged: (s) {
            _saveUndoState();
            setState(() {
              _currentPage = _currentPage.copyWith(spacingPoints: s);
            });
          },
          onFitModeChanged: (mode) {
            _saveUndoState();
            setState(() {
              _currentPage = _currentPage.copyWith(fitMode: mode);
            });
          },
          onCaptionsChanged: (show) {
            _saveUndoState();
            setState(() {
              _currentPage = _currentPage.copyWith(showCaptions: show);
            });
          },
          onAutoContinueChanged: (auto) {
            setState(() {
              _project.autoContinuePages = auto;
            });
          },
          onCustomGridChanged: (r, c) {
            _saveUndoState();
            setState(() {
              _currentPage = _currentPage.copyWith(customRows: r, customCols: c);
            });
          },
          onClearPageImages: () {
            _saveUndoState();
            setState(() {
              _currentPage.images.clear();
            });
          },
        ),
      ],
    );
  }

  Widget _buildMobileLayout() {
    return Column(
      children: [
        _buildCanvasToolbar(),
        Expanded(
          child: PagePreviewCanvas(
            page: _currentPage,
            totalPages: _project.pages.length,
            zoomScale: _zoomScale,
            showPrintableGuides: _showPrintableGuides,
            showSafeMarginGuides: _showSafeGuides,
            backgroundStyle: _bgStyle,
          ),
        ),
        // Mobile bottom action sheet trigger
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Theme.of(context).cardColor,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Page ${_currentPage.pageNumber} / ${_project.pages.length}'),
              TextButton.icon(
                icon: const Icon(Icons.tune),
                label: const Text('Layout Settings'),
                onPressed: () {
                  showModalBottomSheet(
                    context: context,
                    builder: (ctx) => LayoutSettingsPanel(
                      page: _currentPage,
                      autoContinue: _project.autoContinuePages,
                      onPresetChanged: (preset) => setState(() => _currentPage = _currentPage.copyWith(presetType: preset)),
                      onPaperSizeChanged: (sz) => setState(() => _currentPage = _currentPage.copyWith(geometry: _currentPage.geometry.copyWith(paperSize: sz))),
                      onOrientationChanged: (l) => setState(() => _currentPage = _currentPage.copyWith(geometry: _currentPage.geometry.copyWith(isLandscape: l))),
                      onMarginChanged: (m) => setState(() => _currentPage = _currentPage.copyWith(geometry: _currentPage.geometry.copyWith(marginPoints: m))),
                      onSpacingChanged: (s) => setState(() => _currentPage = _currentPage.copyWith(spacingPoints: s)),
                      onFitModeChanged: (fm) => setState(() => _currentPage = _currentPage.copyWith(fitMode: fm)),
                      onCaptionsChanged: (c) => setState(() => _currentPage = _currentPage.copyWith(showCaptions: c)),
                      onAutoContinueChanged: (ac) => setState(() => _project.autoContinuePages = ac),
                      onCustomGridChanged: (r, c) => setState(() => _currentPage = _currentPage.copyWith(customRows: r, customCols: c)),
                      onClearPageImages: () => setState(() => _currentPage.images.clear()),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCanvasToolbar() {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color: Theme.of(context).cardColor,
      child: Row(
        children: [
          // Page Navigation
          IconButton(
            icon: const Icon(Icons.chevron_left),
            tooltip: 'Previous Page',
            onPressed: _currentPageIndex > 0
                ? () => setState(() => _currentPageIndex--)
                : null,
          ),
          Text(
            'Page ${_currentPage.pageNumber} of ${_project.pages.length}',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Next Page',
            onPressed: _currentPageIndex < _project.pages.length - 1
                ? () => setState(() => _currentPageIndex++)
                : null,
          ),
          const VerticalDivider(indent: 10, endIndent: 10),

          // Zoom Controls
          IconButton(
            icon: const Icon(Icons.zoom_out, size: 20),
            tooltip: 'Zoom Out',
            onPressed: () => setState(() => _zoomScale = (_zoomScale - 0.15).clamp(0.4, 3.0)),
          ),
          Text(
            '${(_zoomScale * 100).round()}%',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          IconButton(
            icon: const Icon(Icons.zoom_in, size: 20),
            tooltip: 'Zoom In',
            onPressed: () => setState(() => _zoomScale = (_zoomScale + 0.15).clamp(0.4, 3.0)),
          ),
          TextButton(
            child: const Text('Fit Page', style: TextStyle(fontSize: 11)),
            onPressed: () => setState(() => _zoomScale = 1.0),
          ),
          const VerticalDivider(indent: 10, endIndent: 10),

          // Guides Toggles
          Tooltip(
            message: 'Toggle Margin Printable Guide',
            child: FilterChip(
              label: const Text('Margins', style: TextStyle(fontSize: 11)),
              selected: _showPrintableGuides,
              onSelected: (val) => setState(() => _showPrintableGuides = val),
            ),
          ),
          const SizedBox(width: 6),
          Tooltip(
            message: 'Toggle Xerox Hardware Safe-Area Guide (~5mm)',
            child: FilterChip(
              label: const Text('Xerox Guide', style: TextStyle(fontSize: 11)),
              selected: _showSafeGuides,
              onSelected: (val) => setState(() => _showSafeGuides = val),
            ),
          ),
          const Spacer(),

          // Page Background Tint Selector
          PopupMenuButton<PageBackgroundStyle>(
            tooltip: 'Paper Sheet Background',
            icon: const Icon(Icons.palette_outlined, size: 20),
            onSelected: (style) => setState(() => _bgStyle = style),
            itemBuilder: (context) => [
              const PopupMenuItem(value: PageBackgroundStyle.white, child: Text('White Paper')),
              const PopupMenuItem(value: PageBackgroundStyle.cream, child: Text('Cream / Off-White')),
              const PopupMenuItem(value: PageBackgroundStyle.dark, child: Text('Dark Proofing Canvas')),
            ],
          ),
        ],
      ),
    );
  }

  void _reindexPages() {
    for (var i = 0; i < _project.pages.length; i++) {
      _project.pages[i].pageNumber = i + 1;
    }
  }

  set _currentPage(PdfPageModel newPage) {
    if (_project.pages.isNotEmpty && _currentPageIndex < _project.pages.length) {
      _project.pages[_currentPageIndex] = newPage;
    }
  }
}
