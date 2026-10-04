import 'dart:async';
import 'dart:convert';

import 'package:async/async.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/utils/file_utils.dart';
import '../data/models/device_model.dart';
import '../data/models/history_record.dart';
import '../data/models/pairing_session.dart';
import '../data/models/received_item_model.dart';
import '../data/models/transfer_item.dart';
import '../data/services/peer_link.dart';
import '../data/services/transfer_engine.dart';
import 'app_config.dart';
import 'attempt_limiter.dart';
import 'channel.dart';
import 'connect_flow.dart';
import 'file_source.dart';
import 'internet/webrtc_link.dart';
import 'protocol/handshake.dart';
import 'protocol/transfer_protocol.dart';
import 'secure_channel.dart';
import 'sink_factory.dart';
import 'transfer_method.dart';
import 'transfer_settings.dart';

/// A live, authenticated connection to another device.
class ActiveLink {
  ActiveLink({
    required this.device,
    required this.method,
    required this.session,
    required this.verificationCode,
    this.relayed = false,
    this.resumeId,
  }) : connectedAt = DateTime.now();

  final DeviceModel device;
  final TransferMethod method;
  final PeerSession session;

  /// Four digits shown on both devices; they must match.
  final String verificationCode;

  /// Internet connections: whether data goes through a TURN relay.
  final bool relayed;

  /// Internet connections: secret the receiver handed out for resuming.
  final String? resumeId;
  final DateTime connectedAt;

  /// Live throughput of whatever is transferring on this link.
  double bytesPerSecond = 0;
  int activeTransfers = 0;

  bool get isOpen => session.isOpen;
}

/// An incoming offer waiting for the user to accept or decline.
class PendingOffer {
  PendingOffer(this.offer, this.link);
  final IncomingOffer offer;
  final ActiveLink link;
  final Completer<bool> _decision = Completer<bool>();
  final DateTime receivedAt = DateTime.now();

  bool get isDecided => _decision.isCompleted;
}

class _Tracked {
  _Tracked(this.device, this.method, this.files, this.outgoing);
  final DeviceModel device;
  final TransferMethod method;
  final List<FileSource> files;
  OutgoingTransfer outgoing;
  String? resumeId;
  StreamSubscription<TransferSnapshot>? sub;
}

/// Owns connections, the LAN -> internet -> Bluetooth fallback, and transfer sessions, so
/// screens never deal with how bytes travel. Progress is mirrored into [TransferEngine]'s
/// transfer list and history, which the existing screens already show.
class ConnectionManager extends ChangeNotifier {
  ConnectionManager._();
  static final ConnectionManager instance = ConnectionManager._();
  factory ConnectionManager() => instance;

  AppConfig config = AppConfig.current;
  final TransferSettings settings = TransferSettings.instance;
  late final PartialTransferStore partials = PartialTransferStore(onDiscarded: _onPartialDiscarded);
  final AttemptLimiter limiter = AttemptLimiter();

  /// Live connections by device id.
  final Map<String, ActiveLink> links = {};
  final List<PendingOffer> pendingOffers = [];
  final Map<String, _Tracked> _outgoing = {};

  late ConnectFlow<DeviceModel> flow = _newFlow();

  InternetHost? _host;
  String? _hostedPeerId;
  bool _hosting = false;

  /// Why this device's code is not reachable over the internet (null when it is).
  String? hostStatus;
  final Map<String, InternetHost> _resumeHosts = {};
  bool _started = false;
  StreamSubscription<IncomingLanSession>? _lanSub;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  Timer? _rehostTimer;

  /// Overridable for tests.
  Future<bool> Function() isOnline = _checkOnline;

  TransferEngine get _engine => TransferEngine();

