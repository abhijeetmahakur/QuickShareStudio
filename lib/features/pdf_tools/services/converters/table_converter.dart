import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:xml/xml.dart';
import '../conversion_formats.dart';
import 'converter_utils.dart';
import 'document_converter.dart';

class SheetData {
  final String name;
  final List<List<String>> rows;
  SheetData(this.name, this.rows);

  int get width => rows.fold<int>(0, (m, r) => r.length > m ? r.length : m);
}

class TableModel {
  final String title;
  final List<SheetData> sheets;
  final List<String> warnings = [];
  TableModel(this.title, this.sheets);

  int get rowCount => sheets.fold<int>(0, (n, s) => n + s.rows.length);
}

// =====================================================================
// Readers
// =====================================================================
class TableReader {
  static const _maxRepeat = 2000;

  static TableModel read(SourceKind kind, String fileName, Uint8List bytes) {
    final title = baseNameOf(fileName);
    final TableModel model;
    switch (kind) {
      case SourceKind.xlsx:
        model = _xlsx(title, bytes);
      case SourceKind.ods:
        model = _ods(title, bytes);
      case SourceKind.csv:
        model = TableModel(title, [SheetData(title, parseDelimited(decodeText(bytes)))]);
      case SourceKind.tsv:
        model = TableModel(title, [SheetData(title, parseDelimited(decodeText(bytes), delimiter: '\t'))]);
      case SourceKind.json:
        model = _json(title, decodeText(bytes));
      case SourceKind.pdf:
        model = _pdf(title, bytes);
      default:
        throw ConversionException('${kind.label} files cannot be read as a table.');
    }
    for (final s in model.sheets) {
      _trim(s.rows);
    }
    model.sheets.removeWhere((s) => s.rows.isEmpty && model.sheets.length > 1);
    return model;
  }

  static void _trim(List<List<String>> rows) {
    for (final r in rows) {
      while (r.isNotEmpty && r.last.trim().isEmpty) {
        r.removeLast();
      }
    }
    while (rows.isNotEmpty && rows.last.isEmpty) {
      rows.removeLast();
    }
  }

  /// RFC 4180 parser with quoted fields; the delimiter is auto-detected when not given.
  static List<List<String>> parseDelimited(String text, {String? delimiter}) {
    final firstLine = text.split('\n').first;
    final d = delimiter ??
        ([',', ';', '\t', '|']..sort((a, b) => b.allMatches(firstLine).length.compareTo(a.allMatches(firstLine).length))).first;
    final rows = <List<String>>[];
    var row = <String>[];
    final field = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < text.length; i++) {
      final c = text[i];
      if (inQuotes) {
        if (c == '"') {
          if (i + 1 < text.length && text[i + 1] == '"') {
            field.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          field.write(c);
        }
      } else if (c == '"' && field.isEmpty) {
        inQuotes = true;
      } else if (c == d) {
        row.add(field.toString());
        field.clear();
      } else if (c == '\n') {
        row.add(field.toString());
        field.clear();
        rows.add(row);
        row = [];
      } else if (c != '\r') {
        field.write(c);
      }
    }
    if (field.isNotEmpty || row.isNotEmpty) {
      row.add(field.toString());
      rows.add(row);
    }
    return rows;
  }

