import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_picker_linux/file_picker_linux.dart';
import 'package:flutter/foundation.dart';

/// file_picker asks the XDG desktop portal over D-Bus on Linux. Desktops without a portal
/// backend (minimal XFCE/i3/LXDE setups, older releases) then cannot open any file chooser,
/// so this falls back to the dialog tools those systems ship: kdialog on KDE, otherwise
/// zenity (GNOME, Cinnamon, MATE, XFCE), qarma or yad.
final class FallbackLinuxFilePicker extends FilePickerPlatform {
  FallbackLinuxFilePicker(this._portal, {this.environment});

  final FilePickerPlatform _portal;

  /// Overrides [Platform.environment] in tests.
  final Map<String, String>? environment;
  bool _portalMissing = false;

  static void register() {
    FilePickerPlatform.instance = FallbackLinuxFilePicker(FilePickerLinux());
  }

  Map<String, String> get _env => environment ?? Platform.environment;

  /// D-Bus or socket failures mean "no portal"; a cancelled dialog is not an error.
  static bool _isMissingPortal(Object e) =>
      e is DBusMethodResponseException || e is DBusClosedException || e is SocketException;

  Future<T> _withFallback<T>(Future<T> Function() portal, Future<T> Function() fallback) async {
    if (!_portalMissing) {
      try {
        return await portal();
      } catch (e) {
        if (!_isMissingPortal(e)) rethrow;
        debugPrint('[QuickShare] File chooser portal unavailable ($e); using a dialog tool instead.');
        _portalMissing = true;
      }
    }
    return fallback();
  }

