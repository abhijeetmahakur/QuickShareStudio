import '../../core/constants.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import '../../data/models/pdf_project.dart';
import '../../data/models/screenshot_item.dart';
import '../../core/services/clipboard_image_service.dart';
import '../pdf_layout/models/layout_preset.dart';
import 'widgets/page_preview_canvas.dart';
import 'widgets/page_thumbnails_bar.dart';
import 'widgets/layout_settings_panel.dart';
import 'widgets/export_dialog.dart';
import '../../core/utils/file_utils.dart';
import '../../core/utils/format_utils.dart';
import '../../core/utils/sample_screenshot_generator.dart';

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
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late PdfProject _project;
  late TextEditingController _fileNameController;
  late FocusNode _fileNameFocusNode;
  String _pdfFileName = 'QuickShare_Document.pdf';
  bool _isLayoutPanelVisible = true;
  int _currentPageIndex = 0;
  double _zoomScale = 1.0;
  bool _showPrintableGuides = true;
  bool _showSafeGuides = true;
  PageBackgroundStyle _bgStyle = PageBackgroundStyle.white;
  Timer? _dropPollTimer;

  // In-app Add Images Panel state
  bool _isAddImagesPanelOpen = false;
  final List<ScreenshotItem> _stagedImages = [];
  bool _isStagingLoading = false;

  // Paste control notification state
  final GlobalKey _pasteButtonKey = GlobalKey();
  OverlayEntry? _pasteNoticeOverlay;
  Timer? _pasteNoticeTimer;

  // False while another tab of the app shell's IndexedStack is showing.
  bool _isVisible = true;

  // Official Dark Lime Design Palette Tokens
  static Color get scaffoldBg => AppColors.dashboardBg;
  static Color get panelBg => AppColors.charcoalSurface;
  static Color get cardBg => AppColors.cardBg;
  static Color get limeAccent => AppColors.primaryAccent;
  static Color get softGray => AppColors.secondaryText;
  static Color get primaryWhite => AppColors.primaryText;
  static const Color darkText = AppColors.nearBlack;
  static Color get subtleBorder => AppColors.subtleBorder;
  static Color get subtleBorderLight => AppColors.subtleBorderLight;

  // Undo / Redo stack
  final List<List<PdfPageModel>> _undoStack = [];
  final List<List<PdfPageModel>> _redoStack = [];

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleGlobalKeyboard);
    ClipboardImageService.setWebPasteHandler(_handleWebPaste);
    final initTitle = widget.initialProject?.title;
    if (initTitle != null && initTitle.trim().isNotEmpty && initTitle != 'Untitled_Lab_Document') {
      _pdfFileName = FileUtils.formatPdfFilename(initTitle);
      _project = widget.initialProject!;
    } else {
      _pdfFileName = 'QuickShare_Document.pdf';
      _project = widget.initialProject ?? PdfProject(title: 'QuickShare_Document');
    }
    _fileNameController = TextEditingController(text: _pdfFileName);
    _fileNameFocusNode = FocusNode();
    _fileNameFocusNode.addListener(() {
      if (!_fileNameFocusNode.hasFocus) {
        _commitPdfFileName(_fileNameController.text);
      }
    });
    _dropPollTimer = Timer.periodic(const Duration(milliseconds: 700), (_) => _checkForDroppedFiles());
  }

  @override
  void dispose() {
    _dismissPasteNotice();
    HardwareKeyboard.instance.removeHandler(_handleGlobalKeyboard);
    ClipboardImageService.setWebPasteHandler(null);
    _dropPollTimer?.cancel();
    _fileNameController.dispose();
    _fileNameFocusNode.dispose();
    super.dispose();
  }

  void _openExportDialog() {
    showDialog(
      context: context,
      builder: (context) => ExportDialog(
        project: _project,
        initialFileName: _pdfFileName,
        onFileNameChanged: _commitPdfFileName,
        onSendToDevice: (bytes, name) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Prepared $name for device transmission.',
                style: const TextStyle(fontFamily: 'Poppins'),
              ),
              backgroundColor: cardBg,
            ),
          );
        },
      ),
    );
  }

  bool _handleGlobalKeyboard(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    // On web, Ctrl+V must reach the browser so it fires the native paste event
    // (handled in _handleWebPaste); marking it handled would preventDefault it.
    if (kIsWeb || !_isVisible) return false;
    final isControlOrMeta = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    if (isControlOrMeta && event.logicalKey == LogicalKeyboardKey.keyV) {
      if (_isTextFieldFocused) return false;
      _handlePasteScreenshot();
      return true;
    }
    return false;
  }

  bool get _isTextFieldFocused {
    final focusContext = FocusManager.instance.primaryFocus?.context;
    return focusContext != null &&
        focusContext.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  Future<void> _handleWebPaste(String? dataUrl) async {
    if (!mounted || !_isVisible || _isTextFieldFocused) return;
    final screenshot = dataUrl == null ? null : await ClipboardImageService.screenshotFromDataUrl(dataUrl);
    if (!mounted) return;
    if (screenshot == null) {
      _showPasteFailedNotification();
      return;
    }
    _dismissPasteNotice();
    _addImages([screenshot]);
    _showPastedSnackBar(screenshot.name);
  }

  void _commitPdfFileName(String value) {
    final sanitized = FileUtils.formatPdfFilename(value, fallback: 'QuickShare_Document.pdf');
    if (sanitized != _pdfFileName || _fileNameController.text != sanitized) {
      setState(() {
        _pdfFileName = sanitized;
        _fileNameController.text = sanitized;
        _project.title = sanitized.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');
      });
    }
  }

  Future<void> _checkForDroppedFiles() async {
    // While another section is shown, leave drops queued instead of consuming them here.
    if (!mounted || !_isVisible) return;
    try {
      final dropped = await ClipboardImageService.readDroppedImages();
      if (dropped.isNotEmpty) {
        for (final img in dropped) {
          _handleDroppedImage(img);
        }
      }
    } catch (_) {}
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
    if (imagesToAdd.isEmpty) return;
    setState(() {
      var remaining = List<ScreenshotItem>.from(imagesToAdd);

      // First fill available slots on the current page according to its individual layout settings
      final curAvail = _currentPage.maxSlots - _currentPage.images.length;
      if (curAvail > 0) {
        final takeCount = remaining.length < curAvail ? remaining.length : curAvail;
        _currentPage.images.addAll(remaining.sublist(0, takeCount));
        remaining = remaining.sublist(takeCount);
      }

      // Then sequentially fill available slots in subsequent existing pages following their individual layout settings
      var targetIndex = _currentPageIndex + 1;
      while (remaining.isNotEmpty && targetIndex < _project.pages.length) {
        final targetPage = _project.pages[targetIndex];
        final avail = targetPage.maxSlots - targetPage.images.length;
        if (avail > 0) {
          final takeCount = remaining.length < avail ? remaining.length : avail;
          targetPage.images.addAll(remaining.sublist(0, takeCount));
          remaining = remaining.sublist(takeCount);
        }
        targetIndex++;
      }

      // If still remaining images, create new pages inheriting current page layout
      while (remaining.isNotEmpty) {
        final newPage = PdfPageModel(
          pageNumber: _project.pages.length + 1,
          presetType: _currentPage.presetType,
          geometry: _currentPage.geometry,
          fitMode: _currentPage.fitMode,
          showCaptions: _currentPage.showCaptions,
          customRows: _currentPage.customRows,
          customCols: _currentPage.customCols,
          spacingPoints: _currentPage.spacingPoints,
        );
        final takeCount = remaining.length < newPage.maxSlots ? remaining.length : newPage.maxSlots;
        newPage.images.addAll(remaining.sublist(0, takeCount));
        remaining = remaining.sublist(takeCount);
        _project.pages.add(newPage);
      }

      _reindexPages();
    });
  }

  void _handlePageOverflow(int pageIndex) {
    if (pageIndex < 0 || pageIndex >= _project.pages.length) return;
    final page = _project.pages[pageIndex];
    final max = page.maxSlots;
    if (page.images.length <= max) return;

    final overflow = page.images.sublist(max);
    page.images.removeRange(max, page.images.length);

    var targetIndex = pageIndex + 1;
    var remaining = List<ScreenshotItem>.from(overflow);

    while (remaining.isNotEmpty) {
      if (targetIndex < _project.pages.length) {
        final targetPage = _project.pages[targetIndex];
        final avail = targetPage.maxSlots - targetPage.images.length;
        if (avail > 0) {
          final takeCount = remaining.length < avail ? remaining.length : avail;
          targetPage.images.addAll(remaining.sublist(0, takeCount));
          remaining = remaining.sublist(takeCount);
        }
        targetIndex++;
      } else {
        final newPage = PdfPageModel(
          pageNumber: _project.pages.length + 1,
          presetType: page.presetType,
          geometry: page.geometry,
          fitMode: page.fitMode,
          showCaptions: page.showCaptions,
          customRows: page.customRows,
          customCols: page.customCols,
          spacingPoints: page.spacingPoints,
        );
        final takeCount = remaining.length < newPage.maxSlots ? remaining.length : newPage.maxSlots;
        newPage.images.addAll(remaining.sublist(0, takeCount));
        remaining = remaining.sublist(takeCount);
        _project.pages.add(newPage);
        targetIndex++;
      }
    }
    _reindexPages();
  }

  void _applyLayoutToAllPages() {
    _saveUndoState();
    setState(() {
      final ref = _currentPage;
      final existingCount = _project.pages.length;
      for (var i = 0; i < existingCount; i++) {
        if (i == _currentPageIndex) continue;
        _project.pages[i] = _project.pages[i].copyWith(
          presetType: ref.presetType,
          geometry: ref.geometry,
          customRows: ref.customRows,
          customCols: ref.customCols,
          spacingPoints: ref.spacingPoints,
          fitMode: ref.fitMode,
          showCaptions: ref.showCaptions,
        );
      }
      for (var i = 0; i < _project.pages.length; i++) {
        _handlePageOverflow(i);
      }
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Applied Page ${_currentPage.pageNumber} layout to all ${_project.pages.length} pages',
            style: TextStyle(fontFamily: 'Poppins', color: AppColors.white),
          ),
          backgroundColor: cardBg,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _showDuplicateWarning(List<ScreenshotItem> duplicates, VoidCallback onKeepBoth) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: dialogBg,
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.amber),
            SizedBox(width: 8),
            Text('Duplicate Screenshot Detected', style: TextStyle(fontFamily: 'Poppins', color: primaryWhite)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Found ${duplicates.length} image(s) identical to screenshots already in this document (matching SHA-256 cryptographic hash):',
              style: TextStyle(fontFamily: 'Poppins', color: softGray),
            ),
            const SizedBox(height: 8),
            for (final d in duplicates.take(3))
              Text('• ${d.name} (${d.sha256.substring(0, 8)}...)', style: TextStyle(fontWeight: FontWeight.bold, color: primaryWhite)),
            const SizedBox(height: 12),
            Text('What would you like to do?', style: TextStyle(fontFamily: 'Poppins', color: softGray)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Skip Duplicate', style: TextStyle(color: softGray, fontFamily: 'Poppins')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: limeAccent,
              foregroundColor: darkText,
            ),
            onPressed: () {
              Navigator.pop(context);
              onKeepBoth();
            },
            child: const Text('Keep Both', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  static Color get dialogBg => AppColors.charcoalSurface;

  void _pickImageFiles() {
    setState(() {
      _isAddImagesPanelOpen = true;
    });
  }

  Future<void> _browseForStagedImages() async {
    setState(() => _isStagingLoading = true);
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['png', 'jpg', 'jpeg', 'webp', 'bmp'],
      );

      if (files.isNotEmpty) {
        for (final f in files) {
          final bytes = await f.readAsBytes();
          final item = await ScreenshotItem.create(
            name: f.name,
            bytes: bytes,
            caption: f.name.replaceAll(RegExp(r'\.[^.]+$'), ''),
          );
          if (!_stagedImages.any((img) => img.sha256 == item.sha256)) {
            _stagedImages.add(item);
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error selecting images: $e', style: const TextStyle(fontFamily: 'Poppins')),
            backgroundColor: cardBg,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isStagingLoading = false);
      }
    }
  }

  Future<void> _addSampleToStagedImages() async {
    setState(() => _isStagingLoading = true);
    try {
      final sample = await ClipboardImageService.createSamplePastedScreenshot();
      if (!_stagedImages.any((img) => img.sha256 == sample.sha256)) {
        _stagedImages.add(sample);
      }
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() => _isStagingLoading = false);
      }
    }
  }

  void _closeAddImagesPanel() {
    setState(() {
      _stagedImages.clear();
      _isAddImagesPanelOpen = false;
    });
  }

  void _confirmAddStagedImages() {
    if (_stagedImages.isEmpty) {
      _closeAddImagesPanel();
      return;
    }
    final toAdd = List<ScreenshotItem>.from(_stagedImages);
    setState(() {
      _stagedImages.clear();
      _isAddImagesPanelOpen = false;
    });
    _addImages(toAdd);
  }

  Future<void> _importSampleLabScreenshots() async {
    final samples = await SampleScreenshotGenerator.generateLabSamples();
    _addImages(samples);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle_rounded, color: limeAccent, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Imported 6 realistic lab screenshots (Java, Terminal, Python, etc.)',
                  style: TextStyle(fontFamily: 'Poppins', color: AppColors.white),
                ),
              ),
            ],
          ),
          backgroundColor: cardBg,
        ),
      );
    }
  }

  Future<void> _handlePasteScreenshot() async {
    try {
      final screenshot = await ClipboardImageService.readPastedImage();
      if (screenshot != null) {
        _dismissPasteNotice();
        _addImages([screenshot]);
        _showPastedSnackBar(screenshot.name);
      } else {
        if (mounted) {
          _showPasteFailedNotification();
        }
      }
    } catch (_) {
      if (mounted) {
        _showPasteFailedNotification();
      }
    }
  }

  void _showPastedSnackBar(String name) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle_rounded, color: limeAccent, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Pasted "$name" into document',
                style: TextStyle(fontFamily: 'Poppins', color: AppColors.white),
              ),
            ),
          ],
        ),
        backgroundColor: cardBg,
        behavior: SnackBarBehavior.floating,
        width: 340,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _dismissPasteNotice() {
    _pasteNoticeOverlay?.remove();
    _pasteNoticeOverlay = null;
    _pasteNoticeTimer?.cancel();
    _pasteNoticeTimer = null;
  }

  void _showPasteFailedNotification() {
    _dismissPasteNotice();

    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;

    final renderBox = _pasteButtonKey.currentContext?.findRenderObject() as RenderBox?;
    Offset targetOffset = const Offset(200, 50);
    double targetWidth = 130;
    double targetHeight = 36;
    if (renderBox != null && renderBox.hasSize) {
      targetOffset = renderBox.localToGlobal(Offset.zero);
      targetWidth = renderBox.size.width;
      targetHeight = renderBox.size.height;
    }

    final screenWidth = MediaQuery.of(context).size.width;

    _pasteNoticeOverlay = OverlayEntry(
      builder: (context) {
        final left = (targetOffset.dx + targetWidth / 2 - 130).clamp(16.0, (screenWidth - 276.0).clamp(16.0, 9999.0));
        final top = targetOffset.dy + targetHeight + 6;

        return Positioned(
          left: left,
          top: top,
          child: Material(
            color: Colors.transparent,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              builder: (context, val, child) {
                return Opacity(
                  opacity: val.clamp(0.0, 1.0),
                  child: Transform.translate(
                    offset: Offset(0, (1 - val) * -4),
                    child: child,
                  ),
                );
              },
              child: GestureDetector(
                onTap: _dismissPasteNotice,
                child: Container(
                  key: const Key('paste_failed_notification'),
                  width: 260,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: panelBg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: limeAccent.withValues(alpha: 0.7), width: 1.2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.55),
                        blurRadius: 18,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Icon(Icons.info_outline_rounded, color: limeAccent, size: 16),
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'No image in clipboard',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color: AppColors.white,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Copy an image (Win+Shift+S / PrtScn), then paste.',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 10,
                                color: softGray,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    overlay.insert(_pasteNoticeOverlay!);

    _pasteNoticeTimer = Timer(const Duration(milliseconds: 2400), () {
      _dismissPasteNotice();
    });
  }

  void _handleSlotTap(int slotIndex) async {
    // If clipboard has an image, paste directly
    final screenshot = await ClipboardImageService.readPastedImage();
    if (screenshot != null) {
      _addImages([screenshot]);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Pasted image into Slot ${slotIndex + 1}!',
              style: TextStyle(fontFamily: 'Poppins', color: AppColors.white),
            ),
            backgroundColor: cardBg,
          ),
        );
      }
      return;
    }

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: panelBg,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: Icon(Icons.paste_rounded, color: limeAccent),
              title: Text('Paste from Clipboard (Ctrl+V)', style: TextStyle(fontFamily: 'Poppins', color: primaryWhite)),
              subtitle: Text('Insert copied screenshot directly into document', style: TextStyle(fontFamily: 'Poppins', color: softGray)),
              onTap: () {
                Navigator.pop(ctx);
                _handlePasteScreenshot();
              },
            ),
            ListTile(
              leading: Icon(Icons.upload_file_rounded, color: limeAccent),
              title: Text('Pick Image File from Computer...', style: TextStyle(fontFamily: 'Poppins', color: primaryWhite)),
              subtitle: Text('Browse PNG, JPG, WebP files', style: TextStyle(fontFamily: 'Poppins', color: softGray)),
              onTap: () {
                Navigator.pop(ctx);
                _pickImageFiles();
              },
            ),
            ListTile(
              leading: Icon(Icons.science_outlined, color: limeAccent),
              title: Text('Load Lab Sample Screenshot', style: TextStyle(fontFamily: 'Poppins', color: primaryWhite)),
              onTap: () async {
                Navigator.pop(ctx);
                final sample = await ClipboardImageService.createSamplePastedScreenshot();
                _addImages([sample]);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _removeImage(ScreenshotItem item) {
    _saveUndoState();
    setState(() {
      _currentPage.images.removeWhere((img) => img.id == item.id);
    });
  }

  void _rotateImage(ScreenshotItem item) {
    _saveUndoState();
    setState(() {
      final idx = _currentPage.images.indexWhere((img) => img.id == item.id);
      if (idx != -1) {
        final curRot = _currentPage.images[idx].rotationDegrees;
        _currentPage.images[idx] = _currentPage.images[idx].copyWith(
          rotationDegrees: (curRot + 90) % 360,
        );
      }
    });
  }

  Widget _buildPdfFileNameField(bool isCompact) {
    return Container(
      constraints: const BoxConstraints(
        minWidth: 80,
        maxWidth: 280,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: _fileNameFocusNode.hasFocus ? limeAccent : subtleBorderLight,
          width: 1.1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.picture_as_pdf_rounded, color: limeAccent, size: 13),
                const SizedBox(width: 5),
                Text(
                  'PDF FILE NAME',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 9.0,
                    fontWeight: FontWeight.w800,
                    color: limeAccent,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.edit, size: 10, color: softGray),
              ],
            ),
          ),
          const SizedBox(height: 1),
          SizedBox(
            height: 20,
            child: TextField(
              key: const Key('pdf_file_name_field'),
              controller: _fileNameController,
              focusNode: _fileNameFocusNode,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12.0,
                fontWeight: FontWeight.w600,
                color: primaryWhite,
              ),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintText: 'QuickShare_Document.pdf',
                hintStyle: TextStyle(color: AppColors.mutedText, fontSize: 12),
              ),
              onSubmitted: _commitPdfFileName,
              onTapOutside: (_) => _commitPdfFileName(_fileNameController.text),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShowPanelFloatingButton() {
    return Tooltip(
      message: 'Show Page Layout',
      child: InkWell(
        key: const Key('expand_layout_panel_floating_button'),
        onTap: () {
          setState(() {
            _isLayoutPanelVisible = true;
          });
        },
        borderRadius: const BorderRadius.horizontal(left: Radius.circular(14)),
        child: Container(
          width: 32,
          height: 60,
          decoration: BoxDecoration(
            color: panelBg,
            borderRadius: const BorderRadius.horizontal(left: Radius.circular(14)),
            border: Border.all(color: limeAccent.withValues(alpha: 0.6), width: 1.2),
            boxShadow: [
              BoxShadow(
                color: limeAccent.withValues(alpha: 0.25),
                blurRadius: 12,
                offset: const Offset(-2, 2),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 8,
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.chevron_left, color: limeAccent, size: 20),
              SizedBox(height: 2),
              Icon(Icons.tune, color: softGray, size: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInAppAddImagesPanel() {
    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: panelBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: limeAccent.withValues(alpha: 0.8), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.65),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header Row
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: limeAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.photo_library_rounded, color: limeAccent, size: 18),
                ),
                const SizedBox(width: 10),
                Text(
                  'Add Images',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: primaryWhite,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: subtleBorderLight),
                  ),
                  child: Text(
                    '${_stagedImages.length} selected',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _stagedImages.isNotEmpty ? limeAccent : softGray,
                    ),
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(Icons.close_rounded, color: softGray, size: 20),
                  tooltip: 'Close Panel (Leave unchanged)',
                  onPressed: _closeAddImagesPanel,
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Staged Items area
            if (_isStagingLoading)
              Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: limeAccent),
                  ),
                ),
              )
            else if (_stagedImages.isEmpty)
              InkWell(
                onTap: _browseForStagedImages,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: subtleBorderLight, style: BorderStyle.solid),
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.add_photo_alternate_outlined, color: limeAccent, size: 32),
                      SizedBox(height: 8),
                      Text(
                        'Click to browse and select images from your computer',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: primaryWhite,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Supports PNG, JPG, JPEG, WebP, BMP',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 11,
                          color: softGray,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              SizedBox(
                height: 115,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _stagedImages.length,
                  separatorBuilder: (context, index) => const SizedBox(width: 10),
                  itemBuilder: (ctx, idx) {
                    final img = _stagedImages[idx];
                    return Stack(
                      children: [
                        Container(
                          width: 110,
                          height: 115,
                          decoration: BoxDecoration(
                            color: AppColors.surfaceElevated,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: subtleBorderLight),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: const BorderRadius.vertical(top: Radius.circular(9)),
                                  child: Image.memory(
                                    img.bytes,
                                    fit: BoxFit.cover,
                                    // Small tray tile: decoding full-size screenshots here made the editor sluggish.
                                    cacheWidth: 320,
                                    errorBuilder: (context, error, stackTrace) => Container(
                                      color: AppColors.surfaceElevated,
                                      child: Icon(Icons.image_outlined, color: softGray, size: 28),
                                    ),
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      img.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontFamily: 'Poppins',
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: primaryWhite,
                                      ),
                                    ),
                                    Text(
                                      FormatUtils.formatBytes(img.bytes.length),
                                      style: TextStyle(
                                        fontFamily: 'Poppins',
                                        fontSize: 9,
                                        color: softGray,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        Positioned(
                          top: 4,
                          right: 4,
                          child: InkWell(
                            onTap: () {
                              setState(() {
                                _stagedImages.removeAt(idx);
                              });
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.8),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(Icons.close_rounded, size: 13, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),

            const SizedBox(height: 14),

            // Controls & Footer Action Bar
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: primaryWhite,
                        side: BorderSide(color: subtleBorderLight),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: Icon(Icons.folder_open_rounded, size: 14, color: limeAccent),
                      label: const Text(
                        'Browse More...',
                        style: TextStyle(fontFamily: 'Poppins', fontSize: 11, fontWeight: FontWeight.w500),
                      ),
                      onPressed: _browseForStagedImages,
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: softGray,
                        side: BorderSide(color: subtleBorderLight),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: Icon(Icons.science_outlined, size: 14, color: softGray),
                      label: const Text(
                        'Add Sample',
                        style: TextStyle(fontFamily: 'Poppins', fontSize: 11),
                      ),
                      onPressed: _addSampleToStagedImages,
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Clear / Cancel Button
                    OutlinedButton(
                      key: const Key('add_images_panel_cancel_btn'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: softGray,
                        side: BorderSide(color: subtleBorderLight),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: _closeAddImagesPanel,
                      child: const Text(
                        'Cancel',
                        style: TextStyle(fontFamily: 'Poppins', fontSize: 11.5, fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Confirm Add Button
                    ElevatedButton.icon(
                      key: const Key('add_images_panel_add_btn'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: limeAccent,
                        foregroundColor: darkText,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: const Icon(Icons.check_rounded, size: 15, color: darkText),
                      label: Text(
                        _stagedImages.isNotEmpty ? 'Add (${_stagedImages.length})' : 'Add to Document',
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: darkText,
                        ),
                      ),
                      onPressed: _stagedImages.isNotEmpty ? _confirmAddStagedImages : null,
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 960;
    final isCompact = screenWidth < 760;
    // Below this width the labelled toolbar buttons no longer fit next to the file name.
    final compactToolbar = screenWidth < 1100;
    _isVisible = TickerMode.valuesOf(context).enabled;

    // Ctrl+V is handled by _handleGlobalKeyboard (native) and _handleWebPaste (web).
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): _undo,
        const SingleActivator(LogicalKeyboardKey.keyY, control: true): _redo,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          key: _scaffoldKey,
          backgroundColor: scaffoldBg,
          endDrawer: isDesktop
              ? null
              : Drawer(
                  backgroundColor: panelBg,
                  width: 310,
                  child: SafeArea(
                    child: LayoutSettingsPanel(
                      page: _currentPage,
                      totalPages: _project.pages.length,
                      autoContinue: _project.autoContinuePages,
                      onToggleCollapse: () => Navigator.pop(context),
                      onApplyToAllPages: _project.pages.length > 1
                          ? () {
                              Navigator.pop(context);
                              _applyLayoutToAllPages();
                            }
                          : null,
                      onPresetChanged: (preset) {
                        _saveUndoState();
                        setState(() {
                          _currentPage = _currentPage.copyWith(presetType: preset);
                          _handlePageOverflow(_currentPageIndex);
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
                          _handlePageOverflow(_currentPageIndex);
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
                          _handlePageOverflow(_currentPageIndex);
                        });
                      },
                      onClearPageImages: () {
                        _saveUndoState();
                        setState(() {
                          _currentPage.images.clear();
                        });
                      },
                    ),
                  ),
                ),
          appBar: AppBar(
            backgroundColor: panelBg,
            elevation: 0,
            scrolledUnderElevation: 0,
            shape: Border(
              bottom: BorderSide(color: subtleBorder, width: 1.0),
            ),
            title: _buildPdfFileNameField(isCompact),
            actions: [
              // Undo / Redo
              IconButton(
                icon: const Icon(Icons.undo_rounded),
                tooltip: 'Undo (Ctrl+Z)',
                color: _undoStack.isNotEmpty ? primaryWhite : AppColors.mutedText,
                onPressed: _undoStack.isNotEmpty ? _undo : null,
              ),
              IconButton(
                icon: const Icon(Icons.redo_rounded),
                tooltip: 'Redo (Ctrl+Y)',
                color: _redoStack.isNotEmpty ? primaryWhite : AppColors.mutedText,
                onPressed: _redoStack.isNotEmpty ? _redo : null,
              ),
              const SizedBox(width: 4),

              // Import Sample Lab Screenshots Action
              if (screenWidth >= 860) ...[
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    backgroundColor: cardBg,
                    foregroundColor: primaryWhite,
                    side: BorderSide(color: subtleBorderLight),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                  icon: Icon(Icons.science_outlined, size: 16, color: limeAccent),
                  label: const Text(
                    'Load Lab Samples',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  onPressed: _importSampleLabScreenshots,
                ),
                const SizedBox(width: 8),
              ] else ...[
                IconButton(
                  icon: Icon(Icons.science_outlined, size: 18, color: limeAccent),
                  tooltip: 'Load Lab Samples',
                  onPressed: _importSampleLabScreenshots,
                ),
              ],

              // Paste Screenshot (Ctrl+V) — icon-only when the toolbar is narrow
              if (compactToolbar)
                IconButton(
                  key: _pasteButtonKey,
                  icon: const Icon(Icons.paste_rounded, size: 18),
                  color: AppColors.primaryAccent,
                  tooltip: 'Paste screenshot (Ctrl+V)',
                  onPressed: _handlePasteScreenshot,
                )
              else
              ElevatedButton.icon(
                key: _pasteButtonKey,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.cardBg,
                  foregroundColor: AppColors.primaryAccent,
                  side: BorderSide(color: AppColors.primaryAccent, width: 1.2),
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                icon: const Icon(Icons.paste_rounded, size: 16),
                label: const Text(
                  'Paste (Ctrl+V)',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w600),
                ),
                onPressed: _handlePasteScreenshot,
              ),
              const SizedBox(width: 8),

              // Add Images
              if (compactToolbar)
                IconButton(
                  icon: const Icon(Icons.add_photo_alternate_rounded, size: 18),
                  color: limeAccent,
                  tooltip: 'Add images',
                  onPressed: _pickImageFiles,
                )
              else
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: cardBg,
                  foregroundColor: limeAccent,
                  side: BorderSide(color: limeAccent, width: 1.2),
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                icon: Icon(Icons.add_photo_alternate_rounded, size: 16, color: limeAccent),
                label: const Text(
                  'Add Images',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.bold),
                ),
                onPressed: _pickImageFiles,
              ),
              const SizedBox(width: 8),

              // Export PDF (Primary Action in Lime Green)
              if (screenWidth < 600)
                IconButton.filled(
                  style: IconButton.styleFrom(backgroundColor: limeAccent, foregroundColor: darkText),
                  icon: const Icon(Icons.download_rounded, size: 18),
                  tooltip: 'Export PDF',
                  onPressed: _openExportDialog,
                )
              else
                              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: limeAccent,
                  foregroundColor: darkText,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                icon: const Icon(Icons.download_rounded, size: 17, color: darkText),
                label: const Text(
                  'Export PDF',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w800),
                ),
                onPressed: _openExportDialog,
              ),
              const SizedBox(width: 12),
            ],
          ),
          body: isDesktop ? _buildDesktopLayout() : _buildMobileLayout(),
        ),
      ),
    );
  }

  Widget _buildDesktopLayout() {
    return Column(
      children: [
        // Page Navigation and Viewing Toolbar spanning the full workspace width
        _buildCanvasToolbar(),

        // Main Workspace Area: Left Thumbnails | Resizing Page Preview | Collapsible Sidebar
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
                      SnackBar(
                        content: Text('Cannot delete the only page.', style: TextStyle(fontFamily: 'Poppins')),
                        backgroundColor: cardBg,
                      ),
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
                onPagePresetChanged: (idx, preset) {
                  _saveUndoState();
                  setState(() {
                    _project.pages[idx] = _project.pages[idx].copyWith(presetType: preset);
                    _handlePageOverflow(idx);
                  });
                },
              ),

              // Center: Xerox-Ready Live Preview (resizes to use remaining space)
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Container(
                        color: scaffoldBg,
                        child: PagePreviewCanvas(
                          page: _currentPage,
                          totalPages: _project.pages.length,
                          zoomScale: _zoomScale,
                          showPrintableGuides: _showPrintableGuides,
                          showSafeMarginGuides: _showSafeGuides,
                          backgroundStyle: _bgStyle,
                          onSlotTap: _handleSlotTap,
                          onRemoveImage: _removeImage,
                          onRotateImage: _rotateImage,
                          onDropImage: _handleDroppedImage,
                        ),
                      ),
                    ),
                    if (!_isLayoutPanelVisible)
                      Positioned(
                        right: 0,
                        top: 80,
                        child: _buildShowPanelFloatingButton(),
                      ),
                    if (_isAddImagesPanelOpen)
                      Positioned(
                        left: 20,
                        right: 20,
                        bottom: 16,
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 680),
                            child: _buildInAppAddImagesPanel(),
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // Right: Layout & Page Settings Panel with Smooth Animated Collapse
              AnimatedContainer(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeInOutCubic,
          width: _isLayoutPanelVisible ? 290.0 : 0.0,
          child: ClipRect(
            child: OverflowBox(
              minWidth: 290.0,
              maxWidth: 290.0,
              alignment: Alignment.topRight,
              child: LayoutSettingsPanel(
                page: _currentPage,
                totalPages: _project.pages.length,
                autoContinue: _project.autoContinuePages,
                onToggleCollapse: () {
                  setState(() {
                    _isLayoutPanelVisible = false;
                  });
                },
                isCollapsed: !_isLayoutPanelVisible,
                onApplyToAllPages: _project.pages.length > 1 ? _applyLayoutToAllPages : null,
                onPresetChanged: (preset) {
                  _saveUndoState();
                  setState(() {
                    _currentPage = _currentPage.copyWith(presetType: preset);
                    _handlePageOverflow(_currentPageIndex);
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
                    _handlePageOverflow(_currentPageIndex);
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
                    _handlePageOverflow(_currentPageIndex);
                  });
                },
                onClearPageImages: () {
                  _saveUndoState();
                  setState(() {
                    _currentPage.images.clear();
                  });
                },
              ),
            ),
          ),
        ),
      ],
    ),
  ),
],
);
}

  Widget _buildMobileLayout() {
    return Column(
      children: [
        _buildCanvasToolbar(),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: PagePreviewCanvas(
                  page: _currentPage,
                  totalPages: _project.pages.length,
                  zoomScale: _zoomScale,
                  showPrintableGuides: _showPrintableGuides,
                  showSafeMarginGuides: _showSafeGuides,
                  backgroundStyle: _bgStyle,
                  onSlotTap: _handleSlotTap,
                  onRemoveImage: _removeImage,
                  onRotateImage: _rotateImage,
                  onDropImage: _handleDroppedImage,
                ),
              ),
              Positioned(
                right: 0,
                top: 80,
                child: Tooltip(
                  message: 'Show Page Layout',
                  child: InkWell(
                    onTap: () => _scaffoldKey.currentState?.openEndDrawer(),
                    borderRadius: const BorderRadius.horizontal(left: Radius.circular(14)),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                      decoration: BoxDecoration(
                        color: panelBg,
                        borderRadius: const BorderRadius.horizontal(left: Radius.circular(14)),
                        border: Border.all(
                          color: limeAccent.withValues(alpha: 0.55),
                          width: 1.2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: limeAccent.withValues(alpha: 0.25),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.tune, color: limeAccent, size: 18),
                          SizedBox(height: 2),
                          Icon(Icons.chevron_left, color: softGray, size: 14),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (_isAddImagesPanelOpen)
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 12,
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 680),
                      child: _buildInAppAddImagesPanel(),
                    ),
                  ),
                ),
            ],
          ),
        ),
        // Mobile bottom action bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: panelBg,
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: primaryWhite,
                  side: BorderSide(color: subtleBorderLight),
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                ),
                icon: Icon(Icons.pages_outlined, size: 15, color: limeAccent),
                label: Text(
                  'Pages (${_currentPage.pageNumber}/${_project.pages.length})',
                  style: const TextStyle(fontFamily: 'Poppins'),
                ),
                onPressed: () {
                  showModalBottomSheet(
                    context: context,
                    backgroundColor: panelBg,
                    builder: (ctx) => Container(
                      height: 380,
                      color: panelBg,
                      child: PageThumbnailsBar(
                        pages: _project.pages,
                        selectedPageIndex: _currentPageIndex,
                        onSelectPage: (idx) {
                          setState(() => _currentPageIndex = idx);
                          Navigator.pop(ctx);
                        },
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
                        onPagePresetChanged: (idx, preset) {
                          _saveUndoState();
                          setState(() {
                            _project.pages[idx] = _project.pages[idx].copyWith(presetType: preset);
                            _handlePageOverflow(idx);
                          });
                        },
                      ),
                    ),
                  );
                },
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: limeAccent,
                  foregroundColor: darkText,
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.tune, size: 16),
                label: const Text('Layout Settings', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.bold)),
                onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
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
      decoration: BoxDecoration(
        color: panelBg,
        border: Border(
          bottom: BorderSide(color: subtleBorder, width: 1.0),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Page Navigation: < Page N of M >
            IconButton(
              icon: const Icon(Icons.chevron_left_rounded, size: 20),
              tooltip: 'Previous Page',
              color: softGray,
              onPressed: _currentPageIndex > 0
                  ? () => setState(() => _currentPageIndex--)
                  : null,
            ),
            Text(
              'Page ${_currentPage.pageNumber} of ${_project.pages.length}',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: primaryWhite,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right_rounded, size: 20),
              tooltip: 'Next Page',
              color: softGray,
              onPressed: _currentPageIndex < _project.pages.length - 1
                  ? () => setState(() => _currentPageIndex++)
                  : null,
            ),
            VerticalDivider(color: subtleBorder, indent: 12, endIndent: 12),

            // Zoom Controls: - 100% + Fit Page
            IconButton(
              icon: const Icon(Icons.zoom_out_rounded, size: 19),
              tooltip: 'Zoom Out',
              color: softGray,
              onPressed: () => setState(() => _zoomScale = (_zoomScale - 0.15).clamp(0.4, 3.0)),
            ),
            Text(
              '${(_zoomScale * 100).round()}%',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: primaryWhite,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.zoom_in_rounded, size: 19),
              tooltip: 'Zoom In',
              color: softGray,
              onPressed: () => setState(() => _zoomScale = (_zoomScale + 0.15).clamp(0.4, 3.0)),
            ),
            TextButton(
              child: Text(
                'Fit Page',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: limeAccent, fontWeight: FontWeight.w600),
              ),
              onPressed: () => setState(() => _zoomScale = 1.0),
            ),
            VerticalDivider(color: subtleBorder, indent: 12, endIndent: 12),

            // Guides Toggles (Pill buttons with checkmarks matching screenshot)
            Tooltip(
              message: 'Toggle Margin Printable Guide',
              child: FilterChip(
                avatar: _showPrintableGuides
                    ? const Icon(Icons.check, size: 14, color: darkText)
                    : null,
                label: Text(
                  'Margins',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    fontWeight: _showPrintableGuides ? FontWeight.bold : FontWeight.w500,
                    color: _showPrintableGuides ? darkText : softGray,
                  ),
                ),
                selected: _showPrintableGuides,
                showCheckmark: false,
                selectedColor: limeAccent,
                backgroundColor: cardBg,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: _showPrintableGuides ? limeAccent : subtleBorderLight,
                  ),
                ),
                onSelected: (val) => setState(() => _showPrintableGuides = val),
              ),
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: 'Toggle Xerox Hardware Safe-Area Guide (~5mm)',
              child: FilterChip(
                avatar: _showSafeGuides
                    ? const Icon(Icons.check, size: 14, color: darkText)
                    : null,
                label: Text(
                  'Xerox Guide',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    fontWeight: _showSafeGuides ? FontWeight.bold : FontWeight.w500,
                    color: _showSafeGuides ? darkText : softGray,
                  ),
                ),
                selected: _showSafeGuides,
                showCheckmark: false,
                selectedColor: limeAccent,
                backgroundColor: cardBg,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: _showSafeGuides ? limeAccent : subtleBorderLight,
                  ),
                ),
                onSelected: (val) => setState(() => _showSafeGuides = val),
              ),
            ),
            const SizedBox(width: 12),

            // Page Background Tint Selector
            PopupMenuButton<PageBackgroundStyle>(
              tooltip: 'Paper Sheet Background',
              icon: Icon(Icons.palette_outlined, size: 20, color: softGray),
              color: cardBg,
              onSelected: (style) => setState(() => _bgStyle = style),
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: PageBackgroundStyle.white,
                  child: Text('White Paper', style: TextStyle(fontFamily: 'Poppins', color: primaryWhite)),
                ),
                PopupMenuItem(
                  value: PageBackgroundStyle.cream,
                  child: Text('Cream / Off-White', style: TextStyle(fontFamily: 'Poppins', color: primaryWhite)),
                ),
                PopupMenuItem(
                  value: PageBackgroundStyle.dark,
                  child: Text('Dark Proofing Canvas', style: TextStyle(fontFamily: 'Poppins', color: primaryWhite)),
                ),
              ],
            ),
            VerticalDivider(color: subtleBorder, indent: 12, endIndent: 12),

            // Layout Panel Toggle FilterChip
            Tooltip(
              message: _isLayoutPanelVisible ? 'Hide Page Layout' : 'Show Page Layout',
              child: FilterChip(
                avatar: Icon(
                  _isLayoutPanelVisible ? Icons.tune : Icons.tune_outlined,
                  size: 14,
                  color: _isLayoutPanelVisible ? darkText : softGray,
                ),
                label: Text(
                  _isLayoutPanelVisible ? 'Layout Visible' : 'Layout Panel',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    fontWeight: _isLayoutPanelVisible ? FontWeight.bold : FontWeight.w500,
                    color: _isLayoutPanelVisible ? darkText : softGray,
                  ),
                ),
                selected: _isLayoutPanelVisible,
                showCheckmark: false,
                selectedColor: limeAccent,
                backgroundColor: cardBg,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: _isLayoutPanelVisible ? limeAccent : subtleBorderLight,
                  ),
                ),
                onSelected: (val) {
                  if (MediaQuery.of(context).size.width < 960) {
                    _scaffoldKey.currentState?.openEndDrawer();
                  } else {
                    setState(() {
                      _isLayoutPanelVisible = val;
                    });
                  }
                },
              ),
            ),
          ],
        ),
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

  void _handleDroppedImage(ScreenshotItem item, [int? targetSlotIndex]) {
    _saveUndoState();

    final dims = LayoutPreset.getGridDimensions(
      _currentPage.presetType,
      _currentPage.geometry.isLandscape,
      customRows: _currentPage.customRows,
      customCols: _currentPage.customCols,
    );
    final maxSlots = dims.rows * dims.cols;
    final currentSlotIndex = _currentPage.images.length;

    setState(() {
      if (currentSlotIndex < maxSlots) {
        // Enforce strict sequential slot rule:
        // "when you drop a picture, it must go to first slot 1, then only after it will go to slot 2, then after only it will go to slot 3, and so on."
        _currentPage.images.add(item);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle_rounded, color: limeAccent, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Dropped "${item.name}" into Slot ${currentSlotIndex + 1} (Sequential Fill: Slot 1 → Slot 2 → Slot 3...)',
                    style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.bold, color: AppColors.white),
                  ),
                ),
              ],
            ),
            backgroundColor: cardBg,
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        // Current page is full! Advance to next page or create one, placing into Slot 1
        if (_currentPageIndex < _project.pages.length - 1) {
          _currentPageIndex++;
          _currentPage.images.add(item);
        } else {
          final newPage = PdfPageModel(
            pageNumber: _project.pages.length + 1,
            presetType: _currentPage.presetType,
            geometry: _currentPage.geometry,
            fitMode: _currentPage.fitMode,
            showCaptions: _currentPage.showCaptions,
            customRows: _currentPage.customRows,
            customCols: _currentPage.customCols,
            spacingPoints: _currentPage.spacingPoints,
          );
          newPage.images.add(item);
          _project.pages.add(newPage);
          _reindexPages();
          _currentPageIndex = _project.pages.length - 1;
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.auto_stories_rounded, color: limeAccent, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Page full! Moved to Page ${_currentPage.pageNumber}, Slot 1',
                    style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.bold, color: AppColors.white),
                  ),
                ),
              ],
            ),
            backgroundColor: cardBg,
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    });
  }
}
