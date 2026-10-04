import 'dart:math';

/// Represents an active device pairing session.
/// The pairing code remains active while the sender's application session is open.
/// It is invalidated automatically on disconnect, end session, or app close.
class PairingSession {
  final String sessionId;
  final String numericCode; // 6-digit code
  final String hostDeviceName;
  final String hostIp;
  final int hostPort;
  final DateTime createdAt;
  bool isActive;
  final bool isApproved;
  final int failedAttempts;

  PairingSession({
    required this.sessionId,
    required this.numericCode,
    required this.hostDeviceName,
    required this.hostIp,
    required this.hostPort,
    required this.createdAt,
    this.isActive = true,
    this.isApproved = false,
    this.failedAttempts = 0,
  });

  /// Generates a fresh session-bound pairing code
  factory PairingSession.create({
    required String hostDeviceName,
    required String hostIp,
    required int hostPort,
  }) {
    final rand = Random();
    // 6-digit cryptographically styled numeric code: 100000 - 999999
    final code = (100000 + rand.nextInt(900000)).toString();
    final now = DateTime.now();
    final sessionId = 'pair_${now.microsecondsSinceEpoch}_${rand.nextInt(1000000)}';

    return PairingSession(
      sessionId: sessionId,
      numericCode: code,
      hostDeviceName: hostDeviceName,
      hostIp: hostIp,
      hostPort: hostPort,
      createdAt: now,
      isActive: true,
    );
  }

  void invalidate() {
    isActive = false;
  }

  bool get isExpired => !isActive;

  bool get isLockedOut => failedAttempts >= 5;

  String get code => numericCode;

  /// Formatted numeric code: "123 - 456" for display
  String get formattedCode {
    if (numericCode.length == 6) {
      return '${numericCode.substring(0, 3)} - ${numericCode.substring(3)}';
    }
    return numericCode;
  }

  /// Secure pairing payload for QR scanner or direct link
  String get qrPayload =>
      'quickshare://pair?code=$numericCode&sid=$sessionId&host=$hostIp&port=$hostPort&name=${Uri.encodeComponent(hostDeviceName)}';

  /// App Deep Link for pairing confirmation
  String get appDeepLink =>
      'quickshare://pair?sid=$sessionId&code=$numericCode&host=$hostIp&port=$hostPort&name=${Uri.encodeComponent(hostDeviceName)}';
}
