import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../../core/utils/file_utils.dart';
import '../../../transfer/protocol/streaming_sha256.dart';
import '../../models/app_update_info.dart';
import 'platform_updater.dart';

bool get canSelfUpdate => Platform.isAndroid || Platform.isWindows || Platform.isLinux;

/// How this Linux copy was installed, which decides the release asset and how it is updated.
enum LinuxInstallKind { appImage, deb, tarball }

LinuxInstallKind get linuxInstallKind {
  if (Platform.environment['APPIMAGE']?.isNotEmpty ?? false) return LinuxInstallKind.appImage;
  // The .deb installs the app under /usr/lib/quickshare-studio.
  if (Platform.resolvedExecutable.startsWith('/usr/lib/quickshare-studio/')) return LinuxInstallKind.deb;
  return LinuxInstallKind.tarball;
}

/// The release asset this Linux copy updates from.
String get linuxAssetName => switch (linuxInstallKind) {
      LinuxInstallKind.appImage => linuxAppImageAsset,
      LinuxInstallKind.deb => linuxDebAsset,
      LinuxInstallKind.tarball => linuxTarballAsset,
    };

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

  if (Platform.isLinux) return _installLinux(update, onProgress);

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

/// Downloads [url] into [file] while hashing it. Returns an error result, or null when the
/// file arrived and matches [expectedSha256].
Future<InstallResult?> _download(
  String url,
  File file,
  String expectedSha256,
  int expectedSize,
  void Function(double progress) onProgress,
) async {
  final client = http.Client();
  try {
    final response = await client.send(http.Request('GET', Uri.parse(url)));
    if (response.statusCode != 200) {
      return InstallResult(false, 'Download failed (HTTP ${response.statusCode}). Check your connection and retry.');
    }
    final total = response.contentLength ?? expectedSize;
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
    if (hash.finish() != expectedSha256.toLowerCase()) {
      await file.delete();
      return const InstallResult(false, 'The download was damaged (checksum mismatch) and was deleted. Please retry.');
    }
    return null;
  } catch (_) {
    return const InstallResult(false, 'Download interrupted. Check your connection and retry.');
  } finally {
    client.close();
  }
}

/// Starts [script] detached with [args]; it waits for this process to exit before replacing
/// the app, then starts the new version. Quits the app shortly after.
Future<void> _handOver(Directory dir, String script, List<String> args) async {
  final file = File('${dir.path}/quickshare-update.sh');
  await file.writeAsString(script);
  await Process.start('sh', [file.path, '$pid', ...args], mode: ProcessStartMode.detached);
  Future<void>.delayed(const Duration(milliseconds: 600), () => exit(0));
}

// Runs the new version without the old AppImage's mount variables.
const _relaunch = r'env -u APPDIR -u APPIMAGE -u ARGV0 -u OWD "$1" >/dev/null 2>&1 &';

/// The script that swaps in the new version once the app (first argument: its pid) exits.
/// AppImage: `<pid> <download> <target>`. Tarball: `<pid> <install> <bundle> <staging> <download>`.
@visibleForTesting
String linuxUpdateScript(LinuxInstallKind kind, {String executable = 'quickshare'}) => switch (kind) {
      LinuxInstallKind.appImage => '''#!/bin/sh
set -eu
app_pid="\$1"; download="\$2"; target="\$3"
while kill -0 "\$app_pid" 2>/dev/null; do sleep 1; done
cp "\$download" "\$target.quickshare-update"
chmod 755 "\$target.quickshare-update"
mv -f "\$target.quickshare-update" "\$target"
rm -f "\$download"
set -- "\$target"
$_relaunch
''',
      LinuxInstallKind.tarball => '''#!/bin/sh
set -eu
app_pid="\$1"; install="\$2"; bundle="\$3"; staging="\$4"; download="\$5"
while kill -0 "\$app_pid" 2>/dev/null; do sleep 1; done
rm -rf "\$install.old"
mv "\$install" "\$install.old"
mv "\$bundle" "\$install"
rm -rf "\$install.old" "\$staging" "\$download"
set -- "\$install/$executable"
$_relaunch
''',
      // Installed by the package manager; nothing to swap.
      LinuxInstallKind.deb => '',
    };

