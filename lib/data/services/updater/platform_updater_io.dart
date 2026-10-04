import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../../transfer/protocol/streaming_sha256.dart';
import '../../models/app_update_info.dart';
import 'platform_updater.dart';

bool get canSelfUpdate => Platform.isAndroid;

const _system = MethodChannel('quickshare/system');

Future<InstallResult> downloadAndInstall(AppUpdateInfo update, void Function(double progress) onProgress) async {
  if (!Platform.isAndroid) {
    return const InstallResult(false, 'Download the new version from the release page.', openReleasePage: true);
  }
  final url = update.packageUrl;
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
        openReleasePage: true),
    'wrong_package' => const InstallResult(false, 'The downloaded file is not QuickShare Studio. It was not installed.'),
    _ => const InstallResult(false, 'The downloaded file is not a valid Android package.'),
  };
}
