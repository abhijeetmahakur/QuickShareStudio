import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'desktop_integration_io.dart' if (dart.library.js_interop) 'desktop_integration_web.dart' as impl;

/// The operating system around the app: the system tray, OS notifications and "keep running
/// when the window is closed".
///
/// Linux uses D-Bus (StatusNotifierItem tray, org.freedesktop.Notifications), Windows its
/// runner (notification-area icon and balloons), Android the SystemBridge notification.
/// Everything is a no-op where the platform has no such thing (web, tests).
class DesktopIntegration {
  DesktopIntegration._();

  static const closeToTrayKey = 'close_to_tray';

  /// Before runApp: platform plug-ins that must be swapped in early (the Linux file chooser).
  static void configure() => impl.configure();

  /// After runApp: tray icon and notification click handling.
  static Future<void> start() => impl.start();

  /// Shows an OS notification. Clicking it brings the window back and, with [openSection],
  /// opens that dashboard section. Returns false when nothing could be shown.
  static Future<bool> notify(String title, String body, {bool urgent = false, int? openSection}) =>
      impl.notify(title, body, urgent: urgent, openSection: openSection);

  /// Whether a tray icon is currently shown (closing the window then keeps the app running).
  static ValueListenable<bool> get trayVisible => impl.trayVisible;

  /// Whether this platform has a system tray at all.
  static bool get supportsTray => impl.supportsTray;

  /// The "keep running in the tray when closed" preference (on by default).
  static Future<bool> closeToTrayEnabled() async {
    try {
      return (await SharedPreferences.getInstance()).getBool(closeToTrayKey) ?? true;
    } catch (_) {
      return true;
    }
  }

  static Future<void> setCloseToTray(bool enabled) async {
    try {
      await (await SharedPreferences.getInstance()).setBool(closeToTrayKey, enabled);
    } catch (_) {}
    await impl.applyCloseToTray();
  }
}
