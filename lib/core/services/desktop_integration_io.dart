import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

import '../../app/app_navigation.dart';
import '../platform/linux/fallback_file_picker.dart';
import '../platform/linux/freedesktop_notifications.dart';
import '../platform/linux/status_notifier_tray.dart';
import '../platform/native_channels.dart';
import 'desktop_integration.dart';

/// Matches APPLICATION_ID in linux/CMakeLists.txt and the .desktop file name.
const _appId = 'com.quickshare.quickshare';
const _appName = 'QuickShare Studio';

final ValueNotifier<bool> _trayVisible = ValueNotifier(false);
FreedesktopNotifications? _linuxNotifications;
bool _started = false;
bool _hiddenHintShown = false;
int? _windowsClickSection;

ValueListenable<bool> get trayVisible => _trayVisible;

bool get supportsTray => Platform.isLinux || Platform.isWindows;

// Tray menu entries (ids are shared with the Windows runner's menu).
const _openId = 1;
const _pairingId = 2;
const _receivedId = 3;
const _quitId = 5;

const _menu = [
  TrayMenuItem(_openId, 'Open QuickShare Studio'),
  TrayMenuItem(_pairingId, 'Show pairing code'),
  TrayMenuItem(_receivedId, 'Received files'),
  TrayMenuItem.separator(4),
  TrayMenuItem(_quitId, 'Quit QuickShare Studio'),
];

void configure() {
  if (Platform.isLinux) FallbackLinuxFilePicker.register();
}

Future<void> start() async {
  if (_started || !supportsTray) return;
  _started = true;
  NativeChannels.desktop.setMethodCallHandler(_onNativeCall);
  if (Platform.isLinux) {
    _linuxNotifications = FreedesktopNotifications(appName: _appName, desktopEntry: _appId, iconPath: _bundledIconPath());
    unawaited(_integrateAppImage());
    await _startLinuxTray();
  } else {
    await _startWindowsTray();
  }
}

/// Close-to-tray is only safe while an icon is there to bring the window back.
Future<void> applyCloseToTray() async {
  if (!supportsTray) return;
  final enabled = _trayVisible.value && await DesktopIntegration.closeToTrayEnabled();
  await DesktopWindow.setCloseToTray(enabled);
}

Future<bool> notify(String title, String body, {bool urgent = false, int? openSection}) async {
  void open() {
    unawaited(DesktopWindow.show());
    if (openSection != null) AppNavigation.open(openSection);
  }

  try {
    if (Platform.isLinux) {
      return await (_linuxNotifications ??=
              FreedesktopNotifications(appName: _appName, desktopEntry: _appId, iconPath: _bundledIconPath()))
          .show(title, body, urgent: urgent, onClick: open);
    }
    if (Platform.isWindows) {
      _windowsClickSection = openSection;
      return await NativeChannels.desktop.invokeMethod<bool>('notify', {'title': title, 'body': body}) ?? false;
    }
    if (Platform.isAndroid) {
      return await NativeChannels.android.invokeMethod<bool>('notify', {
            'title': title,
            'body': body,
            'urgent': urgent,
            'section': openSection,
          }) ??
          false;
    }
  } on MissingPluginException {
    return false;
  } catch (e) {
    debugPrint('[QuickShare] Notification failed: $e');
  }
  return false;
}

Future<dynamic> _onNativeCall(MethodCall call) async {
  switch (call.method) {
    case 'windowHidden':
      // Tell people once per run where the app went.
      if (!_hiddenHintShown) {
        _hiddenHintShown = true;
        await notify('$_appName is still running',
            'It keeps receiving files in the background. Use the tray icon to open it or to quit.');
      }
    case 'trayMenu':
      _onMenuItem(call.arguments as int);
    case 'notificationClicked':
      final section = _windowsClickSection;
      _windowsClickSection = null;
      if (section != null) AppNavigation.open(section);
  }
  return null;
}

void _onMenuItem(int id) {
  switch (id) {
    case _openId:
      unawaited(DesktopWindow.show());
    case _pairingId:
      unawaited(DesktopWindow.show());
      AppNavigation.open(AppNavigation.pairing);
    case _receivedId:
      unawaited(DesktopWindow.show());
      AppNavigation.open(AppNavigation.received);
    case _quitId:
      unawaited(DesktopWindow.quit());
  }
}

