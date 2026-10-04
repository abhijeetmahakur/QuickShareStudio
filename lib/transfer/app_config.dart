/// Typed runtime configuration for device-to-device transfers.
///
/// Values are compiled in from a gitignored `.env` file:
///
///     flutter run --dart-define-from-file=.env
///
/// See `.env.example` for every key. Nothing secret is hard-coded here; TURN credentials
/// only exist in the developer's `.env` and in the CI secrets used for release builds.
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
  const AppConfig({
    this.stunServers = const [IceServer(['stun:stun.l.google.com:19302'])],
    this.turnServers = const [],
    this.meteredDomain,
    this.meteredApiKey,
    this.forceRelay = false,
    this.peerServerHost = '0.peerjs.com',
    this.peerServerPort = 443,
    this.peerServerPath = '/',
    this.peerServerKey = 'peerjs',
    this.peerServerSecure = true,
    this.chunkSize = 16 * 1024,
    this.codeTtl = const Duration(minutes: 5),
    this.maxAttempts = 5,
    this.lanTimeout = const Duration(seconds: 5),
    this.internetConnectTimeout = const Duration(seconds: 20),
    this.acceptTimeout = const Duration(minutes: 2),
    this.resumeGracePeriod = const Duration(minutes: 2),
    this.flowControlWindow = 4 * 1024 * 1024,
    this.maxTransferBytes = 8 * 1024 * 1024 * 1024,
    this.maxFilesPerTransfer = 500,
  });

  /// STUN servers, tried first (free, no credentials).
  final List<IceServer> stunServers;

  /// Static TURN servers (e.g. Metered free tier) used when a direct path is impossible.
  final List<IceServer> turnServers;

  /// Alternative to [turnServers]: fetch short-lived Metered TURN credentials at runtime from
  /// `https://<meteredDomain>/api/v1/turn/credentials?apiKey=<meteredApiKey>`.
  final String? meteredDomain;
  final String? meteredApiKey;

  /// Only use relayed (TURN) candidates. For testing the TURN fallback.
  final bool forceRelay;

  /// PeerJS signaling server (PeerJS Cloud by default; no self-hosted server needed).
  final String peerServerHost;
  final int peerServerPort;
  final String peerServerPath;
  final String peerServerKey;
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

  bool get hasTurn => turnServers.isNotEmpty || (meteredDomain != null && meteredApiKey != null);

  /// ICE servers in priority order: STUN first, TURN as the fallback.
  List<IceServer> iceServers({List<IceServer> fetchedTurn = const []}) =>
      [...stunServers, ...turnServers, ...fetchedTurn];

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
  }) {
    return AppConfig(
      stunServers: stunServers ?? this.stunServers,
      turnServers: turnServers ?? this.turnServers,
      meteredDomain: meteredDomain,
      meteredApiKey: meteredApiKey,
      forceRelay: forceRelay ?? this.forceRelay,
      peerServerHost: peerServerHost ?? this.peerServerHost,
      peerServerPort: peerServerPort ?? this.peerServerPort,
      peerServerPath: peerServerPath,
      peerServerKey: peerServerKey,
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
    const stun = String.fromEnvironment('STUN_URLS', defaultValue: 'stun:stun.l.google.com:19302');
    const turnUrls = String.fromEnvironment('TURN_URLS');
    const turnUser = String.fromEnvironment('TURN_USERNAME');
    const turnCredential = String.fromEnvironment('TURN_CREDENTIAL');
    const meteredDomain = String.fromEnvironment('METERED_DOMAIN');
    const meteredKey = String.fromEnvironment('METERED_API_KEY');
    const forceRelay = bool.fromEnvironment('FORCE_TURN');
    const peerHost = String.fromEnvironment('PEER_SERVER_HOST', defaultValue: '0.peerjs.com');
    const peerPort = int.fromEnvironment('PEER_SERVER_PORT', defaultValue: 443);
    const peerSecure = bool.fromEnvironment('PEER_SERVER_SECURE', defaultValue: true);

    List<String> split(String v) => v.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

    return AppConfig(
      stunServers: [if (split(stun).isNotEmpty) IceServer(split(stun))],
      turnServers: [
        if (split(turnUrls).isNotEmpty) IceServer(split(turnUrls), username: turnUser, credential: turnCredential),
      ],
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
