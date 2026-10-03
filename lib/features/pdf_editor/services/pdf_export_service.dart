import 'dart:typed_data';
import 'package:pdf/pdf.dart' as pw_pdf;
import 'package:pdf/widgets.dart' as pw;
import '../../pdf_layout/models/layout_preset.dart';
import '../../pdf_layout/engine/layout_calculator.dart';
import '../../../data/models/pdf_project.dart';

class PdfExportService {
  /// Generates a print-ready vector PDF document matching the on-screen live preview
  static Future<Uint8List> generatePdf({
    required PdfProject project,
    bool includeOcrLayer = false,
    String? defaultOcrText,
  }) async {
    final pdf = pw.Document(
      title: project.title,
      author: 'QuickShare Studio',
      creator: 'QuickShare PDF Engine',
    );

    for (final page in project.pages) {
      final pageFormat = page.geometry.toPdfPageFormat();

      final aspectRatios = page.images.map((img) => img.aspectRatio).toList();

      final cellResults = LayoutCalculator.calculatePageLayout(
        geometry: page.geometry,
        presetType: page.presetType,
        customRows: page.customRows,
        customCols: page.customCols,
        spacingPoints: page.spacingPoints,
        fitMode: page.fitMode,
        showCaptions: page.showCaptions,
        imageAspectRatios: aspectRatios,
      );

      pdf.addPage(
        pw.Page(
          pageFormat: pageFormat,
          margin: pw.EdgeInsets.zero, // Positioned precisely by points
          build: (pw.Context context) {
            final children = <pw.Widget>[];

            // Render each image slot
            for (var i = 0; i < cellResults.length; i++) {
              final cell = cellResults[i];
              if (i >= page.images.length) {
                continue;
              }

              final imgItem = page.images[i];
              final pdfImage = pw.MemoryImage(imgItem.bytes);

              // Positioned image matching exact calculated layout
              children.add(
                pw.Positioned(
                  left: cell.imageRect.left,
                  top: cell.imageRect.top,
                  child: pw.SizedBox(
                    width: cell.imageRect.width,
                    height: cell.imageRect.height,
                    child: pw.ClipRect(
                      child: pw.Image(
                        pdfImage,
                        fit: page.fitMode == ImageFitMode.contain ? pw.BoxFit.contain : pw.BoxFit.cover,
                      ),
                    ),
                  ),
                ),
              );

              // Optional OCR Searchable Invisible Text Layer
              if (includeOcrLayer) {
                final ocrContent = imgItem.caption ?? defaultOcrText ?? 'Screenshot: ${imgItem.name}';
                children.add(
                  pw.Positioned(
                    left: cell.imageRect.left,
                    top: cell.imageRect.top,
                    child: pw.SizedBox(
                      width: cell.imageRect.width,
                      height: cell.imageRect.height,
                      child: pw.Opacity(
                        opacity: 0.001, // Invisible selectable text layer
                        child: pw.Text(
                          ocrContent,
                          style: const pw.TextStyle(
                            fontSize: 10,
                            color: pw_pdf.PdfColors.black,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }

              // Optional Captions
              if (page.showCaptions && cell.captionRect != null) {
                final captionText = imgItem.caption ?? 'Figure ${page.pageNumber}.${i + 1}: ${imgItem.name}';
                children.add(
                  pw.Positioned(
                    left: cell.captionRect!.left,
                    top: cell.captionRect!.top,
                    child: pw.SizedBox(
                      width: cell.captionRect!.width,
                      height: cell.captionRect!.height,
                      child: pw.Text(
                        captionText,
                        style: pw.TextStyle(
                          fontSize: 8.5,
                          fontWeight: pw.FontWeight.bold,
                          color: pw_pdf.PdfColors.grey800,
                        ),
                        textAlign: pw.TextAlign.center,
                        maxLines: 1,
                      ),
                    ),
                  ),
                );
              }
            }

            // Optional Page Number
            if (page.showPageNumber) {
              children.add(
                pw.Positioned(
                  bottom: 10,
                  right: 20,
                  child: pw.Text(
                    'Page ${page.pageNumber} of ${project.pages.length}',
                    style: const pw.TextStyle(fontSize: 8, color: pw_pdf.PdfColors.grey600),
                  ),
                ),
              );
            }

            return pw.Stack(
              children: children,
            );
          },
        ),
      );
    }

    return pdf.save();
  }
}
