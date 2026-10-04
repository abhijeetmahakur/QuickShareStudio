import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:xml/xml.dart';
import '../conversion_formats.dart';
import 'converter_utils.dart';

// =====================================================================
// Raster & vector images
// =====================================================================
class ImageConverter {
  static img.Image decode(Uint8List bytes, String fileName) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw ConversionException('Could not read "${fileName.split('/').last}". The image is damaged or uses an unsupported encoding.');
    }
    return decoded;
  }

  static Future<Uint8List> convertRaster(ConversionFormat format, Uint8List bytes, String fileName) async {
    final image = decode(bytes, fileName);
    switch (format) {
      case ConversionFormat.png:
        return img.encodePng(image);
      case ConversionFormat.jpg:
        return img.encodeJpg(_flatten(image), quality: 92);
      case ConversionFormat.bmp:
        return img.encodeBmp(image);
      case ConversionFormat.gif:
        return img.encodeGif(image);
      case ConversionFormat.tiff:
        return img.encodeTiff(image);
      case ConversionFormat.pdf:
        final isJpg = bytes.length > 3 && bytes[0] == 0xFF && bytes[1] == 0xD8;
        final isPng = bytes.length > 4 && bytes[0] == 0x89 && bytes[1] == 0x50;
        final embed = (isJpg || isPng) ? bytes : img.encodePng(image.frames.first);
        return _imagePdf(embed, image.width, image.height, baseNameOf(fileName));
      default:
        throw ConversionException('${format.label} is not an image format.');
    }
  }

  /// JPEG has no transparency: composite onto white so transparent areas don't turn black.
  static img.Image _flatten(img.Image src) {
    final frame = src.frames.first;
    if (!frame.hasAlpha) return frame;
    final bg = img.Image(width: frame.width, height: frame.height);
    img.fill(bg, color: img.ColorRgb8(255, 255, 255));
    return img.compositeImage(bg, frame);
  }

  static Future<Uint8List> _imagePdf(Uint8List embed, int width, int height, String title) async {
    final pdf = pw.Document(title: title);
    final format = width > height ? PdfPageFormat.a4.landscape : PdfPageFormat.a4;
    pdf.addPage(pw.Page(
      pageFormat: format,
      margin: const pw.EdgeInsets.all(24),
      build: (_) => pw.Center(child: pw.Image(pw.MemoryImage(embed), fit: pw.BoxFit.contain)),
    ));
    return pdf.save();
  }

  static Future<Uint8List> convertSvg(ConversionFormat format, Uint8List bytes, String fileName) async {
    final svg = decodeText(bytes);
    final pdfBytes = await _svgPdf(svg, baseNameOf(fileName));
    if (format == ConversionFormat.pdf) return pdfBytes;
    // Rasterise through the PDF renderer, which supports SVG paths, text and gradients.
    await for (final page in Printing.raster(pdfBytes, dpi: 192)) {
      final png = await page.toPng();
      if (format == ConversionFormat.png) return png;
      final decoded = img.decodePng(png);
      if (decoded == null) break;
      return img.encodeJpg(_flatten(decoded), quality: 92);
    }
    throw ConversionException('Could not render this SVG to an image.');
  }

  static Future<Uint8List> _svgPdf(String svg, String title) async {
    double? dim(String? v) => v == null ? null : double.tryParse(v.replaceAll(RegExp(r'[a-z%]+$'), ''));
    double w = 595, h = 842;
    try {
      final root = XmlDocument.parse(svg).rootElement;
      final viewBox = root.getAttribute('viewBox')?.split(RegExp(r'[\s,]+')).map(double.tryParse).toList();
      final ww = dim(root.getAttribute('width')) ?? (viewBox != null && viewBox.length == 4 ? viewBox[2] : null);
      final hh = dim(root.getAttribute('height')) ?? (viewBox != null && viewBox.length == 4 ? viewBox[3] : null);
      if (ww != null && hh != null && ww > 0 && hh > 0) {
        w = ww;
        h = hh;
      }
    } catch (_) {
      throw ConversionException('This SVG file is not valid XML.');
    }
    final pdf = pw.Document(title: title);
    try {
      pdf.addPage(pw.Page(
        pageFormat: PdfPageFormat(w, h),
        build: (_) => pw.SvgImage(svg: svg, fit: pw.BoxFit.contain),
      ));
      return await pdf.save();
    } catch (e) {
      throw ConversionException('This SVG uses features the converter cannot draw ($e).');
    }
  }
}

// =====================================================================
// 3D meshes (STL / OBJ / 3MF)
// =====================================================================
class Mesh {
  final List<double> vertices = []; // x,y,z triples
  final List<int> triangles = []; // vertex index triples
  final List<String> warnings = [];

  int get vertexCount => vertices.length ~/ 3;
  int get triangleCount => triangles.length ~/ 3;
}

