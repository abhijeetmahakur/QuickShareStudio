import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:provider/provider.dart';
import 'package:quickshare/data/services/transfer_engine.dart';
import 'package:quickshare/features/pdf_tools/pdf_tools_view.dart';
import 'package:quickshare/features/pdf_tools/services/file_converter_service.dart';

final class _MemoryFile extends PlatformFile {
  _MemoryFile(this.name, this.bytes);
  @override
  final String name;
  final Uint8List bytes;
  @override
  Uri get uri => Uri.parse('memory:///$name');
  @override
  get xFile => throw UnimplementedError();
  @override
  int? lengthSync() => bytes.length;
  @override
  Future<int?> length() async => bytes.length;
  @override
  Future<Uint8List> readAsBytes() async => bytes;
  @override
  Stream<Uint8List> readAsByteStream() => Stream.value(bytes);
}

class _FakePicker extends FilePickerPlatform {
  _FakePicker(this.files);
  final List<PlatformFile> files;
  final saved = <String, Uint8List>{};

  @override
  Future<List<PlatformFile>> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async =>
      files;

  @override
  Future<Uri?> saveFile({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
    String? dialogTitle,
    String? initialDirectory,
    Function(FilePickerStatus)? onFileSaving,
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    saved[fileName] = bytes;
    return Uri.parse('memory:///$fileName');
  }
}

Uint8List _utf8(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  testWidgets('Converter queue: add mixed files, "Convert all to" Word, convert, download all as ZIP', (tester) async {
    tester.view.physicalSize = const Size(1400, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final picker = _FakePicker([
      _MemoryFile('Lab1.java', _utf8('class Lab1 {\n  int x = 1;\n}\n')),
      _MemoryFile('marks.csv', _utf8('name,score\nAsha,9\n')),
      _MemoryFile('notes.txt', _utf8('Hello converter\n')),
      _MemoryFile('photo.png', img.encodePng(img.Image(width: 8, height: 8))),
      _MemoryFile('movie.mp4', Uint8List.fromList([0, 1, 2, 3])),
    ]);
    final previous = FilePickerPlatform.instance;
    FilePickerPlatform.instance = picker;
    addTearDown(() => FilePickerPlatform.instance = previous);

    final engine = TransferEngine();
    engine.stopTimers();
    await tester.pumpWidget(
      ChangeNotifierProvider<TransferEngine>.value(
        value: engine,
        child: const MaterialApp(home: PdfToolsView()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ElevatedButton, 'Add Files'));
    await tester.pumpAndSettle();

    // Sensible defaults per type; files with no real conversion are offered ZIP only.
    expect(find.text('5 files in queue'), findsOneWidget);
    expect(find.text(ConversionFormat.codePdf.label), findsOneWidget); // Lab1.java
    expect(find.text(ConversionFormat.pdf.label), findsNWidgets(3)); // csv, txt, png
    expect(find.text(ConversionFormat.zip.label), findsOneWidget); // movie.mp4

    // "Convert all to" Word: only files that can become .docx change.
    await tester.tap(find.byKey(const Key('convert_all_to_menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(ConversionFormat.docx.label).last);
    await tester.pumpAndSettle();
    expect(find.text(ConversionFormat.docx.label), findsNWidgets(2)); // java + txt
    expect(find.text(ConversionFormat.pdf.label), findsNWidgets(2)); // csv + png kept PDF

    await tester.tap(find.textContaining('Convert (5 Files)'));
    for (var i = 0; i < 20 && find.text('Success').evaluate().length + find.text('Failed').evaluate().length < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(find.text('Failed'), findsNothing);
    expect(find.text('Success'), findsNWidgets(5));

    await tester.tap(find.widgetWithText(OutlinedButton, 'Download All (.zip)'));
    await tester.pumpAndSettle();

    final zipBytes = picker.saved['QuickShare_converted.zip'];
    expect(zipBytes, isNotNull);
    final names = ZipDecoder().decodeBytes(zipBytes!).files.map((f) => f.name).toSet();
    expect(names, {'Lab1.docx', 'marks.pdf', 'notes.docx', 'photo.pdf', 'movie.zip'});

    await tester.pumpWidget(const SizedBox());
    engine.stopTimers();
  });
}
