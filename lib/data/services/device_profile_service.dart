import 'dart:convert';
import 'dart:io' show File, Directory, Platform;
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/device_profile.dart';
import '../../core/utils/file_utils.dart';

class DeviceProfileService {
  static const String _profileKey = 'quickshare_device_profile';
  static const String _onboardingCompleteKey = 'quickshare_onboarding_completed';
  static const int maxAvatarSizeBytes = 5 * 1024 * 1024; // 5 MB

  static final DeviceProfileService _instance = DeviceProfileService._internal();
  factory DeviceProfileService() => _instance;
  DeviceProfileService._internal();

  DeviceProfile? _cachedProfile;

  DeviceProfile? get cachedProfile => _cachedProfile;

  /// Detect the current operating platform name
  static String detectPlatform() {
    if (kIsWeb) return 'web';
    try {
      if (Platform.isWindows) return 'windows';
      if (Platform.isMacOS) return 'macos';
      if (Platform.isLinux) return 'linux';
      if (Platform.isAndroid) return 'android';
      if (Platform.isIOS) return 'ios';
    } catch (_) {}
    return 'desktop';
  }

  /// Returns a sensible default device name based on the host platform
  static String getDefaultDeviceName() {
    final p = detectPlatform();
    switch (p) {
      case 'windows':
        return 'My Windows PC';
      case 'macos':
        return 'My Mac';
      case 'linux':
        return 'My Linux Computer';
      case 'android':
        return 'My Android Phone';
      case 'ios':
        return 'My iPhone';
      case 'web':
        return 'My Browser';
      default:
        return 'My Laptop';
    }
  }

  /// Returns default avatar ID based on platform
  static String getDefaultAvatarId() {
    final p = detectPlatform();
    switch (p) {
      case 'android':
      case 'ios':
        return 'smartphone';
      case 'windows':
      case 'macos':
      case 'linux':
        return 'laptop';
      default:
        return 'laptop';
    }
  }

  /// Checks if the first-time onboarding has been completed
  Future<bool> hasCompletedOnboarding() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final flag = prefs.getBool(_onboardingCompleteKey);
      if (flag == true) return true;

      final raw = prefs.getString(_profileKey);
      if (raw != null) {
        final profile = DeviceProfile.fromJson(raw);
        return profile.isOnboardingComplete;
      }
    } catch (e) {
      debugPrint('Error checking onboarding completion: $e');
    }
    return false;
  }

  /// Loads the persisted device profile or creates an initial default
  Future<DeviceProfile> loadProfile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_profileKey);
      if (raw != null && raw.isNotEmpty) {
        _cachedProfile = DeviceProfile.fromJson(raw);
        return _cachedProfile!;
      }
    } catch (e) {
      debugPrint('Error loading device profile: $e');
    }

    // Default initial profile
    _cachedProfile = DeviceProfile(
      displayName: getDefaultDeviceName(),
      avatarId: getDefaultAvatarId(),
      platform: detectPlatform(),
      isOnboardingComplete: false,
    );
    return _cachedProfile!;
  }

  /// Persists device profile to local storage
  Future<bool> saveProfile(DeviceProfile profile) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final updatedProfile = profile.copyWith(updatedAt: DateTime.now());
      await prefs.setString(_profileKey, updatedProfile.toJson());
      await prefs.setBool(_onboardingCompleteKey, updatedProfile.isOnboardingComplete);

      // Keep legacy custom_device_name in sync for compatibility with TransferEngine
      await prefs.setString('custom_device_name', updatedProfile.displayName);

      _cachedProfile = updatedProfile;
      return true;
    } catch (e) {
      debugPrint('Error saving device profile: $e');
      return false;
    }
  }

  /// Marks onboarding as complete
  Future<bool> completeOnboarding(DeviceProfile profile) async {
    final completed = profile.copyWith(
      isOnboardingComplete: true,
      updatedAt: DateTime.now(),
    );
    return await saveProfile(completed);
  }

  /// Resets the onboarding state (used for testing or reconfiguring device)
  Future<bool> resetOnboarding() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_onboardingCompleteKey, false);

      if (_cachedProfile != null) {
        _cachedProfile = _cachedProfile!.copyWith(isOnboardingComplete: false);
        await prefs.setString(_profileKey, _cachedProfile!.toJson());
      }
      return true;
    } catch (e) {
      debugPrint('Error resetting onboarding: $e');
      return false;
    }
  }

  /// Validates a custom image file (size and extension)
  static String? validateCustomAvatar({
    required int byteLength,
    required String fileName,
  }) {
    if (byteLength > maxAvatarSizeBytes) {
      final mb = (byteLength / (1024 * 1024)).toStringAsFixed(1);
      return 'File size ($mb MB) exceeds the 5 MB limit.';
    }

    final ext = fileName.split('.').last.toLowerCase();
    const validExtensions = {'png', 'jpg', 'jpeg', 'webp'};
    if (!validExtensions.contains(ext)) {
      return 'Unsupported format .$ext. Please select PNG, JPG, or WebP.';
    }

    return null;
  }

  /// Persists a custom avatar image to safe, permanent application storage
  Future<String?> persistCustomAvatar({
    required String originalFileName,
    required List<int> bytes,
    String? sourcePath,
  }) async {
    try {
      if (kIsWeb) {
        // In web, store data URL / base64 string
        final ext = originalFileName.split('.').last.toLowerCase();
        final mime = ext == 'png' ? 'image/png' : (ext == 'webp' ? 'image/webp' : 'image/jpeg');
        final base64String = 'data:$mime;base64,${base64Encode(bytes)}';
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('quickshare_web_avatar_data', base64String);
        return base64String;
      }

      // Local platform storage
      final targetDir = _getPersistentAvatarDirectory();
      final dir = Directory(targetDir);
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }

      final ext = originalFileName.split('.').last.toLowerCase();
      final targetPath = FileUtils.joinPath(targetDir, 'custom_avatar_${DateTime.now().millisecondsSinceEpoch}.$ext');
      final targetFile = File(targetPath);
      await targetFile.writeAsBytes(bytes, flush: true);

      return targetFile.path;
    } catch (e) {
      debugPrint('Error persisting custom avatar: $e');
      return null;
    }
  }

  /// Get persistent directory for storing user custom avatar images
  String _getPersistentAvatarDirectory() {
    if (kIsWeb) return 'avatars';
    try {
      if (Platform.isWindows) {
        final appData = Platform.environment['APPDATA'] ?? Platform.environment['LOCALAPPDATA'];
        if (appData != null) {
          return FileUtils.joinPath(appData, 'QuickShare\\Avatars');
        }
      }
      final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
      if (home != null) {
        return FileUtils.joinPath(home, '.quickshare/avatars');
      }
    } catch (_) {}
    return 'quickshare_avatars';
  }
}
