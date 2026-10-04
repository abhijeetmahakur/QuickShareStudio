import 'package:uuid/uuid.dart';
import '../models/screenshot_item.dart';
import '../../features/pdf_layout/models/page_geometry.dart';
import '../../features/pdf_layout/models/layout_preset.dart';

class PdfPageModel {
  final String id;
  int pageNumber;
  final List<ScreenshotItem> images;
  final PageGeometry geometry;
  final LayoutPresetType presetType;
  final int customRows;
  final int customCols;
  final double spacingPoints;
  final ImageFitMode fitMode;
  final bool showCaptions;
  final bool showPageNumber;

  PdfPageModel({
    String? id,
    required this.pageNumber,
    List<ScreenshotItem>? images,
    this.geometry = const PageGeometry(),
    this.presetType = LayoutPresetType.four,
    this.customRows = 2,
    this.customCols = 2,
    this.spacingPoints = 8.0,
    this.fitMode = ImageFitMode.contain,
    this.showCaptions = false,
    this.showPageNumber = true,
  })  : id = id ?? const Uuid().v4(),
        images = images ?? [];

  /// Maximum image slots available on this page according to current preset
  int get maxSlots {
    final dims = LayoutPreset.getGridDimensions(
      presetType,
      geometry.isLandscape,
      customRows: customRows,
      customCols: customCols,
    );
    return dims.rows * dims.cols;
  }

  PdfPageModel copyWith({
    int? pageNumber,
    List<ScreenshotItem>? images,
    PageGeometry? geometry,
    LayoutPresetType? presetType,
    int? customRows,
    int? customCols,
    double? spacingPoints,
    ImageFitMode? fitMode,
    bool? showCaptions,
    bool? showPageNumber,
  }) {
    return PdfPageModel(
      id: id,
      pageNumber: pageNumber ?? this.pageNumber,
      images: images != null ? List<ScreenshotItem>.from(images) : List<ScreenshotItem>.from(this.images),
      geometry: geometry ?? this.geometry,
      presetType: presetType ?? this.presetType,
      customRows: customRows ?? this.customRows,
      customCols: customCols ?? this.customCols,
      spacingPoints: spacingPoints ?? this.spacingPoints,
      fitMode: fitMode ?? this.fitMode,
      showCaptions: showCaptions ?? this.showCaptions,
      showPageNumber: showPageNumber ?? this.showPageNumber,
    );
  }
}

class PdfProject {
  final String id;
  String title;
  List<PdfPageModel> pages;
  bool autoContinuePages;
  final DateTime createdAt;
  DateTime updatedAt;

  PdfProject({
    String? id,
    this.title = 'Untitled_Lab_Document',
    List<PdfPageModel>? pages,
    this.autoContinuePages = true,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : id = id ?? const Uuid().v4(),
        pages = pages ?? [PdfPageModel(pageNumber: 1)],
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  /// Total count of screenshots across all pages
  int get totalImageCount => pages.fold(0, (sum, page) => sum + page.images.length);

  /// Automatically redistributes a flat list of screenshots into pages based on slots per page
  void autoDistributeScreenshots(
    List<ScreenshotItem> allImages, {
    LayoutPresetType defaultPreset = LayoutPresetType.four,
    PageGeometry defaultGeometry = const PageGeometry(),
    ImageFitMode defaultFitMode = ImageFitMode.contain,
    bool defaultCaptions = false,
    int customRows = 2,
    int customCols = 2,
  }) {
    final dims = LayoutPreset.getGridDimensions(
      defaultPreset,
      defaultGeometry.isLandscape,
      customRows: customRows,
      customCols: customCols,
    );
    final slotsPerPage = dims.rows * dims.cols;

    if (allImages.isEmpty) {
      pages = [
        PdfPageModel(
          pageNumber: 1,
          presetType: defaultPreset,
          geometry: defaultGeometry,
          fitMode: defaultFitMode,
          showCaptions: defaultCaptions,
          customRows: customRows,
          customCols: customCols,
        )
      ];
      return;
    }

    final newPages = <PdfPageModel>[];
    var pageNum = 1;

    for (var i = 0; i < allImages.length; i += slotsPerPage) {
      final end = (i + slotsPerPage < allImages.length) ? i + slotsPerPage : allImages.length;
      final pageImages = allImages.sublist(i, end);

      newPages.add(
        PdfPageModel(
          pageNumber: pageNum,
          images: pageImages,
          presetType: defaultPreset,
          geometry: defaultGeometry,
          fitMode: defaultFitMode,
          showCaptions: defaultCaptions,
          customRows: customRows,
          customCols: customCols,
        ),
      );
      pageNum++;
    }

    pages = newPages;
    updatedAt = DateTime.now();
  }
}
