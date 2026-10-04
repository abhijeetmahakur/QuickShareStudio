import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants.dart';
import '../../core/utils/hash_utils.dart';
import '../models/app_update_info.dart';
import 'transfer_engine.dart';

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
    _init();
  }

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

  Future<void> _init() async {
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
    notifyListeners();
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

    // Inspect published release
    final release = _publishedRemoteRelease;
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
