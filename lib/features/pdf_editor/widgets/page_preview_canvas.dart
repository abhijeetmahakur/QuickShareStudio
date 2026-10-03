import 'package:flutter/material.dart';
import '../../../data/models/pdf_project.dart';
import '../../../data/models/screenshot_item.dart';
import '../../pdf_layout/models/layout_preset.dart';
import '../../pdf_layout/engine/layout_calculator.dart';
import '../../../core/constants.dart';

enum PageBackgroundStyle {
  white,
  cream,
  dark,
}

class PagePreviewCanvas extends StatefulWidget {
  final PdfPageModel page;
  final int totalPages;
  final double zoomScale;
  final bool showPrintableGuides;
  final bool showSafeMarginGuides;
  final PageBackgroundStyle backgroundStyle;
  final Function(int slotIndex)? onSlotTap;
  final Function(ScreenshotItem item)? onRemoveImage;
  final Function(ScreenshotItem item)? onRotateImage;

  const PagePreviewCanvas({
    super.key,
    required this.page,
    required this.totalPages,
    this.zoomScale = 1.0,
    this.showPrintableGuides = true,
    this.showSafeMarginGuides = true,
    this.backgroundStyle = PageBackgroundStyle.white,
    this.onSlotTap,
    this.onRemoveImage,
    this.onRotateImage,
  });

  @override
  State<PagePreviewCanvas> createState() => _PagePreviewCanvasState();
}

class _PagePreviewCanvasState extends State<PagePreviewCanvas> {
  @override
  Widget build(BuildContext context) {
    final geometry = widget.page.geometry;
    final aspectRatios = widget.page.images.map((img) => img.aspectRatio).toList();

    final cellResults = LayoutCalculator.calculatePageLayout(
      geometry: geometry,
      presetType: widget.page.presetType,
      customRows: widget.page.customRows,
      customCols: widget.page.customCols,
      spacingPoints: widget.page.spacingPoints,
      fitMode: widget.page.fitMode,
      showCaptions: widget.page.showCaptions,
      imageAspectRatios: aspectRatios,
    );

    // Physical dimensions of the sheet
    final sheetWidth = geometry.pageWidth;
    final sheetHeight = geometry.pageHeight;

    Color sheetBg;
    switch (widget.backgroundStyle) {
      case PageBackgroundStyle.white:
        sheetBg = Colors.white;
        break;
      case PageBackgroundStyle.cream:
        sheetBg = const Color(0xFFFDFBF7);
        break;
      case PageBackgroundStyle.dark:
        sheetBg = const Color(0xFF1E293B);
        break;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Base fit calculation: scale to fit within viewport
        final availableWidth = constraints.maxWidth - 32;
        final availableHeight = constraints.maxHeight - 32;

        final baseScale = (availableWidth / sheetWidth).clamp(0.1, availableHeight / sheetHeight);
        final effectiveScale = (baseScale * widget.zoomScale).clamp(0.2, 4.0);

        final displayWidth = sheetWidth * effectiveScale;
        final displayHeight = sheetHeight * effectiveScale;

        return Center(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SingleChildScrollView(
              scrollDirection: Axis.vertical,
              padding: const EdgeInsets.all(24),
              child: Container(
                width: displayWidth,
                height: displayHeight,
                decoration: BoxDecoration(
                  color: sheetBg,
                  borderRadius: BorderRadius.circular(4),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 3,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    // Margin guide (Printable boundary)
                    if (widget.showPrintableGuides && geometry.marginPoints > 0)
                      Positioned(
                        left: geometry.marginPoints * effectiveScale,
                        top: geometry.marginPoints * effectiveScale,
                        width: (sheetWidth - (geometry.marginPoints * 2)) * effectiveScale,
                        height: (sheetHeight - (geometry.marginPoints * 2)) * effectiveScale,
                        child: IgnorePointer(
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: AppColors.primary.withValues(alpha: 0.35),
                                width: 1.0,
                              ),
                            ),
                          ),
                        ),
                      ),

                    // Xerox Safe Printable Hardware Margin Guide (~5mm edge)
                    if (widget.showSafeMarginGuides && geometry.safeAreaPoints > 0)
                      Positioned(
                        left: geometry.safeAreaPoints * effectiveScale,
                        top: geometry.safeAreaPoints * effectiveScale,
                        width: (sheetWidth - (geometry.safeAreaPoints * 2)) * effectiveScale,
                        height: (sheetHeight - (geometry.safeAreaPoints * 2)) * effectiveScale,
                        child: IgnorePointer(
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: AppColors.error.withValues(alpha: 0.25),
                                width: 1.0,
                                strokeAlign: BorderSide.strokeAlignInside,
                              ),
                            ),
                          ),
                        ),
                      ),

