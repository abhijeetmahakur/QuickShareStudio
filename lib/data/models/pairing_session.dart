import 'dart:math';

class PairingSession {
  final String sessionId;
  final String numericCode; // 6-digit code
  final String hostDeviceName;
  final String hostIp;
  final int hostPort;
  final DateTime createdAt;
  final DateTime expiresAt;
  final bool isApproved;
  final int failedAttempts;

  PairingSession({
    required this.sessionId,
    required this.numericCode,
    required this.hostDeviceName,
    required this.hostIp,
    required this.hostPort,
    required this.createdAt,
    required this.expiresAt,
    this.isApproved = false,
    this.failedAttempts = 0,
  });

  /// Generates a fresh temporary pairing session expiring in 5 minutes
  factory PairingSession.create({
    required String hostDeviceName,
    required String hostIp,
    required int hostPort,
    int durationMinutes = 5,
  }) {
    final rand = Random();
    // 6-digit cryptographically styled numeric code: 100000 - 999999
    final code = (100000 + rand.nextInt(900000)).toString();
    final now = DateTime.now();
    final sessionId = 'pair_${now.millisecondsSinceEpoch}_${rand.nextInt(10000)}';

    return PairingSession(
      sessionId: sessionId,
      numericCode: code,
      hostDeviceName: hostDeviceName,
      hostIp: hostIp,
      hostPort: hostPort,
      createdAt: now,
      expiresAt: now.add(Duration(minutes: durationMinutes)),
    );
  }

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  bool get isLockedOut => failedAttempts >= 5;

  /// Formatted numeric code: "123 - 456" for readability
  String get formattedCode {
    if (numericCode.length == 6) {
      return '${numericCode.substring(0, 3)} - ${numericCode.substring(3)}';
    }
    return numericCode;
  }

  /// Compact JSON string suitable for encoding into a QR code
  String get qrPayload =>
      'quickshare://pair?sid=$sessionId&code=$numericCode&host=$hostIp&port=$hostPort&name=${Uri.encodeComponent(hostDeviceName)}&exp=${expiresAt.millisecondsSinceEpoch}';
}
