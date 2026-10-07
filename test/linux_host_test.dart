@TestOn('linux')
library;

import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickshare/core/platform/linux/fallback_file_picker.dart';
import 'package:quickshare/data/services/updater/platform_updater_io.dart';

/// A portal that is not running (no xdg-desktop-portal on the session bus).
final class _MissingPortal extends FilePickerPlatform {
  int calls = 0;

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
  }) async {
    calls++;
    throw DBusServiceUnknownException(DBusMethodErrorResponse('org.freedesktop.DBus.Error.ServiceUnknown',
        [const DBusString('The name org.freedesktop.portal.Desktop was not provided by any .service files')]));
  }

  @override
  Future<String?> getDirectoryPath({
    String? dialogTitle,
    String? initialDirectory,
    AndroidOptions androidOptions = const AndroidOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    calls++;
    throw const SocketException('No session bus');
  }
}

Future<void> _waitFor(bool Function() condition, String what) async {
  for (var i = 0; i < 100 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  expect(condition(), isTrue, reason: what);
}

void main() {
  late Directory tmp;
  setUp(() async => tmp = await Directory.systemTemp.createTemp('qs_linux_'));
  tearDown(() async => tmp.delete(recursive: true));

  group('file chooser without a desktop portal', () {
    Future<File> fakeTool(String name, String script) async {
      final bin = Directory('${tmp.path}/bin')..createSync();
      final tool = File('${bin.path}/$name')..writeAsStringSync('#!/bin/sh\n$script\n');
      await Process.run('chmod', ['+x', tool.path]);
      return tool;
    }

    test('falls back to zenity and returns the chosen files', () async {
      final a = File('${tmp.path}/Lab 1.png')..writeAsBytesSync([1, 2, 3]);
      final b = File('${tmp.path}/notes.pdf')..writeAsBytesSync([4, 5]);
      // Records its arguments and "chooses" two files.
      await fakeTool('zenity', 'printf "%s\\n" "\$@" > "${tmp.path}/args"\nprintf "%s\\n%s\\n" "${a.path}" "${b.path}"');
      final portal = _MissingPortal();
      final picker = FallbackLinuxFilePicker(portal, environment: {'PATH': '${tmp.path}/bin', 'HOME': tmp.path});

      final files = await picker.pickFiles(type: FileType.custom, allowedExtensions: ['png', 'pdf']);
      expect(files.map((f) => f.path), [a.path, b.path]);
      expect(await files.first.readAsBytes(), [1, 2, 3]);
      final args = File('${tmp.path}/args').readAsStringSync();
      expect(args, contains('--file-selection'));
      expect(args, contains('--multiple'));
      expect(args, contains('--file-filter=Supported files | *.png *.pdf'));

      // The missing portal is remembered: the next dialog goes straight to zenity.
      await picker.pickFiles();
      expect(portal.calls, 1);
    });

    test('a cancelled dialog returns nothing', () async {
      await fakeTool('zenity', 'exit 1');
      final picker = FallbackLinuxFilePicker(_MissingPortal(), environment: {'PATH': '${tmp.path}/bin', 'HOME': tmp.path});
      expect(await picker.pickFiles(), isEmpty);
    });

    test('KDE uses kdialog for folders', () async {
      await fakeTool('kdialog', 'echo "${tmp.path}"');
      await fakeTool('zenity', 'echo /wrong');
      final picker = FallbackLinuxFilePicker(_MissingPortal(),
          environment: {'PATH': '${tmp.path}/bin', 'HOME': tmp.path, 'XDG_CURRENT_DESKTOP': 'KDE'});
      expect(await picker.getDirectoryPath(), tmp.path);
    });

    test('without any dialog tool it explains what to install', () async {
      final picker = FallbackLinuxFilePicker(_MissingPortal(), environment: {'PATH': '${tmp.path}/empty', 'HOME': tmp.path});
      await expectLater(picker.pickFiles(), throwsA(isA<FileSystemException>()
          .having((e) => e.message, 'message', contains('xdg-desktop-portal-gtk'))));
    });
  });

  group('in-app updates', () {
    test('the AppImage is replaced after the app exits, then started again', () async {
      final marker = File('${tmp.path}/started');
      final target = File('${tmp.path}/QuickShare Studio.AppImage')..writeAsStringSync('#!/bin/sh\necho old\n');
      final download = File('${tmp.path}/new.AppImage')
        ..writeAsStringSync('#!/bin/sh\necho "new \$APPIMAGE" > "${marker.path}"\n');
      final script = File('${tmp.path}/update.sh')..writeAsStringSync(linuxUpdateScript(LinuxInstallKind.appImage));
      final app = await Process.start('sleep', ['1']); // stands in for the running app
      final run = await Process.run('sh', [script.path, '${app.pid}', download.path, target.path],
          environment: {'APPIMAGE': '/tmp/.mount_old/AppRun'});
      expect(run.exitCode, 0, reason: '${run.stderr}');
      expect(await app.exitCode, 0, reason: 'the script waited for the app to exit');
      expect(target.readAsStringSync(), contains('new'));
      expect(download.existsSync(), isFalse);
      expect((await Process.run('test', ['-x', target.path])).exitCode, 0, reason: 'executable');
      await _waitFor(marker.existsSync, 'the new version was started');
      // Started without the old AppImage's variables.
      expect(marker.readAsStringSync().trim(), 'new');
    });

    test('the tarball folder is swapped for the new version, then started again', () async {
      final install = Directory('${tmp.path}/QuickShareStudio-Linux-x86_64')..createSync();
      File('${install.path}/quickshare').writeAsStringSync('#!/bin/sh\necho old\n');
      Directory('${install.path}/lib').createSync();
      final staging = Directory('${tmp.path}/.quickshare-update-1')..createSync();
      final bundle = Directory('${staging.path}/QuickShareStudio-Linux-x86_64')..createSync();
      final marker = File('${tmp.path}/started');
      File('${bundle.path}/quickshare').writeAsStringSync('#!/bin/sh\necho new > "${marker.path}"\n');
      await Process.run('chmod', ['+x', '${bundle.path}/quickshare']);
      Directory('${bundle.path}/lib').createSync();
      final download = File('${tmp.path}/QuickShareStudio-Linux-x86_64.tar.gz')..writeAsBytesSync([0]);
      final script = File('${tmp.path}/update.sh')..writeAsStringSync(linuxUpdateScript(LinuxInstallKind.tarball));
      final app = await Process.start('sleep', ['1']);
      final run = await Process.run('sh', [script.path, '${app.pid}', install.path, bundle.path, staging.path, download.path]);
      expect(run.exitCode, 0, reason: '${run.stderr}');
      expect(File('${install.path}/quickshare').readAsStringSync(), contains('new'));
      expect(Directory('${install.path}.old').existsSync(), isFalse);
      expect(staging.existsSync(), isFalse);
      expect(download.existsSync(), isFalse);
      await _waitFor(marker.existsSync, 'the new version was started');
    });
  });
}
