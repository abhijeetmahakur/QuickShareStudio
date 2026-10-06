/// Typed runtime configuration for device-to-device transfers.
///
/// Values are compiled in from a gitignored `.env` file:
///
///     flutter run --dart-define-from-file=.env
///
/// See `.env.example` for optional build-time network configuration. The default setup
/// uses public STUN servers and requires no API keys.
library;

class IceServer {
  const IceServer(this.urls, {this.username, this.credential});

  final List<String> urls;
  final String? username;
  final String? credential;

  bool get isTurn => urls.any((u) => u.startsWith('turn:') || u.startsWith('turns:'));

  Map<String, dynamic> toMap() => {
        'urls': urls,
        if (username != null && username!.isNotEmpty) 'username': username,
        if (credential != null && credential!.isNotEmpty) 'credential': credential,
      };
}

class AppConfig {
  static const List<IceServer> defaultStunServers = [
    IceServer([
      'stun:stun.l.google.com:19302',
      'stun:stun1.l.google.com:19302',
      'stun:stun2.l.google.com:19302',
      'stun:stun3.l.google.com:19302',
      'stun:stun4.l.google.com:19302',
      'stun:stun.cloudflare.com:3478',
      'stun:openrelay.metered.ca:80',
    ]),
  ];

  static const List<IceServer> defaultTurnServers = [
    IceServer(
      [
        'turn:openrelay.metered.ca:80',
        'turn:openrelay.metered.ca:443',
        'turn:openrelay.metered.ca:443?transport=tcp',
        'turns:openrelay.metered.ca:443',
        'turns:openrelay.metered.ca:443?transport=tcp',
      ],
      username: 'openrelayproject',
      credential: 'openrelayproject',
    ),
  ];

  const AppConfig({
    this.stunServers = defaultStunServers,
    this.turnServers = defaultTurnServers,
    this.meteredDomain,
    this.meteredApiKey,
    this.forceRelay = false,
    this.peerServerHost = '0.peerjs.com',
    this.peerServerPort = 443,
    this.peerServerPath = '/',
    this.peerServerSecure = true,
    this.chunkSize = 16 * 1024,
    this.codeTtl = const Duration(minutes: 5),
    this.maxAttempts = 5,
    this.lanTimeout = const Duration(seconds: 3),
    this.internetConnectTimeout = const Duration(seconds: 20),
    this.acceptTimeout = const Duration(minutes: 2),
    this.resumeGracePeriod = const Duration(minutes: 5),
    this.flowControlWindow = 4 * 1024 * 1024,
    this.maxTransferBytes = 8 * 1024 * 1024 * 1024,
    this.maxFilesPerTransfer = 500,
  });

  /// STUN servers, tried first (free, no credentials).
  final List<IceServer> stunServers;

  /// Optional static TURN servers used when a direct path is impossible.
  final List<IceServer> turnServers;

  /// Metered TURN credentials (if dynamically fetched or configured)
  final String? meteredDomain;
  final String? meteredApiKey;

  /// Only use relayed (TURN) candidates. For testing the TURN fallback.
  final bool forceRelay;

  /// PeerJS signaling server (PeerJS Cloud by default; no self-hosted server needed).
  final String peerServerHost;
  final int peerServerPort;
  final String peerServerPath;
  final bool peerServerSecure;

  /// Size of one data chunk on the wire.
  final int chunkSize;

  /// How long a pairing code (and its PeerJS peer) lives.
  final Duration codeTtl;

  /// Wrong codes (sender side) / failed handshakes (receiver side) before lockout / new code.
  final int maxAttempts;

  /// How long LAN discovery may take before offering the internet.
  final Duration lanTimeout;
  final Duration internetConnectTimeout;

  /// How long the sender waits for the receiver to tap Accept.
  final Duration acceptTimeout;

  /// How long an interrupted transfer can be resumed.
  final Duration resumeGracePeriod;

  /// Unacknowledged bytes the sender may have in flight.
  final int flowControlWindow;

  /// Largest single transfer (all files) a receiver accepts.
  final int maxTransferBytes;
  final int maxFilesPerTransfer;

  bool get hasTurn => turnServers.isNotEmpty;

  /// ICE servers in priority order: STUN first, TURN as the fallback.
  List<IceServer> iceServers({List<IceServer> fetchedTurn = const [], bool turnOnly = false}) =>
      turnOnly ? [...turnServers, ...fetchedTurn] : [...stunServers, ...turnServers, ...fetchedTurn];