  @override
  Future<PlatformFile?> pickFile({
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
  }) =>
      _withFallback(
        () => _portal.pickFile(
          dialogTitle: dialogTitle,
          initialDirectory: initialDirectory,
          type: type,
          allowedExtensions: allowedExtensions,
          onFileLoading: onFileLoading,
          compressionQuality: compressionQuality,
          linuxOptions: linuxOptions,
        ),
        () async => (await _pick(dialogTitle, initialDirectory, type, allowedExtensions, multiple: false)).firstOrNull,
      );

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
  }) =>
      _withFallback(
        () => _portal.pickFiles(
          dialogTitle: dialogTitle,
          initialDirectory: initialDirectory,
          type: type,
          allowedExtensions: allowedExtensions,
          onFileLoading: onFileLoading,
          compressionQuality: compressionQuality,
          linuxOptions: linuxOptions,
        ),
        () => _pick(dialogTitle, initialDirectory, type, allowedExtensions, multiple: true),
      );

  @override
  Future<List<String>> pickFileAndDirectoryPaths({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
  }) =>
      _withFallback(
        () => _portal.pickFileAndDirectoryPaths(
          dialogTitle: dialogTitle,
          initialDirectory: initialDirectory,
          type: type,
          allowedExtensions: allowedExtensions,
        ),
        () async => [
          for (final f in await _pick(dialogTitle, initialDirectory, type, allowedExtensions, multiple: true)) f.path!,
        ],
      );

  @override
  Future<String?> getDirectoryPath({
    String? dialogTitle,
    String? initialDirectory,
    AndroidOptions androidOptions = const AndroidOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) =>
      _withFallback(
        () => _portal.getDirectoryPath(
          dialogTitle: dialogTitle,
          initialDirectory: initialDirectory,
          linuxOptions: linuxOptions,
        ),
        () async {
          final tool = _tool();
          final title = dialogTitle ?? 'Choose a folder';
          final start = initialDirectory ?? _env['HOME'] ?? '/';
          final out = await _run(tool, switch (tool.split('/').last) {
            'kdialog' => ['--title', title, '--getexistingdirectory', start],
            _ => ['--file-selection', '--directory', '--title=$title', '--filename=${_withSlash(start)}'],
          });
          return out == null || out.isEmpty ? null : out.first;
        },
      );

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
  }) =>
      _withFallback(
        () => _portal.saveFile(
          fileName: fileName,
          bytes: bytes,
          mimeType: mimeType,
          dialogTitle: dialogTitle,
          initialDirectory: initialDirectory,
          onFileSaving: onFileSaving,
          linuxOptions: linuxOptions,
        ),
        () async {
          final tool = _tool();
          final title = dialogTitle ?? 'Save file';
          final start = '${_withSlash(initialDirectory ?? _env['HOME'] ?? '/')}$fileName';
          final out = await _run(tool, switch (tool.split('/').last) {
            'kdialog' => ['--title', title, '--getsavefilename', start],
            _ => ['--file-selection', '--save', '--confirm-overwrite', '--title=$title', '--filename=$start'],
          });
          if (out == null || out.isEmpty) return null;
          final file = File(out.first);
          await file.writeAsBytes(bytes, flush: true);
          return file.uri;
        },
      );

  Future<List<PlatformFile>> _pick(
    String? dialogTitle,
    String? initialDirectory,
    FileType type,
    List<String>? allowedExtensions, {
    required bool multiple,
  }) async {
    final tool = _tool();
    final title = dialogTitle ?? (multiple ? 'Choose files' : 'Choose a file');
    final start = initialDirectory ?? _env['HOME'] ?? '/';
    final extensions = extensionsFor(type, allowedExtensions);
    final patterns = extensions.map((e) => '*.$e').join(' ');
    final out = await _run(tool, switch (tool.split('/').last) {
      'kdialog' => [
          '--title', title, '--getopenfilename', start,
          if (patterns.isNotEmpty) '$patterns|Supported files' else '',
          if (multiple) ...['--multiple', '--separate-output'],
        ],
      _ => [
          '--file-selection', '--title=$title', '--filename=${_withSlash(start)}',
          if (multiple) ...['--multiple', '--separator=\n'],
          if (patterns.isNotEmpty) '--file-filter=Supported files | $patterns',
        ],
    });
    return [for (final path in out ?? const <String>[]) LinuxPlatformFile.fromPath(path)];
  }

  /// File extensions the dialog should offer for [type] (empty: any file).
  @visibleForTesting
  static List<String> extensionsFor(FileType type, List<String>? custom) => switch (type) {
        FileType.custom => [for (final e in custom ?? const <String>[]) e.replaceFirst('.', '').toLowerCase()],
        FileType.image => const ['png', 'jpg', 'jpeg', 'gif', 'bmp', 'webp'],
        FileType.video => const ['mp4', 'mkv', 'mov', 'avi', 'webm'],
        FileType.audio => const ['mp3', 'wav', 'ogg', 'flac', 'm4a', 'aac'],
        FileType.media => const ['png', 'jpg', 'jpeg', 'gif', 'bmp', 'webp', 'mp4', 'mkv', 'mov', 'avi', 'webm'],
        FileType.any => const [],
      };

  static String _withSlash(String dir) => dir.endsWith('/') ? dir : '$dir/';

  /// kdialog on KDE, otherwise the first zenity-compatible tool that is installed (its path).
  String _tool() {
    final desktop = (_env['XDG_CURRENT_DESKTOP'] ?? '').toLowerCase();
    final candidates = desktop.contains('kde') ? ['kdialog', 'zenity', 'qarma', 'yad'] : ['zenity', 'qarma', 'yad', 'kdialog'];
    final path = (_env['PATH'] ?? '/usr/local/bin:/usr/bin:/bin').split(':');
    for (final tool in candidates) {
      for (final dir in path) {
        if (dir.isNotEmpty && File('$dir/$tool').existsSync()) return '$dir/$tool';
      }
    }
    throw const FileSystemException(
      'No file chooser is available. Install xdg-desktop-portal-gtk (or zenity) and try again.',
    );
  }

  /// Runs the dialog; null when cancelled. Each output line is one chosen path.
  Future<List<String>?> _run(String tool, List<String> args) async {
    final result = await Process.run(tool, args.where((a) => a.isNotEmpty).toList());
    if (result.exitCode != 0) return null;
    final lines = (result.stdout as String).split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    return lines.isEmpty ? null : lines;
  }
}
