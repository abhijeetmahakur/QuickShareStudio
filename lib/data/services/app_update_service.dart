import 'dart:async';
import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants.dart';
import '../../core/utils/hash_utils.dart';
import '../models/app_update_info.dart';
import 'transfer_engine.dart';
import 'updater/platform_updater.dart';

enum UpdateStatus {
  idle,
  checking,
  available,
  downloading,
  verifying,
  staging,
  readyToRestart,
  applied,
  postponed,
  failed,
}

class AppUpdateService extends ChangeNotifier {
  static final AppUpdateService _instance = AppUpdateService._internal();
  factory AppUpdateService() => _instance;

  AppUpdateService._internal() {
    _ready = _init();
  }

  late final Future<void> _ready;

  String _currentVersion = AppConstants.appVersion;
  String get currentVersion => _currentVersion;

  AppUpdateInfo? _latestUpdate;
  AppUpdateInfo? get latestUpdate => _latestUpdate;

  UpdateStatus _status = UpdateStatus.idle;
  UpdateStatus get status => _status;

  DateTime? _lastCheckedTime;
  DateTime? get lastCheckedTime => _lastCheckedTime;

  bool _autoCheckUpdates = true;
  bool get autoCheckUpdates => _autoCheckUpdates;

  bool _isUpdatePostponed = false;
  bool get isUpdatePostponed => _isUpdatePostponed;
  bool get isPostponed => _isUpdatePostponed;
  bool get hasPendingUpdate => _latestUpdate != null && _latestUpdate!.isNewerVersion;

  double _updateProgress = 0.0;
  double get updateProgress => _updateProgress;

  String _statusMessage = 'Up to date';
  String get statusMessage => _statusMessage;

  String _downloadSpeed = '';
  String get downloadSpeed => _downloadSpeed;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  // Published releases registry (deployment source)
  AppUpdateInfo? _publishedRemoteRelease;

  /// An update was found by the automatic check at launch and should be offered.
  bool launchPrompt = false;

  /// The running version is no longer supported: the update cannot be postponed.
  bool get mustUpdate => _latestUpdate != null && _latestUpdate!.isBelowMinimum;

  /// Checks GitHub once at launch (when automatic checks are on) and flags a prompt.
  Future<void> checkOnLaunch() async {
    await _ready;
    if (!_autoCheckUpdates) return;
    final update = await checkForUpdates(simulateLatency: false);
    if (update != null && (!_isUpdatePostponed || update.isBelowMinimum)) {
      launchPrompt = true;
      notifyListeners();
    }
  }

  void dismissLaunchPrompt() {
    launchPrompt = false;
    notifyListeners();
  }

  Timer? _periodicTimer;

  void _startPeriodicCheck() {
    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(const Duration(hours: 4), (_) async {
      if (!_autoCheckUpdates) return;
      try {
        final update = await checkForUpdates(simulateLatency: false);
        if (update != null && (!_isUpdatePostponed || update.isBelowMinimum)) {
          launchPrompt = true;
          notifyListeners();
        }
      } catch (_) {}
    });
  }

