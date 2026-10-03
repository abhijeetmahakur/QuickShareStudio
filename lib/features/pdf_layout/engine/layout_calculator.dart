import 'package:flutter/material.dart';
import '../models/page_geometry.dart';
import '../models/layout_preset.dart';

class CellLayoutResult {
  final int index;
  final int row;
  final int col;
  final Rect cellRect;
  final Rect imageRect;
  final Rect? captionRect;
  final bool isCropped;

  const CellLayoutResult({
    required this.index,
    required this.row,
    required this.col,
    required this.cellRect,
    required this.imageRect,
    this.captionRect,
    required this.isCropped,
  });
}

class LayoutCalculator {
  /// Computes exact geometric layout for cells and images on a page
  static List<CellLayoutResult> calculatePageLayout({
    required PageGeometry geometry,
    required LayoutPresetType presetType,
    int customRows = 2,
    int customCols = 2,
    double spacingPoints = 8.0,
    ImageFitMode fitMode = ImageFitMode.contain,
    bool showCaptions = false,
    List<double>? imageAspectRatios, // width / height for each image slot
  }) {
    final grid = LayoutPreset.getGridDimensions(
      presetType,
      geometry.isLandscape,
      customRows: customRows,
      customCols: customCols,
    );

    final rows = grid.rows;
    final cols = grid.cols;
    final totalSlots = rows * cols;

    final margin = geometry.marginPoints;
    final pageWidth = geometry.pageWidth;
    final pageHeight = geometry.pageHeight;

    final gridWidth = (pageWidth - (margin * 2)).clamp(10.0, pageWidth);
    final gridHeight = (pageHeight - (margin * 2)).clamp(10.0, pageHeight);

    final totalHorizSpacing = spacingPoints * (cols - 1);
    final totalVertSpacing = spacingPoints * (rows - 1);

    final cellWidth = ((gridWidth - totalHorizSpacing) / cols).clamp(10.0, gridWidth);
    final cellHeight = ((gridHeight - totalVertSpacing) / rows).clamp(10.0, gridHeight);

    final captionHeight = showCaptions ? 16.0 : 0.0;
    final usableImageHeight = (cellHeight - captionHeight).clamp(5.0, cellHeight);

    final results = <CellLayoutResult>[];

    for (var index = 0; index < totalSlots; index++) {
      final r = index ~/ cols;
      final c = index % cols;

      final cellX = margin + (c * (cellWidth + spacingPoints));
      final cellY = margin + (r * (cellHeight + spacingPoints));
      final cellRect = Rect.fromLTWH(cellX, cellY, cellWidth, cellHeight);

      // Default aspect ratio if not specified is standard 16:9 screenshot
      final imgAspect = (imageAspectRatios != null && index < imageAspectRatios.length)
          ? imageAspectRatios[index]
          : (16.0 / 9.0);

      Rect fittedImageRect;
      var isCropped = false;

      final usableAspect = cellWidth / usableImageHeight;

      if (fitMode == ImageFitMode.contain) {
        if (usableAspect > imgAspect) {
          // Cell is wider than image -> height fills, width is centered
          final w = usableImageHeight * imgAspect;
          final x = cellX + (cellWidth - w) / 2.0;
          final y = cellY;
          fittedImageRect = Rect.fromLTWH(x, y, w, usableImageHeight);
        } else {
          // Cell is taller than image -> width fills, height is centered
          final h = cellWidth / imgAspect;
          final x = cellX;
          final y = cellY + (usableImageHeight - h) / 2.0;
          fittedImageRect = Rect.fromLTWH(x, y, cellWidth, h);
        }
      } else {
        // Crop-to-fill
        fittedImageRect = Rect.fromLTWH(cellX, cellY, cellWidth, usableImageHeight);
        isCropped = (usableAspect - imgAspect).abs() > 0.05;
      }

      Rect? captionRect;
      if (showCaptions) {
        captionRect = Rect.fromLTWH(cellX, cellY + usableImageHeight + 2, cellWidth, captionHeight);
      }

      results.add(
        CellLayoutResult(
          index: index,
          row: r,
          col: c,
          cellRect: cellRect,
          imageRect: fittedImageRect,
          captionRect: captionRect,
          isCropped: isCropped,
        ),
      );
    }

    return results;
  }
}
