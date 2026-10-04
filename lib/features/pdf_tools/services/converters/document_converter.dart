import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:xml/xml.dart';
import '../conversion_formats.dart';
import 'converter_utils.dart';

enum BlockType { heading, paragraph, bullet, code, table, image, pageBreak }

class DocBlock {
  final BlockType type;
  final String text;
  final int level;
  final List<List<String>> rows;
  final Uint8List? image;

  DocBlock.heading(this.text, [this.level = 1]) : type = BlockType.heading, rows = const [], image = null;
  DocBlock.paragraph(this.text) : type = BlockType.paragraph, level = 0, rows = const [], image = null;
  DocBlock.bullet(this.text) : type = BlockType.bullet, level = 0, rows = const [], image = null;
  DocBlock.code(this.text) : type = BlockType.code, level = 0, rows = const [], image = null;
  DocBlock.table(this.rows) : type = BlockType.table, text = '', level = 0, image = null;
  DocBlock.image(Uint8List this.image) : type = BlockType.image, text = '', level = 0, rows = const [];
  DocBlock.pageBreak() : type = BlockType.pageBreak, text = '', level = 0, rows = const [], image = null;
}

class _TextFragment {
  final double x;
  final double y;
  final String text;
  final double size;
  final int order;
  _TextFragment(this.x, this.y, this.text, this.size, this.order);
}

class SlideData {
  final String title;
  final List<String> lines;
  final List<Uint8List> images;
  SlideData(this.title, this.lines, this.images);
}

/// Format-neutral document: what every reader produces and every writer consumes.
class DocModel {
  final String title;
  final List<DocBlock> blocks;
  final List<String> warnings;
  /// Set for presentations so PDF output keeps one landscape page per slide.
  final List<SlideData>? slides;
  /// Set for source code so PDF output becomes a numbered code listing.
  final String? sourceCode;

  DocModel(this.title, this.blocks, {List<String>? warnings, this.slides, this.sourceCode})
      : warnings = warnings ?? [];

  int get itemCount => slides?.length ?? (sourceCode != null ? '\n'.allMatches(sourceCode!).length + 1 : blocks.length);
}

// =====================================================================
// Readers
// =====================================================================
class DocumentReader {
  static DocModel read(SourceKind kind, String fileName, Uint8List bytes) {
    final title = baseNameOf(fileName);
    switch (kind) {
      case SourceKind.pdf:
        return fromPdf(title, bytes);
      case SourceKind.docx:
        return _fromDocx(title, bytes);
      case SourceKind.doc:
        return _fromLegacyDoc(title, bytes);
      case SourceKind.odt:
        return _fromOdt(title, bytes);
      case SourceKind.rtf:
        return _fromPlainLines(title, _rtfToText(latin1.decode(bytes, allowInvalid: true)));
      case SourceKind.markdown:
        return _fromMarkdown(title, decodeText(bytes));
      case SourceKind.html:
        return _fromHtml(title, decodeText(bytes));
      case SourceKind.pptx:
        return _fromPptx(title, bytes);
      case SourceKind.odp:
        return _fromOdp(title, bytes);
      case SourceKind.code:
      case SourceKind.xml:
      case SourceKind.json:
        return code(fileName, bytes);
      default:
        return _fromPlainLines(title, decodeText(bytes));
    }
  }

  /// Source code (or any text) kept verbatim; PDF output becomes a numbered listing.
  static DocModel code(String fileName, Uint8List bytes) {
    var text = decodeText(bytes);
    if (fileName.toLowerCase().endsWith('.json')) {
      try {
        text = const JsonEncoder.withIndent('  ').convert(jsonDecode(text));
      } catch (_) {}
    }
    return DocModel(fileName.split('/').last, [DocBlock.code(text)], sourceCode: text);
  }

  static DocModel _fromPlainLines(String title, String text) {
    final blocks = <DocBlock>[];
    for (final line in text.replaceAll('\r', '').split('\n')) {
      blocks.add(DocBlock.paragraph(line.trimRight()));
    }
    while (blocks.isNotEmpty && blocks.last.text.isEmpty) {
      blocks.removeLast();
    }
    return DocModel(title, blocks);
  }

  // ---------------- PDF ----------------
  static DocModel fromPdf(String title, Uint8List bytes) {
    final lines = extractPdfLines(bytes);
    final model = DocModel(title, [for (final l in lines) DocBlock.paragraph(l)]);
    if (lines.isEmpty) {
      model.warnings.add('No selectable text found. Scanned or image-only PDFs need OCR (see the OCR tab).');
    }
    return model;
  }

  /// Extracts text lines from a PDF, decompressing FlateDecode content streams.
  static List<String> extractPdfLines(Uint8List bytes) {
    final raw = latin1.decode(bytes, allowInvalid: true);
    final lines = <String>[];
    var pos = 0;
    while (true) {
      final s = raw.indexOf('stream', pos);
      if (s == -1) break;
      pos = s + 6;
      if (s >= 3 && raw.substring(s - 3, s) == 'end') continue;
      var dataStart = s + 6;
      if (dataStart < raw.length && raw[dataStart] == '\r') dataStart++;
      if (dataStart < raw.length && raw[dataStart] == '\n') dataStart++;
      final end = raw.indexOf('endstream', dataStart);
      if (end == -1) break;
      pos = end + 9;
      final dictStart = raw.lastIndexOf('<<', s);
      final dict = dictStart == -1 ? '' : raw.substring(dictStart, s);
      if (dict.contains('/Image') || dict.contains('/FontFile') || dict.contains('/Length1') ||
          dict.contains('/XRef') || dict.contains('/ObjStm') || dict.contains('/Metadata')) {
        continue;
      }
      var data = bytes.sublist(dataStart, end);
      if (dict.contains('/FlateDecode')) {
        try {
          data = ZLibDecoder().decodeBytes(data);
        } catch (_) {
          continue;
        }
      } else if (dict.contains('/Filter')) {
        continue; // other encodings (DCT, LZW, ...) are images or unsupported
      }
      final content = latin1.decode(data, allowInvalid: true);
      if (!content.contains('Tj') && !content.contains('TJ') && !content.contains("'")) continue;
      lines.addAll(_parseContentStream(content));
    }
    return lines;
  }

