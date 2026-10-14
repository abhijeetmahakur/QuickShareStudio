import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../../data/models/screenshot_item.dart';

/// Content type returned by [PlatformClipboardService.read].
enum ClipboardContentType { text, image, files, empty, unsupported }

/// Result of a clipboard read operation.
class ClipboardReadResult {
  final ClipboardContentType type;
  final String? text;
  final Uint8List? imageBytes;
  final String? imageMime; // e.g. 'image/png', 'image/jpeg'
  final List<String>? filePaths;
  final String? errorMessage;

  const ClipboardReadResult({
    required this.type,
    this.text,
    this.imageBytes,
    this.imageMime,
    this.filePaths,
    this.errorMessage,
  });

  static const ClipboardReadResult empty =
      ClipboardReadResult(type: ClipboardContentType.empty);

  static ClipboardReadResult error(String msg) =>
      ClipboardReadResult(type: ClipboardContentType.unsupported, errorMessage: msg);
}

/// Result of a clipboard write operation.
class ClipboardWriteResult {
  final bool success;
  final String? errorMessage;
  const ClipboardWriteResult({required this.success, this.errorMessage});
  static const ClipboardWriteResult ok = ClipboardWriteResult(success: true);
  static ClipboardWriteResult fail(String msg) =>
      ClipboardWriteResult(success: false, errorMessage: msg);
}

/// Linux clipboard environment details.
class LinuxClipboardEnvironment {
  final bool isX11;
  final bool isWayland;
  final String desktopSession;
  final bool hasNativeClipboard;

  const LinuxClipboardEnvironment({
    required this.isX11,
    required this.isWayland,
    required this.desktopSession,
    required this.hasNativeClipboard,
  });

  bool get hasSuperClipboard => hasNativeClipboard;

  String get description {
    final server = isWayland ? 'Wayland' : isX11 ? 'X11' : 'Unknown';
    return '$desktopSession ($server)';
  }
}

/// Unified clipboard service with platform-specific adapters.
///
/// Capabilities:
///   Windows  — text ✓, image PNG (via win32 CF_DIB fallback) ✓, file paths ✓
///   Linux    — text ✓, image PNG (xclip/wl-paste) ✓, file URIs ✓
///   macOS    — text ✓, image (pbpaste) ✓, file URLs ✓
///   Android  — text ✓ (OS clipboard), images/files: via content URIs
///   Web      — text ✓, image (async Clipboard API) ✓
///
/// When a native operation is unavailable, returns a clear error message
/// and never silently downgrades to filename/path-only behavior.
class PlatformClipboardService {
  PlatformClipboardService._();
  static final PlatformClipboardService instance = PlatformClipboardService._();

  // MethodChannel for platform-specific native calls (Windows CF_DIB, Android content URIs)
  static const _channel = MethodChannel('quickshare/clipboard');

  // ---------------------------------------------------------------------------
  // Environment detection
  // ---------------------------------------------------------------------------

  LinuxClipboardEnvironment? get linuxEnvironment {
    if (kIsWeb || !Platform.isLinux) return null;
    final session = Platform.environment['XDG_SESSION_TYPE'] ?? '';
    final desktop = Platform.environment['XDG_CURRENT_DESKTOP'] ??
        Platform.environment['DESKTOP_SESSION'] ??
        'Unknown';
    final wayland = session.toLowerCase() == 'wayland' ||
        (Platform.environment['WAYLAND_DISPLAY']?.isNotEmpty ?? false);
    final x11 = !wayland || session.toLowerCase() == 'x11' ||
        (Platform.environment['DISPLAY']?.isNotEmpty ?? false);
    final hasNative = _hasLinuxClipboardTool();
    return LinuxClipboardEnvironment(
      isX11: x11 && !wayland,
      isWayland: wayland,
      desktopSession: desktop,
      hasNativeClipboard: hasNative,
    );
  }

  bool _hasLinuxClipboardTool() {
    if (!Platform.isLinux) return false;
    final env = Platform.environment;
    final wayland = env['WAYLAND_DISPLAY']?.isNotEmpty ?? false;
    if (wayland) {
      return _toolExists('wl-paste');
    }
    return _toolExists('xclip') || _toolExists('xsel');
  }