  static TableModel _xlsx(String title, Uint8List bytes) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw ConversionException('This .xlsx file is damaged or not an Excel workbook.');
    }
    final shared = <String>[];
    final sst = readArchiveText(archive, 'xl/sharedStrings.xml');
    if (sst != null) {
      for (final si in XmlDocument.parse(sst).findAllElements('si')) {
        // Rich text runs are joined; phonetic hints (<rPh>) are skipped.
        shared.add(si.findAllElements('t').where((t) => t.parentElement?.name.local != 'rPh').map((t) => t.innerText).join());
      }
    }
    final rels = <String, String>{};
    final relsXml = readArchiveText(archive, 'xl/_rels/workbook.xml.rels');
    if (relsXml != null) {
      for (final r in XmlDocument.parse(relsXml).findAllElements('Relationship')) {
        final target = r.getAttribute('Target') ?? '';
        rels[r.getAttribute('Id') ?? ''] = target.startsWith('/') ? target.substring(1) : 'xl/$target';
      }
    }
    final sheets = <SheetData>[];
    final wb = readArchiveText(archive, 'xl/workbook.xml');
    final entries = <MapEntry<String, String>>[];
    if (wb != null) {
      for (final s in XmlDocument.parse(wb).findAllElements('sheet')) {
        final path = rels[s.getAttribute('r:id') ?? ''];
        if (path != null) entries.add(MapEntry(s.getAttribute('name') ?? 'Sheet${entries.length + 1}', path));
      }
    }
    if (entries.isEmpty && archive.findFile('xl/worksheets/sheet1.xml') != null) {
      entries.add(const MapEntry('Sheet1', 'xl/worksheets/sheet1.xml'));
    }
    for (final e in entries) {
      final xml = readArchiveText(archive, e.value);
      if (xml == null) continue;
      final rows = <List<String>>[];
      var nextRow = 0;
      for (final r in XmlDocument.parse(xml).findAllElements('row')) {
        final rowIndex = (int.tryParse(r.getAttribute('r') ?? '') ?? (nextRow + 1)) - 1;
        if (rowIndex - rows.length > _maxRepeat) break;
        while (rows.length < rowIndex) {
          rows.add([]);
        }
        final cells = <String>[];
        var nextCol = 0;
        for (final c in r.findElements('c')) {
          final ref = c.getAttribute('r');
          final col = ref != null ? columnIndexFromRef(ref) : nextCol;
          if (col < 0 || col - cells.length > _maxRepeat) continue;
          while (cells.length < col) {
            cells.add('');
          }
          final type = c.getAttribute('t');
          final v = c.findElements('v').firstOrNull?.innerText ?? '';
          String value;
          switch (type) {
            case 's':
              value = shared.elementAtOrNull(int.tryParse(v) ?? -1) ?? '';
            case 'inlineStr':
              value = c.findAllElements('t').map((t) => t.innerText).join();
            case 'b':
              value = v == '1' ? 'TRUE' : 'FALSE';
            default:
              value = v;
          }
          cells.add(value);
          nextCol = col + 1;
        }
        rows.add(cells);
        nextRow = rowIndex + 1;
      }
      sheets.add(SheetData(e.key, rows));
    }
    if (sheets.isEmpty) throw ConversionException('No worksheets found in this workbook.');
    return TableModel(title, sheets);
  }

  static TableModel _ods(String title, Uint8List bytes) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw ConversionException('This .ods file is damaged or not an OpenDocument spreadsheet.');
    }
    final xml = readArchiveText(archive, 'content.xml');
    if (xml == null) throw ConversionException('This .ods file has no content.');
    final sheets = <SheetData>[];
    for (final table in XmlDocument.parse(xml).findAllElements('table:table')) {
      final rows = <List<String>>[];
      for (final row in table.findAllElements('table:table-row')) {
        final cells = <String>[];
        for (final cell in row.childElements.where((e) => e.name.local.endsWith('table-cell'))) {
          final repeat = int.tryParse(cell.getAttribute('table:number-columns-repeated') ?? '') ?? 1;
          final type = cell.getAttribute('office:value-type');
          var value = cell.findElements('text:p').map(DocumentReader.odfText).join('\n');
          if (value.isEmpty && type == 'float') value = cell.getAttribute('office:value') ?? '';
          if (value.isEmpty && type == 'date') value = cell.getAttribute('office:date-value') ?? '';
          final count = value.isEmpty ? repeat.clamp(1, 1) : repeat.clamp(1, _maxRepeat);
          for (var k = 0; k < count; k++) {
            cells.add(value);
          }
        }
        final repeatRows = int.tryParse(row.getAttribute('table:number-rows-repeated') ?? '') ?? 1;
        final isEmpty = cells.every((c) => c.isEmpty);
        for (var k = 0; k < (isEmpty ? 1 : repeatRows.clamp(1, _maxRepeat)); k++) {
          rows.add(List.of(cells));
        }
      }
      sheets.add(SheetData(table.getAttribute('table:name') ?? 'Sheet${sheets.length + 1}', rows));
    }
    if (sheets.isEmpty) throw ConversionException('No sheets found in this spreadsheet.');
    return TableModel(title, sheets);
  }

  static String _cell(dynamic v) {
    if (v == null) return '';
    if (v is String) return v;
    if (v is num || v is bool) return v.toString();
    return jsonEncode(v);
  }

  static List<List<String>> _jsonRows(List<dynamic> list) {
    if (list.isEmpty) return [];
    if (list.every((e) => e is Map)) {
      final keys = <String>[];
      for (final m in list.cast<Map>()) {
        for (final k in m.keys) {
          if (!keys.contains('$k')) keys.add('$k');
        }
      }
      return [keys, for (final m in list.cast<Map>()) [for (final k in keys) _cell(m[k])]];
    }
    if (list.every((e) => e is List)) {
      return [for (final r in list.cast<List>()) [for (final c in r) _cell(c)]];
    }
    return [['value'], for (final e in list) [_cell(e)]];
  }

  static TableModel _json(String title, String text) {
    final dynamic data;
    try {
      data = jsonDecode(text);
    } catch (e) {
      throw ConversionException('Invalid JSON: ${e.toString().split('\n').first}');
    }
    if (data is List) return TableModel(title, [SheetData(title, _jsonRows(data))]);
    if (data is Map) {
      final listValues = data.entries.where((e) => e.value is List).toList();
      if (listValues.isNotEmpty && listValues.length == data.length) {
        return TableModel(title, [for (final e in listValues) SheetData('${e.key}', _jsonRows(e.value as List))]);
      }
      return TableModel(title, [
        SheetData(title, [
          ['key', 'value'],
          for (final e in data.entries) ['${e.key}', _cell(e.value)],
        ]),
      ]);
    }
    return TableModel(title, [SheetData(title, [['value'], [_cell(data)]])]);
  }

  static TableModel _pdf(String title, Uint8List bytes) {
    final lines = DocumentReader.extractPdfLines(bytes);
    final rows = [
      for (final l in lines) l.split(RegExp(r'\s{2,}|\t')).map((t) => t.trim()).where((t) => t.isNotEmpty).toList(),
    ].where((r) => r.isNotEmpty).toList();
    final model = TableModel(title, [SheetData(title, rows)]);
    if (rows.isEmpty) {
      model.warnings.add('No selectable text found. Scanned or image-only PDFs need OCR (see the OCR tab).');
    } else if (rows.every((r) => r.length == 1)) {
      model.warnings.add('No column structure detected in the PDF; each line was placed in column A.');
    }
    return model;
  }
}