  /// Interprets text operators in a page content stream, tracking the text and
  /// transformation matrices so fragments can be regrouped into lines by position.
  static List<String> _parseContentStream(String s) {
    final frags = <_TextFragment>[];
    final pending = <String>[];
    final nums = <double>[];
    List<String>? array;
    var ctm = _identity;
    final ctmStack = <List<double>>[];
    var tm = _identity;
    var tlm = _identity;
    var fontSize = 10.0;
    var leading = 0.0;
    var order = 0;

    void show(String text) {
      if (text.isEmpty) return;
      final m = _mul(tm, ctm);
      final size = (fontSize * (m[3].abs() > 0 ? m[3].abs() : 1)).clamp(1.0, 200.0);
      frags.add(_TextFragment(m[4], m[5], text, size, order++));
      // Advance roughly by the text width so later fragments in the same block sort after it.
      tm = _mul([1, 0, 0, 1, _estimateWidth(text, fontSize), 0], tm);
    }

    void nextLine(double tx, double ty) {
      tlm = _mul([1, 0, 0, 1, tx, ty], tlm);
      tm = tlm;
    }

    var i = 0;
    final n = s.length;
    while (i < n) {
      final c = s[i];
      if (c == '(') {
        final sb = StringBuffer();
        var depth = 1;
        i++;
        while (i < n && depth > 0) {
          final ch = s[i];
          if (ch == '\\' && i + 1 < n) {
            final e = s[i + 1];
            if (e.codeUnitAt(0) >= 0x30 && e.codeUnitAt(0) <= 0x37) {
              var j = i + 1;
              var oct = '';
              while (j < n && oct.length < 3 && s.codeUnitAt(j) >= 0x30 && s.codeUnitAt(j) <= 0x37) {
                oct += s[j];
                j++;
              }
              sb.writeCharCode(int.parse(oct, radix: 8));
              i = j;
              continue;
            }
            const esc = {'n': '\n', 'r': '', 't': ' ', 'b': '', 'f': ''};
            sb.write(esc[e] ?? (e == '\n' || e == '\r' ? '' : e));
            i += 2;
            continue;
          }
          if (ch == '(') depth++;
          if (ch == ')') {
            depth--;
            if (depth == 0) break;
          }
          sb.write(ch);
          i++;
        }
        i++;
        (array ?? pending).add(sb.toString());
        continue;
      }
      if (c == '<' && i + 1 < n && s[i + 1] != '<') {
        final close = s.indexOf('>', i);
        if (close == -1) break;
        final hex = s.substring(i + 1, close).replaceAll(RegExp(r'\s'), '');
        i = close + 1;
        final bytesOut = <int>[];
        for (var k = 0; k + 1 < hex.length; k += 2) {
          bytesOut.add(int.tryParse(hex.substring(k, k + 2), radix: 16) ?? 0);
        }
        final zeros = bytesOut.where((b) => b == 0).length;
        String decoded;
        if (bytesOut.length >= 2 && bytesOut.length.isEven && zeros * 3 >= bytesOut.length) {
          final units = <int>[];
          for (var k = 0; k + 1 < bytesOut.length; k += 2) {
            units.add((bytesOut[k] << 8) | bytesOut[k + 1]);
          }
          decoded = String.fromCharCodes(units);
        } else {
          decoded = String.fromCharCodes(bytesOut);
        }
        (array ?? pending).add(decoded);
        continue;
      }
      if (c == '<' || c == '>') {
        i += (i + 1 < n && s[i + 1] == c) ? 2 : 1;
        continue;
      }
      if (c == '[') {
        array = [];
        i++;
        continue;
      }
      if (c == ']') {
        if (array != null) pending.add(array.join());
        array = null;
        i++;
        continue;
      }
      if (c == '%') {
        while (i < n && s[i] != '\n' && s[i] != '\r') {
          i++;
        }
        continue;
      }
      if (c == '/') {
        i++;
        while (i < n && !' \t\r\n/[]()<>{}%'.contains(s[i])) {
          i++;
        }
        continue;
      }
      final cu = c.codeUnitAt(0);
      if ((cu >= 0x30 && cu <= 0x39) || c == '.' || c == '-' || c == '+') {
        var j = i + 1;
        while (j < n && ((s.codeUnitAt(j) >= 0x30 && s.codeUnitAt(j) <= 0x39) || s[j] == '.')) {
          j++;
        }
        final v = double.tryParse(s.substring(i, j));
        if (v != null) {
          if (array != null) {
            if (v < -180) array.add(' '); // large kerning gap inside TJ = word space
          } else {
            nums.add(v);
          }
        }
        i = j;
        continue;
      }
      final isOpChar = (cu >= 0x41 && cu <= 0x5A) || (cu >= 0x61 && cu <= 0x7A) || c == "'" || c == '"' || c == '*';
      if (isOpChar) {
        var j = i + 1;
        while (j < n && ((s.codeUnitAt(j) >= 0x41 && s.codeUnitAt(j) <= 0x5A) || (s.codeUnitAt(j) >= 0x61 && s.codeUnitAt(j) <= 0x7A) || s[j] == '*')) {
          j++;
        }
        final op = s.substring(i, j);
        i = j;
        List<double> last(int k) => nums.length >= k ? nums.sublist(nums.length - k) : List.filled(k, 0);
        switch (op) {
          case 'q':
            ctmStack.add(ctm);
          case 'Q':
            if (ctmStack.isNotEmpty) ctm = ctmStack.removeLast();
          case 'cm':
            ctm = _mul(last(6), ctm);
          case 'BT':
            tm = _identity;
            tlm = _identity;
          case 'Tf':
            fontSize = last(1)[0];
          case 'TL':
            leading = last(1)[0];
          case 'Td':
            final t = last(2);
            nextLine(t[0], t[1]);
          case 'TD':
            final t = last(2);
            leading = -t[1];
            nextLine(t[0], t[1]);
          case 'Tm':
            tlm = last(6);
            tm = tlm;
          case 'T*':
            nextLine(0, -leading);
          case 'Tj':
          case 'TJ':
            show(pending.join());
          case "'":
            nextLine(0, -leading);
            show(pending.join());
          case '"':
            nextLine(0, -leading);
            show(pending.join());
        }
        pending.clear();
        nums.clear();
        continue;
      }
      i++;
    }
    return _assembleLines(frags);
  }

  static const _identity = [1.0, 0.0, 0.0, 1.0, 0.0, 0.0];

  /// Standard Helvetica advance widths (1/1000 em) for ASCII 32..126.
  static const _helveticaWidths = [
    278, 278, 355, 556, 556, 889, 667, 191, 333, 333, 389, 584, 278, 333, 278, 278, // space .. /
    556, 556, 556, 556, 556, 556, 556, 556, 556, 556, 278, 278, 584, 584, 584, 556, // 0 .. ?
    1015, 667, 667, 722, 722, 667, 611, 778, 722, 278, 500, 667, 556, 833, 722, 778, // @ .. O
    667, 778, 722, 667, 611, 722, 667, 944, 667, 667, 611, 278, 278, 278, 469, 556, // P .. _
    333, 556, 556, 500, 556, 556, 278, 556, 556, 222, 222, 500, 222, 833, 556, 556, // ` .. o
    556, 556, 333, 500, 278, 556, 500, 722, 500, 500, 500, 334, 260, 334, 584, // p .. ~
  ];

  /// Approximate advance width; real font metrics are not parsed, Helvetica is a good average.
  static double _estimateWidth(String text, double size) {
    var units = 0;
    for (final r in text.runes) {
      units += (r >= 32 && r <= 126) ? _helveticaWidths[r - 32] : 556;
    }
    return units / 1000 * size;
  }

  static List<double> _mul(List<double> a, List<double> b) => [
        a[0] * b[0] + a[1] * b[2],
        a[0] * b[1] + a[1] * b[3],
        a[2] * b[0] + a[3] * b[2],
        a[2] * b[1] + a[3] * b[3],
        a[4] * b[0] + a[5] * b[2] + b[4],
        a[4] * b[1] + a[5] * b[3] + b[5],
      ];

  /// Groups fragments sharing a baseline into lines (top to bottom), ordered left to right.
  static List<String> _assembleLines(List<_TextFragment> frags) {
    if (frags.isEmpty) return [];
    final sorted = [...frags]..sort((a, b) {
        final dy = b.y.compareTo(a.y);
        return dy != 0 ? dy : a.order.compareTo(b.order);
      });
    final lines = <List<_TextFragment>>[];
    for (final f in sorted) {
      if (lines.isNotEmpty && (lines.last.first.y - f.y).abs() <= f.size * 0.4) {
        lines.last.add(f);
      } else {
        lines.add([f]);
      }
    }
    final out = <String>[];
    for (final line in lines) {
      line.sort((a, b) => (a.x - b.x).abs() < 0.01 ? a.order.compareTo(b.order) : a.x.compareTo(b.x));
      final sb = StringBuffer();
      _TextFragment? prev;
      for (final f in line) {
        if (prev != null) {
          final gap = f.x - (prev.x + _estimateWidth(prev.text, prev.size));
          final needsSpace = !prev.text.endsWith(' ') && !f.text.startsWith(' ');
          if (needsSpace && gap > prev.size * 0.12) sb.write(' ');
        }
        sb.write(f.text);
        prev = f;
      }
      final t = sb.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
      if (t.isNotEmpty) out.add(t);
    }
    return out;
  }

