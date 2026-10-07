
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../../transfer/protocol/streaming_sha256.dart';
import '../../models/app_update_info.dart';
import 'platform_updater.dart';

bool get canSelfUpdate =>
    Platform.isAndroid || Platform.isWindows || (Platform.isLinux && (Platform.environment['APPIMAGE']?.isNotEmpty ?? false));

const _system = MethodChannel('quickshare/system');

Future<InstallResult> downloadAndInstall(AppUpdateInfo update, void Function(double progress) onProgress) async {
  final url = update.packageUrl;
  if (Platform.isWindows) {
    if (url.isEmpty) {
      return const InstallResult(false, 'Opening release download page...', openReleasePage: true);
    }
    final dir = Directory('${(await getTemporaryDirectory()).path}${Platform.pathSeparator}updates');
    await dir.create(recursive: true);
    final rawName = Uri.parse(url).pathSegments.isNotEmpty
        ? Uri.parse(url).pathSegments.last
        : 'QuickShareStudio-${update.version}.exe';
    final safeName = rawName.replaceAll(RegExp(r'[^\w\.\-]'), '_');
    final file = File('${dir.path}${Platform.pathSeparator}$safeName');

    final client = http.Client();
    try {
      final response = await client.send(http.Request('GET', Uri.parse(url)));
      if (response.statusCode != 200) {
        return const InstallResult(false, 'Download failed. Opening release page...', openReleasePage: true);
      }
      final total = response.contentLength ?? update.packageSizeBytes;
      final sink = file.openWrite();
      final hash = StreamingSha256();
      var received = 0;
      await for (final chunk in response.stream) {
        sink.add(chunk);
        hash.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress(received / total);
      }
      await sink.close();
      if (update.packageSha256.isNotEmpty && hash.finish() != update.packageSha256.toLowerCase()) {
        try { await file.delete(); } catch (_) {}
        return const InstallResult(false, 'The download was damaged (checksum mismatch). Opening release page...',
            openReleasePage: true);
      }
    } catch (_) {
      return const InstallResult(false, 'Download interrupted. Opening release page...', openReleasePage: true);
    } finally {
      client.close();
    }

    // Launch downloaded installer or package and close the app
    try {
      if (file.path.toLowerCase().endsWith('.exe')) {
        await Process.start(file.path, [], mode: ProcessStartMode.detached);
      } else {
        await Process.start('explorer.exe', ['/select,', file.path], mode: ProcessStartMode.detached);
      }
      // Give the OS detached process a brief moment, then close this app
      Future.delayed(const Duration(milliseconds: 600), () => exit(0));
      return const InstallResult(true, 'Update downloaded! Launching installer and closing app...');
    } catch (_) {
      return const InstallResult(false, 'Could not launch installer. Opening release page...', openReleasePage: true);
    }
  }

  if (Platform.isLinux) {
    if (url.isEmpty || update.packageSha256.isEmpty) {
      return const InstallResult(false, 'This release has no verified Linux AppImage.', openReleasePage: true);
    }
    final appImagePath = Platform.environment['APPIMAGE'];
    if (appImagePath == null || appImagePath.isEmpty) {
      return const InstallResult(false, 'Download the Linux AppImage from the release page.', openReleasePage: true);
    }
    final dir = Directory('${(await getTemporaryDirectory()).path}${Platform.pathSeparator}updates');
    await dir.create(recursive: true);
    final file = File('${dir.path}${Platform.pathSeparator}QuickShareStudio-${update.version}.AppImage');
    final client = http.Client();
    try {
      final response = await client.send(http.Request('GET', Uri.parse(url)));
      if (response.statusCode != 200) {
        return InstallResult(false, 'Download failed (HTTP ${response.statusCode}). Check your connection and retry.');
      }
      final total = response.contentLength ?? update.packageSizeBytes;
      final sink = file.openWrite();
      final hash = StreamingSha256();
      var received = 0;
      await for (final chunk in response.stream) {
        sink.add(chunk);
        hash.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress(received / total);
      }
      await sink.close();
      if (hash.finish() != update.packageSha256.toLowerCase()) {
        await file.delete();
        return const InstallResult(false, 'The download was damaged (checksum mismatch) and was deleted. Please retry.');
      }
    } catch (_) {
      return const InstallResult(false, 'Download interrupted. Check your connection and retry.');
    } finally {
      client.close();
    }

    try {
      final target = File(appImagePath);
      final probe = File('${target.path}.quickshare-write-check-$pid');
      await probe.writeAsBytes(const []);
      await probe.delete();
      final script = File('${dir.path}${Platform.pathSeparator}install-appimage-update.sh');
      await script.writeAsString(r'''#!/bin/sh
set -eu
app_pid="$1"
download="$2"
target="$3"
staged="${target}.quickshare-update"
while kill -0 "$app_pid" 2>/dev/null; do sleep 1; done
cp "$download" "$staged"
chmod 755 "$staged"
mv -f "$staged" "$target"
rm -f "$download"
"$target" >/dev/null 2>&1 &
''');
      await Process.start('sh', [script.path, '$pid', file.path, target.path], mode: ProcessStartMode.detached);
      Future<void>.delayed(const Duration(milliseconds: 600), () => exit(0));
      return const InstallResult(true, 'Verified. Replacing the AppImage and restarting QuickShare Studio...');
    } catch (_) {
      return const InstallResult(false, 'Could not replace this AppImage. Move it to a writable folder and retry.');
    }
  }

  if (!Platform.isAndroid) {
    return const InstallResult(false, 'Download the new version from the release page.', openReleasePage: true);
  }
  if (url.isEmpty || update.packageSha256.isEmpty) {
    return const InstallResult(false, 'This release has no verified Android package. Download it from the release page.',
        openReleasePage: true);
  }
  final dir = Directory('${(await getTemporaryDirectory()).path}${Platform.pathSeparator}updates');
  await dir.create(recursive: true);
  final file = File('${dir.path}${Platform.pathSeparator}QuickShareStudio-${update.version}.apk');
  final client = http.Client();
  try {
    final response = await client.send(http.Request('GET', Uri.parse(url)));
    if (response.statusCode != 200) {
      return InstallResult(false, 'Download failed (HTTP ${response.statusCode}). Check your connection and retry.');
    }
    final total = response.contentLength ?? update.packageSizeBytes;
    final sink = file.openWrite();
    final hash = StreamingSha256();
    var received = 0;
    await for (final chunk in response.stream) {
      sink.add(chunk);
      hash.add(chunk);
      received += chunk.length;
      if (total > 0) onProgress(received / total);
    }
    await sink.close();
    if (hash.finish() != update.packageSha256.toLowerCase()) {
      await file.delete();
      return const InstallResult(false, 'The download was damaged (checksum mismatch) and was deleted. Please retry.');
    }
  } catch (_) {
    return const InstallResult(false, 'Download interrupted. Check your connection and retry.');
  } finally {
    client.close();
  }

  final result = await _system.invokeMethod<String>('installApk', {'path': file.path});
  return switch (result) {
    'started' => const InstallResult(true, 'Verified. Follow the Android installer to finish updating.'),
    'needs_permission' => const InstallResult(false,
        'Allow QuickShare to install apps (the setting just opened), then tap Update again.'),
    'signature_mismatch' => const InstallResult(false,
        'This update is signed with a different key than the installed app, so Android would reject it. '
        'Uninstall this version and install the new one from the release page.',
        openReleasePage: true,
        signatureMismatch: true),
    'wrong_package' => const InstallResult(false, 'The downloaded file is not QuickShare Studio. It was not installed.'),
    _ => const InstallResult(false, 'The downloaded file is not a valid Android package.'),
  };
}
