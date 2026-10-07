import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

/// What the platform runners add on top of Flutter: clipboard images and window control.
///
/// Linux (linux/runner/desktop_channel.cc) and Windows (windows/runner/desktop_channel.cpp)
/// answer on "quickshare/desktop"; Android answers the clipboard calls on
/// "quickshare/system" (SystemBridge.kt). Every call degrades to a no-op where it is missing
/// (web, tests), so callers never need platform checks.
class NativeChannels {
  NativeChannels._();

  static const MethodChannel desktop = MethodChannel('quickshare/desktop');
  static const MethodChannel android = MethodChannel('quickshare/system');

  static bool get isDesktop =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.linux || defaultTargetPlatform == TargetPlatform.windows);

  static bool get isAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
}

/// Images on the system clipboard (text goes through Flutter's own [Clipboard]).
class NativeClipboard {
  NativeClipboard._();

  static MethodChannel? get _channel => NativeChannels.isDesktop
      ? NativeChannels.desktop
      : NativeChannels.isAndroid
          ? NativeChannels.android
          : null;

  static bool get supportsImages => _channel != null;

  /// The image on the clipboard as PNG bytes, or null when it holds no image.
  static Future<Uint8List?> readImage() async {
    final channel = _channel;
    if (channel == null) return null;
    try {
      final bytes = await channel.invokeMethod<Uint8List>('clipboardReadImage');
      if (bytes == null || bytes.isEmpty) return null;
      return isPng(bytes) ? bytes : await compute(_toPng, bytes);
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      debugPrint('[QuickShare] Clipboard image unavailable: ${e.message}');
      return null;
    }
  }

  /// Puts an image (PNG, JPEG, BMP, ...) on the clipboard. Returns whether it worked.
  static Future<bool> writeImage(Uint8List bytes) async {
    final channel = _channel;
    if (channel == null) return false;
    try {
      return await channel.invokeMethod<bool>('clipboardWriteImage', bytes) ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (e) {
      debugPrint('[QuickShare] Could not copy the image: ${e.message}');
      return false;
    }
  }

  static bool isPng(Uint8List b) =>
      b.length > 8 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47;

  /// Windows hands over device-independent bitmaps (BMP); everything else stays PNG.
  static Uint8List? _toPng(Uint8List bytes) {
    try {
      final decoded = img.decodeImage(bytes);
      return decoded == null ? null : img.encodePng(decoded);
    } catch (_) {
      return null;
    }
  }
}

/// The desktop window and its close-to-tray behaviour.
class DesktopWindow {
  DesktopWindow._();

  static Future<void> _call(String method, [Object? args]) async {
    if (!NativeChannels.isDesktop) return;
    try {
      await NativeChannels.desktop.invokeMethod<void>(method, args);
    } on MissingPluginException {
      // Older runner or a test: nothing to control.
    } on PlatformException catch (e) {
      debugPrint('[QuickShare] $method failed: ${e.message}');
    }
  }

  /// Shows the window (also when it is hidden in the tray) and brings it to the front.
  static Future<void> show() => _call('windowShow');

  static Future<void> hide() => _call('windowHide');

  /// When on, closing the window keeps QuickShare running in the system tray.
  static Future<void> setCloseToTray(bool enabled) => _call('setCloseToTray', enabled);

  /// Quits for real (the tray menu's Quit).
  static Future<void> quit() => _call('quit');
}
