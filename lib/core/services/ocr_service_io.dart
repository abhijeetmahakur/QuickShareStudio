import 'dart:io';

import 'package:flutter/foundation.dart';

import 'ocr_service.dart';

// Native OCR runs the Tesseract command-line engine: the copy bundled with the Linux AppImage
// and tarball (tesseract/ next to the executable), or one installed on the system (apt/dnf on
// Linux, the UB Mannheim installer on Windows). Android has no OCR engine.

bool get isSupported => Platform.isLinux || Platform.isWindows || Platform.isMacOS;

class _Engine {
  _Engine(this.executable, this.tessdataDir, this.environment, this.languages, this.label);
  final String executable;

  /// Passed as --tessdata-dir (bundled copy); null uses the engine's own data.
  final String? tessdataDir;
  final Map<String, String> environment;
  final Set<String> languages;
  final String label;

  List<String> get dataArgs => tessdataDir == null ? const [] : ['--tessdata-dir', tessdataDir!];
}

_Engine? _engine;

Future<OcrAvailability> availability(String languageCode) async {
  if (!isSupported) {
    return const OcrAvailability(ready: false, hint: 'Text recognition runs in the Windows and Linux apps.');
  }
  var engine = await _findEngine();
  if (engine == null) return OcrAvailability(ready: false, hint: installHint());
  var missing = languageCode.split('+').where((l) => !engine!.languages.contains(l)).toList();
  if (missing.isNotEmpty) {
    // The language may have been installed since the last check.
    _engine = null;
    engine = await _findEngine();
    if (engine == null) return OcrAvailability(ready: false, hint: installHint());
    missing = languageCode.split('+').where((l) => !engine!.languages.contains(l)).toList();
  }
  if (missing.isNotEmpty) {
    return OcrAvailability(ready: false, engine: engine.label, hint: languageHint(missing));
  }
  return OcrAvailability(ready: true, engine: engine.label);
}

Future<OcrResult> recognize(
  List<Uint8List> images,
  String languageCode,
  void Function(int done, int total)? onProgress,
) async {
  final status = await availability(languageCode);
  if (!status.ready) throw OcrUnavailableException(status.hint ?? 'Text recognition is not available.');
  final engine = _engine!;
  final work = await Directory.systemTemp.createTemp('quickshare_ocr_');
  try {
    final texts = <String>[];
    final pdfs = <Uint8List>[];
    final confidences = <double>[];
    for (var i = 0; i < images.length; i++) {
      final input = File('${work.path}${Platform.pathSeparator}page_$i.png');
      await input.writeAsBytes(images[i]);
      final base = '${work.path}${Platform.pathSeparator}page_$i';
      final result = await Process.run(
        engine.executable,
        [
          input.path,
          base,
          ...engine.dataArgs,
          '-l',
          languageCode,
          // One pass writes the text, the searchable PDF page and per-word confidences.
          '-c', 'tessedit_create_txt=1',
          '-c', 'tessedit_create_pdf=1',
          '-c', 'tessedit_create_tsv=1',
        ],
        environment: engine.environment,
      );
      if (result.exitCode != 0) {
        final detail = '${result.stderr}'.trim().split('\n').where((l) => l.trim().isNotEmpty).lastOrNull;
        throw Exception('Tesseract could not read page ${i + 1}${detail == null ? '' : ': $detail'}');
      }
      texts.add((await File('$base.txt').readAsString()).trim());
      pdfs.add(await File('$base.pdf').readAsBytes());
      confidences.addAll(tsvConfidences(await File('$base.tsv').readAsString()));
      onProgress?.call(i + 1, images.length);
    }
    final confidence = confidences.isEmpty ? 0.0 : confidences.reduce((a, b) => a + b) / confidences.length;
    return OcrResult(texts.join('\n\n'), confidence, pdfs);
  } finally {
    try {
      await work.delete(recursive: true);
    } catch (_) {}
  }
}

/// Word confidences (0-100) from Tesseract's TSV output.
@visibleForTesting
List<double> tsvConfidences(String tsv) {
  final values = <double>[];
  for (final line in tsv.split('\n').skip(1)) {
    final cols = line.split('\t');
    if (cols.length < 12 || cols[0] != '5' || cols[11].trim().isEmpty) continue;
    final conf = double.tryParse(cols[10]);
    if (conf != null && conf >= 0) values.add(conf);
  }
  return values;
}

/// Languages listed by `tesseract --list-langs`.
@visibleForTesting
Set<String> parseLanguages(String output) => output
    .split('\n')
    .map((l) => l.trim())
    .where((l) => l.isNotEmpty && !l.startsWith('List of available languages') && !l.contains(' '))
    .toSet();