class MeshConverter {
  static Mesh read(SourceKind kind, Uint8List bytes) {
    final Mesh mesh;
    switch (kind) {
      case SourceKind.stl:
        mesh = _stl(bytes);
      case SourceKind.obj:
        mesh = _obj(decodeText(bytes));
      case SourceKind.threeMf:
        mesh = _threeMf(bytes);
      default:
        throw ConversionException('${kind.label} is not a 3D model.');
    }
    if (mesh.triangleCount == 0) throw ConversionException('No triangles found in this model.');
    return mesh;
  }

  static Uint8List write(ConversionFormat format, Mesh mesh) {
    switch (format) {
      case ConversionFormat.stl:
        return _writeStl(mesh);
      case ConversionFormat.obj:
        return _writeObj(mesh);
      case ConversionFormat.threeMf:
        return _writeThreeMf(mesh);
      default:
        throw ConversionException('${format.label} is not a 3D format.');
    }
  }

  static Mesh _stl(Uint8List bytes) {
    final mesh = Mesh();
    final index = <String, int>{};
    int vertex(double x, double y, double z) {
      final key = '$x,$y,$z';
      return index.putIfAbsent(key, () {
        mesh.vertices.addAll([x, y, z]);
        return index.length;
      });
    }

    final data = ByteData.sublistView(bytes);
    final isBinary = bytes.length >= 84 && 84 + 50 * data.getUint32(80, Endian.little) == bytes.length;
    if (isBinary) {
      final count = data.getUint32(80, Endian.little);
      for (var t = 0; t < count; t++) {
        final base = 84 + t * 50 + 12; // skip the stored normal
        for (var v = 0; v < 3; v++) {
          final o = base + v * 12;
          mesh.triangles.add(vertex(
            data.getFloat32(o, Endian.little),
            data.getFloat32(o + 4, Endian.little),
            data.getFloat32(o + 8, Endian.little),
          ));
        }
      }
    } else {
      final re = RegExp(r'vertex\s+(\S+)\s+(\S+)\s+(\S+)');
      for (final m in re.allMatches(latin1.decode(bytes, allowInvalid: true))) {
        mesh.triangles.add(vertex(double.parse(m[1]!), double.parse(m[2]!), double.parse(m[3]!)));
      }
      final extra = mesh.triangles.length % 3;
      if (extra != 0) mesh.triangles.removeRange(mesh.triangles.length - extra, mesh.triangles.length);
    }
    return mesh;
  }

  static Mesh _obj(String text) {
    final mesh = Mesh();
    for (final raw in text.split('\n')) {
      final line = raw.trim();
      if (line.startsWith('v ')) {
        final p = line.split(RegExp(r'\s+'));
        if (p.length >= 4) mesh.vertices.addAll([double.parse(p[1]), double.parse(p[2]), double.parse(p[3])]);
      } else if (line.startsWith('f ')) {
        final idx = line.split(RegExp(r'\s+')).skip(1).map((tok) {
          final i = int.parse(tok.split('/').first);
          return i < 0 ? mesh.vertexCount + i : i - 1;
        }).toList();
        for (var k = 1; k + 1 < idx.length; k++) {
          mesh.triangles.addAll([idx[0], idx[k], idx[k + 1]]); // fan-triangulate polygons
        }
      }
    }
    return mesh;
  }

