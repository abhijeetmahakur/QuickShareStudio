import 'dart:typed_data';

import '../models/device_model.dart';

/// A user-facing failure from pairing or sending (wrong code, device unreachable, ...).
class PeerLinkException implements Exception {
  final String message;
  PeerLinkException(this.message);

  @override
  String toString() => message;
}

/// Real device-to-device networking (LAN peer protocol v1).
///
/// Implemented natively by [CrossDeviceTransferService] (Android/iOS/desktop builds) and,
/// for the browser-based desktop app, by [BridgePeerLink] via the local `server.py`.
/// When no link is attached, [TransferEngine] falls back to its labelled demo mode.
abstract class PeerLink {
  /// Whether the network side is running and other devices can reach this one.
  bool get isAvailable;

  /// Address other devices use to reach this one.
  String get localIp;
  int get localPort;

  /// Tells the link the code/identity this device currently shows, so incoming pairing
  /// requests can be checked against it.
  void updateSession({
    required String? code,
    required String deviceId,
    required String deviceName,
  });

  /// Finds the device on this network that shows [code] and pairs with it.
  Future<DeviceModel> pairWithCode(String code);

  /// Pairs with the device at [host]:[port] (from its QR code) using [code].
  Future<DeviceModel> pairDirect(String host, int port, String code);

  /// Sends a file to a paired device. Throws [PeerLinkException] on failure.
  Future<void> sendFile(
    DeviceModel peer,
    String fileName,
    Uint8List bytes, {
    void Function(double progress)? onProgress,
  });

  /// Forgets the pairing with [peerId].
  Future<void> unpair(String peerId);
}