  // ---------------- DOCX ----------------
  static DocModel _fromDocx(String title, Uint8List bytes) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw ConversionException('This .docx file is damaged or not a Word document.');
    }
    final xmlStr = readArchiveText(archive, 'word/document.xml');
    if (xmlStr == null) throw ConversionException('This .docx file has no document body.');
    final rels = _readRels(archive, 'word/_rels/document.xml.rels', 'word/');
    final body = XmlDocument.parse(xmlStr).findAllElements('w:body').firstOrNull;
    final blocks = <DocBlock>[];
    if (body != null) _docxChildren(body, blocks, archive, rels);
    return DocModel(title, blocks);
  }

  static void _docxChildren(XmlElement parent, List<DocBlock> blocks, Archive archive, Map<String, String> rels) {
    for (final child in parent.childElements) {
      switch (child.name.qualified) {
        case 'w:p':
          _docxParagraph(child, blocks, archive, rels);
        case 'w:tbl':
          final rows = <List<String>>[];
          for (final tr in child.findElements('w:tr')) {
            rows.add([
              for (final tc in tr.findElements('w:tc'))
                tc.findAllElements('w:p').map(_docxRunText).join('\n').trim(),
            ]);
          }
          if (rows.isNotEmpty) blocks.add(DocBlock.table(rows));
        case 'w:sdt':
          final content = child.findElements('w:sdtContent').firstOrNull;
          if (content != null) _docxChildren(content, blocks, archive, rels);
      }
    }
  }

  static String _docxRunText(XmlElement p) {
    final sb = StringBuffer();
    for (final e in p.descendants.whereType<XmlElement>()) {
      switch (e.name.qualified) {
        case 'w:t':
          sb.write(e.innerText);
        case 'w:tab':
          if (e.parentElement?.name.qualified == 'w:r') sb.write('\t');
        case 'w:br':
        case 'w:cr':
          sb.write('\n');
      }
    }
    return sb.toString();
  }

  static void _docxParagraph(XmlElement p, List<DocBlock> blocks, Archive archive, Map<String, String> rels) {
    final pPr = p.findElements('w:pPr').firstOrNull;
    final style = pPr?.findElements('w:pStyle').firstOrNull?.getAttribute('w:val')?.toLowerCase() ?? '';
    final isList = pPr?.findElements('w:numPr').isNotEmpty == true || style.contains('list');
    final text = _docxRunText(p);
    if (style.startsWith('heading') || style == 'title' || style == 'subtitle') {
      final level = style == 'title' ? 1 : int.tryParse(style.replaceAll(RegExp(r'[^0-9]'), '')) ?? 2;
      if (text.trim().isNotEmpty) blocks.add(DocBlock.heading(text.trim(), level.clamp(1, 4)));
    } else if (isList && text.trim().isNotEmpty) {
      blocks.add(DocBlock.bullet(text.trim()));
    } else {
      blocks.add(DocBlock.paragraph(text));
    }
    for (final blip in p.findAllElements('a:blip')) {
      final id = blip.getAttribute('r:embed');
      final data = id == null ? null : archive.findFile(rels[id] ?? '')?.content;
      if (data != null) blocks.add(DocBlock.image(Uint8List.fromList(data)));
    }
    if (p.findAllElements('w:br').any((b) => b.getAttribute('w:type') == 'page')) {
      blocks.add(DocBlock.pageBreak());
    }
  }

  /// Reads an OPC relationships part into Id -> archive path.
  static Map<String, String> _readRels(Archive archive, String relsPath, String baseDir) {
    final xml = readArchiveText(archive, relsPath);
    if (xml == null) return {};
    final map = <String, String>{};
    for (final r in XmlDocument.parse(xml).findAllElements('Relationship')) {
      final id = r.getAttribute('Id');
      final target = r.getAttribute('Target');
      if (id == null || target == null) continue;
      map[id] = _resolvePath(baseDir, target);
    }
    return map;
  }

  static String _resolvePath(String baseDir, String target) {
    if (target.startsWith('/')) return target.substring(1);
    final parts = [...baseDir.split('/').where((p) => p.isNotEmpty)];
    for (final seg in target.split('/')) {
      if (seg == '..') {
        if (parts.isNotEmpty) parts.removeLast();
      } else if (seg != '.' && seg.isNotEmpty) {
        parts.add(seg);
      }
    }
    return parts.join('/');
  }

  // ---------------- Legacy .doc (best effort) ----------------
  static DocModel _fromLegacyDoc(String title, Uint8List bytes) {
    // Word 97-2003 stores text as UTF-16LE or CP1252 runs inside an OLE container.
    final utf16 = StringBuffer();
    final run = StringBuffer();
    var runLen = 0;
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      final ch = bytes[i] | (bytes[i + 1] << 8);
      final printable = (ch >= 0x20 && ch < 0xD800 && ch != 0xFFFF) || ch == 0x0D || ch == 0x09;
      if (printable) {
        run.writeCharCode(ch);
        runLen++;
      } else {
        if (runLen >= 12) utf16.write(run);
        run.clear();
        runLen = 0;
      }
    }
    if (runLen >= 12) utf16.write(run);

    final ascii = StringBuffer();
    final run8 = StringBuffer();
    for (final b in bytes) {
      if ((b >= 0x20 && b < 0x7F) || b == 0x0D || b == 0x09 || (b >= 0xA0)) {
        run8.writeCharCode(b);
      } else {
        if (run8.length >= 24) ascii.write('${run8.toString()}\r');
        run8.clear();
      }
    }
    String pick(String s) {
      final letters = RegExp(r'[A-Za-z]').allMatches(s).length;
      return letters > s.length * 0.45 ? s : '';
    }

    final a = pick(utf16.toString());
    final b = pick(ascii.toString());
    final text = a.length >= b.length ? a : b;
    final lines = text
        .split('\r')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty && RegExp(r'[A-Za-z]{2}').hasMatch(l))
        .toList();
    if (lines.isEmpty) throw ConversionException('Could not read text from this .doc file. Re-save it as .docx and try again.');
    return DocModel(title, [for (final l in lines) DocBlock.paragraph(l)],
        warnings: ['Legacy .doc: text extracted on a best-effort basis; formatting and images are not kept.']);
  }

  // ---------------- ODT ----------------
  static DocModel _fromOdt(String title, Uint8List bytes) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw ConversionException('This .odt file is damaged or not an OpenDocument text file.');
    }
    final xml = readArchiveText(archive, 'content.xml');
    if (xml == null) throw ConversionException('This .odt file has no content.');
    final body = XmlDocument.parse(xml).findAllElements('office:text').firstOrNull;
    final blocks = <DocBlock>[];
    if (body != null) _odfChildren(body, blocks, archive);
    return DocModel(title, blocks);
  }

  static void _odfChildren(XmlElement parent, List<DocBlock> blocks, Archive archive, {bool inList = false}) {
    for (final child in parent.childElements) {
      switch (child.name.qualified) {
        case 'text:h':
          final level = int.tryParse(child.getAttribute('text:outline-level') ?? '') ?? 1;
          blocks.add(DocBlock.heading(odfText(child).trim(), level.clamp(1, 4)));
        case 'text:p':
          final t = odfText(child);
          blocks.add(inList ? DocBlock.bullet(t.trim()) : DocBlock.paragraph(t));
          for (final image in child.findAllElements('draw:image')) {
            final data = archive.findFile(image.getAttribute('xlink:href') ?? '')?.content;
            if (data != null) blocks.add(DocBlock.image(Uint8List.fromList(data)));
          }
        case 'text:list':
        case 'text:list-item':
        case 'text:section':
          _odfChildren(child, blocks, archive, inList: inList || child.name.qualified != 'text:section');
        case 'table:table':
          final rows = <List<String>>[];
          for (final row in child.findAllElements('table:table-row')) {
            rows.add([for (final cell in row.findElements('table:table-cell')) odfText(cell).trim()]);
          }
          if (rows.isNotEmpty) blocks.add(DocBlock.table(rows));
      }
    }
  }

  /// Text of an ODF element, honouring <text:s>, <text:tab> and <text:line-break>.
  static String odfText(XmlNode node) {
    final sb = StringBuffer();
    for (final c in node.children) {
      if (c is XmlText) {
        sb.write(c.value);
      } else if (c is XmlElement) {
        switch (c.name.qualified) {
          case 'text:s':
            sb.write(' ' * (int.tryParse(c.getAttribute('text:c') ?? '') ?? 1));
          case 'text:tab':
            sb.write('\t');
          case 'text:line-break':
            sb.write('\n');
          case 'text:p':
          case 'text:h':
            if (sb.isNotEmpty) sb.write('\n');
            sb.write(odfText(c));
          case 'draw:frame':
          case 'office:annotation':
            break;
          default:
            sb.write(odfText(c));
        }
      }
    }
    return sb.toString();
  }

  // ---------------- RTF ----------------
  static const _rtfSkipDestinations = {
    'fonttbl', 'colortbl', 'stylesheet', 'info', 'pict', 'object', 'header', 'footer', 'headerl', 'headerr',
    'headerf', 'footerl', 'footerr', 'footerf', 'listtable', 'listoverridetable', 'rsidtbl', 'generator',
    'themedata', 'colorschememapping', 'latentstyles', 'datastore', 'xmlnstbl', 'mmathPr', 'pgdsctbl',
    'revtbl', 'fldinst', 'filetbl', 'footnote', 'annotation', 'bkmkstart', 'bkmkend', 'shppict', 'nonshppict',
  };

  static String _rtfToText(String rtf) {
    final out = StringBuffer();
    final skipStack = <bool>[false];
    final ucStack = <int>[1];
    var i = 0;
    var skipFallback = 0;
    while (i < rtf.length) {
      final c = rtf[i];
      final skip = skipStack.last;
      if (c == '{') {
        skipStack.add(skip);
        ucStack.add(ucStack.last);
        i++;
      } else if (c == '}') {
        if (skipStack.length > 1) {
          skipStack.removeLast();
          ucStack.removeLast();
        }
        i++;
      } else if (c == '\\' && i + 1 < rtf.length) {
        final nx = rtf[i + 1];
        if (nx == '\\' || nx == '{' || nx == '}') {
          if (!skip) out.write(nx);
          i += 2;
        } else if (nx == "'") {
          final code = int.tryParse(rtf.substring(i + 2, (i + 4).clamp(0, rtf.length)), radix: 16);
          if (!skip && code != null) {
            if (skipFallback > 0) {
              skipFallback--;
            } else {
              out.writeCharCode(code);
            }
          }
          i += 4;
        } else if (nx == '*') {
          skipStack[skipStack.length - 1] = true;
          i += 2;
        } else if (nx == '~') {
          if (!skip) out.write(' ');
          i += 2;
        } else if (nx == '_') {
          if (!skip) out.write('-');
          i += 2;
        } else if (RegExp(r'[a-zA-Z]').hasMatch(nx)) {
          var j = i + 1;
          while (j < rtf.length && RegExp(r'[a-zA-Z]').hasMatch(rtf[j])) {
            j++;
          }
          final word = rtf.substring(i + 1, j);
          var k = j;
          if (k < rtf.length && (rtf[k] == '-' || RegExp(r'[0-9]').hasMatch(rtf[k]))) {
            k++;
            while (k < rtf.length && RegExp(r'[0-9]').hasMatch(rtf[k])) {
              k++;
            }
          }
          final param = int.tryParse(rtf.substring(j, k));
          if (k < rtf.length && rtf[k] == ' ') k++;
          i = k;
          if (_rtfSkipDestinations.contains(word)) {
            skipStack[skipStack.length - 1] = true;
            continue;
          }
          if (skip) continue;
          switch (word) {
            case 'par':
            case 'line':
            case 'sect':
            case 'page':
            case 'row':
              out.write('\n');
            case 'tab':
            case 'cell':
              out.write('\t');
            case 'uc':
              ucStack[ucStack.length - 1] = param ?? 1;
            case 'u':
              if (param != null) {
                out.writeCharCode(param < 0 ? param + 65536 : param);
                skipFallback = ucStack.last;
              }
            case 'emdash':
              out.write('\u2014');
            case 'endash':
              out.write('\u2013');
            case 'bullet':
              out.write('\u2022');
            case 'lquote':
              out.write('\u2018');
            case 'rquote':
              out.write('\u2019');
            case 'ldblquote':
              out.write('\u201C');
            case 'rdblquote':
              out.write('\u201D');
          }
        } else {
          i += 2;
        }
      } else if (c == '\r' || c == '\n') {
        i++;
      } else {
        if (!skip) {
          if (skipFallback > 0) {
            skipFallback--;
          } else {
            out.write(c);
          }
        }
        i++;
      }
    }
    return out.toString();
  }

  // ---------------- Markdown ----------------
  static DocModel _fromMarkdown(String title, String md) {
    final blocks = <DocBlock>[];
    final lines = md.split('\n');
    var i = 0;
    String inline(String s) => s
        .replaceAllMapped(RegExp(r'!\[([^\]]*)\]\([^)]*\)'), (m) => m[1]!)
        .replaceAllMapped(RegExp(r'\[([^\]]+)\]\(([^)]*)\)'), (m) => '${m[1]} (${m[2]})')
        .replaceAll(RegExp(r'(\*\*|__)'), '')
        .replaceAll('`', '');
    while (i < lines.length) {
      final line = lines[i];
      final t = line.trim();
      if (t.startsWith('```')) {
        final code = <String>[];
        i++;
        while (i < lines.length && !lines[i].trim().startsWith('```')) {
          code.add(lines[i]);
          i++;
        }
        blocks.add(DocBlock.code(code.join('\n')));
      } else if (RegExp(r'^#{1,6}\s').hasMatch(t)) {
        final level = t.indexOf(' ');
        blocks.add(DocBlock.heading(inline(t.substring(level).trim()), level.clamp(1, 4)));
      } else if (RegExp(r'^([-*+]|\d+[.)])\s+').hasMatch(t)) {
        blocks.add(DocBlock.bullet(inline(t.replaceFirst(RegExp(r'^([-*+]|\d+[.)])\s+'), ''))));
      } else if (t.startsWith('|')) {
        final rows = <List<String>>[];
        while (i < lines.length && lines[i].trim().startsWith('|')) {
          final row = lines[i].trim();
          if (!RegExp(r'^\|[\s:|-]+\|?$').hasMatch(row)) {
            rows.add(row.replaceAll(RegExp(r'^\||\|$'), '').split('|').map((c) => inline(c.trim())).toList());
          }
          i++;
        }
        blocks.add(DocBlock.table(rows));
        continue;
      } else if (RegExp(r'^(-{3,}|\*{3,}|_{3,})$').hasMatch(t)) {
        blocks.add(DocBlock.paragraph(''));
      } else {
        blocks.add(DocBlock.paragraph(inline(t.startsWith('>') ? t.substring(1).trim() : line.trimRight())));
      }
      i++;
    }
    return DocModel(title, blocks);
  }

  // ---------------- HTML ----------------
  static const _entities = {
    'amp': '&', 'lt': '<', 'gt': '>', 'quot': '"', 'apos': "'", 'nbsp': ' ', 'copy': '\u00A9',
    'reg': '\u00AE', 'mdash': '\u2014', 'ndash': '\u2013', 'hellip': '\u2026', 'rsquo': '\u2019',
    'lsquo': '\u2018', 'ldquo': '\u201C', 'rdquo': '\u201D', 'bull': '\u2022', 'middot': '\u00B7',
    'times': '\u00D7', 'rarr': '\u2192', 'larr': '\u2190', 'deg': '\u00B0',
  };

  static String decodeEntities(String s) => s.replaceAllMapped(RegExp(r'&(#x?[0-9a-fA-F]+|[a-zA-Z]+);'), (m) {
        final e = m[1]!;
        if (e.startsWith('#x') || e.startsWith('#X')) {
          final v = int.tryParse(e.substring(2), radix: 16);
          return v == null ? m[0]! : String.fromCharCode(v);
        }
        if (e.startsWith('#')) {
          final v = int.tryParse(e.substring(1));
          return v == null ? m[0]! : String.fromCharCode(v);
        }
        return _entities[e.toLowerCase()] ?? m[0]!;
      });

  static DocModel _fromHtml(String fallbackTitle, String html) {
    final titleMatch = RegExp(r'<title[^>]*>(.*?)</title>', caseSensitive: false, dotAll: true).firstMatch(html);
    final title = titleMatch != null ? decodeEntities(titleMatch[1]!.trim()) : fallbackTitle;
    var s = html
        .replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '')
        .replaceAll(RegExp(r'<(script|style|head|noscript|svg)[^>]*>.*?</\1>', caseSensitive: false, dotAll: true), '');
    final blocks = <DocBlock>[];
    final buf = StringBuffer();
    var mode = 'p';
    var headingLevel = 1;
    var pre = 0;
    List<List<String>>? table;
    List<String>? row;
    StringBuffer? cell;

    void flush() {
      final raw = buf.toString();
      buf.clear();
      final text = pre > 0 ? raw : raw.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (text.trim().isEmpty) return;
      if (mode == 'h') {
        blocks.add(DocBlock.heading(decodeEntities(text), headingLevel));
      } else if (mode == 'li') {
        blocks.add(DocBlock.bullet(decodeEntities(text)));
      } else if (mode == 'pre') {
        blocks.add(DocBlock.code(decodeEntities(text)));
      } else {
        blocks.add(DocBlock.paragraph(decodeEntities(text)));
      }
    }

    for (final m in RegExp(r'<(/?)([a-zA-Z0-9]+)[^>]*?>|([^<]+)', dotAll: true).allMatches(s)) {
      final text = m[3];
      if (text != null) {
        (cell ?? buf).write(text);
        continue;
      }
      final closing = m[1] == '/';
      final tag = m[2]!.toLowerCase();
      if (table != null && cell != null && !{'td', 'th', 'tr', 'table'}.contains(tag)) {
        if (tag == 'br' || tag == 'p') cell.write(' ');
        continue;
      }
      switch (tag) {
        case 'h1':
        case 'h2':
        case 'h3':
        case 'h4':
        case 'h5':
        case 'h6':
          flush();
          mode = closing ? 'p' : 'h';
          headingLevel = int.parse(tag.substring(1)).clamp(1, 4);
        case 'li':
          flush();
          mode = closing ? 'p' : 'li';
        case 'pre':
          flush();
          pre += closing ? -1 : 1;
          mode = pre > 0 ? 'pre' : 'p';
        case 'br':
          if (pre > 0) {
            buf.write('\n');
          } else {
            flush();
          }
        case 'p':
        case 'div':
        case 'section':
        case 'article':
        case 'header':
        case 'footer':
        case 'ul':
        case 'ol':
        case 'blockquote':
        case 'tr':
        case 'hr':
        case 'main':
        case 'nav':
        case 'form':
          if (tag == 'tr' && table != null) {
            if (closing) {
              if (row != null && row.isNotEmpty) table.add(row);
              row = null;
            } else {
              row = [];
            }
          } else {
            flush();
            if (!closing && mode != 'li') mode = 'p';
          }
        case 'table':
          flush();
          if (closing) {
            if (table != null && table.isNotEmpty) blocks.add(DocBlock.table(table));
            table = null;
          } else {
            table = [];
          }
        case 'td':
        case 'th':
          if (table != null) {
            if (closing) {
              row ??= [];
              row.add(decodeEntities((cell ?? StringBuffer()).toString().replaceAll(RegExp(r'\s+'), ' ').trim()));
              cell = null;
            } else {
              cell = StringBuffer();
            }
          }
      }
    }
    flush();
    if (table != null && table.isNotEmpty) blocks.add(DocBlock.table(table));
    return DocModel(title, blocks);
  }

  // ---------------- Presentations ----------------
  static DocModel _fromPptx(String title, Uint8List bytes) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw ConversionException('This .pptx file is damaged or not a PowerPoint presentation.');
    }
    final presXml = readArchiveText(archive, 'ppt/presentation.xml');
    final presRels = _readRels(archive, 'ppt/_rels/presentation.xml.rels', 'ppt/');
    final slidePaths = <String>[];
    if (presXml != null) {
      for (final id in XmlDocument.parse(presXml).findAllElements('p:sldId')) {
        final path = presRels[id.getAttribute('r:id') ?? ''];
        if (path != null) slidePaths.add(path);
      }
    }
    if (slidePaths.isEmpty) {
      slidePaths.addAll(archive.files
          .map((f) => f.name)
          .where((n) => RegExp(r'^ppt/slides/slide\d+\.xml$').hasMatch(n))
          .toList()
        ..sort((a, b) => int.parse(RegExp(r'\d+').allMatches(a).last[0]!)
            .compareTo(int.parse(RegExp(r'\d+').allMatches(b).last[0]!))));
    }
    final slides = <SlideData>[];
    for (final path in slidePaths) {
      final xml = readArchiveText(archive, path);
      if (xml == null) continue;
      final dir = path.substring(0, path.lastIndexOf('/') + 1);
      final rels = _readRels(archive, '${dir}_rels/${path.split('/').last}.rels', dir);
      final doc = XmlDocument.parse(xml);
      var slideTitle = '';
      final lines = <String>[];
      for (final sp in doc.findAllElements('p:sp')) {
        final phType = sp.findAllElements('p:ph').firstOrNull?.getAttribute('type') ?? '';
        final paras = sp
            .findAllElements('a:p')
            .map((p) => p.findAllElements('a:t').map((t) => t.innerText).join())
            .where((t) => t.trim().isNotEmpty)
            .toList();
        if ((phType == 'title' || phType == 'ctrTitle') && slideTitle.isEmpty) {
          slideTitle = paras.join(' ');
        } else {
          lines.addAll(paras);
        }
      }
      for (final tbl in doc.findAllElements('a:tbl')) {
        for (final tr in tbl.findAllElements('a:tr')) {
          lines.add(tr.findAllElements('a:tc').map((tc) => tc.findAllElements('a:t').map((t) => t.innerText).join()).join('  |  '));
        }
      }
      final images = <Uint8List>[];
      for (final blip in doc.findAllElements('a:blip')) {
        final data = archive.findFile(rels[blip.getAttribute('r:embed') ?? ''] ?? '')?.content;
        if (data != null) images.add(Uint8List.fromList(data));
      }
      slides.add(SlideData(slideTitle, lines, images));
    }
    if (slides.isEmpty) throw ConversionException('No slides found in this presentation.');
    return _slidesModel(title, slides);
  }

  static DocModel _fromOdp(String title, Uint8List bytes) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw ConversionException('This .odp file is damaged or not an OpenDocument presentation.');
    }
    final xml = readArchiveText(archive, 'content.xml');
    if (xml == null) throw ConversionException('This .odp file has no content.');
    final slides = <SlideData>[];
    for (final page in XmlDocument.parse(xml).findAllElements('draw:page')) {
      var slideTitle = '';
      final lines = <String>[];
      final images = <Uint8List>[];
      for (final frame in page.findAllElements('draw:frame')) {
        final cls = frame.getAttribute('presentation:class') ?? '';
        final paras = frame.findAllElements('text:p').map(odfText).where((t) => t.trim().isNotEmpty).toList();
        if (cls == 'title' && slideTitle.isEmpty) {
          slideTitle = paras.join(' ');
        } else if (cls != 'notes') {
          lines.addAll(paras);
        }
        for (final image in frame.findElements('draw:image')) {
          final data = archive.findFile(image.getAttribute('xlink:href') ?? '')?.content;
          if (data != null) images.add(Uint8List.fromList(data));
        }
      }
      slides.add(SlideData(slideTitle, lines, images));
    }
    if (slides.isEmpty) throw ConversionException('No slides found in this presentation.');
    return _slidesModel(title, slides);
  }

  static DocModel _slidesModel(String title, List<SlideData> slides) {
    final blocks = <DocBlock>[];
    for (var i = 0; i < slides.length; i++) {
      final s = slides[i];
      blocks.add(DocBlock.heading('Slide ${i + 1}${s.title.isNotEmpty ? ': ${s.title}' : ''}', 2));
      for (final l in s.lines) {
        blocks.add(DocBlock.bullet(l));
      }
      for (final im in s.images) {
        blocks.add(DocBlock.image(im));
      }
    }
    return DocModel(title, blocks, slides: slides);
  }
}