Future<InstallResult> _installLinux(AppUpdateInfo update, void Function(double progress) onProgress) async {
  final kind = linuxInstallKind;
  final url = update.packageUrl;
  if (url.isEmpty || update.packageSha256.isEmpty || !url.endsWith(linuxAssetName)) {
    return InstallResult(false, 'This release has no verified $linuxAssetName for this copy.', openReleasePage: true);
  }
  final dir = Directory('${(await getTemporaryDirectory()).path}/quickshare-updates');
  await dir.create(recursive: true);
  final download = File('${dir.path}/$linuxAssetName');
  final failed = await _download(url, download, update.packageSha256, update.packageSizeBytes, onProgress);
  if (failed != null) return failed;

  switch (kind) {
    case LinuxInstallKind.appImage:
      final target = File(Platform.environment['APPIMAGE']!);
      if (!await _writable(target.parent)) {
        return InstallResult(false,
            'Cannot replace ${target.path}: the folder is read-only. Move the AppImage to a folder you own (for example ~/Applications) and retry.');
      }
      await _handOver(dir, linuxUpdateScript(LinuxInstallKind.appImage), [download.path, target.path]);
      return const InstallResult(true, 'Verified. Replacing the AppImage and restarting QuickShare Studio...');

    case LinuxInstallKind.tarball:
      final install = File(Platform.resolvedExecutable).parent;
      if (!await _writable(install.parent)) {
        return InstallResult(false, 'Cannot update ${install.path}: the folder is read-only.', openReleasePage: true);
      }
      final staging = Directory('${install.parent.path}/.quickshare-update-$pid');
      if (staging.existsSync()) await staging.delete(recursive: true);
      await staging.create();
      final untar = await Process.run('tar', ['-xzf', download.path, '-C', staging.path]);
      final bundle = untar.exitCode == 0 ? _findBundle(staging) : null;
      if (bundle == null) {
        await staging.delete(recursive: true);
        return const InstallResult(false, 'The downloaded package could not be unpacked. Please retry.');
      }
      final exe = Platform.resolvedExecutable.split('/').last;
      await _handOver(dir, linuxUpdateScript(LinuxInstallKind.tarball, executable: exe),
          [install.path, bundle.path, staging.path, download.path]);
      return const InstallResult(true, 'Verified. Installing the new version and restarting QuickShare Studio...');

    case LinuxInstallKind.deb:
      // System packages need the package manager (and an administrator password): hand the
      // verified .deb to the desktop's software installer.
      final downloads = Directory(FileUtils.getDefaultDownloadDirectory());
      await downloads.create(recursive: true);
      final saved = await download.copy('${downloads.path}/$linuxAssetName');
      await download.delete();
      final opened = await Process.run('xdg-open', [saved.path]).then((r) => r.exitCode == 0, onError: (_) => false);
      return InstallResult(
        opened,
        opened
            ? 'Verified and saved to ${saved.path}. Your software installer is opening it: install it, then reopen QuickShare Studio.'
            : 'Verified and saved to ${saved.path}. Install it with: sudo apt install "${saved.path}"',
      );
  }
}

Future<bool> _writable(Directory dir) async {
  try {
    final probe = File('${dir.path}/.quickshare-write-check-$pid');
    await probe.writeAsBytes(const []);
    await probe.delete();
    return true;
  } catch (_) {
    return false;
  }
}

/// The unpacked app folder (the one holding the quickshare executable and its lib/).
Directory? _findBundle(Directory root) {
  for (final entity in root.listSync(recursive: true, followLinks: false)) {
    if (entity is File && entity.path.endsWith('/quickshare') && Directory('${entity.parent.path}/lib').existsSync()) {
      return entity.parent;
    }
  }
  return null;
}
