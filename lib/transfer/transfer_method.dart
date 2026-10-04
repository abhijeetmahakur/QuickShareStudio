import 'package:flutter/material.dart';

/// How two devices are connected.
enum TransferMethod {
  /// Same Wi-Fi / hotspot: discovery + encrypted WebSocket session.
  lan,

  /// Different networks: PeerJS Cloud signaling + WebRTC (DTLS), TURN relay if needed.
  internet,

  /// Offline and nearby (Android): BLE handshake, Wi-Fi Direct for the data.
  bluetooth;

  /// Short badge text.
  String get badge => switch (this) {
        TransferMethod.lan => 'LAN',
        TransferMethod.internet => 'Internet',
        TransferMethod.bluetooth => 'Bluetooth',
      };

  String get description => switch (this) {
        TransferMethod.lan => 'Same Wi-Fi',
        TransferMethod.internet => 'Over the internet',
        TransferMethod.bluetooth => 'Nearby, no internet',
      };

  IconData get icon => switch (this) {
        TransferMethod.lan => Icons.wifi_rounded,
        TransferMethod.internet => Icons.public_rounded,
        TransferMethod.bluetooth => Icons.bluetooth_rounded,
      };

  /// Label recorded in transfer history.
  String get historyLabel => switch (this) {
        TransferMethod.lan => 'Local Network (encrypted)',
        TransferMethod.internet => 'Internet (WebRTC, encrypted)',
        TransferMethod.bluetooth => 'Bluetooth + Wi-Fi Direct (encrypted)',
      };

  static TransferMethod? tryParse(String? value) {
    for (final m in values) {
      if (m.name == value) return m;
    }
    return null;
  }
}