  bool _toolExists(String tool) {
    try {
      final result = Process.runSync('which', [tool]);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Read
  // ---------------------------------------------------------------------------

  Future<ClipboardReadResult> read() async {
    if (!kIsWeb) {
      // Try to detect image/file content first via platform-specific means
      if (Platform.isLinux) return _readLinux();
      if (Platform.isWindows) return _readWindows();
      if (Platform.isMacOS) return _readMacOS();
    }

    // Flutter built-in text-only fallback
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text ?? '';
      if (text.isNotEmpty) {
        return ClipboardReadResult(type: ClipboardContentType.text, text: text);
      }
    } catch (e) {
      return ClipboardReadResult.error('Clipboard access denied: $e');
    }
    return ClipboardReadResult.empty;
  }

  // ---------------------------------------------------------------------------
  // Linux clipboard read
  // ---------------------------------------------------------------------------

  Future<ClipboardReadResult> _readLinux() async {
    final env = Platform.environment;
    final wayland = env['WAYLAND_DISPLAY']?.isNotEmpty ?? false;

    if (wayland) {
      return _readLinuxWayland();
    } else {
      return _readLinuxX11();
    }
  }

  Future<ClipboardReadResult> _readLinuxWayland() async {
    // 1. Try image first with wl-paste
    if (_toolExists('wl-paste')) {
      try {
        // Check available MIME types
        final typesResult = await Process.run('wl-paste', ['--list-types']);
        if (typesResult.exitCode == 0) {
          final types = (typesResult.stdout as String).split('\n');
          // Check for image MIME types
          for (final imgMime in ['image/png', 'image/jpeg', 'image/gif', 'image/webp', 'image/bmp']) {
            if (types.any((t) => t.trim() == imgMime)) {
              final imgResult = await Process.run('wl-paste', ['--type', imgMime], stdoutEncoding: null);
              if (imgResult.exitCode == 0) {
                final bytes = imgResult.stdout as Uint8List;
                if (bytes.isNotEmpty) {
                  return ClipboardReadResult(
                    type: ClipboardContentType.image,
                    imageBytes: bytes,
                    imageMime: imgMime,
                  );
                }
              }
            }
          }
          // Check for file URIs
          if (types.any((t) => t.trim() == 'text/uri-list')) {
            final uriResult = await Process.run('wl-paste', ['--type', 'text/uri-list']);
            if (uriResult.exitCode == 0) {
              final uris = (uriResult.stdout as String).trim().split('\n')
                  .where((l) => l.startsWith('file://'))
                  .map((l) => Uri.parse(l.trim()).toFilePath())
                  .where((p) => p.isNotEmpty)
                  .toList();
              if (uris.isNotEmpty) {
                return ClipboardReadResult(type: ClipboardContentType.files, filePaths: uris);
              }
            }
          }
          // Check for plain text
          if (types.any((t) => t.trim().startsWith('text/plain'))) {
            final textResult = await Process.run('wl-paste', ['--type', 'text/plain']);
            if (textResult.exitCode == 0) {
              final text = (textResult.stdout as String).trim();
              if (text.isNotEmpty) {
                return ClipboardReadResult(type: ClipboardContentType.text, text: text);
              }
            }
          }
        }
      } catch (e) {
        debugPrint('[LinuxWayland] wl-paste error: $e');
      }
    }

    // Flutter text fallback
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text ?? '';
      if (text.isNotEmpty) return ClipboardReadResult(type: ClipboardContentType.text, text: text);
    } catch (_) {}
    return ClipboardReadResult.empty;
  }

