import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

/// Whether Bluetooth transfers can work here, and why not.
///
/// The Bluetooth path needs BLE advertising + a GATT server (receiver) and Wi-Fi Direct with
/// configurable groups (Android 10+). Browsers (the desktop app) cannot advertise or open a
/// GATT server, and iOS has no Wi-Fi Direct, so those platforms say so instead of faking it.
abstract final class BluetoothSupport {
  static const MethodChannel channel = MethodChannel('quickshare/bluetooth');

  static bool get platformSupported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static String? get unsupportedReason {
    if (platformSupported) return null;
    if (kIsWeb) {
      return "Bluetooth transfers need the Android app. Browsers (which the desktop app runs in) can't advertise over "
          'Bluetooth or create Wi-Fi Direct links. Use the same Wi-Fi, or the internet.';
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return "iOS doesn't let apps use Wi-Fi Direct, so Bluetooth transfers are Android-only. Use the same Wi-Fi or the internet.";
    }
    return 'Bluetooth transfers are available in the Android app.';
  }

  static Future<BluetoothCapabilities> capabilities() async {
    final raw = await channel.invokeMapMethod<String, Object?>('capabilities') ?? const {};
    return BluetoothCapabilities(
      sdk: (raw['sdk'] as int?) ?? 0,
      ble: raw['ble'] == true,
      wifiDirect: raw['wifiDirect'] == true,
      advertise: raw['advertise'] == true,
      enabled: raw['enabled'] == true,
    );
  }

  /// Shows the system "Turn on Bluetooth?" prompt. True when Bluetooth ends up on.
  static Future<bool> requestEnable() async => await channel.invokeMethod<bool>('requestEnable') ?? false;
}

class BluetoothCapabilities {
  const BluetoothCapabilities({
    required this.sdk,
    required this.ble,
    required this.wifiDirect,
    required this.advertise,
    required this.enabled,
  });

  final int sdk;
  final bool ble;
  final bool wifiDirect;

  /// Can act as the receiver (advertise + GATT server).
  final bool advertise;
  final bool enabled;

  bool get supported => sdk >= 29 && ble && wifiDirect;

  String? get unsupportedReason {
    if (sdk < 29) return 'Bluetooth transfers need Android 10 or newer (this phone runs Android API $sdk).';
    if (!ble) return "This device doesn't have Bluetooth Low Energy.";
    if (!wifiDirect) return "This device doesn't support Wi-Fi Direct, which carries the files after the Bluetooth handshake.";
    return null;
  }
}

/// One permission prompt, explained before the system dialog appears.
class PermissionStep {
  const PermissionStep({required this.id, required this.title, required this.rationale, required this.permissions, this.optional = false});
  final String id;
  final String title;
  final String rationale;
  final List<Permission> permissions;

  /// The feature works without it (e.g. the progress notification).
  final bool optional;
}

enum PermissionState { granted, denied, permanentlyDenied }

/// The runtime permissions the Bluetooth path needs on this Android version:
///  * Android 12+ (API 31+): BLUETOOTH_SCAN (neverForLocation), BLUETOOTH_CONNECT, BLUETOOTH_ADVERTISE
///  * Android 11 and below: location (BLUETOOTH / BLUETOOTH_ADMIN are install-time)
///  * Wi-Fi Direct: NEARBY_WIFI_DEVICES (API 33+), location below
abstract final class BluetoothPermissions {
  static List<PermissionStep> stepsFor(int sdk) => [
        if (sdk >= 31)
          const PermissionStep(
            id: 'bluetooth',
            title: 'Allow nearby Bluetooth devices',
            rationale: 'QuickShare uses Bluetooth to find the other phone and agree on an encryption key with it. '
                "It doesn't use Bluetooth to track your location.",
            permissions: [Permission.bluetoothScan, Permission.bluetoothConnect, Permission.bluetoothAdvertise],
          ),
        if (sdk >= 33)
          const PermissionStep(
            id: 'wifi',
            title: 'Allow nearby Wi-Fi devices',
            rationale: 'Files travel over a direct Wi-Fi link between the two phones (Wi-Fi Direct). No router or internet needed.',
            permissions: [Permission.nearbyWifiDevices],
          )
        else
          PermissionStep(
            id: 'location',
            title: 'Allow location access',
            rationale: sdk >= 31
                ? 'Android ${sdk >= 32 ? '12L' : '12'} requires location access for Wi-Fi Direct, the direct link that carries the files. '
                    "QuickShare doesn't read or store your location."
                : 'Android 11 and older require location access to scan for Bluetooth devices and to use Wi-Fi Direct. '
                    "QuickShare doesn't read or store your location.",
            permissions: const [Permission.locationWhenInUse],
          ),
        if (sdk >= 33)
          const PermissionStep(
            id: 'notifications',
            title: 'Show transfer progress',
            rationale: 'A notification shows progress and keeps the transfer running if you switch apps.',
            permissions: [Permission.notification],
            optional: true,
          ),
      ];

  static Future<PermissionState> status(PermissionStep step) async {
    var permanently = false;
    for (final p in step.permissions) {
      final s = await p.status;
      if (s.isGranted || s.isLimited) continue;
      if (s.isPermanentlyDenied || s.isRestricted) permanently = true;
      return permanently ? PermissionState.permanentlyDenied : PermissionState.denied;
    }
    return PermissionState.granted;
  }

  static Future<PermissionState> request(PermissionStep step) async {
    final results = await step.permissions.request();
    if (results.values.every((s) => s.isGranted || s.isLimited)) return PermissionState.granted;
    if (results.values.any((s) => s.isPermanentlyDenied || s.isRestricted)) return PermissionState.permanentlyDenied;
    return PermissionState.denied;
  }

  /// Location services (the system switch) must be on for BLE scans on Android 11 and older.
  static Future<bool> locationServiceNeededAndOff(int sdk) async {
    if (sdk >= 31) return false;
    return (await Permission.location.serviceStatus) == ServiceStatus.disabled;
  }
}