  Uri get peerServerSocketUri {
    final path = peerServerPath.endsWith('/') ? peerServerPath : '$peerServerPath/';
    return Uri.parse('${peerServerSecure ? 'wss' : 'ws'}://$peerServerHost:$peerServerPort${path}peerjs');
  }

  AppConfig copyWith({
    List<IceServer>? stunServers,
    List<IceServer>? turnServers,
    bool? forceRelay,
    int? chunkSize,
    Duration? codeTtl,
    int? maxAttempts,
    Duration? lanTimeout,
    Duration? internetConnectTimeout,
    Duration? acceptTimeout,
    Duration? resumeGracePeriod,
    int? flowControlWindow,
    int? maxTransferBytes,
    String? peerServerHost,
    int? peerServerPort,
    bool? peerServerSecure,
    String? meteredDomain,
    String? meteredApiKey,
  }) {
    return AppConfig(
      stunServers: stunServers ?? this.stunServers,
      turnServers: turnServers ?? this.turnServers,
      meteredDomain: meteredDomain ?? this.meteredDomain,
      meteredApiKey: meteredApiKey ?? this.meteredApiKey,
      forceRelay: forceRelay ?? this.forceRelay,
      peerServerHost: peerServerHost ?? this.peerServerHost,
      peerServerPort: peerServerPort ?? this.peerServerPort,
      peerServerPath: peerServerPath,
      peerServerSecure: peerServerSecure ?? this.peerServerSecure,
      chunkSize: chunkSize ?? this.chunkSize,
      codeTtl: codeTtl ?? this.codeTtl,
      maxAttempts: maxAttempts ?? this.maxAttempts,
      lanTimeout: lanTimeout ?? this.lanTimeout,
      internetConnectTimeout: internetConnectTimeout ?? this.internetConnectTimeout,
      acceptTimeout: acceptTimeout ?? this.acceptTimeout,
      resumeGracePeriod: resumeGracePeriod ?? this.resumeGracePeriod,
      flowControlWindow: flowControlWindow ?? this.flowControlWindow,
      maxTransferBytes: maxTransferBytes ?? this.maxTransferBytes,
      maxFilesPerTransfer: maxFilesPerTransfer,
    );
  }

  /// Reads the `--dart-define-from-file=.env` values.
  factory AppConfig.fromEnvironment() {
    const stun = String.fromEnvironment(
      'STUN_URLS',
      defaultValue:
          'stun:stun.l.google.com:19302,stun:stun1.l.google.com:19302,stun:stun2.l.google.com:19302,stun:stun3.l.google.com:19302,stun:stun4.l.google.com:19302,stun:stun.cloudflare.com:3478',
    );
    const turnUrls = String.fromEnvironment('TURN_URLS');
    const turnUser = String.fromEnvironment('TURN_USERNAME');
    const turnCredential = String.fromEnvironment('TURN_CREDENTIAL');
    const forceRelay = bool.fromEnvironment('FORCE_TURN');
    const peerHost = String.fromEnvironment('PEER_SERVER_HOST', defaultValue: '0.peerjs.com');
    const peerPort = int.fromEnvironment('PEER_SERVER_PORT', defaultValue: 443);
    const peerSecure = bool.fromEnvironment('PEER_SERVER_SECURE', defaultValue: true);
    const meteredDomain = String.fromEnvironment('METERED_DOMAIN');
    const meteredKey = String.fromEnvironment('METERED_API_KEY');

    List<String> split(String v) => v.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

    final userStun = split(stun);
    final userTurn = split(turnUrls);

    return AppConfig(
      stunServers: userStun.isNotEmpty ? [IceServer(userStun)] : defaultStunServers,
      turnServers: userTurn.isNotEmpty
          ? [IceServer(userTurn, username: turnUser, credential: turnCredential)]
          : defaultTurnServers,
      meteredDomain: meteredDomain.isEmpty ? null : meteredDomain,
      meteredApiKey: meteredKey.isEmpty ? null : meteredKey,
      forceRelay: forceRelay,
      peerServerHost: peerHost,
      peerServerPort: peerPort,
      peerServerSecure: peerSecure,
    );
  }

  /// The configuration the app runs with. Tests may replace it.
  static AppConfig current = AppConfig.fromEnvironment();
}