                    // Rendered Image Slots
                    for (var i = 0; i < cellResults.length; i++)
                      _buildSlotWidget(
                        context,
                        index: i,
                        cell: cellResults[i],
                        effectiveScale: effectiveScale,
                      ),

                    // Page number footer
                    if (widget.page.showPageNumber)
                      Positioned(
                        bottom: 12 * effectiveScale,
                        right: 20 * effectiveScale,
                        child: Text(
                          'Page ${widget.page.pageNumber} of ${widget.totalPages}',
                          style: TextStyle(
                            fontSize: (9.0 * effectiveScale).clamp(8.0, 14.0),
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w500,
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
    );
  }

  Widget _buildSlotWidget(
    BuildContext context, {
    required int index,
    required CellLayoutResult cell,
    required double effectiveScale,
  }) {
    final hasImage = index < widget.page.images.length;
    final img = hasImage ? widget.page.images[index] : null;

    final cellLeft = cell.cellRect.left * effectiveScale;
    final cellTop = cell.cellRect.top * effectiveScale;
    final cellWidth = cell.cellRect.width * effectiveScale;
    final cellHeight = cell.cellRect.height * effectiveScale;

    final imgLeft = cell.imageRect.left * effectiveScale;
    final imgTop = cell.imageRect.top * effectiveScale;
    final imgWidth = cell.imageRect.width * effectiveScale;
    final imgHeight = cell.imageRect.height * effectiveScale;

    return Positioned(
      left: cellLeft,
      top: cellTop,
      width: cellWidth,
      height: cellHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Cell slot outline
          Container(
            decoration: BoxDecoration(
              border: Border.all(
                color: hasImage ? Colors.transparent : Colors.grey.shade300,
                width: 1,
              ),
              color: hasImage ? Colors.transparent : Colors.grey.shade50.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(3),
            ),
          ),

          // Actual Image Preview
          if (hasImage && img != null)
            Positioned(
              left: imgLeft - cellLeft,
              top: imgTop - cellTop,
              width: imgWidth,
              height: imgHeight,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.memory(
                      img.bytes,
                      fit: widget.page.fitMode == ImageFitMode.contain ? BoxFit.contain : BoxFit.cover,
                    ),

                    // Cropping warning indicator
                    if (cell.isCropped && widget.page.fitMode == ImageFitMode.cropFill)
                      Positioned(
                        top: 4,
                        right: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade800.withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: const Text(
                            'CROPPED',
                            style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),

          // Caption label if enabled
          if (widget.page.showCaptions && cell.captionRect != null)
            Positioned(
              left: 0,
              bottom: 0,
              width: cellWidth,
              height: (cell.captionRect!.height * effectiveScale).clamp(12.0, 24.0),
              child: Center(
                child: Text(
                  img?.caption ?? 'Figure ${widget.page.pageNumber}.${index + 1}',
                  style: TextStyle(
                    fontSize: (8.5 * effectiveScale).clamp(7.0, 11.0),
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade800,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),

          // Empty slot placeholder
          if (!hasImage)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.add_photo_alternate_outlined,
                    size: (24 * effectiveScale).clamp(14.0, 36.0),
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Slot ${index + 1}',
                    style: TextStyle(
                      fontSize: (9.0 * effectiveScale).clamp(8.0, 12.0),
                      color: Colors.grey.shade400,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
