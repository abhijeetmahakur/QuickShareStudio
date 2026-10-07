import 'dart:async';

import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart';

/// Desktop notifications on Linux through org.freedesktop.Notifications, which every
/// desktop (GNOME, KDE, Cinnamon, XFCE, ...) provides on X11 and Wayland alike.
class FreedesktopNotifications {
  FreedesktopNotifications({required this.appName, required this.desktopEntry, this.iconPath, this._client});

  static const _service = 'org.freedesktop.Notifications';
  static final _path = DBusObjectPath('/org/freedesktop/Notifications');

  final String appName;

  /// The .desktop file id (without ".desktop"), so the desktop groups notifications under
  /// QuickShare Studio and uses its icon.
  final String desktopEntry;
  final String? iconPath;

  DBusClient? _client;
  bool _ownsClient = false;
  StreamSubscription<DBusSignal>? _actions;
  final Map<int, VoidCallback> _onClick = {};

  DBusClient get _bus {
    if (_client == null) {
      _client = DBusClient.session();
      _ownsClient = true;
    }
    return _client!;
  }

  /// Shows a notification; [onClick] runs when the user clicks it. Returns false when no
  /// notification service is running.
  Future<bool> show(String title, String body, {VoidCallback? onClick, bool urgent = false}) async {
    try {
      _listen();
      final reply = await _bus.callMethod(
        destination: _service,
        path: _path,
        interface: _service,
        name: 'Notify',
        values: [
          DBusString(appName),
          const DBusUint32(0),
          DBusString(iconPath ?? ''),
          DBusString(title),
          DBusString(body),
          // "default" is the click on the notification itself.
          DBusArray.string(onClick == null ? const [] : const ['default', 'Open']),
          DBusDict.stringVariant({
            'desktop-entry': DBusString(desktopEntry),
            'urgency': DBusByte(urgent ? 2 : 1),
          }),
          const DBusInt32(-1),
        ],
        replySignature: DBusSignature('u'),
      );
      final id = reply.values.first.asUint32();
      if (onClick != null) _onClick[id] = onClick;
      return true;
    } catch (e) {
      debugPrint('[QuickShare] Notification not shown: $e');
      return false;
    }
  }

  void _listen() {
    if (_actions != null) return;
    _actions = DBusSignalStream(_bus, interface: _service, path: _path).listen((signal) {
      if (signal.values.isEmpty) return;
      final id = signal.values[0].asUint32();
      if (signal.name == 'ActionInvoked') {
        _onClick.remove(id)?.call();
      } else if (signal.name == 'NotificationClosed') {
        _onClick.remove(id);
      }
    });
  }

  Future<void> dispose() async {
    await _actions?.cancel();
    _actions = null;
    if (_ownsClient) await _client?.close();
    _client = null;
  }
}