// =====================================================================
// Writers
// =====================================================================
class TableWriter {
  static final _numeric = RegExp(r'^-?(\d+\.?\d*|\.\d+)([eE][-+]?\d+)?$');

  static Future<Uint8List> write(ConversionFormat format, TableModel table) async {
    switch (format) {
      case ConversionFormat.xlsx:
        return _xlsx(table);
      case ConversionFormat.ods:
        return _ods(table);
      case ConversionFormat.csv:
        if (table.sheets.length > 1) {
          table.warnings.add('CSV holds one sheet: only "${table.sheets.first.name}" was exported.');
        }
        return encodeText(_csv(table.sheets.first));
      case ConversionFormat.json:
        return encodeText(_json(table));
      case ConversionFormat.html:
        return encodeText(_html(table));
      case ConversionFormat.pdf:
        return _pdf(table);
      case ConversionFormat.txt:
        return encodeText(table.sheets.map((s) => s.rows.map((r) => r.join('\t')).join('\n')).join('\n\n'));
      case ConversionFormat.docx:
      case ConversionFormat.odt:
      case ConversionFormat.rtf:
      case ConversionFormat.md:
        final blocks = <DocBlock>[];
        for (final s in table.sheets) {
          if (table.sheets.length > 1) blocks.add(DocBlock.heading(s.name, 2));
          blocks.add(DocBlock.table(s.rows));
        }
        return DocumentWriter.write(format, DocModel(table.title, blocks, warnings: table.warnings));
      default:
        throw ConversionException('${format.label} is not a table format.');
    }
  }

