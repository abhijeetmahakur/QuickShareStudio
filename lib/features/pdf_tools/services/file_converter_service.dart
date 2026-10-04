import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'conversion_formats.dart';
import 'converters/converter_utils.dart';
import 'converters/document_converter.dart';
import 'converters/media_converters.dart';
import 'converters/table_converter.dart';

export 'conversion_formats.dart';
export 'converters/converter_utils.dart' show ConversionException;

class ConversionResult {
  final String outputFileName;
  final Uint8List outputBytes;
  final int pageOrItemCount;
  final String details;
  final bool hasWarnings;
  final String? warningMessage;

  ConversionResult({
    required this.outputFileName,
    required this.outputBytes,
    required this.pageOrItemCount,
    required this.details,
    this.hasWarnings = false,
    this.warningMessage,
  });
}

/// Offline, universal file conversion. Inputs are detected by extension
/// ([ConversionFormats.detect]); [ConversionFormats.targetsFor] lists valid outputs.
class FileConverterService {
  static const _tableFormats = {ConversionFormat.xlsx, ConversionFormat.ods, ConversionFormat.csv, ConversionFormat.json};
  static const _meshFormats = {ConversionFormat.stl, ConversionFormat.obj, ConversionFormat.threeMf};
  static const _archiveKinds = {SourceKind.zip, SourceKind.tar, SourceKind.tarGz, SourceKind.gzip};
  static const _tableKinds = {SourceKind.xlsx, SourceKind.ods, SourceKind.csv, SourceKind.tsv};

  /// Whether [fileName] can be converted to [format].
  static bool isSupported(String fileName, ConversionFormat format) =>
      ConversionFormats.targetsFor(fileName).contains(format);

  static Future<ConversionResult> convert({
    required ConversionFormat format,
    required String inputFileName,
    required Uint8List inputBytes,
    Function(double progress, String status)? onProgress,
  }) async {
    onProgress?.call(0.1, 'Reading ${inputFileName.split('/').last}...');
    final kind = ConversionFormats.detect(inputFileName);
    final baseName = baseNameOf(inputFileName);
    if (!isSupported(inputFileName, format)) {
      throw ConversionException('${kind.label} files cannot be converted to ${format.label}.');
    }
    // Let the progress indicator paint before CPU-heavy work starts.
    await Future<void>.delayed(Duration.zero);

    late Uint8List out;
    var count = 1;
    var details = '';
    final warnings = <String>[];

    if (format == ConversionFormat.zip || _archiveKinds.contains(kind)) {
      onProgress?.call(0.4, 'Packing archive...');
      final archive = ArchiveConverter.read(kind, inputFileName, inputBytes);
      out = ArchiveConverter.write(format, archive);
      count = archive.files.where((f) => f.isFile).length;
      details = 'Packed $count file(s) into ${format.label}.';
    } else if (format == ConversionFormat.pdfPagesPng) {
      return _pdfToImages(baseName, inputBytes, onProgress);
    } else if (kind == SourceKind.image) {
      onProgress?.call(0.4, 'Decoding image...');
      out = await ImageConverter.convertRaster(format, inputBytes, inputFileName);
      details = 'Converted image to ${format.label}.';
    } else if (kind == SourceKind.svg) {
      onProgress?.call(0.4, 'Rendering vector graphic...');
      out = await ImageConverter.convertSvg(format, inputBytes, inputFileName);
      details = 'Rendered SVG to ${format.label}.';
    } else if (_meshFormats.contains(format)) {
      onProgress?.call(0.4, 'Reading 3D mesh...');
      final mesh = MeshConverter.read(kind, inputBytes);
      out = MeshConverter.write(format, mesh);
      count = mesh.triangleCount;
      warnings.addAll(mesh.warnings);
      details = 'Converted ${mesh.triangleCount} triangles / ${mesh.vertexCount} vertices to ${format.label}.';
    } else if (_tableKinds.contains(kind) || _tableFormats.contains(format)) {
      onProgress?.call(0.4, 'Reading table data...');
      final table = TableReader.read(kind, inputFileName, inputBytes);
      onProgress?.call(0.7, 'Writing ${format.label}...');
      out = await TableWriter.write(format, table);
      count = table.rowCount;
      warnings.addAll(table.warnings);
      details = 'Converted ${table.rowCount} row(s) across ${table.sheets.length} sheet(s) to ${format.label}.';
    } else {
      onProgress?.call(0.4, 'Reading document structure...');
      final doc = DocumentReader.read(kind, inputFileName, inputBytes);
      onProgress?.call(0.7, 'Writing ${format.label}...');
      out = await DocumentWriter.write(format, doc);
      count = doc.itemCount;
      warnings.addAll(doc.warnings);
      final unit = doc.slides != null ? 'slide(s)' : doc.sourceCode != null ? 'line(s)' : 'block(s)';
      details = 'Converted $count $unit to ${format.label}.';
    }

    onProgress?.call(1.0, 'Conversion complete!');
    final uniqueWarnings = warnings.toSet().toList();
    return ConversionResult(
      outputFileName: '$baseName${format.outputExtension}',
      outputBytes: out,
      pageOrItemCount: count,
      details: details,
      hasWarnings: uniqueWarnings.isNotEmpty,
      warningMessage: uniqueWarnings.isEmpty ? null : uniqueWarnings.join('\n'),
    );
  }

  static Future<ConversionResult> _pdfToImages(
    String baseName,
    Uint8List pdfBytes,
    Function(double, String)? onProgress,
  ) async {
    onProgress?.call(0.2, 'Rasterizing PDF pages at 150 DPI...');
    final archive = Archive();
    var pageIndex = 0;

    await for (final page in Printing.raster(pdfBytes, dpi: 150)) {
      pageIndex++;
      onProgress?.call(0.2 + (pageIndex * 0.1).clamp(0.0, 0.7), 'Rendering page $pageIndex to PNG...');
      final pngBytes = await page.toPng();
      archive.addFile(ArchiveFile.bytes('${baseName}_Page_${pageIndex.toString().padLeft(2, '0')}.png', pngBytes));
    }

    if (pageIndex == 0) {
      // Fallback: render a title page if the rasterizer yielded nothing.
      final doc = pw.Document();
      doc.addPage(pw.Page(build: (ctx) => pw.Center(child: pw.Text(pdfSafe(baseName)))));
      await for (final page in Printing.raster(await doc.save(), dpi: 150)) {
        pageIndex++;
        archive.addFile(ArchiveFile.bytes('${baseName}_Page_01.png', await page.toPng()));
      }
    }

    onProgress?.call(1.0, 'Rendered $pageIndex image pages!');
    return ConversionResult(
      outputFileName: '${baseName}_images.zip',
      outputBytes: zipArchive(archive),
      pageOrItemCount: pageIndex,
      details: 'Rasterized $pageIndex page(s) into individual lossless PNGs.',
    );
  }
}
