import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quickshare/data/models/app_update_info.dart';
import 'package:quickshare/data/services/app_update_service.dart';
import 'package:quickshare/data/services/updater/platform_updater.dart';

/// How an installed (older) version detects a new GitHub release, including the minimum
/// supported version and checksum verification from latest.json.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const apkSha = 'aa11aa11aa11aa11aa11aa11aa11aa11aa11aa11aa11aa11aa11aa11aa11aa11';
  const winSha = 'bb22bb22bb22bb22bb22bb22bb22bb22bb22bb22bb22bb22bb22bb22bb22bb22';
  const setupSha = 'cc33cc33cc33cc33cc33cc33cc33cc33cc33cc33cc33cc33cc33cc33cc33cc33';
  const appImageSha = 'dd44dd44dd44dd44dd44dd44dd44dd44dd44dd44dd44dd44dd44dd44dd44dd44';
  const debSha = 'ee55ee55ee55ee55ee55ee55ee55ee55ee55ee55ee55ee55ee55ee55ee55ee55';
  const tarballSha = 'ff66ff66ff66ff66ff66ff66ff66ff66ff66ff66ff66ff66ff66ff66ff66ff66';

  MockClient github({required String tag, required String minSupported, String? digest, String? manifestSha}) {
    return MockClient((request) async {
      if (request.url.path.endsWith('/releases/latest')) {
        return http.Response(
          jsonEncode({
            'tag_name': tag,
            'name': 'QuickShare Studio $tag',
            'html_url': 'https://github.com/abhijeetmahakur/QuickShareStudio/releases/tag/$tag',
            'published_at': '2026-10-05T10:00:00Z',
            'body': 'Internet and Bluetooth transfers.\n- Connect over the internet\n- Bluetooth for offline transfers',
            'assets': [
              {
                'name': 'QuickShareStudio-Android.apk',
                'size': 1000,
                if (digest != null) 'digest': 'sha256:$digest',
                'browser_download_url': 'https://github.com/abhijeetmahakur/QuickShareStudio/releases/download/$tag/QuickShareStudio-Android.apk',
              },
              {
                'name': 'QuickShareStudio-Windows-x64.zip',
                'size': 2000,
                'browser_download_url': 'https://github.com/abhijeetmahakur/QuickShareStudio/releases/download/$tag/QuickShareStudio-Windows-x64.zip',
              },
              {
                'name': 'QuickShareStudio-Windows-Setup.exe',
                'size': 3000,
                'browser_download_url': 'https://github.com/abhijeetmahakur/QuickShareStudio/releases/download/$tag/QuickShareStudio-Windows-Setup.exe',
              },
              {
                'name': 'QuickShareStudio-Linux-x86_64.deb',
                'size': 4000,
                'browser_download_url': 'https://github.com/abhijeetmahakur/QuickShareStudio/releases/download/$tag/QuickShareStudio-Linux-x86_64.deb',
              },
              {
                'name': 'QuickShareStudio-Linux-x86_64.tar.gz',
                'size': 4500,
                'browser_download_url': 'https://github.com/abhijeetmahakur/QuickShareStudio/releases/download/$tag/QuickShareStudio-Linux-x86_64.tar.gz',
              },
              {
                'name': 'QuickShareStudio-Linux-x86_64.AppImage',
                'size': 5000,
                'browser_download_url': 'https://github.com/abhijeetmahakur/QuickShareStudio/releases/download/$tag/QuickShareStudio-Linux-x86_64.AppImage',
              },
              {
                'name': 'latest.json',
                'size': 100,
                'browser_download_url': 'https://github.com/abhijeetmahakur/QuickShareStudio/releases/download/$tag/latest.json',
              },
            ],
          }),
          200,
        );
      }
      if (request.url.path.endsWith('/latest.json')) {
        return http.Response(
          jsonEncode({
            'version': tag.substring(1),
            'minSupportedVersion': minSupported,
            'notes': ['Connect over the internet', 'Bluetooth for offline transfers'],
            'packages': {
              'android': {'name': 'QuickShareStudio-Android.apk', 'sha256': manifestSha ?? apkSha},
              'windows': {'name': 'QuickShareStudio-Windows-x64.zip', 'sha256': winSha},
              'windows_setup': {'name': 'QuickShareStudio-Windows-Setup.exe', 'sha256': setupSha},
              'linux_appimage': {'name': 'QuickShareStudio-Linux-x86_64.AppImage', 'sha256': appImageSha},
              'linux_deb': {'name': 'QuickShareStudio-Linux-x86_64.deb', 'sha256': debSha},
              'linux_tarball': {'name': 'QuickShareStudio-Linux-x86_64.tar.gz', 'sha256': tarballSha},
            },
          }),
          200,
        );
      }
      return http.Response('not found', 404);
    });
  }

  setUp(() => AppUpdateService().resetTestingState());

  test('an older version finds the new release, its direct package and verified checksum', () async {
    final service = AppUpdateService();
    final info = await http.runWithClient(
      () => service.fetchLatestGitHubRelease(),
      () => github(tag: 'v9.0.0', minSupported: '2.0.0'),
    );
    expect(info, isNotNull);
    expect(info!.version, '9.0.0');
    expect(info.isNewerVersion, isTrue);
    expect(info.isBelowMinimum, isFalse);
    expect(info.releaseNotes, ['Connect over the internet', 'Bluetooth for offline transfers']);
    // flutter_test's default target platform is Android, so the APK is selected.
    expect(info.packageUrl,
        'https://github.com/abhijeetmahakur/QuickShareStudio/releases/download/v9.0.0/QuickShareStudio-Android.apk');
    expect(info.packageSha256, apkSha);
    expect(info.downloadUrl, contains('/releases/tag/v9.0.0'));
  });

  test('a version below minSupportedVersion must update', () async {
    final service = AppUpdateService();
    final info = await http.runWithClient(
      () => service.fetchLatestGitHubRelease(),
      () => github(tag: 'v9.0.0', minSupported: '3.0.0'),
    );
    expect(info!.isBelowMinimum, isTrue);
    expect(info.isMandatory, isTrue);
  });

  group('native Linux updates from the package it was installed with', () {
    Future<dynamic> fetchAs(String? asset) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      AppUpdateService.debugLinuxAsset = asset;
      addTearDown(() {
        debugDefaultTargetPlatformOverride = null;
        AppUpdateService.debugLinuxAsset = null;
      });
      return http.runWithClient(
        () => AppUpdateService().fetchLatestGitHubRelease(),
        () => github(tag: 'v9.0.0', minSupported: '2.0.0'),
      );
    }

    test('an AppImage downloads the verified AppImage', () async {
      final info = await fetchAs(linuxAppImageAsset);
      expect(info!.packageUrl, endsWith('/QuickShareStudio-Linux-x86_64.AppImage'));
      expect(info.packageSha256, appImageSha);
    });

    test('a .deb install downloads the verified .deb', () async {
      final info = await fetchAs(linuxDebAsset);
      expect(info!.packageUrl, endsWith('/QuickShareStudio-Linux-x86_64.deb'));
      expect(info.packageSha256, debSha);
    });

    test('a tarball install downloads the verified tarball', () async {
      final info = await fetchAs(linuxTarballAsset);
      expect(info!.packageUrl, endsWith('/QuickShareStudio-Linux-x86_64.tar.gz'));
      expect(info.packageSha256, tarballSha);
    });

    test('a missing package falls back to the AppImage', () async {
      final info = await fetchAs('QuickShareStudio-Linux-arm64.AppImage');
      expect(info!.packageUrl, endsWith('/QuickShareStudio-Linux-x86_64.AppImage'));
    });
  });

  test('Windows selects the installer executable for one-tap updates', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final info = await http.runWithClient(
      () => AppUpdateService().fetchLatestGitHubRelease(),
      () => github(tag: 'v9.0.0', minSupported: '2.0.0'),
    );
    expect(info!.packageUrl, endsWith('/QuickShareStudio-Windows-Setup.exe'));
    expect(info.packageSha256, setupSha);
  });

  test('the updater status clearly says Update available for older installs', () async {
    final service = AppUpdateService();
    await http.runWithClient(
      () => service.checkForUpdates(simulateLatency: false),
      () => github(tag: 'v9.0.0', minSupported: '2.0.0'),
    );
    expect(service.statusMessage, 'Update available: v9.0.0');
  });

  test('checkOnLaunch flags a prompt when a newer release exists', () async {
    final service = AppUpdateService();
    await service.setAutoCheckUpdates(true);
    await http.runWithClient(() => service.checkOnLaunch(), () => github(tag: 'v9.0.0', minSupported: '2.0.0'));
    expect(service.launchPrompt, isTrue);
    expect(service.latestUpdate!.version, '9.0.0');
    expect(service.mustUpdate, isFalse);
    service.dismissLaunchPrompt();
    expect(service.launchPrompt, isFalse);
  });

  test('no prompt when already up to date', () async {
    final service = AppUpdateService();
    await http.runWithClient(() => service.checkOnLaunch(), () => github(tag: 'v2.0.0', minSupported: '2.0.0'));
    expect(service.launchPrompt, isFalse);
    expect(service.hasPendingUpdate, isFalse);
  });

  test('conflicting checksums (GitHub digest vs latest.json) are not offered', () async {
    final service = AppUpdateService();
    await expectLater(
      http.runWithClient(
        () => service.fetchLatestGitHubRelease(),
        () => github(tag: 'v9.0.0', minSupported: '2.0.0', digest: apkSha, manifestSha: 'cc33' * 16),
      ),
      throwsA(anything),
    );
  });

  test('version comparison', () {
    expect(AppUpdateInfo.compareVersions('2.0.0', '1.6.0'), greaterThan(0));
    expect(AppUpdateInfo.compareVersions('2.0.0', '2.0.0'), 0);
    expect(AppUpdateInfo.compareVersions('1.9.9', '2.0.0'), lessThan(0));
    expect(AppUpdateInfo.compareVersions('v2.10.0', '2.9.9'), greaterThan(0));
  });
}