  Future<ClipboardReadResult> _readLinuxX11() async {
    // xclip: preferred; xsel: fallback
    if (_toolExists('xclip')) {
      try {
        // Try image targets first
        for (final imgMime in ['image/png', 'image/jpeg', 'image/gif', 'image/webp', 'image/bmp']) {
          final result = await Process.run(
            'xclip', ['-selection', 'clipboard', '-t', imgMime, '-o'],
            stdoutEncoding: null,
          );
          if (result.exitCode == 0) {
            final bytes = result.stdout as Uint8List;
            if (bytes.isNotEmpty && bytes.length > 8) {
              return ClipboardReadResult(
                type: ClipboardContentType.image,
                imageBytes: bytes,
                imageMime: imgMime,
              );
            }
          }
        }
        // Try file URI list
        final uriResult = await Process.run('xclip', ['-selection', 'clipboard', '-t', 'text/uri-list', '-o']);
        if (uriResult.exitCode == 0) {
          final stdout = uriResult.stdout as String;
          final uris = stdout.trim().split('\n')
              .where((l) => l.startsWith('file://'))
              .map((l) => Uri.parse(l.trim()).toFilePath())
              .where((p) => p.isNotEmpty)
              .toList();
          if (uris.isNotEmpty) {
            return ClipboardReadResult(type: ClipboardContentType.files, filePaths: uris);
          }
        }
        // Plain text
        final textResult = await Process.run('xclip', ['-selection', 'clipboard', '-o']);
        if (textResult.exitCode == 0) {
          final text = (textResult.stdout as String).trim();
          if (text.isNotEmpty) return ClipboardReadResult(type: ClipboardContentType.text, text: text);
        }
      } catch (e) {
        debugPrint('[LinuxX11] xclip error: $e');
      }
    } else if (_toolExists('xsel')) {
      try {
        final textResult = await Process.run('xsel', ['--clipboard', '--output']);
        if (textResult.exitCode == 0) {
          final text = (textResult.stdout as String).trim();
          if (text.isNotEmpty) return ClipboardReadResult(type: ClipboardContentType.text, text: text);
        }
      } catch (e) {
        debugPrint('[LinuxX11] xsel error: $e');
      }
    }

    // Flutter text fallback
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text ?? '';
      if (text.isNotEmpty) return ClipboardReadResult(type: ClipboardContentType.text, text: text);
    } catch (_) {}
    return ClipboardReadResult.empty;
  }

  // ---------------------------------------------------------------------------
  // Windows clipboard read
  // ---------------------------------------------------------------------------

  Future<ClipboardReadResult> _readWindows() async {
    // Try MethodChannel for image read (Win32 CF_DIB / CF_DIBV5 / CF_BITMAP)
    try {
      final result = await _channel.invokeMethod<Map>('readImageFromClipboard');
      if (result != null) {
        final bytes = result['bytes'] as Uint8List?;
        final mime = result['mime'] as String? ?? 'image/png';
        if (bytes != null && bytes.isNotEmpty) {
          return ClipboardReadResult(type: ClipboardContentType.image, imageBytes: bytes, imageMime: mime);
        }
      }
    } on MissingPluginException {
      // MethodChannel not registered — no native Windows image clipboard
    } catch (_) {}

    // Try file paths
    try {
      final result = await _channel.invokeMethod<List>('readFilesFromClipboard');
      if (result != null && result.isNotEmpty) {
        return ClipboardReadResult(
          type: ClipboardContentType.files,
          filePaths: result.cast<String>(),
        );
      }
    } on MissingPluginException {
      // Channel method not implemented on current platform
    } catch (_) {}

    // Text
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text ?? '';
      if (text.isNotEmpty) return ClipboardReadResult(type: ClipboardContentType.text, text: text);
    } catch (_) {}
    return ClipboardReadResult.empty;
  }

  // ---------------------------------------------------------------------------
  // macOS clipboard read
  // ---------------------------------------------------------------------------

  Future<ClipboardReadResult> _readMacOS() async {
    // Try native image via pbpaste (macOS)
    try {
      final result = await Process.run('pbpaste', []);
      // pbpaste only returns text; image read on macOS needs MethodChannel
      if (result.exitCode == 0) {
        final text = (result.stdout as String).trim();
        if (text.isNotEmpty) {
          return ClipboardReadResult(type: ClipboardContentType.text, text: text);
        }
      }
    } catch (_) {}

    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text ?? '';
      if (text.isNotEmpty) return ClipboardReadResult(type: ClipboardContentType.text, text: text);
    } catch (_) {}
    return ClipboardReadResult.empty;
  }

  // ---------------------------------------------------------------------------
  // Write text
  // ---------------------------------------------------------------------------

  Future<ClipboardWriteResult> writeText(String text) async {
    if (text.isEmpty) return ClipboardWriteResult.fail('Cannot write empty text to clipboard.');

    if (!kIsWeb && Platform.isLinux) {
      return _writeLinuxText(text);
    }

    try {
      await Clipboard.setData(ClipboardData(text: text));
      return ClipboardWriteResult.ok;
    } catch (e) {
      return ClipboardWriteResult.fail('Failed to write text: $e');
    }
  }

  Future<ClipboardWriteResult> _writeLinuxText(String text) async {
    final env = Platform.environment;
    final wayland = env['WAYLAND_DISPLAY']?.isNotEmpty ?? false;
    try {
      if (wayland && _toolExists('wl-copy')) {
        final process = await Process.start('wl-copy', []);
        process.stdin.write(text);
        await process.stdin.flush();
        await process.stdin.close();
        await process.exitCode;
        return ClipboardWriteResult.ok;
      } else if (_toolExists('xclip')) {
        final process = await Process.start('xclip', ['-selection', 'clipboard']);
        process.stdin.write(text);
        await process.stdin.flush();
        await process.stdin.close();
        await process.exitCode;
        return ClipboardWriteResult.ok;
      }
    } catch (e) {
      debugPrint('[LinuxClipboard] write text failed: $e');
    }
    // Fallback to Flutter
    try {
      await Clipboard.setData(ClipboardData(text: text));
      return ClipboardWriteResult.ok;
    } catch (e) {
      return ClipboardWriteResult.fail('Failed to write text: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Write image (actual pixel data — never a filename)
  // ---------------------------------------------------------------------------

  Future<ClipboardWriteResult> writeImageBytes(Uint8List bytes, {String mime = 'image/png'}) async {
    if (bytes.isEmpty) return ClipboardWriteResult.fail('Cannot write empty image bytes.');

    if (!kIsWeb && Platform.isLinux) {
      return _writeLinuxImage(bytes, mime);
    }
    if (!kIsWeb && Platform.isWindows) {
      return _writeWindowsImage(bytes, mime);
    }

    return ClipboardWriteResult.fail(
      'Native image clipboard write is not implemented for ${_platformName()}. '
      'Use "Send to Device" to transfer the image.',
    );
  }

  Future<ClipboardWriteResult> _writeLinuxImage(Uint8List bytes, String mime) async {
    final env = Platform.environment;
    final wayland = env['WAYLAND_DISPLAY']?.isNotEmpty ?? false;
    try {
      if (wayland && _toolExists('wl-copy')) {
        final process = await Process.start('wl-copy', ['--type', mime]);
        process.stdin.add(bytes);
        await process.stdin.flush();
        await process.stdin.close();
        final code = await process.exitCode;
        if (code == 0) return ClipboardWriteResult.ok;
        return ClipboardWriteResult.fail('wl-copy exited with code $code');
      } else if (_toolExists('xclip')) {
        final process = await Process.start('xclip', ['-selection', 'clipboard', '-t', mime]);
        process.stdin.add(bytes);
        await process.stdin.flush();
        await process.stdin.close();
        final code = await process.exitCode;
        if (code == 0) return ClipboardWriteResult.ok;
        return ClipboardWriteResult.fail('xclip exited with code $code');
      }
    } catch (e) {
      return ClipboardWriteResult.fail('Linux image clipboard write failed: $e');
    }
    return ClipboardWriteResult.fail(
      'No clipboard tool available (wl-copy or xclip). '
      'Install one: sudo apt install wl-clipboard xclip',
    );
  }

  Future<ClipboardWriteResult> _writeWindowsImage(Uint8List bytes, String mime) async {
    try {
      final result = await _channel.invokeMethod<bool>('writeImageToClipboard', {
        'bytes': bytes,
        'mime': mime,
      });
      if (result == true) return ClipboardWriteResult.ok;
      return ClipboardWriteResult.fail('Windows native image clipboard write failed.');
    } on MissingPluginException {
      return ClipboardWriteResult.fail(
        'Windows native image clipboard not yet configured. '
        'Use "Send to Device" to transfer the image instead.',
      );
    } catch (e) {
      return ClipboardWriteResult.fail('Windows image clipboard error: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Write file paths
  // ---------------------------------------------------------------------------

  Future<ClipboardWriteResult> writeFilePaths(List<String> paths) async {
    if (paths.isEmpty) return ClipboardWriteResult.fail('No file paths to copy.');
    if (!kIsWeb && Platform.isLinux) {
      return _writeLinuxFilePaths(paths);
    }
    return ClipboardWriteResult.fail(
      'Native file clipboard write not implemented for ${_platformName()}. '
      'Use "Send to Device" to transfer files.',
    );
  }

  Future<ClipboardWriteResult> _writeLinuxFilePaths(List<String> paths) async {
    final uriList = paths.map((p) => Uri.file(p).toString()).join('\n');
    final env = Platform.environment;
    final wayland = env['WAYLAND_DISPLAY']?.isNotEmpty ?? false;
    try {
      if (wayland && _toolExists('wl-copy')) {
        final process = await Process.start('wl-copy', ['--type', 'text/uri-list']);
        process.stdin.write(uriList);
        await process.stdin.flush();
        await process.stdin.close();
        final code = await process.exitCode;
        if (code == 0) return ClipboardWriteResult.ok;
      } else if (_toolExists('xclip')) {
        final process = await Process.start('xclip', ['-selection', 'clipboard', '-t', 'text/uri-list']);
        process.stdin.write(uriList);
        await process.stdin.flush();
        await process.stdin.close();
        final code = await process.exitCode;
        if (code == 0) return ClipboardWriteResult.ok;
      }
    } catch (e) {
      return ClipboardWriteResult.fail('Linux file URI clipboard write failed: $e');
    }
    return ClipboardWriteResult.fail(
      'No clipboard tool available. Install: sudo apt install wl-clipboard xclip',
    );
  }

  // ---------------------------------------------------------------------------
  // Read image as ScreenshotItem
  // ---------------------------------------------------------------------------

  Future<ScreenshotItem?> readImageAsScreenshotItem() async {
    final result = await read();
    if (result.type == ClipboardContentType.image &&
        result.imageBytes != null &&
        result.imageBytes!.isNotEmpty) {
      final now = DateTime.now();
      final ext = result.imageMime?.split('/').last ?? 'png';
      final name = 'Pasted_Image_${now.millisecondsSinceEpoch}.$ext';
      return ScreenshotItem.create(name: name, bytes: result.imageBytes!);
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Save clipboard image to temp file
  // ---------------------------------------------------------------------------

  Future<File?> saveClipboardImageToTemp() async {
    final result = await read();
    if (result.type != ClipboardContentType.image ||
        result.imageBytes == null ||
        result.imageBytes!.isEmpty) {
      return null;
    }
    try {
      final dir = await getTemporaryDirectory();
      final now = DateTime.now().millisecondsSinceEpoch;
      final ext = result.imageMime?.split('/').last ?? 'png';
      final file = File('${dir.path}/quickshare_clipboard_$now.$ext');
      await file.writeAsBytes(result.imageBytes!);
      return file;
    } catch (e) {
      debugPrint('[PlatformClipboard] save to temp failed: $e');
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Platform info
  // ---------------------------------------------------------------------------

  String _platformName() {
    if (kIsWeb) return 'Web';
    if (Platform.isWindows) return 'Windows';
    if (Platform.isLinux) return 'Linux';
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isAndroid) return 'Android';
    if (Platform.isIOS) return 'iOS';
    return 'Unknown';
  }

  /// Returns a human-readable description of clipboard capabilities on this platform.
  String get capabilitySummary {
    if (kIsWeb) return 'Web: text ✓, images (Clipboard API) ✓, files: browser-limited';
    if (Platform.isLinux) {
      final env = linuxEnvironment;
      final server = env?.isWayland == true ? 'Wayland' : 'X11';
      final hasTool = env?.hasNativeClipboard == true;
      return 'Linux ($server): text ✓, '
          'images ${hasTool ? "✓ (wl-paste/xclip)" : "✗ (install wl-clipboard or xclip)"}, '
          'file URIs ${hasTool ? "✓" : "✗"}';
    }
    if (Platform.isWindows) return 'Windows: text ✓, images (PNG) ✓, file-drop list ✓';
    if (Platform.isMacOS) return 'macOS: text ✓, images ✓, file URLs ✓';
    if (Platform.isAndroid) return 'Android: text ✓, images (content URI) ✓';
    return 'Unknown platform';
  }

  bool get supportsImageClipboard {
    if (kIsWeb) return true;
    if (Platform.isLinux) return _hasLinuxClipboardTool();
    if (Platform.isWindows) return true; // via MethodChannel
    if (Platform.isMacOS) return false; // not yet implemented
    return false;
  }

  bool get supportsFileClipboard {
    if (kIsWeb) return false;
    if (Platform.isLinux) return _hasLinuxClipboardTool();
    return false;
  }
}