  static String _csv(SheetData sheet) {
    String q(String v) => v.contains(RegExp(r'[",\n\r]')) ? '"${v.replaceAll('"', '""')}"' : v;
    // Pad every row to the full width so columns stay aligned in strict CSV readers.
    final width = sheet.width;
    return '${sheet.rows.map((r) => [for (var c = 0; c < width; c++) q(c < r.length ? r[c] : '')].join(',')).join('\r\n')}\r\n';
  }

  static String _json(TableModel t) {
    List<Map<String, dynamic>> objects(List<List<String>> rows) {
      if (rows.isEmpty) return [];
      final header = [for (var i = 0; i < rows.first.length; i++) rows.first[i].isEmpty ? 'column${i + 1}' : rows.first[i]];
      return [
        for (final r in rows.skip(1))
          {
            for (var i = 0; i < header.length; i++)
              header[i]: i < r.length ? (_numeric.hasMatch(r[i]) ? num.parse(r[i]) : r[i]) : null,
          },
      ];
    }

    const enc = JsonEncoder.withIndent('  ');
    if (t.sheets.length == 1) return enc.convert(objects(t.sheets.first.rows));
    return enc.convert({for (final s in t.sheets) s.name: objects(s.rows)});
  }

  static String _html(TableModel t) {
    String esc(String s) => const HtmlEscape(HtmlEscapeMode.element).convert(s);
    final sb = StringBuffer('<!DOCTYPE html>\n<html><head><meta charset="utf-8"><title>${esc(t.title)}</title>'
        '<style>body{font-family:system-ui,Segoe UI,sans-serif;margin:2rem}table{border-collapse:collapse;margin-bottom:2rem}'
        'td,th{border:1px solid #ccc;padding:4px 8px;text-align:left}th{background:#f0f0f0}</style></head><body>\n');
    for (final s in t.sheets) {
      sb.write('<h2>${esc(s.name)}</h2>\n<table>\n');
      for (var r = 0; r < s.rows.length; r++) {
        final tag = r == 0 ? 'th' : 'td';
        sb.write('<tr>${[for (var c = 0; c < s.width; c++) '<$tag>${esc(c < s.rows[r].length ? s.rows[r][c] : '')}</$tag>'].join()}</tr>\n');
      }
      sb.write('</table>\n');
    }
    sb.write('</body></html>\n');
    return sb.toString();
  }

