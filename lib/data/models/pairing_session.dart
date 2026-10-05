import 'dart:convert';
import 'dart:math';

/// The code this device shows so another device can connect to it (on the LAN, or over the
/// internet as PeerJS peer `qs-<code>`).
///
/// Credentials are temporary: the code, its one-time nonce and the peer ID die when the code
/// expires ([ttl], 5 minutes by default), is used, is regenerated, or after too many failed
/// handshakes. A code is never handed out twice in the same app run.
class PairingSession {
  PairingSession({
    required this.sessionId,
    required this.numericCode,
    required this.hostDeviceName,
    required this.hostIp,
    required this.hostPort,
    required this.createdAt,
    String? nonce,
    this.ttl = const Duration(minutes: 5),
    this.isActive = true,
    this.isApproved = false,
    this.failedAttempts = 0,
    this.maxFailedAttempts = 5,
  }) : nonce = nonce ?? _randomNonce();

  final String sessionId;
  final String numericCode; // 6-digit code
  final String hostDeviceName;
  final String hostIp;
  final int hostPort;
  final DateTime createdAt;

  /// One-time secret carried only in the QR code (never typed, never on a server).
  final String nonce;
  final Duration ttl;
  bool isActive;
  final bool isApproved;
  int failedAttempts;
  final int maxFailedAttempts;

  static final Random _secure = Random.secure();

  /// Codes handed out in this run, so none is reused.
  static final Set<String> _issued = {};

  static String _randomNonce() => base64Url.encode(List<int>.generate(16, (_) => _secure.nextInt(256))).replaceAll('=', '');

  /// Generates a fresh code with a cryptographically secure RNG.
  factory PairingSession.create({
    required String hostDeviceName,
    required String hostIp,
    required int hostPort,
    Duration ttl = const Duration(minutes: 5),
    int maxFailedAttempts = 5,
    DateTime? now,
  }) {
    String code;
    do {
      code = (100000 + _secure.nextInt(900000)).toString();
    } while (_issued.contains(code));
    _issued.add(code);
    final created = now ?? DateTime.now();
    final sessionId = 'pair_${created.microsecondsSinceEpoch}_${_randomNonce().substring(0, 8)}';

    return PairingSession(
      sessionId: sessionId,
      numericCode: code,
      hostDeviceName: hostDeviceName,
      hostIp: hostIp,
      hostPort: hostPort,
      createdAt: created,
      ttl: ttl,
      maxFailedAttempts: maxFailedAttempts,
    );
  }

  DateTime get expiresAt => createdAt.add(ttl);

  /// Time left before the code stops working.
  Duration remaining([DateTime? now]) {
    final left = expiresAt.difference(now ?? DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  bool hasTimedOut([DateTime? now]) => !(now ?? DateTime.now()).isBefore(expiresAt);

  void invalidate() {
    isActive = false;
  }

  bool get isExpired => !isActive || hasTimedOut();

  bool get isLockedOut => failedAttempts >= maxFailedAttempts;

  /// Records a failed handshake. Returns true when the code must be invalidated.
  bool registerFailedAttempt() {
    failedAttempts++;
    if (isLockedOut) invalidate();
    return isLockedOut;
  }

  String get code => numericCode;

  /// PeerJS peer ID other devices connect to over the internet (the 6-digit code).
  String get peerId => numericCode;

  /// Formatted numeric code: "123 - 456" for display
  String get formattedCode {
    if (numericCode.length == 6) {
      return '${numericCode.substring(0, 3)} - ${numericCode.substring(3)}';
    }
    return numericCode;
  }

  /// QR payload: the code and peerId plus the one-time nonce, and the LAN address for direct pairing.
  String get qrPayload =>
      'quickshare://pair?code=$numericCode&peerId=$numericCode&n=$nonce&sid=$sessionId&host=$hostIp&port=$hostPort&name=${Uri.encodeComponent(hostDeviceName)}';

  /// App Deep Link for pairing confirmation
  String get appDeepLink => qrPayload;

  /// For tests: forget which codes were issued.
  static void resetIssuedCodes() => _issued.clear();
}