Future<void> _startLinuxTray() async {
  List<TrayPixmap> pixmaps = const [];
  try {
    final logo = await rootBundle.load('assets/logo.png');
    pixmaps = await compute(_trayPixmaps, logo.buffer.asUint8List(logo.offsetInBytes, logo.lengthInBytes));
  } catch (e) {
    debugPrint('[QuickShare] Tray icon image unavailable: $e');
  }
  final tray = StatusNotifierTray(
    id: 'quickshare-studio',
    title: _appName,
    tooltip: 'Ready to receive files',
    pixmaps: pixmaps,
    menu: _menu,
    onActivate: () => unawaited(DesktopWindow.show()),
    onMenuItem: _onMenuItem,
    onHostChanged: (visible) {
      _trayVisible.value = visible;
      unawaited(applyCloseToTray());
      // The tray went away while the window was hidden: show it, or it would be unreachable.
      if (!visible) unawaited(DesktopWindow.show());
    },
  );
  // The session bus keeps the exported tray objects alive for the life of the app.
  _trayVisible.value = await tray.start();
  await applyCloseToTray();
}

Future<void> _startWindowsTray() async {
  try {
    final ok = await NativeChannels.desktop.invokeMethod<bool>('trayCreate', {
          'tooltip': _appName,
          'items': [
            for (final item in _menu) {'id': item.id, 'label': item.label ?? ''},
          ],
        }) ??
        false;
    _trayVisible.value = ok;
  } on MissingPluginException {
    _trayVisible.value = false;
  } catch (e) {
    debugPrint('[QuickShare] Tray unavailable: $e');
    _trayVisible.value = false;
  }
  await applyCloseToTray();
}

/// ARGB32 pixmaps of the logo in the sizes tray hosts ask for.
List<TrayPixmap> _trayPixmaps(Uint8List png) {
  final logo = img.decodePng(png);
  if (logo == null) return const [];
  return [
    for (final size in const [16, 22, 24, 32, 48, 64, 128])
      TrayPixmap(
        size,
        img
            .copyResize(logo, width: size, height: size, interpolation: img.Interpolation.average)
            .convert(numChannels: 4)
            .getBytes(order: img.ChannelOrder.argb),
      ),
  ];
}

/// The window icon the runner installs next to the executable (data/app_icon.png).
String? _bundledIconPath() {
  final icon = File('${File(Platform.resolvedExecutable).parent.path}/data/app_icon.png');
  return icon.existsSync() ? icon.path : null;
}

/// An AppImage is a single file nobody installed: add it to the application menu (with its
/// icon) for this user, the way AppImage integration tools do. The entry follows the file
/// when it is moved, and updates replace the file in place.
Future<void> _integrateAppImage() async {
  final appImage = Platform.environment['APPIMAGE'];
  final home = Platform.environment['HOME'];
  if (appImage == null || appImage.isEmpty || home == null) return;
  try {
    final dataHome = Platform.environment['XDG_DATA_HOME'] ?? '$home/.local/share';
    final icon = File('$dataHome/icons/hicolor/256x256/apps/$_appId.png');
    if (!icon.existsSync()) {
      final logo = await rootBundle.load('assets/logo.png');
      final png = await compute(_resizedPng, logo.buffer.asUint8List(logo.offsetInBytes, logo.lengthInBytes));
      await icon.parent.create(recursive: true);
      await icon.writeAsBytes(png);
    }
    final entry = desktopEntryFor(appImage);
    final desktop = File('$dataHome/applications/$_appId.desktop');
    if (!desktop.existsSync() || desktop.readAsStringSync() != entry) {
      await desktop.parent.create(recursive: true);
      await desktop.writeAsString(entry);
    }
  } catch (e) {
    debugPrint('[QuickShare] Could not add the AppImage to the application menu: $e');
  }
}

Uint8List _resizedPng(Uint8List png) =>
    img.encodePng(img.copyResize(img.decodePng(png)!, width: 256, height: 256, interpolation: img.Interpolation.average));

/// The .desktop entry that launches [appImage] (quoted per the Desktop Entry spec).
@visibleForTesting
String desktopEntryFor(String appImage) {
  final quoted = appImage.replaceAllMapped(RegExp(r'["`$\\]'), (m) => '\\${m[0]}');
  return '''[Desktop Entry]
Type=Application
Name=$_appName
GenericName=File Sharing
Comment=Share files, clipboard and PDFs between your devices
Exec="$quoted" %U
TryExec=$appImage
Icon=$_appId
Terminal=false
Categories=Utility;Network;FileTransfer;
Keywords=share;transfer;pdf;clipboard;qr;
StartupWMClass=$_appId
StartupNotify=true
X-AppImage-Integrate=false
''';
}