  static Future<Uint8List> _pdf(TableModel t) async {
    final pdf = pw.Document(title: t.title);
    for (final s in t.sheets) {
      final width = s.width;
      if (width == 0) continue;
      final fontSize = width > 14 ? 6.0 : width > 9 ? 7.0 : 9.0;
      final rows = [for (final r in s.rows) [for (var c = 0; c < width; c++) pdfSafe(c < r.length ? r[c] : '')]];
      pdf.addPage(pw.MultiPage(
        pageFormat: width > 5 ? PdfPageFormat.a4.landscape : PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        maxPages: 2000,
        header: (ctx) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 8),
          child: pw.Text(pdfSafe(t.sheets.length > 1 ? '${t.title} - ${s.name}' : t.title),
              style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
        ),
        footer: (ctx) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
        ),
        build: (_) => [
          pw.TableHelper.fromTextArray(
            data: rows,
            headerCount: 1,
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: fontSize),
            cellStyle: pw.TextStyle(fontSize: fontSize),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
            cellAlignment: pw.Alignment.centerLeft,
            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          ),
        ],
      ));
    }
    if (t.sheets.every((s) => s.width == 0)) {
      pdf.addPage(pw.Page(build: (_) => pw.Text('(empty table)')));
    }
    return pdf.save();
  }

  static Uint8List _xlsx(TableModel t) {
    final archive = Archive();
    final sheetNames = <String>[];
    for (final s in t.sheets) {
      var name = s.name.replaceAll(RegExp(r'[\\/?*\[\]:]'), '_');
      if (name.isEmpty) name = 'Sheet${sheetNames.length + 1}';
      if (name.length > 31) name = name.substring(0, 31);
      while (sheetNames.contains(name)) {
        name = '${name.substring(0, name.length.clamp(0, 28))}_${sheetNames.length}';
      }
      sheetNames.add(name);
    }
    addText(archive, '[Content_Types].xml', '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
${[for (var i = 0; i < t.sheets.length; i++) '  <Override PartName="/xl/worksheets/sheet${i + 1}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'].join('\n')}
</Types>''');
    addText(archive, '_rels/.rels', '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>''');
    addText(archive, 'xl/workbook.xml', '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <sheets>
${[for (var i = 0; i < sheetNames.length; i++) '    <sheet name="${escapeXml(sheetNames[i])}" sheetId="${i + 1}" r:id="rId${i + 1}"/>'].join('\n')}
  </sheets>
</workbook>''');
    addText(archive, 'xl/_rels/workbook.xml.rels', '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
${[for (var i = 0; i < t.sheets.length; i++) '  <Relationship Id="rId${i + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet${i + 1}.xml"/>'].join('\n')}
</Relationships>''');
    for (var i = 0; i < t.sheets.length; i++) {
      final sb = StringBuffer('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
          '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>');
      final rows = t.sheets[i].rows;
      for (var r = 0; r < rows.length; r++) {
        sb.write('<row r="${r + 1}">');
        for (var c = 0; c < rows[r].length; c++) {
          final v = rows[r][c];
          if (v.isEmpty) continue;
          final ref = '${columnName(c)}${r + 1}';
          if (_numeric.hasMatch(v) && v.length < 16 && !(v.length > 1 && v.startsWith('0') && !v.startsWith('0.'))) {
            sb.write('<c r="$ref"><v>$v</v></c>');
          } else {
            sb.write('<c r="$ref" t="inlineStr"><is><t xml:space="preserve">${escapeXml(xmlSafe(v))}</t></is></c>');
          }
        }
        sb.write('</row>');
      }
      sb.write('</sheetData></worksheet>');
      addText(archive, 'xl/worksheets/sheet${i + 1}.xml', sb.toString());
    }
    return zipArchive(archive);
  }

  static Uint8List _ods(TableModel t) {
    final body = StringBuffer();
    for (final s in t.sheets) {
      body.write('<table:table table:name="${escapeXml(s.name)}">');
      body.write('<table:table-column table:number-columns-repeated="${s.width.clamp(1, 16384)}"/>');
      for (final r in s.rows) {
        body.write('<table:table-row>');
        for (var c = 0; c < s.width; c++) {
          final v = c < r.length ? r[c] : '';
          if (v.isEmpty) {
            body.write('<table:table-cell/>');
          } else if (_numeric.hasMatch(v) && v.length < 16) {
            body.write('<table:table-cell office:value-type="float" office:value="$v"><text:p>$v</text:p></table:table-cell>');
          } else {
            body.write('<table:table-cell office:value-type="string"><text:p>${escapeXml(xmlSafe(v))}</text:p></table:table-cell>');
          }
        }
        body.write('</table:table-row>');
      }
      body.write('</table:table>');
    }
    final content = '''<?xml version="1.0" encoding="UTF-8"?>
<office:document-content xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0"
 xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0" xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0"
 office:version="1.2"><office:body><office:spreadsheet>$body</office:spreadsheet></office:body></office:document-content>''';
    return packOpenDocument('application/vnd.oasis.opendocument.spreadsheet', content);
  }
}