  static String get platformName {
    if (kIsWeb) {
      return switch (defaultTargetPlatform) {
        TargetPlatform.windows => 'Windows',
        TargetPlatform.linux => 'Linux',
        TargetPlatform.macOS => 'macOS',
        _ => 'Desktop',
      };
    }
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'Android',
      TargetPlatform.iOS => 'iOS',
      TargetPlatform.windows => 'Windows',
      TargetPlatform.macOS => 'macOS',
      TargetPlatform.linux => 'Linux',
      _ => 'Device',
    };
  }

  LocalIdentity get me => LocalIdentity(id: _engine.localDeviceId, name: _engine.localDeviceName, platform: platformName);

  static Future<bool> _checkOnline() async {
    try {
      final results = await Connectivity().checkConnectivity();
      return results.any((r) => r != ConnectivityResult.none);
    } catch (_) {
      return true; // unknown: let the attempt itself decide
    }
  }

  bool get isStarted => _started;

  /// Starts background work (internet hosting, code expiry). Not called in tests.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    await settings.load();
    _engine.scheduleCodeExpiry();
    final link = _engine.peerLink;
    if (link != null) attachLan(link);
    final session = _engine.currentPairingSession;
    if (session != null) unawaited(hostCode(session));
    // Coming back online (or the service recovering) makes the code reachable again.
    try {
      _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
        if (results.any((r) => r != ConnectivityResult.none)) _rehost();
      });
    } catch (_) {}
    _rehostTimer = Timer.periodic(const Duration(seconds: 30), (_) => _rehost());
  }

  void _rehost() {
    final session = _engine.currentPairingSession;
    if (!settings.internetEnabled || _hosting || isHostingInternet || session == null || session.isExpired) return;
    unawaited(hostCode(session));
  }

  // -------------------------------------------------------------------------------------
  // Receiving side: make the current code reachable
  // -------------------------------------------------------------------------------------

  void attachLan(PeerLink link) {
    _lanSub?.cancel();
    _lanSub = link.incomingSessions.listen(_onIncomingLan);
  }

  /// Hosts [session]'s code on PeerJS (`qs-<code>`); the previous code's peer is destroyed.
  Future<void> hostCode(PairingSession session) async {
    if (!_started) return;
    if (_hostedPeerId == session.peerId && (_host?.isListening ?? false)) return;
    await stopHosting();
    if (!settings.internetEnabled) {
      hostStatus = 'Internet connections are turned off in Settings.';
      notifyListeners();
      return;
    }
    if (session.isExpired) return;
    _hostedPeerId = session.peerId;
    final host = InternetHost(
      config: config,
      peerId: session.peerId,
      me: me,
      verify: _verifyInternetProof,
      onConnection: _onInternetConnection,
      onFailedAttempt: (_) {
        final current = _engine.currentPairingSession;
        if (current != null && current.peerId == session.peerId && current.registerFailedAttempt()) {
          // Too many failed handshakes: this code is burned.
          _engine.regeneratePairingCode();
        }
      },
    );
    _host = host;
    _hosting = true;
    try {
      await host.start();
      if (_host == host) hostStatus = null;
    } catch (_) {
      if (_host == host) {
        _host = null;
        _hostedPeerId = null;
        hostStatus = (await isOnline())
            ? 'The internet connection service is unavailable right now. Same-Wi-Fi pairing still works.'
            : 'Offline: other devices can reach this one on the same Wi-Fi or over Bluetooth.';
      }
    } finally {
      _hosting = false;
    }
    notifyListeners();
  }

  bool get isHostingInternet => _host?.isListening ?? false;
  bool get isStartingHost => _hosting;

  Future<void> stopHosting() async {
    final host = _host;
    _host = null;
    _hostedPeerId = null;
    await host?.stop();
  }

  String _verifyInternetProof(String mode, String proof, String nonce, String binding) {
    final session = _engine.currentPairingSession;
    if (session == null || session.isExpired || session.peerId != _hostedPeerId) {
      throw HandshakeException('This code has expired. Ask for the new one.', countsAsFailedAttempt: true);
    }
    final List<int> secret = switch (mode) {
      'code' => utf8.encode(session.numericCode),
      'qr' => utf8.encode('${session.numericCode}|${session.nonce}'),
      _ => throw HandshakeException('Unsupported connection.', countsAsFailedAttempt: true),
    };
    if (!constantTimeEquals(proof, computeProof(secret, nonce, binding))) {
      throw HandshakeException('Wrong code.', countsAsFailedAttempt: true);
    }
    return randomToken(24);
  }

  void _onInternetConnection(InternetConnection c) {
    // A code works once: the next device needs a fresh one.
    _engine.regeneratePairingCode();
    _adopt(
      channel: c.channel,
      frames: c.frames,
      remote: c.remote,
      method: TransferMethod.internet,
      verificationCode: c.verificationCode,
      relayed: c.channel.relayed,
      resumeId: c.remote.resumeId,
    );
    HapticFeedback.mediumImpact();
  }

  Future<void> _onIncomingLan(IncomingLanSession s) async {
    final token = _engine.peerLink?.pairingToken(s.peerId);
    if (token == null) {
      await s.channel.close();
      return;
    }
    try {
      final secure = await SecureFrameChannel.establish(s.channel, StreamQueue(s.channel.frames),
          initiator: false, psk: utf8.encode(token));
      final known = _engine.pairedDevices.where((d) => d.id == s.peerId).firstOrNull;
      _adopt(
        channel: secure,
        frames: StreamQueue(secure.frames),
        remote: RemoteIdentity(id: s.peerId, name: known?.name ?? 'Paired device', platform: known?.platform ?? 'Device'),
        method: TransferMethod.lan,
        verificationCode: secure.verificationCode,
        listInDevices: false,
      );
    } catch (_) {
      await s.channel.close();
    }
  }

  /// Registers a Bluetooth (Wi-Fi Direct) connection set up by the Bluetooth transport.
  ActiveLink adoptBluetooth({
    required FrameChannel channel,
    required StreamQueue<Uint8List> frames,
    required RemoteIdentity remote,
    required String verificationCode,
  }) =>
      _adopt(channel: channel, frames: frames, remote: remote, method: TransferMethod.bluetooth, verificationCode: verificationCode);

  ActiveLink _adopt({
    required FrameChannel channel,
    required StreamQueue<Uint8List> frames,
    required RemoteIdentity remote,
    required TransferMethod method,
    required String verificationCode,
    bool relayed = false,
    String? resumeId,
    bool listInDevices = true,
  }) {
    final existing = _engine.pairedDevices.where((d) => d.id == remote.id).firstOrNull;
    final device = (existing ??
            DeviceModel(
              id: remote.id,
              name: remote.name,
              ip: method == TransferMethod.lan ? '' : method.badge,
              port: 0,
              platform: remote.platform,
              deviceType: _deviceType(remote.platform),
              isTrusted: true,
              isOnline: true,
            ))
        .copyWith(
      method: method == TransferMethod.lan && existing != null ? existing.method : method,
      verificationCode: verificationCode,
      isOnline: true,
    );
    late final ActiveLink link;
    final session = PeerSession(
      channel: channel,
      frames: frames,
      remote: remote,
      config: config,
      partials: partials,
      onOffer: (offer) => _onOffer(offer, link),
      openSink: (offer, i) => openIncomingSink(
        fileName: offer.files[i].name,
        size: offer.files[i].size,
        directory: _engine.downloadDirectory,
      ),
    );
    link = ActiveLink(
      device: device,
      method: method,
      session: session,
      verificationCode: verificationCode,
      relayed: relayed,
      resumeId: resumeId,
    );
    // An incoming LAN session must not replace this device's own outgoing session entry.
    if (listInDevices || !links.containsKey(device.id)) links[device.id] = link;
    session.incomingUpdates.listen((s) => _onIncomingUpdate(s, link));
    session.start();
    unawaited(session.closed.then((_) => _onLinkClosed(link)));
    if (listInDevices && method != TransferMethod.lan) {
      _engine.pairedDevices.removeWhere((d) => d.id == device.id);
      _engine.addPairedDevice(device);
    }
    notifyListeners();
    return link;
  }

  static DeviceType _deviceType(String platform) {
    final p = platform.toLowerCase();
    if (p.contains('android') || p.contains('ios') || p.contains('phone')) return DeviceType.mobile;
    return DeviceType.desktop;
  }

  void _onLinkClosed(ActiveLink link) {
    if (identical(links[link.device.id], link)) links.remove(link.device.id);
    pendingOffers.removeWhere((p) {
      if (identical(p.link, link) && !p.isDecided) {
        p._decision.complete(false);
        return true;
      }
      return false;
    });
    // Internet and Bluetooth devices exist only while connected.
    if (link.method != TransferMethod.lan && !links.containsKey(link.device.id)) {
      _engine.pairedDevices.removeWhere((d) => d.id == link.device.id && d.method == link.method);
      _engine.notifyListeners();
    }
    if (link.method == TransferMethod.internet) _hostResumeIfNeeded(link);
    notifyListeners();
  }

  /// After an internet drop mid-transfer, the receiver stays reachable for a resume at an
  /// unguessable peer ID, for [AppConfig.resumeGracePeriod].
  void _hostResumeIfNeeded(ActiveLink link) {
    final resumeId = link.resumeId;
    if (!_started || resumeId == null || _resumeHosts.containsKey(resumeId)) return;
    final interrupted = _engine.activeTransfers.any((t) =>
        !t.isSender && t.peerDeviceId == link.device.id && t.status == TransferStatus.paused);
    if (!interrupted) return;
    final host = InternetHost(
      config: config,
      peerId: 'qs-r-$resumeId',
      me: me,
      verify: (mode, proof, nonce, binding) {
        if (mode != 'resume' || !constantTimeEquals(proof, computeProof(utf8.encode(resumeId), nonce, binding))) {
          throw HandshakeException('Not allowed.', countsAsFailedAttempt: true);
        }
        return resumeId;
      },
      onConnection: (c) {
        _adopt(
          channel: c.channel,
          frames: c.frames,
          remote: c.remote,
          method: TransferMethod.internet,
          verificationCode: c.verificationCode,
          relayed: c.channel.relayed,
          resumeId: resumeId,
        );
      },
    );
    _resumeHosts[resumeId] = host;
    host.start().catchError((_) {});
    Timer(config.resumeGracePeriod, () async {
      await _resumeHosts.remove(resumeId)?.stop();
    });
  }

  // -------------------------------------------------------------------------------------
  // Sending side: connect with a code (LAN first, then the internet)
  // -------------------------------------------------------------------------------------

  ConnectFlow<DeviceModel> _newFlow({String code = '', String? qrNonce, String? host, int? port}) {
    return ConnectFlow<DeviceModel>(
      lan: (token) => _connectLan(code, host, port, token),
      internet: (token) => _connectInternet(code, qrNonce, token),
      isOnline: () => isOnline(),
      lanTimeout: config.lanTimeout,
      autoInternet: settings.autoFallback,
    );
  }

  ConnectFlowState get connectState => flow.state.value;

  /// Connects to the device showing [code]. With a scanned QR code pass its [qrNonce] (and
  /// LAN [host]/[port]). Progress is published through [flow].
  Future<DeviceModel?> connectWithCode(String code, {String? qrNonce, String? host, int? port}) async {
    final clean = code.replaceAll(RegExp(r'\D'), '');
    await flow.cancel(silent: true);
    final old = flow;
    flow = _newFlow(code: clean, qrNonce: qrNonce, host: host, port: port);
    _forwardFlow();
    old.dispose();
    if (limiter.isLocked) {
      flow.state.value = ConnectFlowState(
        phase: ConnectPhase.failed,
        failure: ConnectFailure.lockedOut,
        detail: 'Too many wrong codes. Try again in ${_seconds(limiter.lockRemaining)}.',
      );
      return null;
    }
    final preferred = settings.defaultMethod;
    if (preferred == TransferMethod.internet) return flow.tryInternet();
    return flow.run();
  }

  /// [Try over internet] after the LAN search failed.
  Future<DeviceModel?> tryInternet() => flow.tryInternet();

  Future<DeviceModel?> retryConnect() => flow.run();

  Future<void> cancelConnect() => flow.cancel();

  void resetConnect() => flow.reset();

  void _forwardFlow() => flow.state.addListener(notifyListeners);

  static String _seconds(Duration d) => d.inSeconds >= 90 ? '${(d.inSeconds / 60).ceil()} minutes' : '${d.inSeconds} seconds';

  Future<DeviceModel> _connectLan(String code, String? host, int? port, CancelToken token) async {
    final link = _engine.peerLink;
    if (link == null || !link.isAvailable) {
      throw ConnectException(ConnectFailure.notFoundOnLan, 'Local network sharing is not available.');
    }
    try {
      final device = (host != null && host.isNotEmpty && host != '0.0.0.0' && port != null && port > 0)
          ? await link.pairDirect(host, port, code)
          : await link.pairWithCode(code);
      if (token.isCancelled) throw CancelledException();
      _engine.lastPairingError = null;
      _engine.addPairedDevice(device);
      limiter.recordSuccess();
      return device;
    } on PeerLinkException catch (e) {
      if (e.message.contains('Too many wrong codes')) throw ConnectException(ConnectFailure.lockedOut, e.message);
      throw ConnectException(ConnectFailure.notFoundOnLan, e.message);
    }
  }

  Future<DeviceModel> _connectInternet(String code, String? qrNonce, CancelToken token) async {
    if (limiter.isLocked) {
      throw ConnectException(ConnectFailure.lockedOut, 'Too many wrong codes. Try again in ${_seconds(limiter.lockRemaining)}.');
    }
    final own = _engine.currentPairingSession;
    if (own != null && own.numericCode == code) {
      throw ConnectException(ConnectFailure.wrongCode, "That's this device's own code. Enter the code shown on the other device.");
    }
    try {
      final c = await connectToPeer(
        config: config,
        targetPeerId: 'qs-$code',
        me: me,
        mode: qrNonce != null ? 'qr' : 'code',
        secret: utf8.encode(qrNonce != null ? '$code|$qrNonce' : code),
        token: token,
      );
      limiter.recordSuccess();
      final link = _adopt(
        channel: c.channel,
        frames: c.frames,
        remote: c.remote,
        method: TransferMethod.internet,
        verificationCode: c.verificationCode,
        relayed: c.channel.relayed,
        resumeId: c.remote.resumeId,
      );
      HapticFeedback.mediumImpact();
      return link.device;
    } on ConnectException catch (e) {
      if (e.kind == ConnectFailure.wrongCode || e.kind == ConnectFailure.rejected) {
        if (limiter.recordFailure()) {
          throw ConnectException(ConnectFailure.lockedOut,
              '${e.message} Too many wrong codes: wait ${_seconds(limiter.lockRemaining)} before trying again.');
        }
        final left = limiter.remainingAttempts;
        throw ConnectException(e.kind, '${e.message} ($left ${left == 1 ? 'try' : 'tries'} left)');
      }
      rethrow;
    }
  }

  // -------------------------------------------------------------------------------------
  // Sending files
  // -------------------------------------------------------------------------------------

  /// Whether [device] can receive files right now.
  bool canSendTo(DeviceModel device) {
    if (device.method == TransferMethod.lan) return _engine.peerLink?.isAvailable ?? false;
    return links[device.id]?.isOpen ?? false;
  }

  Future<PeerSession> _sessionFor(DeviceModel device) async {
    if (device.method != TransferMethod.lan) {
      final link = links[device.id];
      if (link == null || !link.isOpen) {
        throw PeerLinkException('"${device.name}" is no longer connected. Connect again with a new code.');
      }
      return link.session;
    }
    final peerLink = _engine.peerLink;
    if (peerLink == null) throw PeerLinkException('Local network sharing is not available.');
    final token = peerLink.pairingToken(device.id);
    if (token == null) throw PeerLinkException('"${device.name}" is not paired with this device. Pair again.');
    final raw = await peerLink.openSession(device);
    try {
      final secure = await SecureFrameChannel.establish(raw, StreamQueue(raw.frames), initiator: true, psk: utf8.encode(token));
      final link = _adopt(
        channel: secure,
        frames: StreamQueue(secure.frames),
        remote: RemoteIdentity(id: device.id, name: device.name, platform: device.platform ?? 'Device'),
        method: TransferMethod.lan,
        verificationCode: secure.verificationCode,
      );
      return link.session;
    } on SecureChannelException catch (e) {
      throw PeerLinkException(e.authentication
          ? '"${device.name}" could not prove it is the device you paired with. Pair again.'
          : 'Could not set up an encrypted connection with "${device.name}".');
    }
  }

  /// Starts sending [files] to [device]; returns the tracked item at once.
  Future<TransferItem> send(DeviceModel device, List<FileSource> files) async {
    final session = await _sessionFor(device);
    final link = links[device.id];
    final method = link?.method ?? device.method;
    final out = OutgoingTransfer(files: files, config: config, peerName: device.name);
    final total = files.fold<int>(0, (s, f) => s + f.size);
    final item = TransferItem(
      transferId: out.transferId,
      fileName: files.length == 1 ? files.first.name : '${files.first.name} + ${files.length - 1} more',
      fileSizeBytes: total,
      fileType: files.length == 1 && FileUtils.isPdfFilename(files.first.name)
          ? TransferFileType.pdf
          : files.length == 1 && FileUtils.isImageFilename(files.first.name)
              ? TransferFileType.image
              : TransferFileType.other,
      sha256: '',
      totalChunks: (total / config.chunkSize).ceil().clamp(1, 1 << 30),
      isSender: true,
      peerDeviceName: device.name,
      peerDeviceId: device.id,
      connectionType: method.historyLabel,
      method: method,
      fileCount: files.length,
      rawBytes: files.length == 1 && files.first is BytesFileSource ? (files.first as BytesFileSource).bytes : null,
      status: TransferStatus.queued,
    );
    _engine.addActiveTransfer(item);
    final tracked = _Tracked(device, method, files, out);
    _outgoing[out.transferId] = tracked;
    _watch(tracked);
    unawaited(_run(tracked, session));
    return item;
  }

  void _watch(_Tracked t) {
    t.sub?.cancel();
    t.sub = t.outgoing.updates.listen((s) {
      final link = links[t.device.id];
      if (link != null) link.bytesPerSecond = s.phase == TransferPhase.transferring ? s.bytesPerSecond : 0;
      _mirror(s, t.device, t.method);
    });
  }

  Future<void> _run(_Tracked t, PeerSession session, {bool resume = false}) async {
    final link = links[t.device.id];
    link?.activeTransfers++;
    final result = await t.outgoing.run(session, resume: resume);
    link?.activeTransfers--;
    _mirror(result, t.device, t.method);
    if (result.phase.isFinal && result.phase != TransferPhase.interrupted) {
      _recordOutgoingHistory(t, result);
    }
    if (result.phase == TransferPhase.completed) HapticFeedback.lightImpact();
    // LAN sessions are opened per transfer; close once idle.
    if (t.method == TransferMethod.lan && link != null && link.activeTransfers == 0) {
      Timer(const Duration(seconds: 3), () {
        if (link.activeTransfers == 0 && identical(links[t.device.id], link)) link.session.close();
      });
    }
  }

  void _recordOutgoingHistory(_Tracked t, TransferSnapshot s) {
    final status = switch (s.phase) {
      TransferPhase.completed => 'completed',
      TransferPhase.cancelled => 'cancelled',
      TransferPhase.declined => 'declined',
      _ => 'failed',
    };
    for (var i = 0; i < t.files.length; i++) {
      final f = t.files[i];
      final delivered = s.phase == TransferPhase.completed || i < t.outgoing.completedFiles;
      _engine.addHistoryRecord(HistoryRecord(
        fileName: f.name,
        fileSize: f.size,
        senderName: _engine.localDeviceName,
        recipientName: t.device.name,
        isIncoming: false,
        status: delivered ? 'completed' : status,
        sha256: '',
        connectionType: t.method.historyLabel,
      ));
    }
  }

  /// Mirrors a protocol snapshot into the engine's transfer list.
  void _mirror(TransferSnapshot s, DeviceModel device, TransferMethod method) {
    final idx = _engine.activeTransfers.indexWhere((t) => t.transferId == s.transferId);
    if (idx == -1) return;
    final status = switch (s.phase) {
      TransferPhase.waitingForAccept => TransferStatus.queued,
      TransferPhase.transferring => TransferStatus.transferring,
      TransferPhase.completed => TransferStatus.completed,
      TransferPhase.cancelled || TransferPhase.declined => TransferStatus.cancelled,
      TransferPhase.failed => TransferStatus.failed,
      TransferPhase.interrupted => TransferStatus.paused,
    };
    final current = _engine.activeTransfers[idx];
    _engine.updateTransfer(current.copyWith(
      progress: s.progress.clamp(0.0, 1.0),
      transferredChunks: (s.progress * current.totalChunks).floor(),
      status: status,
      speedBytesPerSec: s.phase == TransferPhase.transferring ? s.bytesPerSecond : 0,
      eta: s.eta,
      clearEta: s.eta == null,
      errorMessage: s.phase == TransferPhase.waitingForAccept
          ? 'Waiting for ${device.name} to accept...'
          : (s.error == null || s.error!.isEmpty ? null : s.error),
      resumable: s.resumable,
      completedTime: s.phase == TransferPhase.completed ? DateTime.now() : null,
    ));
  }

  /// Continues an interrupted outgoing transfer where it stopped.
  Future<void> resume(String transferId) async {
    final t = _outgoing[transferId];
    if (t == null) throw PeerLinkException('This transfer can no longer be resumed. Send it again.');
    PeerSession session;
    if (t.method == TransferMethod.internet && !(links[t.device.id]?.isOpen ?? false)) {
      final resumeId = t.resumeId ?? links[t.device.id]?.resumeId;
      if (resumeId == null) throw PeerLinkException('Reconnect with a new code and send again.');
      final c = await connectToPeer(
        config: config,
        targetPeerId: 'qs-r-$resumeId',
        me: me,
        mode: 'resume',
        secret: utf8.encode(resumeId),
        token: CancelToken(),
      ).catchError((Object e) => throw PeerLinkException(
          '${t.device.name} is no longer reachable for a resume. Connect again with a new code and resend.'));
      final link = _adopt(
        channel: c.channel,
        frames: c.frames,
        remote: c.remote,
        method: TransferMethod.internet,
        verificationCode: c.verificationCode,
        relayed: c.channel.relayed,
        resumeId: resumeId,
      );
      session = link.session;
    } else {
      session = await _sessionFor(t.device);
    }
    _watch(t);
    unawaited(_run(t, session, resume: true));
  }

  /// Starts an interrupted or failed transfer again from the beginning.
  Future<TransferItem?> retry(String transferId) async {
    final t = _outgoing.remove(transferId);
    if (t == null) return null;
    await t.sub?.cancel();
    _engine.removeTransfer(transferId);
    return send(t.device, t.files);
  }

  bool isTracked(String transferId) => _outgoing.containsKey(transferId) || _incomingIds.contains(transferId);

  final Set<String> _incomingIds = {};

  /// Cancels a transfer in either direction; partial data is deleted.
  Future<void> cancel(String transferId) async {
    final t = _outgoing[transferId];
    if (t != null) {
      await t.outgoing.cancel();
      _mirror(t.outgoing.snapshot, t.device, t.method);
      return;
    }
    // Interrupted incoming transfers wait in the resume store, detached from any connection.
    if (await partials.discard(transferId)) return;
    for (final link in links.values) {
      await link.session.cancelIncoming(transferId);
    }
  }

  void _onPartialDiscarded(String transferId, {required bool expired}) {
    final idx = _engine.activeTransfers.indexWhere((t) => t.transferId == transferId);
    if (idx == -1) return;
    _engine.updateTransfer(_engine.activeTransfers[idx].copyWith(
      status: expired ? TransferStatus.failed : TransferStatus.cancelled,
      errorMessage: expired ? "The sender didn't resume in time; the partial file was deleted." : 'Cancelled. The partial file was deleted.',
      resumable: false,
      speedBytesPerSec: 0,
      clearEta: true,
    ));
  }

  // -------------------------------------------------------------------------------------
  // Receiving files
  // -------------------------------------------------------------------------------------

  Future<bool> _onOffer(IncomingOffer offer, ActiveLink link) async {
    if (offer.isResume) return true;
    if (settings.autoAccept) return true;
    final pending = PendingOffer(offer, link);
    pendingOffers.add(pending);
    HapticFeedback.heavyImpact();
    notifyListeners();
    final decision = await pending._decision.future
        .timeout(config.acceptTimeout - const Duration(seconds: 5), onTimeout: () => false);
    pendingOffers.remove(pending);
    notifyListeners();
    return decision;
  }

  void acceptOffer(PendingOffer p) {
    if (!p.isDecided) p._decision.complete(true);
    pendingOffers.remove(p);
    notifyListeners();
  }

  void declineOffer(PendingOffer p) {
    if (!p.isDecided) p._decision.complete(false);
    pendingOffers.remove(p);
    notifyListeners();
  }

  final Map<String, int> _deliveredCounts = {};

  void _onIncomingUpdate(TransferSnapshot s, ActiveLink link) {
    _incomingIds.add(s.transferId);
    final idx = _engine.activeTransfers.indexWhere((t) => t.transferId == s.transferId);
    if (idx == -1 && s.phase == TransferPhase.transferring) {
      _engine.addActiveTransfer(TransferItem(
        transferId: s.transferId,
        fileName: s.files.length == 1 ? s.files.first.name : '${s.files.first.name} + ${s.files.length - 1} more',
        fileSizeBytes: s.totalBytes,
        fileType: TransferFileType.other,
        sha256: '',
        totalChunks: (s.totalBytes / config.chunkSize).ceil().clamp(1, 1 << 30),
        isSender: false,
        peerDeviceName: link.device.name,
        peerDeviceId: link.device.id,
        connectionType: link.method.historyLabel,
        method: link.method,
        fileCount: s.files.length,
        status: TransferStatus.transferring,
      ));
    }
    link.bytesPerSecond = s.phase == TransferPhase.transferring ? s.bytesPerSecond : 0;
    _mirror(s, link.device, link.method);

    // Hand each verified file to Received Items / history as soon as it is complete.
    final delivered = _deliveredCounts[s.transferId] ?? 0;
    for (var i = delivered; i < s.received.length; i++) {
      final f = s.received[i];
      _engine.receiveIncomingTransfer(
        senderDeviceName: '${link.device.name} (${link.device.platform ?? link.method.badge})',
        fileName: f.name,
        bytes: f.bytes ?? Uint8List(0),
        fileType: FileUtils.isPdfFilename(f.name)
            ? ReceivedFileType.pdf
            : FileUtils.isImageFilename(f.name)
                ? ReceivedFileType.image
                : ReceivedFileType.other,
        savedPath: f.path,
        sha256: f.sha256,
        sizeBytes: f.size,
        connectionType: link.method.historyLabel,
      );
    }
    _deliveredCounts[s.transferId] = s.received.length;
    if (s.phase.isFinal && s.phase != TransferPhase.completed && s.phase != TransferPhase.interrupted) {
      _engine.addHistoryRecord(HistoryRecord(
        fileName: s.currentFileName,
        fileSize: s.totalBytes,
        senderName: link.device.name,
        recipientName: _engine.localDeviceName,
        isIncoming: true,
        status: s.phase == TransferPhase.declined ? 'declined' : (s.phase == TransferPhase.cancelled ? 'cancelled' : 'failed'),
        sha256: '',
        connectionType: link.method.historyLabel,
      ));
    }
  }

  // -------------------------------------------------------------------------------------
  // Disconnect & cleanup
  // -------------------------------------------------------------------------------------

  /// Ends the connection with [deviceId] (internet / Bluetooth devices disappear).
  Future<void> disconnect(String deviceId) async {
    final link = links.remove(deviceId);
    await link?.session.close();
    notifyListeners();
  }

  /// Everything off: used when the app closes or the user ends all sessions.
  Future<void> shutdown() async {
    await _connectivitySub?.cancel();
    _rehostTimer?.cancel();
    await flow.cancel(silent: true);
    await stopHosting();
    for (final h in _resumeHosts.values) {
      await h.stop();
    }
    _resumeHosts.clear();
    for (final link in links.values.toList()) {
      await link.session.close();
    }
    links.clear();
    partials.discardAll();
  }

  @visibleForTesting
  void resetForTest() {
    links.clear();
    pendingOffers.clear();
    _outgoing.clear();
    _incomingIds.clear();
    _deliveredCounts.clear();
    limiter.recordSuccess();
    flow.reset();
  }
}