Future<_Engine?> _findEngine() async {
  final cached = _engine;
  if (cached != null) return cached;
  for (final candidate in _candidates()) {
    try {
      final result = await Process.run(
        candidate.executable,
        [...candidate.dataArgs, '--list-langs'],
        environment: candidate.environment,
      );
      if (result.exitCode != 0) continue;
      final languages = parseLanguages('${result.stdout}\n${result.stderr}');
      return _engine = _Engine(
        candidate.executable,
        candidate.tessdataDir,
        candidate.environment,
        languages,
        candidate.label,
      );
    } catch (_) {
      // Not installed there; try the next place.
    }
  }
  return null;
}

Iterable<_Engine> _candidates() sync* {
  final exeDir = File(Platform.resolvedExecutable).parent.path;
  final sep = Platform.pathSeparator;
  // Bundled with the Linux AppImage / tarball: tesseract/{bin,lib,tessdata}.
  final bundled = '$exeDir${sep}tesseract';
  if (File('$bundled${sep}bin${sep}tesseract').existsSync()) {
    yield _Engine(
      '$bundled${sep}bin${sep}tesseract',
      '$bundled${sep}tessdata',
      {'LD_LIBRARY_PATH': '$bundled${sep}lib'},
      const {},
      'Tesseract (built in)',
    );
  }
  if (Platform.isWindows) {
    final local = Platform.environment['LOCALAPPDATA'];
    for (final path in [
      r'C:\Program Files\Tesseract-OCR\tesseract.exe',
      r'C:\Program Files (x86)\Tesseract-OCR\tesseract.exe',
      if (local != null) '$local\\Programs\\Tesseract-OCR\\tesseract.exe',
    ]) {
      if (File(path).existsSync()) yield _Engine(path, null, const {}, const {}, 'Tesseract ($path)');
    }
  }
  // Anything on PATH (apt/dnf/pacman packages, Homebrew, a Windows PATH entry).
  yield _Engine('tesseract', null, const {}, const {}, 'Tesseract (system)');
}

/// How to install Tesseract on this computer.
@visibleForTesting
String installHint({String? osRelease}) {
  if (Platform.isWindows) {
    return 'Tesseract OCR is not installed. Install it from github.com/UB-Mannheim/tesseract/wiki '
        '(tick Hindi under "Additional language data" if you need it), then open PDF Tools again.';
  }
  if (Platform.isMacOS) return 'Tesseract OCR is not installed. Install it with: brew install tesseract tesseract-lang';
  return 'Tesseract OCR is not installed. Install it with: ${linuxInstallCommand(['eng', 'hin'], osRelease)}';
}

@visibleForTesting
String languageHint(List<String> missing, {String? osRelease}) {
  final names = missing.map((l) => l == 'hin' ? 'Hindi' : l == 'eng' ? 'English' : l).join(' and ');
  if (Platform.isWindows) {
    return 'The $names language data is missing. Run the Tesseract installer again and tick it under '
        '"Additional language data".';
  }
  if (Platform.isMacOS) return 'The $names language data is missing. Install it with: brew install tesseract-lang';
  return 'The $names language data is missing. Install it with: ${linuxInstallCommand(missing, osRelease)}';
}

/// The command that installs Tesseract and [languages] on the Linux distribution described
/// by [osRelease] (/etc/os-release when null).
@visibleForTesting
String linuxInstallCommand(List<String> languages, String? osRelease) {
  String release = osRelease ?? '';
  if (osRelease == null) {
    try {
      release = File('/etc/os-release').readAsStringSync();
    } catch (_) {}
  }
  final ids = RegExp(r'^(ID|ID_LIKE)="?([^"\n]*)"?', multiLine: true)
      .allMatches(release)
      .expand((m) => m.group(2)!.split(' '))
      .toSet();
  bool any(List<String> names) => names.any(ids.contains);
  if (any(['debian', 'ubuntu', 'linuxmint', 'pop', 'elementary', 'zorin', 'kali'])) {
    return 'sudo apt install tesseract-ocr ${languages.map((l) => 'tesseract-ocr-$l').join(' ')}';
  }
  if (any(['fedora', 'rhel', 'centos', 'rocky', 'almalinux'])) {
    return 'sudo dnf install tesseract ${languages.map((l) => 'tesseract-langpack-$l').join(' ')}';
  }
  if (any(['arch', 'manjaro', 'endeavouros'])) {
    return 'sudo pacman -S tesseract ${languages.map((l) => 'tesseract-data-$l').join(' ')}';
  }
  if (any(['opensuse', 'suse', 'opensuse-tumbleweed', 'opensuse-leap'])) {
    return 'sudo zypper install tesseract-ocr ${languages.map((l) => 'tesseract-ocr-traineddata-${l == 'hin' ? 'hindi' : 'english'}').join(' ')}';
  }
  return 'your package manager (package "tesseract-ocr" or "tesseract", plus the ${languages.join(', ')} language data)';
}