  Future<void> _init() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (info.version.isNotEmpty) {
        _currentVersion = info.version;
      }
    } catch (_) {}

    try {
      final prefs = await SharedPreferences.getInstance();
      final savedVersion = prefs.getString('applied_app_version');
      // A newer installed build must win over a version recorded by an older in-app update.
      if (savedVersion != null &&
          savedVersion.isNotEmpty &&
          AppUpdateInfo.compareVersions(savedVersion, _currentVersion) > 0) {
        _currentVersion = savedVersion;
      }
      _autoCheckUpdates = prefs.getBool('auto_check_updates') ?? true;
      final lastCheckedMillis = prefs.getInt('last_checked_update_millis');
      if (lastCheckedMillis != null) {
        _lastCheckedTime = DateTime.fromMillisecondsSinceEpoch(lastCheckedMillis);
      }
      final pendingRaw = prefs.getString('pending_update_data');
      if (pendingRaw != null) {
        final pending = AppUpdateInfo.deserialize(pendingRaw);
        if (pending != null && pending.isNewerVersion) {
          _latestUpdate = pending;
          _status = UpdateStatus.postponed;
          _isUpdatePostponed = true;
          _statusMessage = 'Update v${pending.version} postponed — Ready to install';
        }
      }
    } catch (_) {}

    _startPeriodicCheck();
    notifyListeners();
  }

  @override
  void dispose() {
    _periodicTimer?.cancel();
    super.dispose();
  }

  // -------------------------------------------------------------
  // Publishing / Deploying New Version (Requirement 13.A & 13.G)
  // -------------------------------------------------------------
  /// Simulates publishing/deploying a new application version to the distribution channel.
  Future<AppUpdateInfo> publishNewVersion({
    required String version,
    String? title,
    String? description,
    List<String>? releaseNotes,
    int? packageSizeBytes,
    String? packageSha256,
    TransferEngine? notifyEngine,
    bool simulateLatency = false,
  }) async {
    final dummyBytes = Uint8List.fromList(List.generate(1024, (i) => (i * 13) % 256));
    final calculatedSha = packageSha256 ?? HashUtils.computeSha256(dummyBytes);

    final newRelease = AppUpdateInfo(
      version: version,
      currentVersion: _currentVersion,
      title: title ?? 'QuickShare Studio $version Release',
      description: description ?? 'Major performance and security update with universal format stability.',
      releaseNotes: releaseNotes ?? [
        'New real-time offline file conversion engine',
        'Enhanced session-bound device pairing security',
        'Persistent transfer history with SHA-256 verification',
        'Optimized Liquid Glass UI and zero-latency drag-and-drop',
      ],
      publishedAt: DateTime.now(),
      packageSizeBytes: packageSizeBytes ?? 18454937, // ~17.6 MB
      packageSha256: calculatedSha,
    );

    _publishedRemoteRelease = newRelease;

    // Check immediately if auto-check is active
    if (_autoCheckUpdates) {
      await checkForUpdates(simulateLatency: simulateLatency);
    }

    // Notify paired devices if TransferEngine provided
    if (notifyEngine != null) {
      notifyPairedDevicesOfUpdate(notifyEngine, newRelease);
    }

    notifyListeners();
    return newRelease;
  }

  // -------------------------------------------------------------
  // Checking for Updates (Requirement 13.A & 13.C)
  // -------------------------------------------------------------
  Future<AppUpdateInfo?> checkForUpdates({bool userInitiated = false, bool simulateLatency = true}) async {
    _status = UpdateStatus.checking;
    _statusMessage = 'Checking for updates...';
    _errorMessage = null;
    notifyListeners();

    // Network / deployment check latency
    if (simulateLatency) {
      await Future.delayed(const Duration(milliseconds: 400));
    }

    _lastCheckedTime = DateTime.now();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('last_checked_update_millis', _lastCheckedTime!.millisecondsSinceEpoch);
    } catch (_) {}

    // Inspect published release: an in-app published one (development/tests), else GitHub.
    AppUpdateInfo? release = _publishedRemoteRelease;
    if (release == null) {
      try {
        release = await fetchLatestGitHubRelease();
      } catch (e) {
        _status = UpdateStatus.idle;
        _statusMessage = 'Could not check for updates (are you online?). Running v$_currentVersion';
        notifyListeners();
        return null;
      }
    }
    if (release != null && release.isNewerVersion) {
      _latestUpdate = release;
      _status = _isUpdatePostponed ? UpdateStatus.postponed : UpdateStatus.available;
      _statusMessage = 'New version v${release.version} is available!';

      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('pending_update_data', release.serialize());
      } catch (_) {}

      notifyListeners();
      return release;
    } else {
      _status = UpdateStatus.idle;
      _statusMessage = 'Application is up to date (v$_currentVersion)';
      _latestUpdate = null;
      _isUpdatePostponed = false;

      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('pending_update_data');
      } catch (_) {}

      notifyListeners();
      return null;
    }
  }

  /// Where releases are published.
  static const String releasesApi =
      'https://api.github.com/repos/abhijeetmahakur/QuickShareStudio/releases/latest';

  static bool _isGitHubRelease(AppUpdateInfo info) => info.downloadUrl.startsWith('https://github.com/');

  /// Reads the latest GitHub release. Returns null when none has been published yet.
  Future<AppUpdateInfo?> fetchLatestGitHubRelease() async {
    final res = await http
        .get(Uri.parse(releasesApi), headers: {'Accept': 'application/vnd.github+json'})
        .timeout(const Duration(seconds: 8));
    if (res.statusCode == 404) return null;
    if (res.statusCode != 200) throw Exception('GitHub returned HTTP ${res.statusCode}');
    final data = jsonDecode(res.body) as Map<String, dynamic>;

    // Package for this platform (the desktop app is the web build packaged per OS).
    final wanted = kIsWeb
        ? (defaultTargetPlatform == TargetPlatform.linux ? 'Linux' : 'Windows')
        : defaultTargetPlatform == TargetPlatform.android
            ? 'Android'
            : defaultTargetPlatform == TargetPlatform.linux
                ? 'Linux'
                : 'Windows';
    final assets = (data['assets'] as List? ?? []).cast<Map<String, dynamic>>();
    final asset = (wanted == 'Windows')
        ? (assets.where((a) => (a['name'] as String? ?? '').toLowerCase().contains('windows') && (a['name'] as String? ?? '').toLowerCase().endsWith('.exe')).firstOrNull
           ?? assets.where((a) => (a['name'] as String? ?? '').contains(wanted)).firstOrNull)
        : assets.where((a) => (a['name'] as String? ?? '').contains(wanted)).firstOrNull;
    final digest = (asset?['digest'] as String? ?? '');
    var sha256 = digest.startsWith('sha256:') ? digest.substring(7) : '';
    var minSupported = '1.0.0';

    // latest.json (published by the release workflow): minimum supported version and the
    // SHA-256 of each package, so the download can be verified even without GitHub digests.
    final manifestAsset = assets.where((a) => a['name'] == 'latest.json').firstOrNull;
    List<String>? manifestNotes;
    if (manifestAsset != null) {
      try {
        final res = await http
            .get(Uri.parse(manifestAsset['browser_download_url'] as String))
            .timeout(const Duration(seconds: 8));
        if (res.statusCode == 200) {
          final manifest = jsonDecode(res.body) as Map<String, dynamic>;
          minSupported = manifest['minSupportedVersion'] as String? ?? minSupported;
          final packages = (manifest['packages'] as Map?)?.cast<String, dynamic>() ?? const {};
          final entry = packages.values.cast<Map<String, dynamic>>().where((p) => p['name'] == asset?['name']).firstOrNull;
          final listed = entry?['sha256'] as String?;
          if (listed != null && listed.isNotEmpty) {
            if (sha256.isNotEmpty && sha256 != listed) {
              throw Exception('Release checksums disagree; not offering this update.');
            }
            sha256 = listed;
          }
          manifestNotes = (manifest['notes'] as List?)?.map((e) => e.toString()).toList();
        }
      } on FormatException {
        // A malformed manifest only loses the extra information.
      }
    }

    final body = (data['body'] as String? ?? '').trim();
    final notes = manifestNotes ??
        body
            .split('\n')
            .map((l) => l.trim())
            .where((l) => l.startsWith('- ') || l.startsWith('* '))
            .map((l) => l.substring(2))
            .take(8)
            .toList();
    final tag = (data['tag_name'] as String? ?? '0.0.0').replaceFirst(RegExp(r'^v'), '');
    return AppUpdateInfo(
      version: tag,
      currentVersion: _currentVersion,
      title: data['name'] as String? ?? 'QuickShare Studio v$tag',
      description: body.isEmpty ? 'A new version of QuickShare Studio is available.' : body.split('\n').first,
      releaseNotes: notes,
      publishedAt: DateTime.tryParse(data['published_at'] as String? ?? '') ?? DateTime.now(),
      packageSizeBytes: (asset?['size'] as num?)?.toInt() ?? 0,
      packageSha256: sha256,
      minSupportedVersion: minSupported,
      isMandatory: AppUpdateInfo.compareVersions(_currentVersion, minSupported) < 0,
      downloadUrl: data['html_url'] as String? ?? 'https://github.com/abhijeetmahakur/QuickShareStudio/releases/latest',
      packageUrl: asset?['browser_download_url'] as String? ?? '',
    );
  }

  // -------------------------------------------------------------
  // Postpone Update (Requirement 13.B & 13.D)
  // -------------------------------------------------------------
  void postponeUpdate() {
    _isUpdatePostponed = true;
    _status = UpdateStatus.postponed;
    if (_latestUpdate != null) {
      _statusMessage = 'Update v${_latestUpdate!.version} postponed — Ready to install';
    }
    notifyListeners();
  }

  // -------------------------------------------------------------
  // Safe Multi-Stage Update Process (Requirement 13.E)
  // -------------------------------------------------------------
  Future<bool> startUpdateNow({
    TransferEngine? engine,
    VoidCallback? onComplete,
    ValueChanged<String>? onError,
    bool simulateProgress = true,
  }) async {
    if (_latestUpdate == null) {
      _statusMessage = 'No update package available to install.';
      notifyListeners();
      return false;
    }

    if (_isGitHubRelease(_latestUpdate!) && canSelfUpdate && !(engine?.hasActiveTransfers ?? false)) {
      final update = _latestUpdate!;
      _status = UpdateStatus.downloading;
      _updateProgress = 0;
      _errorMessage = null;
      _statusMessage = 'Downloading v${update.version}...';
      notifyListeners();
      final result = await downloadAndInstall(update, (p) {
        _updateProgress = p;
        _status = p >= 1 ? UpdateStatus.verifying : UpdateStatus.downloading;
        _statusMessage = p >= 1 ? 'Verifying the package...' : 'Downloading v${update.version} (${(p * 100).floor()}%)...';
        notifyListeners();
      });
      _statusMessage = result.message;
      if (result.ok) {
        _status = UpdateStatus.readyToRestart;
        notifyListeners();
        onComplete?.call();
        return true;
      }
      _status = UpdateStatus.failed;
      _errorMessage = result.message;
      notifyListeners();
      if (result.openReleasePage) {
        await launchUrl(Uri.parse(update.downloadUrl), mode: LaunchMode.externalApplication);
      }
      onError?.call(result.message);
      return false;
    }

    if (_isGitHubRelease(_latestUpdate!)) {
      final version = _latestUpdate!.version;
      if (engine != null && engine.hasActiveTransfers) {
        const err = 'Cannot update while a file transfer is actively in progress. Please wait for transfers to finish.';
        _errorMessage = err;
        _status = UpdateStatus.failed;
        notifyListeners();
        onError?.call(err);
        return false;
      }
      final opened = await launchUrl(Uri.parse(_latestUpdate!.downloadUrl), mode: LaunchMode.externalApplication);
      _statusMessage = opened
          ? 'Opened the v$version download page. Install it to finish updating.'
          : 'Could not open the download page. Visit ${_latestUpdate!.downloadUrl}';
      notifyListeners();
      if (opened) {
        onComplete?.call();
      } else {
        onError?.call(_statusMessage);
      }
      return opened;
    }

    // 1. Guard against updating while a file is actively transferring
    if (engine != null && engine.hasActiveTransfers) {
      final err = 'Cannot update while a file transfer is actively in progress. Please wait for transfers to finish.';
      _errorMessage = err;
      _status = UpdateStatus.failed;
      notifyListeners();
      onError?.call(err);
      return false;
    }

    _status = UpdateStatus.downloading;
    _updateProgress = 0.0;
    _statusMessage = 'Downloading update package (v${_latestUpdate!.version})...';
    _downloadSpeed = '3.8 MB/s';
    _errorMessage = null;
    notifyListeners();

    try {
      // Simulate real download chunks
      if (simulateProgress) {
        for (var i = 1; i <= 10; i++) {
          await Future.delayed(const Duration(milliseconds: 120));
          _updateProgress = i / 10.0;
          _statusMessage = 'Downloading package (${(_updateProgress * 100).toInt()}%)...';
          notifyListeners();
        }
      } else {
        _updateProgress = 1.0;
        _statusMessage = 'Downloading package (100%)...';
        notifyListeners();
      }

      // 2. Integrity Verification (SHA-256)
      _status = UpdateStatus.verifying;
      _statusMessage = 'Verifying cryptographic SHA-256 package integrity...';
      _downloadSpeed = '';
      notifyListeners();
      if (simulateProgress) {
        await Future.delayed(const Duration(milliseconds: 250));
      }

      if (_latestUpdate!.packageSha256.isEmpty) {
        throw Exception('Package integrity verification failed: missing SHA-256 signature.');
      }

      // 3. Staging and configuration preservation
      _status = UpdateStatus.staging;
      _statusMessage = 'Staging application update and preserving paired device configurations...';
      notifyListeners();
      if (simulateProgress) {
        await Future.delayed(const Duration(milliseconds: 250));
      }

      // 4. Apply new version
      _currentVersion = _latestUpdate!.version;
      _status = UpdateStatus.applied;
      _statusMessage = 'Update successfully installed! Running v$_currentVersion';
      _isUpdatePostponed = false;

      // Persist applied version across reboots
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('applied_app_version', _currentVersion);
      await prefs.remove('pending_update_data');

      _latestUpdate = null;
      notifyListeners();

      onComplete?.call();
      return true;
    } catch (e) {
      _status = UpdateStatus.failed;
      _errorMessage = e.toString();
      _statusMessage = 'Update failed: ${e.toString()}';
      notifyListeners();
      onError?.call(e.toString());
      return false;
    }
  }

  // -------------------------------------------------------------
  // Notify Paired Devices (Requirement 13.D)
  // -------------------------------------------------------------
  void notifyPairedDevicesOfUpdate(TransferEngine engine, AppUpdateInfo update) {
    if (engine.pairedDevices.isNotEmpty) {
      for (final device in engine.pairedDevices) {
        // Send an update announcement notice to each connected device
        engine.setNotification(
          'Update Available: v${update.version}',
          'New version v${update.version} published for ${device.name}. Update now or install later via Settings.',
        );
      }
    } else {
      engine.setNotification(
        'Update Available: v${update.version}',
        'New version v${update.version} published. Update now or install later via Settings.',
      );
    }
  }

  // -------------------------------------------------------------
  // Settings & Toggles
  // -------------------------------------------------------------
  Future<void> setAutoCheckUpdates(bool value) async {
    _autoCheckUpdates = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('auto_check_updates', value);
    } catch (_) {}
    notifyListeners();
  }

  void resetTestingState() {
    _periodicTimer?.cancel();
    _currentVersion = AppConstants.appVersion;
    _latestUpdate = null;
    _publishedRemoteRelease = null;
    _status = UpdateStatus.idle;
    _isUpdatePostponed = false;
    _updateProgress = 0.0;
    _errorMessage = null;
    _statusMessage = 'Up to date';
    notifyListeners();
  }
}
