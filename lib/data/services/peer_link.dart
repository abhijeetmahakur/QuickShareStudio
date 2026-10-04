import '../../transfer/channel.dart';
import '../models/device_model.dart';

/// A user-facing failure from pairing or sending (wrong code, device unreachable, ...).
class PeerLinkException implements Exception {
  final String message;
  PeerLinkException(this.message);

  @override
  String toString() => message;
}

/// A paired device opened a transfer session with this one.
class IncomingLanSession {
  IncomingLanSession(this.channel, this.peerId);

  /// Raw channel; the connection manager wraps it in end-to-end encryption.
  final FrameChannel channel;
  final String peerId;
}

/// Real device-to-device networking on the local network (LAN peer protocol v2).
///
/// Implemented natively by [CrossDeviceTransferService] (Android/iOS/desktop builds) and,
/// for the browser-based desktop app, by [BridgePeerLink] via the local `server.py`.
/// Discovery and pairing are unchanged from v1; transfers run over an encrypted session
/// (see `lib/transfer/`). When no link is attached, [TransferEngine] runs in demo mode.
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

  /// Forgets the pairing with [peerId].
  Future<void> unpair(String peerId);

  /// Secret shared with [peerId] at pairing time; the pre-shared key for encryption.
  String? pairingToken(String peerId);

  /// Opens a raw session to a paired device. Throws [PeerLinkException].
  Future<FrameChannel> openSession(DeviceModel peer);

  /// Sessions paired devices open to this one.
  Stream<IncomingLanSession> get incomingSessions;
}
