import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:web/web.dart' as web;

import '../../models/app_update_info.dart';
import 'platform_updater.dart';

/// The desktop app is a web bundle served by the launcher (server.py), which can replace
/// its own files.
bool get canSelfUpdate => true;

Uri _api(String path) => Uri.base.resolve(path);

Future<InstallResult> downloadAndInstall(AppUpdateInfo update, void Function(double progress) onProgress) async {
  if (update.packageUrl.isEmpty || update.packageSha256.isEmpty) {
    return const InstallResult(false, 'This release has no verified desktop package. Download it from the release page.',
        openReleasePage: true);
  }
  final http.Response res;
  try {
    res = await http.post(
      _api('/api/update/apply'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'url': update.packageUrl, 'sha256': update.packageSha256, 'version': update.version}),
    );
  } catch (_) {
    return const InstallResult(false, 'The QuickShare background service is not responding. Restart the app and retry.');
  }
  final body = jsonDecode(res.body) as Map<String, dynamic>;
  if (res.statusCode == 501) {
    return InstallResult(false, body['error'] as String? ?? 'Update this copy manually.', openReleasePage: true);
  }
  if (res.statusCode != 200) {
    return InstallResult(false, body['error'] as String? ?? 'The update could not be applied.');
  }
  // The launcher downloads, verifies and swaps in the background; follow its progress.
  final deadline = DateTime.now().add(const Duration(minutes: 10));
  while (DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 700));
    try {
      final status = jsonDecode((await http.get(_api('/api/update/status'))).body) as Map<String, dynamic>;
      final state = status['state'] as String? ?? '';
      onProgress((status['progress'] as num?)?.toDouble() ?? 0);
      if (state == 'failed') return InstallResult(false, status['error'] as String? ?? 'The update failed.');
      if (state == 'restarting' || state == 'done') break;
    } catch (_) {
      break; // the server is restarting
    }
  }
  // Wait for the restarted launcher, then load the new version.
  for (var i = 0; i < 60; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    try {
      final status = jsonDecode((await http.get(_api('/api/update/status'))).body) as Map<String, dynamic>;
      if (status['version'] == update.version) {
        web.window.location.reload();
        return InstallResult(true, 'Updated to v${update.version}. Reloading...');
      }
    } catch (_) {}
  }
  web.window.location.reload();
  return InstallResult(true, 'Update installed. Reloading...');
}
