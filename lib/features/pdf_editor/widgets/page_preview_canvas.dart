import '../../../core/constants.dart';
import 'package:flutter/material.dart';
import '../../../data/models/pdf_project.dart';
import '../../../data/models/screenshot_item.dart';
import '../../pdf_layout/models/layout_preset.dart';
import '../../pdf_layout/engine/layout_calculator.dart';
import '../../../core/widgets/hover_card.dart';

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
  final Function(ScreenshotItem item, int targetSlotIndex)? onDropImage;

  // Official Dark Lime Design Palette Tokens
  static Color get canvasBg => AppColors.dashboardBg;
  static Color get panelBg => AppColors.charcoalSurface;
  static Color get cardBg => AppColors.cardBg;
  static Color get limeAccent => AppColors.primaryAccent;
  static Color get softGray => AppColors.secondaryText;
  static Color get primaryWhite => AppColors.primaryText;
  static const Color darkText = AppColors.nearBlack;

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
    this.onDropImage,
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
        sheetBg = const Color(0xFF171717);
        break;
    }

    return Container(
      color: PagePreviewCanvas.canvasBg,
      child: LayoutBuilder(
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
                        color: Colors.black.withValues(alpha: 0.45),
                        blurRadius: 28,
                        offset: const Offset(0, 10),
                      ),
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.20),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: DragTarget<ScreenshotItem>(
                    onWillAcceptWithDetails: (_) => true,
                    onAcceptWithDetails: (details) {
                      widget.onDropImage?.call(details.data, widget.page.images.length);
                    },
                    builder: (context, candidateData, rejectedData) {
                      final isSheetCandidate = candidateData.isNotEmpty;
                      return Container(
                        decoration: BoxDecoration(
                          border: isSheetCandidate
                              ? Border.all(color: PagePreviewCanvas.limeAccent, width: 2.0)
                              : null,
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
                                        color: AppColors.primaryAccent.withValues(alpha: 0.35),
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
                                        color: const Color(0xFFF87171).withValues(alpha: 0.38),
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
                                    fontFamily: 'Poppins',
                                    fontSize: (9.0 * effectiveScale).clamp(8.0, 14.0),
                                    color: Colors.grey.shade600,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSlotWidget(
    BuildContext context, {
    required int index,
    required CellLayoutResult cell,
    required double effectiveScale,
  }) {
    final hasImage = index < widget.page.images.length;
    final isNextTarget = !hasImage && (index == widget.page.images.length);
    final img = hasImage ? widget.page.images[index] : null;

    final cellLeft = cell.cellRect.left * effectiveScale;
    final cellTop = cell.cellRect.top * effectiveScale;
    final cellWidth = cell.cellRect.width * effectiveScale;
    final cellHeight = cell.cellRect.height * effectiveScale;

    final captionH = (widget.page.showCaptions && cell.captionRect != null)
        ? (cell.captionRect!.height * effectiveScale).clamp(12.0, 24.0)
        : 0.0;
    final imageSlotHeight = cellHeight - captionH;

    return Positioned(
      left: cellLeft,
      top: cellTop,
      width: cellWidth,
      height: cellHeight,
      child: DragTarget<ScreenshotItem>(
        onWillAcceptWithDetails: (_) => true,
        onAcceptWithDetails: (details) {
          widget.onDropImage?.call(details.data, index);
        },
        builder: (context, candidateData, rejectedData) {
          final isDragOver = candidateData.isNotEmpty;

          return HoverCard(
            onTap: () => widget.onSlotTap?.call(index),
            borderRadius: BorderRadius.circular(4),
            liftOffset: 2.0,
            scale: 1.012,
            borderColor: isDragOver
                ? PagePreviewCanvas.limeAccent
                : (isNextTarget
                    ? PagePreviewCanvas.limeAccent
                    : (hasImage ? Colors.transparent : Colors.grey.shade300)),
            hoverBorderColor: PagePreviewCanvas.limeAccent,
            color: isDragOver
                ? PagePreviewCanvas.limeAccent.withValues(alpha: 0.15)
                : (isNextTarget
                    ? PagePreviewCanvas.limeAccent.withValues(alpha: 0.06)
                    : (hasImage ? Colors.transparent : Colors.grey.shade50.withValues(alpha: 0.6))),
            hoverColor: hasImage ? Colors.transparent : PagePreviewCanvas.limeAccent.withValues(alpha: 0.08),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Cell slot outline
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: isDragOver
                          ? PagePreviewCanvas.limeAccent
                          : (isNextTarget
                              ? PagePreviewCanvas.limeAccent
                              : (hasImage ? Colors.transparent : Colors.grey.shade300)),
                      width: isDragOver || isNextTarget ? 1.8 : 1.0,
                    ),
                    color: isDragOver
                        ? PagePreviewCanvas.limeAccent.withValues(alpha: 0.12)
                        : (isNextTarget
                            ? PagePreviewCanvas.limeAccent.withValues(alpha: 0.05)
                            : (hasImage ? Colors.transparent : Colors.grey.shade50.withValues(alpha: 0.5))),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),

                // Actual Image Preview
                if (hasImage && img != null)
                  Positioned(
                    left: 0,
                    top: 0,
                    width: cellWidth,
                    height: imageSlotHeight,
                    child: Center(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Transform.rotate(
                              angle: (img.rotationDegrees * 3.1415926535) / 180.0,
                              child: Image.memory(
                                img.bytes,
                                // Bounded decode size: enough for zoomed-in preview, far cheaper than full resolution.
                                cacheWidth: 1200,
                                fit: widget.page.fitMode == ImageFitMode.contain ? BoxFit.contain : BoxFit.cover,
                                alignment: Alignment.center,
                              ),
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
                                  child: Text(
                                    'CROPPED',
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      color: Colors.white,
                                      fontSize: 8,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // Slot action controls (Rotate / Delete)
                if (hasImage && index < widget.page.images.length)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.onRotateImage != null)
                          InkWell(
                            onTap: () => widget.onRotateImage?.call(widget.page.images[index]),
                            borderRadius: BorderRadius.circular(4),
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              margin: const EdgeInsets.only(right: 3),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.7),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Icon(Icons.rotate_right, size: 13, color: Colors.white),
                            ),
                          ),
                        if (widget.onRemoveImage != null)
                          InkWell(
                            onTap: () => widget.onRemoveImage?.call(widget.page.images[index]),
                            borderRadius: BorderRadius.circular(4),
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF87171).withValues(alpha: 0.9),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Icon(Icons.close, size: 13, color: Colors.white),
                            ),
                          ),
                      ],
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
                          fontFamily: 'Poppins',
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
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 4.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: isNextTarget
                                  ? PagePreviewCanvas.limeAccent
                                  : Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isNextTarget ? Icons.download_done_rounded : Icons.lock_outline,
                                  size: (11 * effectiveScale).clamp(9.0, 14.0),
                                  color: isNextTarget ? PagePreviewCanvas.darkText : Colors.grey.shade700,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  isNextTarget ? 'TARGET: SLOT ${index + 1}' : 'SLOT ${index + 1}',
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: (8.0 * effectiveScale).clamp(7.0, 10.5),
                                    fontWeight: FontWeight.bold,
                                    color: isNextTarget ? PagePreviewCanvas.darkText : Colors.grey.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 5),
                          Icon(
                            isNextTarget
                                ? Icons.add_photo_alternate_rounded
                                : Icons.photo_outlined,
                            size: (26 * effectiveScale).clamp(16.0, 38.0),
                            color: isNextTarget ? PagePreviewCanvas.darkText : Colors.grey.shade400,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            isNextTarget
                                ? 'Drop Picture Here'
                                : 'Fills after Slot $index',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: (8.5 * effectiveScale).clamp(7.0, 11.5),
                              color: isNextTarget ? PagePreviewCanvas.darkText : Colors.grey.shade700,
                              fontWeight: isNextTarget ? FontWeight.bold : FontWeight.w500,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          if (isNextTarget)
                            Text(
                              'Sequential Fill (1 → 2 → 3)',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: (7.2 * effectiveScale).clamp(6.2, 9.5),
                                color: Colors.grey.shade600,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
