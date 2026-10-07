// Real Linux desktop checks, run by .github/workflows/linux.yml on X11 (Xvfb) and on Wayland
// (headless sway) with the app built by `flutter test -d linux`:
//
//  - the system clipboard: text with real Ctrl+V / Ctrl+C / Ctrl+X key presses in a text field,
//    and images (read, write, Ctrl+V into Screenshot Sessions), checked against xclip or
//    wl-clipboard, the tools other apps use;
//  - the runner's window channel (hide/show for the tray);
//  - notifications and the tray icon over D-Bus, against stand-in services on the test bus;
//  - OCR with Tesseract.
//
//   dbus-run-session -- xvfb-run -a flutter test integration_test/linux_desktop_test.dart -d linux
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:quickshare/core/platform/linux/freedesktop_notifications.dart';
import 'package:quickshare/core/platform/linux/status_notifier_tray.dart';
import 'package:quickshare/core/platform/native_channels.dart';
import 'package:quickshare/core/services/ocr_service.dart';
import 'package:quickshare/data/services/transfer_engine.dart';
import 'package:quickshare/features/screenshot_collections/screenshot_collections_view.dart';

final bool wayland = Platform.environment['GDK_BACKEND'] == 'wayland';
final String session = wayland ? 'Wayland' : 'X11';

/// The clipboard as every other app sees it, through xclip (X11) or wl-clipboard (Wayland).
class SystemClipboard {
  static Future<void> setText(String text) async {
    final p = wayland ? await Process.start('wl-copy', []) : await Process.start('xclip', ['-selection', 'clipboard', '-in']);
    p.stdin.add(utf8.encode(text));
    await p.stdin.close();
    await p.exitCode.timeout(const Duration(seconds: 5));
  }

  static Future<String> getText() async {
    final r = wayland
        ? await Process.run('wl-paste', ['--no-newline'], stdoutEncoding: utf8)
        : await Process.run('xclip', ['-selection', 'clipboard', '-o'], stdoutEncoding: utf8);
    return r.stdout as String;
  }

  static Future<void> setImage(String pngPath) async {
    final p = wayland
        ? await Process.start('sh', ['-c', 'wl-copy --type image/png < "\$0"', pngPath])
        : await Process.start('xclip', ['-selection', 'clipboard', '-t', 'image/png', '-i', pngPath]);
    await p.exitCode.timeout(const Duration(seconds: 5));
  }

  static Future<Uint8List> getImage() async {
    final r = wayland
        ? await Process.run('wl-paste', ['--type', 'image/png'], stdoutEncoding: null)
        : await Process.run('xclip', ['-selection', 'clipboard', '-t', 'image/png', '-o'], stdoutEncoding: null);
    return Uint8List.fromList(r.stdout as List<int>);
  }

  /// Presses a shortcut like a person would: real key events from the window system.
  static Future<void> press(String key, {bool ctrl = true}) async {
    if (wayland) {
      await _run('wtype', [if (ctrl) ...['-M', 'ctrl'], key, if (ctrl) ...['-m', 'ctrl']]);
    } else {
      await _focusWindow();
      await _run('xdotool', ['key', '--clearmodifiers', ctrl ? 'ctrl+$key' : key]);
    }
  }

  /// Without a window manager X11 does not focus new windows by itself.
  static Future<void> _focusWindow() async {
    final search = await Process.run('xdotool', ['search', '--sync', '--onlyvisible', '--name', 'QuickShare Studio']);
    final id = (search.stdout as String).trim().split('\n').first;
    await _run('xdotool', ['windowfocus', '--sync', id]);
  }

  static Future<void> _run(String exe, List<String> args) async {
    final r = await Process.run(exe, args);
    if (r.exitCode != 0) throw StateError('$exe ${args.join(' ')} failed: ${r.stderr}');
  }
}

/// Pumps frames until [check] holds (the clipboard and key events are real, so they take real time).
Future<void> eventually(WidgetTester tester, FutureOr<bool> Function() check, String what,
    {Duration timeout = const Duration(seconds: 20)}) async {
  final end = DateTime.now().add(timeout);
  while (true) {
    await tester.pump(const Duration(milliseconds: 50));
    if (await check()) return;
    if (DateTime.now().isAfter(end)) fail('$session: timed out waiting for $what');
    await Future<void>.delayed(const Duration(milliseconds: 150));
  }
}

/// A stand-in notification daemon on the test session bus.
class _NotificationServer extends DBusObject {
  _NotificationServer() : super(DBusObjectPath('/org/freedesktop/Notifications'));
  final calls = <List<DBusValue>>[];

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall call) async {
    switch (call.name) {
      case 'Notify':
        calls.add(call.values);
        return DBusMethodSuccessResponse([DBusUint32(calls.length)]);
      case 'GetCapabilities':
        return DBusMethodSuccessResponse([DBusArray.string(['actions', 'body'])]);
      default:
        return DBusMethodErrorResponse.unknownMethod();
    }
  }
}

