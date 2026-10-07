import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:provider/provider.dart';
import 'package:quickshare/app/app_navigation.dart';
import 'package:quickshare/core/platform/linux/fallback_file_picker.dart';
import 'package:quickshare/core/platform/native_channels.dart';
import 'package:quickshare/core/services/desktop_integration_io.dart' show desktopEntryFor;
import 'package:quickshare/core/services/ocr_service_io.dart' as ocr;
import 'package:quickshare/core/utils/file_utils.dart';
import 'package:quickshare/data/services/app_update_service.dart';
import 'package:quickshare/data/services/transfer_engine.dart';
import 'package:quickshare/data/services/updater/platform_updater.dart';
import 'package:quickshare/features/clipboard/universal_clipboard_view.dart';
import 'package:quickshare/features/connect/qr_image_decoder.dart';
import 'package:quickshare/features/dashboard/dashboard_screen.dart';
import 'package:quickshare/features/screenshot_collections/screenshot_collections_view.dart';
import 'package:quickshare/features/transfer_history/transfer_history_view.dart';
import 'package:quickshare/transfer/lan/lan_address.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zxing2/qrcode.dart';

/// Renders [text] as a QR code: [scale] pixels per module, a quiet zone, optional inversion
/// (dark-mode screenshots) and a transparent background.
Uint8List qrPng(String text, {int scale = 6, bool inverted = false, bool transparent = false, int padding = 40}) {
  final matrix = Encoder.encode(text, ErrorCorrectionLevel.m).matrix!;
  final size = matrix.width * scale + padding * 2;
  final light = transparent ? img.ColorRgba8(0, 0, 0, 0) : img.ColorRgba8(255, 255, 255, 255);
  final dark = img.ColorRgba8(0, 0, 0, 255);
  final image = img.Image(width: size, height: size, numChannels: 4)..clear(inverted ? dark : light);
  for (var x = 0; x < matrix.width; x++) {
    for (var y = 0; y < matrix.height; y++) {
      if (matrix.get(x, y) == 1) {
        img.fillRect(image,
            x1: padding + x * scale,
            y1: padding + y * scale,
            x2: padding + x * scale + scale - 1,
            y2: padding + y * scale + scale - 1,
            color: inverted ? img.ColorRgba8(255, 255, 255, 255) : dark);
      }
    }
  }
  return img.encodePng(image);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('QR code from an image file', () {
    const payload = 'quickshare://pair?code=482913&n=Zx81_nonce&host=192.168.1.40&port=8088&mode=lan';

    test('decodes a screenshot of the pairing QR code', () {
      expect(QrImageDecoder.decodeSync(qrPng(payload)), payload);
    });

    test('decodes light-on-dark (dark mode) and transparent QR codes', () {
      expect(QrImageDecoder.decodeSync(qrPng(payload, inverted: true)), payload);
      expect(QrImageDecoder.decodeSync(qrPng(payload, transparent: true)), payload);
    });

    test('decodes a large photo-sized image after scaling it down', () {
      expect(QrImageDecoder.decodeSync(qrPng(payload, scale: 40, padding: 400)), payload);
    });

    test('returns null for a picture without a QR code', () {
      final blank = img.encodePng(img.Image(width: 300, height: 200)..clear(img.ColorRgb8(200, 220, 240)));
      expect(QrImageDecoder.decodeSync(blank), isNull);
      expect(QrImageDecoder.decodeSync(Uint8List.fromList([1, 2, 3])), isNull);
    });
  });

  group('LAN address for the QR code and discovery', () {
    test('prefers the Wi-Fi address over Docker, libvirt and VPN bridges', () {
      expect(
        pickLanAddress([
          (interface: 'docker0', address: '172.17.0.1'),
          (interface: 'virbr0', address: '192.168.122.1'),
          (interface: 'tailscale0', address: '100.101.102.103'),
          (interface: 'wlp3s0', address: '192.168.1.42'),
        ]),
        '192.168.1.42',
      );
    });

    test('prefers Ethernet over the Windows WSL adapter', () {
      expect(
        pickLanAddress([
          (interface: 'vEthernet (WSL)', address: '172.28.48.1'),
          (interface: 'Ethernet', address: '10.0.0.15'),
        ]),
        '10.0.0.15',
      );
    });

    test('falls back to a virtual adapter, skips link-local and loopback', () {
      expect(pickLanAddress([(interface: 'docker0', address: '172.17.0.1')]), '172.17.0.1');
      expect(pickLanAddress([(interface: 'eth0', address: '169.254.10.2'), (interface: 'lo', address: '127.0.0.1')]), isNull);
    });
  });

  group('OCR with Tesseract', () {
    test('averages word confidences from the TSV output', () {
      const tsv = 'level\tpage_num\tblock_num\tpar_num\tline_num\tword_num\tleft\ttop\twidth\theight\tconf\ttext\n'
          '1\t1\t0\t0\t0\t0\t0\t0\t800\t600\t-1\t\n'
          '5\t1\t1\t1\t1\t1\t10\t10\t90\t20\t96.5\tQuickShare\n'
          '5\t1\t1\t1\t1\t2\t110\t10\t60\t20\t88.5\tStudio\n'
          '5\t1\t1\t1\t1\t3\t180\t10\t5\t20\t-1\t \n';
      expect(ocr.tsvConfidences(tsv), [96.5, 88.5]);
    });

    test('reads the installed languages', () {
      expect(ocr.parseLanguages('List of available languages in "/usr/share/tessdata/" (3):\neng\nhin\nosd\n'),
          {'eng', 'hin', 'osd'});
    });

    test('install hints name the right package manager', () {
      const mint = 'NAME="Linux Mint"\nID=linuxmint\nID_LIKE="ubuntu debian"\n';
      expect(ocr.linuxInstallCommand(['eng', 'hin'], mint), 'sudo apt install tesseract-ocr tesseract-ocr-eng tesseract-ocr-hin');
      expect(ocr.linuxInstallCommand(['hin'], 'ID=fedora\n'), 'sudo dnf install tesseract tesseract-langpack-hin');
      expect(ocr.linuxInstallCommand(['eng'], 'ID=manjaro\nID_LIKE=arch\n'), 'sudo pacman -S tesseract tesseract-data-eng');
      expect(ocr.linuxInstallCommand(['eng'], 'ID=debian\n'), 'sudo apt install tesseract-ocr tesseract-ocr-eng');
      expect(ocr.linuxInstallCommand(['eng'], 'ID=nixos\n'), contains('package manager'));
    });
  });

  group('Linux desktop integration', () {
    test('the Downloads folder follows user-dirs.dirs', () {
      expect(FileUtils.xdgDownloadDir('/home/ana', userDirs: 'XDG_DOWNLOAD_DIR="\$HOME/Téléchargements"\n'),
          '/home/ana/Téléchargements');
      expect(FileUtils.xdgDownloadDir('/home/ana', userDirs: 'XDG_DESKTOP_DIR="\$HOME/Desktop"\n'), isNull);
      expect(FileUtils.xdgDownloadDir('/home/ana', userDirs: 'XDG_DOWNLOAD_DIR="\$HOME/"\n'), isNull);
    });

    test('the AppImage menu entry quotes paths with spaces and specials', () {
      final entry = desktopEntryFor(r'/home/ana/My Apps/Quick$hare.AppImage');
      expect(entry, contains(r'Exec="/home/ana/My Apps/Quick\$hare.AppImage" %U'));
      expect(entry, contains('Icon=com.quickshare.quickshare'));
      expect(entry, contains('StartupWMClass=com.quickshare.quickshare'));
    });

    test('the dialog-tool fallback filters by the requested file types', () {
      expect(FallbackLinuxFilePicker.extensionsFor(FileType.custom, ['.PNG', 'pdf']), ['png', 'pdf']);
      expect(FallbackLinuxFilePicker.extensionsFor(FileType.image, null), contains('webp'));
      expect(FallbackLinuxFilePicker.extensionsFor(FileType.any, null), isEmpty);
    });
  });

  group('Linux updates pick the package matching the install', () {
    test('each Linux package name is distinct and stable', () {
      expect({linuxAppImageAsset, linuxDebAsset, linuxTarballAsset}, hasLength(3));
      expect(linuxAppImageAsset, 'QuickShareStudio-Linux-x86_64.AppImage');
      expect(linuxDebAsset, 'QuickShareStudio-Linux-x86_64.deb');
      expect(linuxTarballAsset, 'QuickShareStudio-Linux-x86_64.tar.gz');
    });
  });

  group('Back and Esc', () {
    Widget dashboard() {
      final engine = TransferEngine()..stopTimers();
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<TransferEngine>.value(value: engine),
          ChangeNotifierProvider<AppUpdateService>.value(value: AppUpdateService()),
        ],
        child: const MaterialApp(home: DashboardScreen()),
      );
    }

    testWidgets('Esc returns to the previous section, then to the dashboard', (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(dashboard());
      await tester.pump();

      AppNavigation.open(6); // Universal Clipboard
      await tester.pump();
      AppNavigation.open(7); // Transfer History
      await tester.pump();
      expect(find.byType(TransferHistoryView), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.byType(UniversalClipboardView), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.text('PRIMARY ACTIONS & WORKSPACE'), findsOneWidget);

      // On the dashboard Esc does nothing.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.text('PRIMARY ACTIONS & WORKSPACE'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the first Esc leaves a text field instead of the section', (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(dashboard());
      await tester.pump();
      AppNavigation.open(6);
      await tester.pump();

      await tester.tap(find.byType(TextField));
      await tester.pump();
      expect(FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<EditableText>(), isNotNull);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.byType(UniversalClipboardView), findsOneWidget, reason: 'still in the section');
      expect(FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<EditableText>(), isNull);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.text('PRIMARY ACTIONS & WORKSPACE'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('Clipboard images (Linux runner channel)', () {
    final png = img.encodePng(img.Image(width: 64, height: 48)..clear(img.ColorRgb8(40, 200, 90)));
    late List<MethodCall> calls;

    setUp(() {
      calls = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(NativeChannels.desktop,
          (call) async {
        calls.add(call);
        return switch (call.method) {
          'clipboardReadImage' => png,
          'clipboardWriteImage' => true,
          _ => null,
        };
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(NativeChannels.desktop, null);
    });

    test('NativeClipboard reads and writes images through the runner', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      expect(await NativeClipboard.readImage(), png);
      expect(await NativeClipboard.writeImage(png), isTrue);
      expect(calls.map((c) => c.method), ['clipboardReadImage', 'clipboardWriteImage']);
    });

    testWidgets('Ctrl+V pastes the clipboard screenshot into the open session', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final engine = TransferEngine()..stopTimers();
      await tester.pumpWidget(ChangeNotifierProvider<TransferEngine>.value(
        value: engine,
        child: const MaterialApp(home: ScreenshotCollectionsView()),
      ));
      await tester.pump();
      final session = engine.screenshotSessions.first;
      final before = session.screenshots.length;

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      // Decoding the image dimensions gives up after 500 ms in tests.
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));

      expect(calls.map((c) => c.method), contains('clipboardReadImage'));
      expect(engine.screenshotSessions.firstWhere((s) => s.id == session.id).screenshots.length, before + 1);
      expect(find.textContaining('Pasted Pasted_Screenshot_'), findsOneWidget);
      expect(find.byKey(const Key('session_paste_button')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

    testWidgets('Universal Clipboard sends a pasted screenshot as a PNG', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final engine = TransferEngine()..stopTimers();
      engine.pairedDevices.clear();
      final phone = await engine.simulateInstantPair(deviceName: 'Pixel 8');
      await tester.pumpWidget(ChangeNotifierProvider<TransferEngine>.value(
        value: engine,
        child: const MaterialApp(home: UniversalClipboardView()),
      ));
      await tester.pump();

      await tester.tap(find.text('Paste from System Clipboard'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const Key('clipboard_image_preview')), findsOneWidget);
      expect(find.text('Image Preview (sent as PNG):'), findsOneWidget);

      final send = find.widgetWithText(ElevatedButton, 'Send Clipboard to Selected Device');
      await tester.ensureVisible(send);
      await tester.tap(send);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Clipboard image sent to ${phone.name}.'), findsOneWidget);
      expect(engine.activeTransfers.any((t) => t.fileName.startsWith('Clipboard_Image_') && t.fileName.endsWith('.png')),
          isTrue);
      engine.pairedDevices.clear();
      await tester.pumpWidget(const SizedBox());
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
  });
}
