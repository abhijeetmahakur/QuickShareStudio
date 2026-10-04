import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';

/// Thrown when an input can be read but not into the requested output (e.g. JSON that is not a table).
class ConversionException implements Exception {
  final String message;
  ConversionException(this.message);
  @override
  String toString() => message;
}

String escapeXml(String input) => input
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

/// Strips characters that are illegal in XML 1.0 (control chars except tab/newline/CR).
String xmlSafe(String input) => input.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');

const _pdfReplacements = {
  '‘': "'", '’': "'", '‚': "'", '‛': "'",
  '“': '"', '”': '"', '„': '"', '′': "'", '″': '"',
  '–': '-', '—': '-', '―': '-', '−': '-', '‐': '-', '‑': '-',
  '•': '·', '●': '·', '▪': '·', '‣': '>', '⁃': '-',
  '…': '...', ' ': ' ', ' ': ' ', '​': '', '﻿': '',
  '→': '->', '←': '<-', '↔': '<->', '⇒': '=>',
  '≤': '<=', '≥': '>=', '≠': '!=', '≈': '~',
  '™': '(TM)', '€': 'EUR', '₹': 'Rs.', '✓': 'v', '✔': 'v', '✗': 'x',
};

/// The PDF writer's built-in fonts only cover Latin-1: map common Unicode punctuation and
/// replace anything else with '?' so conversions never fail on a stray character.
String pdfSafe(String input) {
  final sb = StringBuffer();
  for (final rune in input.runes) {
    final ch = String.fromCharCode(rune);
    final rep = _pdfReplacements[ch];
    if (rep != null) {
      sb.write(rep);
    } else if (rune == 0x09) {
      sb.write('    ');
    } else if (rune < 0x20 && rune != 0x0A) {
      continue;
    } else if (rune <= 0xFF) {
      sb.write(ch);
    } else {
      sb.write('?');
    }
  }
  return sb.toString();
}

String decodeText(Uint8List bytes) {
  // UTF-16 with BOM (common for Windows "Unicode" text exports).
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
    return String.fromCharCodes(Uint16List.view(Uint8List.fromList(bytes.sublist(2, bytes.length - (bytes.length % 2))).buffer));
  }
  if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
    final units = <int>[];
    for (var i = 2; i + 1 < bytes.length; i += 2) {
      units.add((bytes[i] << 8) | bytes[i + 1]);
    }
    return String.fromCharCodes(units);
  }
  var text = utf8.decode(bytes, allowMalformed: true);
  if (text.startsWith('﻿')) text = text.substring(1);
  return text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
}

Uint8List encodeText(String text) => Uint8List.fromList(utf8.encode(text));

String? readArchiveText(Archive archive, String path) {
  final f = archive.findFile(path);
  if (f == null) return null;
  return utf8.decode(f.content, allowMalformed: true);
}

Uint8List zipArchive(Archive archive) => ZipEncoder().encodeBytes(archive);

void addText(Archive archive, String path, String content) {
  archive.addFile(ArchiveFile.bytes(path, utf8.encode(content)));
}

/// Packages an OpenDocument file (ODT/ODS): `mimetype` must be first and stored uncompressed.
Uint8List packOpenDocument(String mimeType, String contentXml) {
  final archive = Archive();
  final mime = utf8.encode(mimeType);
  archive.addFile(ArchiveFile.noCompress('mimetype', mime.length, mime));
  addText(archive, 'content.xml', contentXml);
  addText(archive, 'META-INF/manifest.xml', '''<?xml version="1.0" encoding="UTF-8"?>
<manifest:manifest xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0" manifest:version="1.2">
  <manifest:file-entry manifest:full-path="/" manifest:media-type="$mimeType"/>
  <manifest:file-entry manifest:full-path="content.xml" manifest:media-type="text/xml"/>
</manifest:manifest>''');
  return zipArchive(archive);
}

/// Spreadsheet column name for a zero-based index: 0 -> A, 25 -> Z, 26 -> AA.
String columnName(int index) {
  var n = index + 1;
  final sb = StringBuffer();
  while (n > 0) {
    final rem = (n - 1) % 26;
    sb.write(String.fromCharCode(65 + rem));
    n = (n - 1) ~/ 26;
  }
  return sb.toString().split('').reversed.join();
}

/// Zero-based column index from a cell reference like "AB12".
int columnIndexFromRef(String ref) {
  var col = 0;
  for (final c in ref.codeUnits) {
    if (c >= 65 && c <= 90) {
      col = col * 26 + (c - 64);
    } else if (c >= 97 && c <= 122) {
      col = col * 26 + (c - 96);
    } else {
      break;
    }
  }
  return col - 1;
}

String baseNameOf(String fileName) {
  final name = fileName.split('/').last.split('\\').last;
  final lower = name.toLowerCase();
  if (lower.endsWith('.tar.gz')) return name.substring(0, name.length - 7);
  final dot = name.lastIndexOf('.');
  return dot <= 0 ? name : name.substring(0, dot);
}