/// A stand-in system tray (what a panel runs) on the test session bus.
class _Watcher extends DBusObject {
  _Watcher() : super(DBusObjectPath('/StatusNotifierWatcher'));
  final registered = <String>[];

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall call) async {
    if (call.name == 'RegisterStatusNotifierItem') {
      registered.add(call.values.first.asString());
      return DBusMethodSuccessResponse();
    }
    return DBusMethodErrorResponse.unknownMethod();
  }
}

Future<Uint8List> _renderText(String text) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(const Rect.fromLTWH(0, 0, 1000, 220), Paint()..color = Colors.white);
  final painter = TextPainter(
    text: TextSpan(text: text, style: const TextStyle(fontSize: 56, color: Colors.black)),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: 960);
  painter.paint(canvas, const Offset(30, 60));
  final image = await recorder.endRecording().toImage(1000, 220);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  return bytes!.buffer.asUint8List();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final random = Random();

  testWidgets('text fields: real Ctrl+V, Ctrl+C and Ctrl+X use the system clipboard', (tester) async {
    final controller = TextEditingController();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Center(child: SizedBox(width: 500, child: TextField(controller: controller, autofocus: true)))),
    ));
    await tester.pumpAndSettle();

    final text = 'QuickShare $session clipboard ${random.nextInt(1 << 30)} ✓';
    await SystemClipboard.setText(text);
    await SystemClipboard.press('v');
    await eventually(tester, () => controller.text == text, 'Ctrl+V to paste "$text"');
    debugPrint('[$session] Ctrl+V pasted text from another app');

    await SystemClipboard.press('a');
    await SystemClipboard.setText('placeholder');
    await SystemClipboard.press('c');
    await eventually(tester, () async => await SystemClipboard.getText() == text, 'Ctrl+C to copy for other apps');
    debugPrint('[$session] Ctrl+C copied text that other apps read');

    await SystemClipboard.setText('placeholder');
    await SystemClipboard.press('x');
    await eventually(tester, () => controller.text.isEmpty, 'Ctrl+X to cut');
    expect(await SystemClipboard.getText(), text);
    debugPrint('[$session] Ctrl+X cut text that other apps read');
  });

  testWidgets('clipboard images: read, Ctrl+V into Screenshot Sessions, and copy out', (tester) async {
    final shot = img.encodePng(img.Image(width: 320, height: 200)..clear(img.ColorRgb8(30, 144, 255)));
    final file = File('${Directory.systemTemp.path}/qs_clip_$pid.png')..writeAsBytesSync(shot);
    await SystemClipboard.setImage(file.path);

    final read = await NativeClipboard.readImage();
    expect(read, isNotNull, reason: '$session: the screenshot on the clipboard is readable');
    final decoded = img.decodePng(read!)!;
    expect([decoded.width, decoded.height], [320, 200]);
    debugPrint('[$session] read a 320x200 clipboard image');

    final engine = TransferEngine()..stopTimers();
    await tester.pumpWidget(ChangeNotifierProvider<TransferEngine>.value(
      value: engine,
      child: const MaterialApp(home: ScreenshotCollectionsView()),
    ));
    await tester.pumpAndSettle();
    final sessionId = engine.screenshotSessions.first.id;
    int count() => engine.screenshotSessions.firstWhere((s) => s.id == sessionId).screenshots.length;
    final before = count();
    await SystemClipboard.press('v');
    await eventually(tester, () => count() == before + 1, 'Ctrl+V to paste the screenshot into the session');
    final pasted = engine.screenshotSessions.firstWhere((s) => s.id == sessionId).screenshots.last;
    expect([pasted.width, pasted.height], [320, 200]);
    debugPrint('[$session] Ctrl+V pasted the screenshot into Screenshot Sessions');

    final out = img.encodePng(img.Image(width: 120, height: 90)..clear(img.ColorRgb8(200, 40, 40)));
    expect(await NativeClipboard.writeImage(out), isTrue);
    await eventually(tester, () async {
      try {
        return img.decodePng(await SystemClipboard.getImage())?.width == 120;
      } catch (_) {
        return false;
      }
    }, 'other apps to read the copied image');
    debugPrint('[$session] copied an image that other apps read');
    file.deleteSync();
  });

  testWidgets('the runner hides and shows the window for the tray', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('window'))));
    await tester.pumpAndSettle();
    Future<bool> visible() async => await NativeChannels.desktop.invokeMethod<bool>('windowIsVisible') ?? false;
    expect(await visible(), isTrue);
    await DesktopWindow.hide();
    expect(await visible(), isFalse);
    await DesktopWindow.show();
    expect(await visible(), isTrue);
    await DesktopWindow.setCloseToTray(false);
    debugPrint('[$session] window hide/show works');
  });

  testWidgets('notifications reach org.freedesktop.Notifications and clicks come back', (tester) async {
    final bus = DBusClient.session();
    final server = _NotificationServer();
    await bus.requestName('org.freedesktop.Notifications');
    await bus.registerObject(server);
    final clicked = Completer<void>();
    final notifications = FreedesktopNotifications(appName: 'QuickShare Studio', desktopEntry: 'com.quickshare.quickshare');

    final shown = await notifications.show('Pixel 8 wants to send you 2 files', '20.0 MB. Open QuickShare Studio to accept.',
        urgent: true, onClick: clicked.complete);
    expect(shown, isTrue);
    final call = server.calls.single;
    expect(call[0].asString(), 'QuickShare Studio');
    expect(call[3].asString(), 'Pixel 8 wants to send you 2 files');
    expect(call[5].asStringArray(), contains('default'));
    final hints = call[6].asStringVariantDict();
    expect(hints['desktop-entry']?.asString(), 'com.quickshare.quickshare');
    expect(hints['urgency']?.asByte(), 2);

    await server.emitSignal('org.freedesktop.Notifications', 'ActionInvoked', [const DBusUint32(1), const DBusString('default')]);
    await clicked.future.timeout(const Duration(seconds: 5));
    debugPrint('[$session] notification shown and its click handled');
    await notifications.dispose();
    await bus.close();
  });

  testWidgets('the tray icon registers with the panel and serves its menu', (tester) async {
    final bus = DBusClient.session();
    final watcher = _Watcher();
    await bus.requestName(StatusNotifierTray.watcherName);
    await bus.registerObject(watcher);
    var activated = 0;
    final clicked = <int>[];
    final tray = StatusNotifierTray(
      id: 'quickshare-studio',
      title: 'QuickShare Studio',
      tooltip: 'Ready to receive files',
      pixmaps: [TrayPixmap(16, Uint8List(16 * 16 * 4))],
      menu: const [
        TrayMenuItem(1, 'Open QuickShare Studio'),
        TrayMenuItem.separator(4),
        TrayMenuItem(5, 'Quit QuickShare Studio'),
      ],
      onActivate: () => activated++,
      onMenuItem: clicked.add,
    );
    expect(await tray.start(), isTrue);
    expect(watcher.registered.single, 'org.kde.StatusNotifierItem-$pid-1');

    final item = DBusRemoteObject(bus, name: watcher.registered.single, path: DBusObjectPath('/StatusNotifierItem'));
    expect((await item.getProperty('org.kde.StatusNotifierItem', 'Title')).asString(), 'QuickShare Studio');
    expect((await item.getProperty('org.kde.StatusNotifierItem', 'Menu')).asObjectPath().value, '/MenuBar');
    expect((await item.getProperty('org.kde.StatusNotifierItem', 'IconPixmap')).asArray(), isNotEmpty);
    await item.callMethod('org.kde.StatusNotifierItem', 'Activate', [const DBusInt32(0), const DBusInt32(0)],
        replySignature: DBusSignature(''));
    expect(activated, 1);

    final menu = DBusRemoteObject(bus, name: watcher.registered.single, path: DBusObjectPath('/MenuBar'));
    final layout = await menu.callMethod('com.canonical.dbusmenu', 'GetLayout',
        [const DBusInt32(0), const DBusInt32(-1), DBusArray.string(const [])],
        replySignature: DBusSignature('u(ia{sv}av)'));
    final children = layout.values[1].asStruct()[2].asArray().map((v) => v.asVariant().asStruct()).toList();
    final labels = [for (final c in children) c[1].asStringVariantDict()['label']?.asString()];
    expect(labels, ['Open QuickShare Studio', null, 'Quit QuickShare Studio']);
    await menu.callMethod('com.canonical.dbusmenu', 'Event',
        [const DBusInt32(5), const DBusString('clicked'), const DBusVariant(DBusInt32(0)), const DBusUint32(0)],
        replySignature: DBusSignature(''));
    expect(clicked, [5]);
    debugPrint('[$session] tray icon registered; menu ${labels.whereType<String>().join(' / ')}');
    await tray.stop();
    await bus.close();
  });

  testWidgets('OCR reads text from a screenshot with Tesseract', (tester) async {
    final status = await OcrService.availability('eng+hin');
    expect(status.ready, isTrue, reason: status.hint);
    final result = await OcrService.recognize([await _renderText('QuickShare Studio OCR 2026')], 'eng');
    expect(result.text, contains('QuickShare'));
    expect(result.pdfPages.single.sublist(0, 5), '%PDF-'.codeUnits);
    expect(result.confidence, greaterThan(50));
    debugPrint('[$session] OCR: "${result.text.trim()}" (${result.confidence.round()}%) with ${status.engine}');
  }, skip: kIsWeb);
}
