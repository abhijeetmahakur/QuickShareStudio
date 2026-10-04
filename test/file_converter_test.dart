import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:quickshare/features/pdf_tools/services/file_converter_service.dart';

Uint8List _text(String s) => Uint8List.fromList(utf8.encode(s));

Future<ConversionResult> _convert(String name, Uint8List bytes, ConversionFormat to) =>
    FileConverterService.convert(format: to, inputFileName: name, inputBytes: bytes);

Future<String> _asText(String name, Uint8List bytes) async =>
    utf8.decode((await _convert(name, bytes, ConversionFormat.txt)).outputBytes);

Uint8List _zip(Map<String, String> files) {
  final a = Archive();
  files.forEach((k, v) => a.addFile(ArchiveFile.bytes(k, utf8.encode(v))));
  return ZipEncoder().encodeBytes(a);
}

void main() {
  group('Format detection and targets', () {
    test('every input gets a sensible default and a ZIP fallback', () {
      expect(ConversionFormats.targetsFor('Lab1.java').first, ConversionFormat.codePdf);
      expect(ConversionFormats.targetsFor('report.docx').first, ConversionFormat.pdf);
      expect(ConversionFormats.targetsFor('report.pdf').first, ConversionFormat.docx);
      expect(ConversionFormats.targetsFor('photo.PNG'), isNot(contains(ConversionFormat.png)));
      expect(ConversionFormats.targetsFor('photo.jpeg'), isNot(contains(ConversionFormat.jpg)));
      expect(ConversionFormats.targetsFor('part.stl'), containsAll([ConversionFormat.obj, ConversionFormat.threeMf]));
      expect(ConversionFormats.targetsFor('clip.mp4'), [ConversionFormat.zip]);
      expect(ConversionFormats.targetsFor('setup.exe'), [ConversionFormat.zip]);
      expect(ConversionFormats.targetsFor('backup.tar.gz'), [ConversionFormat.zip, ConversionFormat.tar]);
      for (final name in ['a.pdf', 'a.docx', 'a.csv', 'a.png', 'a.py', 'a.pptx', 'a.obj', 'a.mp3']) {
        expect(ConversionFormats.targetsFor(name), contains(ConversionFormat.zip), reason: name);
      }
    });

    test('unsupported pairs are rejected with a readable message', () async {
      await expectLater(
        _convert('clip.mp4', _text('x'), ConversionFormat.pdf),
        throwsA(isA<ConversionException>().having((e) => e.message, 'message', contains('cannot be converted'))),
      );
    });
  });

  group('Documents', () {
    test('PDF text extraction survives a TXT -> PDF -> TXT round trip line by line', () async {
      final pdf = await _convert('notes.txt', _text('First line here\nSecond line, with comma\nThird'), ConversionFormat.pdf);
      final back = await _asText('notes.pdf', pdf.outputBytes);
      final lines = back.split('\n');
      expect(lines, containsAllInOrder(['First line here', 'Second line, with comma', 'Third']));
    });

    test('Markdown -> DOCX -> TXT keeps headings, bullets and tables', () async {
      const md = '# Lab Report\n\nIntro paragraph.\n\n- step one\n- step two\n\n| Name | Score |\n|---|---|\n| Asha | 9 |\n';
      final docx = await _convert('report.md', _text(md), ConversionFormat.docx);
      final text = await _asText('report.docx', docx.outputBytes);
      expect(text, contains('Lab Report'));
      expect(text, contains('Intro paragraph.'));
      expect(text, contains('step two'));
      expect(text, contains('Asha\t9'));
    });

    test('TXT -> ODT -> TXT and TXT -> RTF -> TXT round trips', () async {
      const body = 'Experiment 4\nResult: 42 units\n';
      final odt = await _convert('exp.txt', _text(body), ConversionFormat.odt);
      expect(await _asText('exp.odt', odt.outputBytes), contains('Result: 42 units'));
      final rtf = await _convert('exp.txt', _text('Café {braces} \\ slash\n'), ConversionFormat.rtf);
      expect(await _asText('exp.rtf', rtf.outputBytes), contains('Café {braces} \\ slash'));
    });

    test('HTML -> Markdown drops scripts and keeps structure', () async {
      const html = '<html><head><title>Doc</title><style>p{}</style></head><body>'
          '<h1>Title &amp; More</h1><p>Hello <b>world</b></p><script>alert(1)</script>'
          '<ul><li>One</li><li>Two</li></ul><table><tr><th>A</th><th>B</th></tr><tr><td>1</td><td>2</td></tr></table></body></html>';
      final md = utf8.decode((await _convert('page.html', _text(html), ConversionFormat.md)).outputBytes);
      expect(md, contains('Title & More'));
      expect(md, contains('Hello world'));
      expect(md, contains('- Two'));
      expect(md, contains('| 1 | 2 |'));
      expect(md, isNot(contains('alert')));
    });

    test('legacy .doc text is recovered on a best-effort basis', () async {
      final text = 'This is the body of an old Word document.\rSecond paragraph text.\r';
      final utf16 = <int>[0xD0, 0xCF, 0x11, 0xE0, 0, 0, 0, 0];
      for (final u in text.codeUnits) {
        utf16..add(u & 0xFF)..add(u >> 8);
      }
      final res = await _convert('old.doc', Uint8List.fromList(utf16), ConversionFormat.txt);
      expect(utf8.decode(res.outputBytes), contains('Second paragraph text.'));
      expect(res.hasWarnings, isTrue);
    });

    test('PPTX -> TXT reads slide titles and bullets in order', () async {
      String slide(String title, String body) => '<p:sld xmlns:p="p" xmlns:a="a"><p:cSld><p:spTree>'
          '<p:sp><p:nvSpPr><p:nvPr><p:ph type="title"/></p:nvPr></p:nvSpPr><p:txBody><a:p><a:r><a:t>$title</a:t></a:r></a:p></p:txBody></p:sp>'
          '<p:sp><p:txBody><a:p><a:r><a:t>$body</a:t></a:r></a:p></p:txBody></p:sp></p:spTree></p:cSld></p:sld>';
      final pptx = _zip({
        'ppt/presentation.xml': '<p:presentation xmlns:p="p" xmlns:r="r"><p:sldIdLst><p:sldId r:id="rId2"/><p:sldId r:id="rId1"/></p:sldIdLst></p:presentation>',
        'ppt/_rels/presentation.xml.rels': '<Relationships><Relationship Id="rId1" Target="slides/slide1.xml"/><Relationship Id="rId2" Target="slides/slide2.xml"/></Relationships>',
        'ppt/slides/slide1.xml': slide('Second Title', 'beta'),
        'ppt/slides/slide2.xml': slide('First Title', 'alpha'),
      });
      final text = await _asText('deck.pptx', pptx);
      expect(text.indexOf('First Title'), lessThan(text.indexOf('Second Title')));
      expect(text, contains('alpha'));
      final pdf = await _convert('deck.pptx', pptx, ConversionFormat.pdf);
      expect(pdf.pageOrItemCount, 2);
    });

    test('source code becomes a numbered PDF listing and text survives', () async {
      const code = 'public class Lab1 {\n  public static void main(String[] a) {\n    System.out.println("hi");\n  }\n}\n';
      final pdf = await _convert('Lab1.java', _text(code), ConversionFormat.codePdf);
      final text = await _asText('Lab1.pdf', pdf.outputBytes);
      expect(text, contains('public class Lab1 {'));
      expect(text, contains('System.out.println("hi");'));
    });

    test('non-Latin text does not break PDF output', () async {
      final res = await _convert('u.txt', _text('Smart “quotes” — नमस्ते \u{1F600}'), ConversionFormat.pdf);
      expect(res.outputBytes.length, greaterThan(500));
    });
  });

  group('Spreadsheets and data', () {
    const csv = 'name,score,notes\nAsha,9.5,"likes, commas"\nRavi,7,"multi\nline"\n';

    test('CSV -> XLSX -> CSV is lossless, including quotes and newlines', () async {
      final xlsx = await _convert('marks.csv', _text(csv), ConversionFormat.xlsx);
      final back = utf8.decode((await _convert('marks.xlsx', xlsx.outputBytes, ConversionFormat.csv)).outputBytes);
      expect(back.replaceAll('\r\n', '\n'), csv);
    });

    test('CSV -> ODS -> JSON produces typed records', () async {
      final ods = await _convert('marks.csv', _text(csv), ConversionFormat.ods);
      final json = jsonDecode(utf8.decode((await _convert('marks.ods', ods.outputBytes, ConversionFormat.json)).outputBytes));
      expect(json, [
        {'name': 'Asha', 'score': 9.5, 'notes': 'likes, commas'},
        {'name': 'Ravi', 'score': 7, 'notes': 'multi\nline'},
      ]);
    });

    test('Excel shared strings, multiple sheets and columns past Z are read correctly', () async {
      final wide = [for (var i = 0; i < 30; i++) 'c$i'].join(',');
      final xlsx = await _convert('wide.csv', _text('$wide\n'), ConversionFormat.xlsx);
      final back = utf8.decode((await _convert('wide.xlsx', xlsx.outputBytes, ConversionFormat.csv)).outputBytes).trim();
      expect(back, wide);

      final book = _zip({
        'xl/workbook.xml': '<workbook xmlns:r="r"><sheets><sheet name="Marks" r:id="rId1"/><sheet name="Other" r:id="rId2"/></sheets></workbook>',
        'xl/_rels/workbook.xml.rels': '<Relationships><Relationship Id="rId1" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Target="worksheets/sheet2.xml"/></Relationships>',
        'xl/sharedStrings.xml': '<sst><si><t>Student</t></si><si><r><t>Ash</t></r><r><t>a</t></r></si></sst>',
        'xl/worksheets/sheet1.xml': '<worksheet><sheetData><row r="1"><c r="A1" t="s"><v>0</v></c><c r="C1"><v>12</v></c></row>'
            '<row r="2"><c r="A2" t="s"><v>1</v></c></row></sheetData></worksheet>',
        'xl/worksheets/sheet2.xml': '<worksheet><sheetData><row r="1"><c r="A1" t="inlineStr"><is><t>x</t></is></c></row></sheetData></worksheet>',
      });
      final json = jsonDecode(utf8.decode((await _convert('book.xlsx', book, ConversionFormat.json)).outputBytes)) as Map;
      expect(json.keys, ['Marks', 'Other']);
      expect((json['Marks'] as List).first, {'Student': 'Asha', 'column2': null, '12': null});
    });

    test('JSON array of objects -> CSV', () async {
      final res = await _convert('data.json', _text('[{"a":1,"b":"x"},{"a":2,"c":true}]'), ConversionFormat.csv);
      expect(utf8.decode(res.outputBytes).replaceAll('\r\n', '\n'), 'a,b,c\n1,x,\n2,,true\n');
    });

    test('spreadsheet -> PDF renders', () async {
      final res = await _convert('marks.csv', _text(csv), ConversionFormat.pdf);
      final text = await _asText('marks.pdf', res.outputBytes);
      expect(text, contains('Asha'));
    });
  });

  group('Images', () {
    final source = img.Image(width: 40, height: 20, numChannels: 4)..clear(img.ColorRgba8(200, 30, 30, 255));
    final png = img.encodePng(source);

    test('PNG converts to JPG, BMP, GIF, TIFF and back with the same size', () async {
      for (final f in [ConversionFormat.jpg, ConversionFormat.bmp, ConversionFormat.gif, ConversionFormat.tiff]) {
        final out = await _convert('red.png', png, f);
        final decoded = img.decodeImage(out.outputBytes);
        expect(decoded, isNotNull, reason: f.name);
        expect([decoded!.width, decoded.height], [40, 20], reason: f.name);
      }
    });

    test('image -> PDF and SVG -> PDF', () async {
      final pdf = await _convert('red.png', png, ConversionFormat.pdf);
      expect(latin1.decode(pdf.outputBytes.sublist(0, 5)), '%PDF-');
      const svg = '<svg xmlns="http://www.w3.org/2000/svg" width="100" height="50"><rect width="100" height="50" fill="#0a0"/></svg>';
      final svgPdf = await _convert('logo.svg', _text(svg), ConversionFormat.pdf);
      expect(latin1.decode(svgPdf.outputBytes.sublist(0, 5)), '%PDF-');
    });

    test('corrupt images fail with a clear message', () async {
      await expectLater(
        _convert('broken.png', _text('not an image'), ConversionFormat.jpg),
        throwsA(isA<ConversionException>().having((e) => e.message, 'message', contains('broken.png'))),
      );
    });
  });

  group('3D models', () {
    const asciiStl = 'solid cube\n'
        'facet normal 0 0 1\nouter loop\nvertex 0 0 0\nvertex 1 0 0\nvertex 1 1 0\nendloop\nendfacet\n'
        'facet normal 0 0 1\nouter loop\nvertex 0 0 0\nvertex 1 1 0\nvertex 0 1 0\nendloop\nendfacet\nendsolid cube\n';

    test('ASCII STL -> OBJ -> 3MF -> binary STL keeps every triangle', () async {
      final obj = await _convert('quad.stl', _text(asciiStl), ConversionFormat.obj);
      final objText = utf8.decode(obj.outputBytes);
      expect('\nv '.allMatches(objText).length, 4, reason: 'shared vertices are de-duplicated');
      expect('\nf '.allMatches(objText).length, 2);
      final mf = await _convert('quad.obj', obj.outputBytes, ConversionFormat.threeMf);
      final stl = await _convert('quad.3mf', mf.outputBytes, ConversionFormat.stl);
      expect(stl.outputBytes.length, 84 + 2 * 50);
      expect(stl.pageOrItemCount, 2);
    });

    test('OBJ quads are triangulated', () async {
      final res = await _convert('q.obj', _text('v 0 0 0\nv 1 0 0\nv 1 1 0\nv 0 1 0\nf 1/1/1 2/2/2 3/3/3 4/4/4\n'), ConversionFormat.stl);
      expect(res.pageOrItemCount, 2);
    });
  });

  group('Archives', () {
    test('ZIP -> TAR.GZ -> ZIP preserves paths and contents', () async {
      final zip = _zip({'docs/a.txt': 'alpha', 'b.txt': 'beta'});
      final tgz = await _convert('bundle.zip', zip, ConversionFormat.tarGz);
      expect(tgz.outputFileName, 'bundle.tar.gz');
      final back = await _convert('bundle.tar.gz', tgz.outputBytes, ConversionFormat.zip);
      final archive = ZipDecoder().decodeBytes(back.outputBytes);
      expect(utf8.decode(archive.findFile('docs/a.txt')!.content), 'alpha');
      expect(utf8.decode(archive.findFile('b.txt')!.content), 'beta');
    });

    test('any file can be packed into a ZIP', () async {
      final res = await _convert('movie.mp4', Uint8List.fromList([1, 2, 3, 4]), ConversionFormat.zip);
      final archive = ZipDecoder().decodeBytes(res.outputBytes);
      expect(archive.findFile('movie.mp4')!.content, [1, 2, 3, 4]);
    });
  });
}