  static Mesh _threeMf(Uint8List bytes) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw ConversionException('This .3mf file is damaged.');
    }
    final model = archive.files.where((f) => f.isFile && f.name.toLowerCase().endsWith('.model')).firstOrNull;
    if (model == null) throw ConversionException('No 3D model found inside this .3mf file.');
    final doc = XmlDocument.parse(utf8.decode(model.content, allowMalformed: true));
    final mesh = Mesh();
    for (final m in doc.findAllElements('mesh')) {
      final offset = mesh.vertexCount;
      for (final v in m.findAllElements('vertex')) {
        mesh.vertices.addAll([
          double.parse(v.getAttribute('x') ?? '0'),
          double.parse(v.getAttribute('y') ?? '0'),
          double.parse(v.getAttribute('z') ?? '0'),
        ]);
      }
      for (final t in m.findAllElements('triangle')) {
        mesh.triangles.addAll([
          offset + int.parse(t.getAttribute('v1') ?? '0'),
          offset + int.parse(t.getAttribute('v2') ?? '0'),
          offset + int.parse(t.getAttribute('v3') ?? '0'),
        ]);
      }
    }
    if (doc.findAllElements('components').isNotEmpty || doc.findAllElements('item').any((i) => i.getAttribute('transform') != null)) {
      mesh.warnings.add('3MF component transforms were not applied; parts keep their local positions.');
    }
    return mesh;
  }

  static Uint8List _writeStl(Mesh mesh) {
    final count = mesh.triangleCount;
    final out = ByteData(84 + count * 50);
    final header = 'QuickShare Studio STL export'.codeUnits;
    for (var i = 0; i < header.length; i++) {
      out.setUint8(i, header[i]);
    }
    out.setUint32(80, count, Endian.little);
    final v = mesh.vertices;
    for (var t = 0; t < count; t++) {
      final a = mesh.triangles[t * 3] * 3, b = mesh.triangles[t * 3 + 1] * 3, c = mesh.triangles[t * 3 + 2] * 3;
      final ux = v[b] - v[a], uy = v[b + 1] - v[a + 1], uz = v[b + 2] - v[a + 2];
      final wx = v[c] - v[a], wy = v[c + 1] - v[a + 1], wz = v[c + 2] - v[a + 2];
      var nx = uy * wz - uz * wy, ny = uz * wx - ux * wz, nz = ux * wy - uy * wx;
      final len = math.sqrt(nx * nx + ny * ny + nz * nz);
      if (len > 0) {
        nx /= len;
        ny /= len;
        nz /= len;
      }
      var o = 84 + t * 50;
      for (final f in [nx, ny, nz, v[a], v[a + 1], v[a + 2], v[b], v[b + 1], v[b + 2], v[c], v[c + 1], v[c + 2]]) {
        out.setFloat32(o, f, Endian.little);
        o += 4;
      }
    }
    return out.buffer.asUint8List();
  }

  static String _num(double d) => d == d.roundToDouble() ? d.toInt().toString() : d.toStringAsFixed(6).replaceFirst(RegExp(r'0+$'), '');

  static Uint8List _writeObj(Mesh mesh) {
    final sb = StringBuffer('# QuickShare Studio OBJ export\n# ${mesh.vertexCount} vertices, ${mesh.triangleCount} triangles\n');
    for (var i = 0; i < mesh.vertices.length; i += 3) {
      sb.write('v ${_num(mesh.vertices[i])} ${_num(mesh.vertices[i + 1])} ${_num(mesh.vertices[i + 2])}\n');
    }
    for (var i = 0; i < mesh.triangles.length; i += 3) {
      sb.write('f ${mesh.triangles[i] + 1} ${mesh.triangles[i + 1] + 1} ${mesh.triangles[i + 2] + 1}\n');
    }
    return encodeText(sb.toString());
  }

  static Uint8List _writeThreeMf(Mesh mesh) {
    final sb = StringBuffer('<?xml version="1.0" encoding="UTF-8"?>\n'
        '<model unit="millimeter" xml:lang="en-US" xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02">'
        '<resources><object id="1" type="model"><mesh><vertices>');
    for (var i = 0; i < mesh.vertices.length; i += 3) {
      sb.write('<vertex x="${_num(mesh.vertices[i])}" y="${_num(mesh.vertices[i + 1])}" z="${_num(mesh.vertices[i + 2])}"/>');
    }
    sb.write('</vertices><triangles>');
    for (var i = 0; i < mesh.triangles.length; i += 3) {
      sb.write('<triangle v1="${mesh.triangles[i]}" v2="${mesh.triangles[i + 1]}" v3="${mesh.triangles[i + 2]}"/>');
    }
    sb.write('</triangles></mesh></object></resources><build><item objectid="1"/></build></model>');
    final archive = Archive();
    addText(archive, '[Content_Types].xml', '''<?xml version="1.0" encoding="UTF-8"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="model" ContentType="application/vnd.ms-package.3dmanufacturing-3dmodel+xml"/>
</Types>''');
    addText(archive, '_rels/.rels', '''<?xml version="1.0" encoding="UTF-8"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Target="/3D/3dmodel.model" Id="rel0" Type="http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel"/>
</Relationships>''');
    addText(archive, '3D/3dmodel.model', sb.toString());
    return zipArchive(archive);
  }
}

// =====================================================================
// Archives (ZIP / TAR / TAR.GZ / GZ) and "pack any file into a ZIP"
// =====================================================================
class ArchiveConverter {
  static Archive read(SourceKind kind, String fileName, Uint8List bytes) {
    try {
      switch (kind) {
        case SourceKind.zip:
          return ZipDecoder().decodeBytes(bytes);
        case SourceKind.tar:
          return TarDecoder().decodeBytes(bytes);
        case SourceKind.tarGz:
          return TarDecoder().decodeBytes(GZipDecoder().decodeBytes(bytes));
        case SourceKind.gzip:
          return Archive()..addFile(ArchiveFile.bytes(baseNameOf(fileName), GZipDecoder().decodeBytes(bytes)));
        default:
          return wrap(fileName, bytes);
      }
    } on ConversionException {
      rethrow;
    } catch (_) {
      throw ConversionException('This ${kind.label} is damaged or password-protected.');
    }
  }

  static Archive wrap(String fileName, Uint8List bytes) =>
      Archive()..addFile(ArchiveFile.bytes(fileName.split('/').last, bytes));

  static Uint8List write(ConversionFormat format, Archive source) {
    final archive = Archive();
    for (final f in source.files) {
      if (f.isFile) archive.addFile(ArchiveFile.bytes(f.name, f.content));
    }
    switch (format) {
      case ConversionFormat.zip:
        return ZipEncoder().encodeBytes(archive);
      case ConversionFormat.tar:
        return TarEncoder().encodeBytes(archive);
      case ConversionFormat.tarGz:
        return GZipEncoder().encodeBytes(TarEncoder().encodeBytes(archive));
      default:
        throw ConversionException('${format.label} is not an archive format.');
    }
  }
}