// =====================================================================
// Writers
// =====================================================================
class DocumentWriter {
  static Future<Uint8List> write(ConversionFormat format, DocModel doc) async {
    switch (format) {
      case ConversionFormat.pdf:
        if (doc.slides != null) return _slidesPdf(doc);
        if (doc.sourceCode != null) return _codePdf(doc);
        return _pdf(doc);
      case ConversionFormat.codePdf:
        return _codePdf(doc);
      case ConversionFormat.docx:
        return _docx(doc);
      case ConversionFormat.odt:
        return _odt(doc);
      case ConversionFormat.rtf:
        return _rtf(doc);
      case ConversionFormat.txt:
        return encodeText(doc.sourceCode ?? _plainText(doc));
      case ConversionFormat.html:
        return encodeText(_html(doc));
      case ConversionFormat.md:
        return encodeText(_markdown(doc));
      default:
        throw ConversionException('${format.label} is not a document format.');
    }
  }

  /// Returns PNG/JPEG bytes the PDF writer can embed, re-encoding other formats; null if undecodable.
  static Uint8List? _embeddable(Uint8List bytes, List<String> warnings) {
    final isPng = bytes.length > 4 && bytes[0] == 0x89 && bytes[1] == 0x50;
    final isJpg = bytes.length > 3 && bytes[0] == 0xFF && bytes[1] == 0xD8;
    if (isPng || isJpg) return bytes;
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      warnings.add('An embedded image in an unsupported format (e.g. EMF/WMF) was skipped.');
      return null;
    }
    return img.encodePng(decoded);
  }

  static pw.Widget _footer(pw.Context ctx, String title) => pw.Container(
        alignment: pw.Alignment.centerRight,
        margin: const pw.EdgeInsets.only(top: 10),
        child: pw.Text(
          '${pdfSafe(title)}   ·   Page ${ctx.pageNumber} of ${ctx.pagesCount}',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
        ),
      );

  static Future<Uint8List> _pdf(DocModel doc) async {
    final pdf = pw.Document(title: doc.title);
    final widgets = <pw.Widget>[];
    for (final b in doc.blocks) {
      switch (b.type) {
        case BlockType.heading:
          final size = switch (b.level) { 1 => 20.0, 2 => 16.0, 3 => 13.5, _ => 12.0 };
          widgets.add(pw.Padding(
            padding: pw.EdgeInsets.only(top: b.level <= 2 ? 12 : 8, bottom: 6),
            child: pw.Text(pdfSafe(b.text), style: pw.TextStyle(fontSize: size, fontWeight: pw.FontWeight.bold)),
          ));
        case BlockType.paragraph:
          widgets.add(b.text.trim().isEmpty
              ? pw.SizedBox(height: 6)
              : pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 4),
                  child: pw.Text(pdfSafe(b.text), style: const pw.TextStyle(fontSize: 11, lineSpacing: 2)),
                ));
        case BlockType.bullet:
          widgets.add(pw.Bullet(text: pdfSafe(b.text), style: const pw.TextStyle(fontSize: 11)));
        case BlockType.code:
          final mono = pw.Font.courier();
          for (final line in b.text.split('\n')) {
            widgets.add(pw.Text(pdfSafe(line.isEmpty ? ' ' : line), style: pw.TextStyle(font: mono, fontSize: 9)));
          }
          widgets.add(pw.SizedBox(height: 6));
        case BlockType.table:
          final width = b.rows.fold<int>(0, (m, r) => r.length > m ? r.length : m);
          if (width == 0) break;
          final rows = [for (final r in b.rows) [for (var c = 0; c < width; c++) pdfSafe(c < r.length ? r[c] : '')]];
          widgets.add(pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 6),
            child: pw.TableHelper.fromTextArray(
              data: rows,
              headerCount: 1,
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: width > 8 ? 7 : 9),
              cellStyle: pw.TextStyle(fontSize: width > 8 ? 7 : 9),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
              cellAlignment: pw.Alignment.centerLeft,
              cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
            ),
          ));
        case BlockType.image:
          final data = _embeddable(b.image!, doc.warnings);
          if (data != null) {
            widgets.add(pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 6),
              child: pw.ConstrainedBox(
                constraints: const pw.BoxConstraints(maxHeight: 520),
                child: pw.Image(pw.MemoryImage(data), fit: pw.BoxFit.contain),
              ),
            ));
          }
        case BlockType.pageBreak:
          widgets.add(pw.NewPage());
      }
    }
    if (widgets.isEmpty) widgets.add(pw.Text('(empty document)'));
    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(48, 44, 48, 36),
      maxPages: 2000,
      footer: (ctx) => _footer(ctx, doc.title),
      build: (_) => widgets,
    ));
    return pdf.save();
  }

  static Future<Uint8List> _codePdf(DocModel doc) async {
    final code = doc.sourceCode ?? _plainText(doc);
    final lines = code.split('\n');
    final mono = pw.Font.courier();
    final digits = lines.length.toString().length;
    final pdf = pw.Document(title: doc.title);
    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(36, 40, 36, 32),
      maxPages: 2000,
      header: (ctx) => pw.Container(
        padding: const pw.EdgeInsets.only(bottom: 6),
        margin: const pw.EdgeInsets.only(bottom: 8),
        decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey400, width: 0.6))),
        child: pw.Row(children: [
          pw.Expanded(child: pw.Text(pdfSafe(doc.title), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11))),
          pw.Text('${lines.length} lines', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
        ]),
      ),
      footer: (ctx) => _footer(ctx, doc.title),
      build: (_) => [
        for (var i = 0; i < lines.length; i++)
          pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.SizedBox(
              width: 8.0 + digits * 5.5,
              child: pw.Text('${i + 1}', style: pw.TextStyle(font: mono, fontSize: 7.5, color: PdfColors.grey500)),
            ),
            pw.Expanded(
              child: pw.Text(pdfSafe(lines[i].isEmpty ? ' ' : lines[i]), style: pw.TextStyle(font: mono, fontSize: 8.5)),
            ),
          ]),
      ],
    ));
    return pdf.save();
  }

  static Future<Uint8List> _slidesPdf(DocModel doc) async {
    final pdf = pw.Document(title: doc.title);
    final slides = doc.slides!;
    for (var i = 0; i < slides.length; i++) {
      final s = slides[i];
      final images = [for (final im in s.images.take(3)) _embeddable(im, doc.warnings)].whereType<Uint8List>().toList();
      pdf.addPage(pw.Page(
        pageFormat: const PdfPageFormat(960, 540, marginAll: 40),
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            if (s.title.isNotEmpty)
              pw.Text(pdfSafe(s.title), style: pw.TextStyle(fontSize: 28, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 14),
            for (final l in s.lines.take(14)) pw.Bullet(text: pdfSafe(l), style: const pw.TextStyle(fontSize: 15)),
            if (images.isNotEmpty) ...[
              pw.SizedBox(height: 10),
              pw.Expanded(
                child: pw.Row(children: [
                  for (final im in images)
                    pw.Expanded(
                      child: pw.Padding(
                        padding: const pw.EdgeInsets.all(4),
                        child: pw.Image(pw.MemoryImage(im), fit: pw.BoxFit.contain),
                      ),
                    ),
                ]),
              ),
            ] else
              pw.Spacer(),
            pw.Align(
              alignment: pw.Alignment.bottomRight,
              child: pw.Text('${i + 1} / ${slides.length}', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
            ),
          ],
        ),
      ));
      if (s.lines.length > 14) doc.warnings.add('Slide ${i + 1}: text beyond 14 lines was trimmed in the PDF.');
    }
    return pdf.save();
  }

  // ---------------- DOCX ----------------
  static Uint8List _docx(DocModel doc) {
    final body = StringBuffer();
    final media = <String, Uint8List>{};
    String run(String text, {bool bold = false, int? size, bool mono = false}) {
      final props = StringBuffer();
      if (mono) props.write('<w:rFonts w:ascii="Consolas" w:hAnsi="Consolas" w:cs="Consolas"/>');
      if (bold) props.write('<w:b/>');
      if (size != null) props.write('<w:sz w:val="$size"/>');
      final parts = xmlSafe(text).split('\n');
      final sb = StringBuffer('<w:r>${props.isEmpty ? '' : '<w:rPr>$props</w:rPr>'}');
      for (var i = 0; i < parts.length; i++) {
        if (i > 0) sb.write('<w:br/>');
        final segs = parts[i].split('\t');
        for (var j = 0; j < segs.length; j++) {
          if (j > 0) sb.write('<w:tab/>');
          sb.write('<w:t xml:space="preserve">${escapeXml(segs[j])}</w:t>');
        }
      }
      sb.write('</w:r>');
      return sb.toString();
    }

    body.write('<w:p><w:pPr><w:pStyle w:val="Title"/></w:pPr>${run(doc.title, bold: true, size: 36)}</w:p>');
    final blocks = doc.sourceCode != null ? [DocBlock.code(doc.sourceCode!)] : doc.blocks;
    for (final b in blocks) {
      switch (b.type) {
        case BlockType.heading:
          final size = switch (b.level) { 1 => 32, 2 => 28, 3 => 24, _ => 22 };
          body.write('<w:p><w:pPr><w:pStyle w:val="Heading${b.level}"/><w:spacing w:before="240" w:after="120"/></w:pPr>'
              '${run(b.text, bold: true, size: size)}</w:p>');
        case BlockType.paragraph:
          body.write('<w:p>${run(b.text)}</w:p>');
        case BlockType.bullet:
          body.write('<w:p><w:pPr><w:ind w:left="720" w:hanging="360"/></w:pPr>${run('\u2022\t${b.text}')}</w:p>');
        case BlockType.code:
          for (final line in b.text.split('\n')) {
            body.write('<w:p><w:pPr><w:spacing w:before="0" w:after="0"/></w:pPr>${run(line, mono: true, size: 18)}</w:p>');
          }
        case BlockType.table:
          body.write('<w:tbl><w:tblPr><w:tblStyle w:val="TableGrid"/><w:tblW w:w="0" w:type="auto"/><w:tblBorders>'
              '<w:top w:val="single" w:sz="4"/><w:left w:val="single" w:sz="4"/><w:bottom w:val="single" w:sz="4"/>'
              '<w:right w:val="single" w:sz="4"/><w:insideH w:val="single" w:sz="4"/><w:insideV w:val="single" w:sz="4"/>'
              '</w:tblBorders></w:tblPr>');
          for (var r = 0; r < b.rows.length; r++) {
            body.write('<w:tr>');
            for (final c in b.rows[r]) {
              body.write('<w:tc><w:p>${run(c, bold: r == 0)}</w:p></w:tc>');
            }
            body.write('</w:tr>');
          }
          body.write('</w:tbl><w:p/>');
        case BlockType.image:
          final data = _embeddable(b.image!, doc.warnings);
          final decoded = data == null ? null : img.decodeImage(data);
          if (data == null || decoded == null) break;
          final idx = media.length + 1;
          final ext = data[0] == 0xFF ? 'jpeg' : 'png';
          media['image$idx.$ext'] = data;
          // Fit inside ~6 inches wide; EMU = 914400 per inch, images assumed 96 dpi.
          var w = decoded.width * 9525.0;
          var h = decoded.height * 9525.0;
          const maxW = 5486400.0;
          if (w > maxW) {
            h = h * maxW / w;
            w = maxW;
          }
          body.write('<w:p><w:r><w:drawing><wp:inline><wp:extent cx="${w.round()}" cy="${h.round()}"/>'
              '<wp:docPr id="$idx" name="Image $idx"/><a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">'
              '<pic:pic><pic:nvPicPr><pic:cNvPr id="$idx" name="image$idx.$ext"/><pic:cNvPicPr/></pic:nvPicPr>'
              '<pic:blipFill><a:blip r:embed="rIdImg$idx"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>'
              '<pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="${w.round()}" cy="${h.round()}"/></a:xfrm>'
              '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr></pic:pic></a:graphicData></a:graphic>'
              '</wp:inline></w:drawing></w:r></w:p>');
        case BlockType.pageBreak:
          body.write('<w:p><w:r><w:br w:type="page"/></w:r></w:p>');
      }
    }

    final archive = Archive();
    addText(archive, '[Content_Types].xml', '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Default Extension="png" ContentType="image/png"/>
  <Default Extension="jpeg" ContentType="image/jpeg"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
</Types>''');
    addText(archive, '_rels/.rels', '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>''');
    final rels = StringBuffer('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">');
    var n = 0;
    media.forEach((name, data) {
      n++;
      rels.write('<Relationship Id="rIdImg$n" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/$name"/>');
      archive.addFile(ArchiveFile.bytes('word/media/$name', data));
    });
    rels.write('</Relationships>');
    addText(archive, 'word/_rels/document.xml.rels', rels.toString());
    addText(archive, 'word/document.xml', '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
        '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
        'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" '
        'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
        'xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">'
        '<w:body>$body<w:sectPr><w:pgSz w:w="11906" w:h="16838"/>'
        '<w:pgMar w:top="1134" w:right="1134" w:bottom="1134" w:left="1134" w:header="708" w:footer="708" w:gutter="0"/>'
        '</w:sectPr></w:body></w:document>');
    return zipArchive(archive);
  }

  // ---------------- ODT ----------------
  static Uint8List _odt(DocModel doc) {
    String esc(String s) => escapeXml(xmlSafe(s))
        .replaceAll('\t', '<text:tab/>')
        .replaceAll('\n', '<text:line-break/>')
        .replaceAllMapped(RegExp(r'  +'), (m) => ' <text:s text:c="${m[0]!.length - 1}"/>');
    final body = StringBuffer('<text:h text:outline-level="1" text:style-name="H1">${esc(doc.title)}</text:h>');
    final blocks = doc.sourceCode != null ? [DocBlock.code(doc.sourceCode!)] : doc.blocks;
    for (final b in blocks) {
      switch (b.type) {
        case BlockType.heading:
          body.write('<text:h text:outline-level="${b.level}" text:style-name="H${b.level.clamp(1, 3)}">${esc(b.text)}</text:h>');
        case BlockType.paragraph:
          body.write('<text:p>${esc(b.text)}</text:p>');
        case BlockType.bullet:
          body.write('<text:p>\u2022 ${esc(b.text)}</text:p>');
        case BlockType.code:
          for (final line in b.text.split('\n')) {
            body.write('<text:p text:style-name="Code">${esc(line)}</text:p>');
          }
        case BlockType.table:
          final width = b.rows.fold<int>(0, (m, r) => r.length > m ? r.length : m);
          body.write('<table:table><table:table-column table:number-columns-repeated="${width.clamp(1, 1000)}"/>');
          for (final r in b.rows) {
            body.write('<table:table-row>');
            for (var c = 0; c < width; c++) {
              body.write('<table:table-cell office:value-type="string"><text:p>${esc(c < r.length ? r[c] : '')}</text:p></table:table-cell>');
            }
            body.write('</table:table-row>');
          }
          body.write('</table:table>');
        case BlockType.image:
          doc.warnings.add('Images are not embedded in ODT output; use PDF or DOCX to keep them.');
        case BlockType.pageBreak:
          body.write('<text:p text:style-name="Break"/>');
      }
    }
    final content = '''<?xml version="1.0" encoding="UTF-8"?>
<office:document-content xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0"
 xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0" xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0"
 xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0" xmlns:fo="urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0"
 office:version="1.2">
<office:automatic-styles>
 <style:style style:name="H1" style:family="paragraph"><style:text-properties fo:font-size="20pt" fo:font-weight="bold"/></style:style>
 <style:style style:name="H2" style:family="paragraph"><style:text-properties fo:font-size="16pt" fo:font-weight="bold"/></style:style>
 <style:style style:name="H3" style:family="paragraph"><style:text-properties fo:font-size="13pt" fo:font-weight="bold"/></style:style>
 <style:style style:name="Code" style:family="paragraph"><style:text-properties style:font-name="Courier New" fo:font-family="'Courier New'" fo:font-size="9pt"/></style:style>
 <style:style style:name="Break" style:family="paragraph"><style:paragraph-properties fo:break-after="page"/></style:style>
</office:automatic-styles>
<office:body><office:text>$body</office:text></office:body>
</office:document-content>''';
    return packOpenDocument('application/vnd.oasis.opendocument.text', content);
  }

  // ---------------- RTF ----------------
  static Uint8List _rtf(DocModel doc) {
    String esc(String s) {
      final sb = StringBuffer();
      for (final r in s.runes) {
        if (r == 0x5C || r == 0x7B || r == 0x7D) {
          sb.write('\\${String.fromCharCode(r)}');
        } else if (r == 0x09) {
          sb.write('\\tab ');
        } else if (r == 0x0A) {
          sb.write('\\line ');
        } else if (r < 0x80) {
          sb.writeCharCode(r);
        } else if (r <= 0xFFFF) {
          sb.write('\\u${r > 32767 ? r - 65536 : r}?');
        } else {
          sb.write('?');
        }
      }
      return sb.toString();
    }

    final sb = StringBuffer(r'{\rtf1\ansi\ansicpg1252\deff0{\fonttbl{\f0\fswiss Calibri;}{\f1\fmodern Courier New;}}\fs22 ');
    sb.write('{\\b\\fs36 ${esc(doc.title)}\\par}');
    final blocks = doc.sourceCode != null ? [DocBlock.code(doc.sourceCode!)] : doc.blocks;
    for (final b in blocks) {
      switch (b.type) {
        case BlockType.heading:
          final size = switch (b.level) { 1 => 32, 2 => 28, 3 => 24, _ => 22 };
          sb.write('{\\b\\fs$size ${esc(b.text)}\\par}');
        case BlockType.paragraph:
          sb.write('${esc(b.text)}\\par\n');
        case BlockType.bullet:
          sb.write('{\\li360\\fi-240 \\bullet  ${esc(b.text)}\\par}\n');
        case BlockType.code:
          for (final line in b.text.split('\n')) {
            sb.write('{\\f1\\fs18 ${esc(line)}\\par}\n');
          }
        case BlockType.table:
          for (final r in b.rows) {
            sb.write('${r.map(esc).join('\\tab ')}\\par\n');
          }
        case BlockType.image:
          doc.warnings.add('Images are not embedded in RTF output; use PDF or DOCX to keep them.');
        case BlockType.pageBreak:
          sb.write('\\page\n');
      }
    }
    sb.write('}');
    return Uint8List.fromList(latin1.encode(sb.toString()));
  }

  // ---------------- Text formats ----------------
  static String _plainText(DocModel doc) {
    final sb = StringBuffer();
    for (final b in doc.blocks) {
      switch (b.type) {
        case BlockType.heading:
          if (sb.isNotEmpty) sb.writeln();
          sb.writeln(b.text);
          sb.writeln((b.level <= 1 ? '=' : '-') * b.text.length.clamp(3, 80));
        case BlockType.paragraph:
          sb.writeln(b.text);
        case BlockType.bullet:
          sb.writeln('  \u2022 ${b.text}');
        case BlockType.code:
          sb.writeln(b.text);
        case BlockType.table:
          for (final r in b.rows) {
            sb.writeln(r.join('\t'));
          }
          sb.writeln();
        case BlockType.image:
          sb.writeln('[image]');
        case BlockType.pageBreak:
          sb.writeln('\f');
      }
    }
    return sb.toString();
  }

  static String _html(DocModel doc) {
    String esc(String s) => const HtmlEscape(HtmlEscapeMode.element).convert(s);
    final sb = StringBuffer('<!DOCTYPE html>\n<html lang="en"><head><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width, initial-scale=1">'
        '<title>${esc(doc.title)}</title><style>'
        'body{font-family:system-ui,Segoe UI,Roboto,sans-serif;max-width:860px;margin:2rem auto;padding:0 1rem;line-height:1.6;color:#1a1a1a}'
        'pre{background:#f4f5f0;padding:12px;border-radius:8px;overflow:auto;font-size:13px}'
        'table{border-collapse:collapse;margin:1rem 0}td,th{border:1px solid #ccc;padding:4px 8px;text-align:left}'
        'th{background:#f0f0f0}img{max-width:100%}'
        '</style></head><body>\n');
    if (doc.sourceCode != null) {
      sb.write('<h1>${esc(doc.title)}</h1>\n<pre><code>${esc(doc.sourceCode!)}</code></pre>\n</body></html>\n');
      return sb.toString();
    }
    var inList = false;
    for (final b in doc.blocks) {
      if (b.type != BlockType.bullet && inList) {
        sb.write('</ul>\n');
        inList = false;
      }
      switch (b.type) {
        case BlockType.heading:
          sb.write('<h${b.level}>${esc(b.text)}</h${b.level}>\n');
        case BlockType.paragraph:
          if (b.text.trim().isNotEmpty) sb.write('<p>${esc(b.text)}</p>\n');
        case BlockType.bullet:
          if (!inList) sb.write('<ul>\n');
          inList = true;
          sb.write('<li>${esc(b.text)}</li>\n');
        case BlockType.code:
          sb.write('<pre><code>${esc(b.text)}</code></pre>\n');
        case BlockType.table:
          sb.write('<table>\n');
          for (var r = 0; r < b.rows.length; r++) {
            final tag = r == 0 ? 'th' : 'td';
            sb.write('<tr>${b.rows[r].map((c) => '<$tag>${esc(c)}</$tag>').join()}</tr>\n');
          }
          sb.write('</table>\n');
        case BlockType.image:
          final mime = b.image![0] == 0xFF ? 'image/jpeg' : 'image/png';
          sb.write('<p><img alt="" src="data:$mime;base64,${base64Encode(b.image!)}"></p>\n');
        case BlockType.pageBreak:
          sb.write('<hr>\n');
      }
    }
    if (inList) sb.write('</ul>\n');
    sb.write('</body></html>\n');
    return sb.toString();
  }

  static String _markdown(DocModel doc) {
    if (doc.sourceCode != null) return '# ${doc.title}\n\n```\n${doc.sourceCode}\n```\n';
    final sb = StringBuffer('# ${doc.title}\n\n');
    for (final b in doc.blocks) {
      switch (b.type) {
        case BlockType.heading:
          sb.write('\n${'#' * (b.level + 1).clamp(2, 6)} ${b.text}\n\n');
        case BlockType.paragraph:
          sb.write(b.text.trim().isEmpty ? '\n' : '${b.text}\n\n');
        case BlockType.bullet:
          sb.write('- ${b.text}\n');
        case BlockType.code:
          sb.write('\n```\n${b.text}\n```\n\n');
        case BlockType.table:
          if (b.rows.isEmpty) break;
          final width = b.rows.fold<int>(0, (m, r) => r.length > m ? r.length : m);
          String row(List<String> r) =>
              '| ${[for (var c = 0; c < width; c++) (c < r.length ? r[c] : '').replaceAll('|', '\\|').replaceAll('\n', ' ')].join(' | ')} |';
          sb.write('\n${row(b.rows.first)}\n|${List.filled(width, ' --- ').join('|')}|\n');
          for (final r in b.rows.skip(1)) {
            sb.write('${row(r)}\n');
          }
          sb.write('\n');
        case BlockType.image:
          sb.write('*(image)*\n\n');
        case BlockType.pageBreak:
          sb.write('\n---\n\n');
      }
    }
    return sb.toString();
  }
}
