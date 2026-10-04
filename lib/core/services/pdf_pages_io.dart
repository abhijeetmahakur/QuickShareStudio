import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

// Native fallback: no lossless page copier is available, so pages are re-rendered at
// 150 DPI and placed on pages of their original size.

Future<int> pageCount(Uint8List bytes) async {
  final count = await Printing.raster(bytes, dpi: 1).length;
  if (count == 0) throw Exception('No pages found in this PDF');
  return count;
}

Future<List<PdfRaster>> _rasterize(Uint8List bytes, {List<int>? zeroBasedPages}) =>
    Printing.raster(bytes, dpi: 150, pages: zeroBasedPages).toList();

Future<void> _addRasterPages(pw.Document doc, List<PdfRaster> pages) async {
  for (final page in pages) {
    final png = await page.toPng();
    // Raster size is in pixels at 150 DPI; convert back to PDF points (72 per inch).
    final format = PdfPageFormat(page.width * 72 / 150, page.height * 72 / 150);
    doc.addPage(pw.Page(
      pageFormat: format,
      margin: pw.EdgeInsets.zero,
      build: (_) => pw.FullPage(ignoreMargins: true, child: pw.Image(pw.MemoryImage(png), fit: pw.BoxFit.fill)),
    ));
  }
}

Future<Uint8List> extractPages(Uint8List bytes, List<int> pageNumbers) async {
  final doc = pw.Document();
  final rendered = await _rasterize(bytes, zeroBasedPages: [for (final p in pageNumbers) p - 1]);
  if (rendered.length != pageNumbers.length) {
    throw Exception('Could not read all requested pages');
  }
  await _addRasterPages(doc, rendered);
  return doc.save();
}

Future<Uint8List> merge(List<Uint8List> documents) async {
  final doc = pw.Document();
  for (final bytes in documents) {
    final rendered = await _rasterize(bytes);
    if (rendered.isEmpty) throw Exception('A PDF could not be read');
    await _addRasterPages(doc, rendered);
  }
  return doc.save();
}
