import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:async/async.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;

import '../app_config.dart';
import '../channel.dart';
import '../connect_flow.dart';
import '../protocol/handshake.dart';
import 'peerjs_signaling.dart';

/// [FrameChannel] over an RTCDataChannel (encrypted by WebRTC's DTLS).
///
/// Backpressure: when `bufferedAmount` rises above [highWaterMark], [send] waits for the
/// `bufferedamountlow` event (threshold [lowWaterMark]) before letting the caller continue.
class DataChannelFrameChannel implements FrameChannel {
  DataChannelFrameChannel(this.pc, this.dc, {this.highWaterMark = 1024 * 1024, this.lowWaterMark = 256 * 1024}) {
    dc.bufferedAmountLowThreshold = lowWaterMark;
    dc.onBufferedAmountLow = (_) => _wakeSenders();
    dc.onMessage = (m) {
      if (_incoming.isClosed) return;
      _incoming.add(m.isBinary ? m.binary : Uint8List.fromList(utf8.encode(m.text)));
    };
    dc.onDataChannelState = (s) {
      if (s == RTCDataChannelState.RTCDataChannelClosed || s == RTCDataChannelState.RTCDataChannelClosing) {
        _shutdown();
      }
    };
    pc.onConnectionState = (s) {
      switch (s) {
        case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
        case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
          _shutdown();
        case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
          // Often recovers within seconds (e.g. a network switch); give it a moment.
          _disconnectTimer ??= Timer(const Duration(seconds: 8), _shutdown);
        case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
          _disconnectTimer?.cancel();
          _disconnectTimer = null;
        default:
          break;
      }
    };
  }

  final RTCPeerConnection pc;
  final RTCDataChannel dc;
  final int highWaterMark;
  final int lowWaterMark;
  final _incoming = StreamController<Uint8List>();
  final _closed = Completer<void>();
  final List<Completer<void>> _waiters = [];
  Timer? _disconnectTimer;

  /// Four digits derived from both DTLS fingerprints (see [fingerprintCode]).
  String verificationCode = '';

  /// Whether the active path goes through a TURN relay (set after connecting).
  bool relayed = false;

  @override
  Stream<Uint8List> get frames => _incoming.stream;

  @override
  bool get isOpen => !_closed.isCompleted;

  @override
  Future<void> get closed => _closed.future;

  void _wakeSenders() {
    for (final w in _waiters) {
      if (!w.isCompleted) w.complete();
    }
    _waiters.clear();
  }

  @override
  Future<void> send(Uint8List frame) async {
    if (!isOpen) throw ChannelClosedException();
    while (isOpen && (dc.bufferedAmount ?? 0) > highWaterMark) {
      final waiter = Completer<void>();
      _waiters.add(waiter);
      // The event is the fast path; the poll guards against a missed event.
      await Future.any([waiter.future, closed, Future<void>.delayed(const Duration(milliseconds: 30))]);
      if ((dc.bufferedAmount ?? 0) > highWaterMark) {
        try {
          await dc.getBufferedAmount();
        } catch (_) {}
      }
    }
    if (!isOpen) throw ChannelClosedException();
    await dc.send(RTCDataChannelMessage.fromBinary(frame));
  }

  @override
  Future<void> close() async {
    if (!isOpen) return;
    _shutdown();
  }

  void _shutdown() {
    if (_closed.isCompleted) return;
    _disconnectTimer?.cancel();
    _closed.complete();
    _wakeSenders();
    _incoming.close();
    // Closing tears down DTLS/ICE; nothing about the session survives.
    unawaited(() async {
      try {
        await dc.close();
      } catch (_) {}
      try {
        await pc.close();
      } catch (_) {}
    }());
  }
}

/// SHA-256 fingerprints from an SDP (`a=fingerprint:sha-256 AB:CD:...`).
List<String> sdpFingerprints(String? sdp) {
  if (sdp == null) return const [];
  return RegExp(r'^a=fingerprint:(\S+) (\S+)\s*$', multiLine: true)
      .allMatches(sdp)
      .map((m) => '${m.group(1)!.toLowerCase()} ${m.group(2)!.toUpperCase()}')
      .toSet()
      .toList()
    ..sort();
}

/// The same 4 digits on both devices if, and only if, both see the same pair of DTLS
/// certificates, i.e. nobody (not even the signaling server) is in the middle.
String fingerprintCode(String localFingerprint, String remoteFingerprint) {
  final pair = [localFingerprint, remoteFingerprint]..sort();
  final digest = sha256.convert(utf8.encode('quickshare-sas-v1|${pair.join('|')}')).bytes;
  final n = ((digest[0] << 24) | (digest[1] << 16) | (digest[2] << 8) | digest[3]) & 0x7FFFFFFF;
  return (n % 10000).toString().padLeft(4, '0');
}

/// Result of an internet connection: an authenticated channel plus who is on the other end.
class InternetConnection {
  InternetConnection(this.channel, this.frames, this.remote);
  final DataChannelFrameChannel channel;
  final StreamQueue<Uint8List> frames;
  final RemoteIdentity remote;
  String get verificationCode => channel.verificationCode;
}

/// Short-lived TURN credentials from Metered (cached for 10 minutes).
class TurnCredentials {
  static List<IceServer>? _cached;
  static DateTime? _fetchedAt;

  static Future<List<IceServer>> fetch(AppConfig config, {http.Client? client}) async {
    final domain = config.meteredDomain, key = config.meteredApiKey;
    if (domain == null || key == null) return const [];
    final fetchedAt = _fetchedAt;
    if (_cached != null && fetchedAt != null && DateTime.now().difference(fetchedAt) < const Duration(minutes: 10)) {
      return _cached!;
    }
    try {
      final c = client ?? http.Client();
      final res = await c
          .get(Uri.https(domain, '/api/v1/turn/credentials', {'apiKey': key}))
          .timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) return const [];
      final list = (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
      _cached = [
        for (final s in list)
          IceServer(
            s['urls'] is List ? (s['urls'] as List).cast<String>() : [s['urls'].toString()],
            username: s['username']?.toString(),
            credential: s['credential']?.toString(),
          ),
      ];
      _fetchedAt = DateTime.now();
      return _cached!;
    } catch (_) {
      // Without TURN most connections still work (STUN); strict NATs will fail with noRoute.
      return const [];
    }
  }
}

Future<RTCPeerConnection> _newPeerConnection(AppConfig config) async {
  final turn = await TurnCredentials.fetch(config);
  final servers = config.iceServers(fetchedTurn: turn);
  return createPeerConnection({
    'iceServers': [for (final s in servers) s.toMap()],
    'iceTransportPolicy': config.forceRelay ? 'relay' : 'all',
    'sdpSemantics': 'unified-plan',
  });
}

Map<String, dynamic> _candidateJson(RTCIceCandidate c) => {
      'candidate': c.candidate,
      'sdpMid': c.sdpMid,
      'sdpMLineIndex': c.sdpMLineIndex,
    };

RTCIceCandidate _candidateFrom(Map<String, dynamic> c) => RTCIceCandidate(
      c['candidate']?.toString(),
      c['sdpMid']?.toString(),
      (c['sdpMLineIndex'] as num?)?.toInt(),
    );

/// Applies remote candidates only after the remote description is set.
class _CandidateBuffer {
  _CandidateBuffer(this.pc);
  final RTCPeerConnection pc;
  final List<RTCIceCandidate> _pending = [];
  bool _ready = false;

  Future<void> add(RTCIceCandidate c) async {
    if (!_ready) {
      _pending.add(c);
      return;
    }
    try {
      await pc.addCandidate(c);
    } catch (_) {}
  }

  Future<void> flush() async {
    _ready = true;
    for (final c in _pending) {
      try {
        await pc.addCandidate(c);
      } catch (_) {}
    }
    _pending.clear();
  }
}

/// The path is relayed if either end of the selected pair is a TURN relay (only one side may
/// need one).
bool _pairUsesRelay(Map<String, StatsReport> byId, StatsReport? pair) {
  if (pair == null) return false;
  final local = byId[pair.values['localCandidateId']];
  final remote = byId[pair.values['remoteCandidateId']];
  return local?.values['candidateType'] == 'relay' || remote?.values['candidateType'] == 'relay';
}

Future<bool> _isRelayed(RTCPeerConnection pc) async {
  try {
    final stats = await pc.getStats();
    final byId = {for (final r in stats) r.id: r};
    for (final r in stats) {
      if (r.type == 'transport' && r.values['selectedCandidatePairId'] != null) {
        return _pairUsesRelay(byId, byId[r.values['selectedCandidatePairId']]);
      }
    }
    for (final r in stats) {
      if (r.type == 'candidate-pair' && (r.values['nominated'] == true || r.values['selected'] == true) && r.values['state'] == 'succeeded') {
        return _pairUsesRelay(byId, r);
      }
    }
  } catch (_) {}
  return false;
}

Future<void> _bindVerification(RTCPeerConnection pc, DataChannelFrameChannel channel) async {
  final local = sdpFingerprints((await pc.getLocalDescription())?.sdp);
  final remote = sdpFingerprints((await pc.getRemoteDescription())?.sdp);
  channel.verificationCode = fingerprintCode(local.join(','), remote.join(','));
  channel.relayed = await _isRelayed(pc);
}

/// Binding of the handshake proof to this exact DTLS session.
Future<String> _sessionBinding(RTCPeerConnection pc) async {
  final local = sdpFingerprints((await pc.getLocalDescription())?.sdp).join(',');
  final remote = sdpFingerprints((await pc.getRemoteDescription())?.sdp).join(',');
  return ([local, remote]..sort()).join('|');
}

/// Sender side: connects to the device registered as [targetPeerId] and proves it knows the
/// code (and, from a QR scan, the one-time nonce).
Future<InternetConnection> connectToPeer({
  required AppConfig config,
  required String targetPeerId,
  required LocalIdentity me,
  required String mode,
  required List<int> secret,
  required CancelToken token,
}) async {
  debugPrint('[QuickShare] Joiner connecting to target peer ID: $targetPeerId (mode: $mode)');
  final signaling = PeerJsSignaling(config: config, peerId: PeerJsSignaling.randomSenderId());
  token.onCancel(signaling.close);
  try {
    await signaling.open();
    debugPrint('[QuickShare] Joiner signaling connected to ${config.peerServerHost}');
  } on SignalingException catch (e) {
    debugPrint('[QuickShare] Signaling exception during connect: ${e.message}');
    if (token.isCancelled) throw CancelledException();
    throw ConnectException(ConnectFailure.signalingUnavailable, e.message);
  }
  if (token.isCancelled) {
    await signaling.close();
    throw CancelledException();
  }

  final pc = await _newPeerConnection(config);
  var established = false;
  token.onCancel(() async {
    if (!established) await pc.close();
  });
  final connectionId = 'dc_${PeerJsSignaling.randomSenderId().substring(5)}';
  final dc = await pc.createDataChannel(connectionId, RTCDataChannelInit()..ordered = true..binaryType = 'binary');
  final channel = DataChannelFrameChannel(pc, dc);
  final frames = StreamQueue(channel.frames);
  final candidates = _CandidateBuffer(pc);
  final opened = Completer<void>();

  pc.onIceCandidate = (c) {
    if (c.candidate != null && c.candidate!.isNotEmpty) {
      final cand = c.candidate!;
      final typeMatch = RegExp(r'typ (\w+)').firstMatch(cand);
      final candType = typeMatch?.group(1) ?? 'unknown';
      debugPrint('[QuickShare] Joiner ICE candidate generated: type=$candType');
      signaling.sendCandidate(targetPeerId, connectionId: connectionId, candidate: _candidateJson(c));
    }
  };
  pc.onIceConnectionState = (s) {
    debugPrint('[QuickShare] Joiner ICE state: $s');
    if (s == RTCIceConnectionState.RTCIceConnectionStateFailed && !opened.isCompleted) {
      debugPrint('[QuickShare] Joiner ICE state failed with target $targetPeerId');
      opened.completeError(ConnectException(
        ConnectFailure.noRoute,
        config.hasTurn
            ? "The devices found each other but couldn't open a connection, even through the relay. Check that neither network blocks it, or use the same Wi-Fi."
            : "The devices found each other but their networks block a direct connection. A TURN relay is needed (see Settings → Help), or use the same Wi-Fi.",
      ));
    }
  };
  pc.onConnectionState = (s) {
    debugPrint('[QuickShare] Joiner PeerConnection state: $s');
  };
  // DataChannelFrameChannel installed its own state handler (closing); chain onto it.
  final closeHandler = dc.onDataChannelState;
  dc.onDataChannelState = (s) {
    debugPrint('[QuickShare] Joiner DataChannel state: $s');
    if (s == RTCDataChannelState.RTCDataChannelOpen && !opened.isCompleted) opened.complete();
    closeHandler?.call(s);
  };

  final sub = signaling.messages.listen((m) async {
    if (m.type == 'EXPIRE' && m.src == targetPeerId && !opened.isCompleted) {
      debugPrint('[QuickShare] PeerJS returned EXPIRE for $targetPeerId (host not online)');
      opened.completeError(ConnectException(
        ConnectFailure.wrongCode,
        'No device is online with that code. Check the code, or ask for a new one if it expired.',
      ));
    } else if (m.type == 'ANSWER' && m.connectionId == connectionId && m.sdp != null) {
      debugPrint('[QuickShare] Received answer SDP from $targetPeerId');
      await pc.setRemoteDescription(RTCSessionDescription(m.sdp, 'answer'));
      await candidates.flush();
    } else if (m.type == 'CANDIDATE' && m.connectionId == connectionId && m.candidate != null) {
      final cand = m.candidate!['candidate']?.toString() ?? '';
      final typeMatch = RegExp(r'typ (\w+)').firstMatch(cand);
      final candType = typeMatch?.group(1) ?? 'unknown';
      debugPrint('[QuickShare] Received remote candidate type: $candType');
      await candidates.add(_candidateFrom(m.candidate!));
    }
  });
  token.onCancel(sub.cancel);

  final offer = await pc.createOffer({});
  await pc.setLocalDescription(offer);
  signaling.sendOffer(targetPeerId, connectionId: connectionId, sdp: offer.sdp!);

  try {
    await Future.any([
      opened.future,
      token.whenCancelled.then((_) => throw CancelledException()),
    ]).timeout(config.internetConnectTimeout);
  } on TimeoutException {
    await channel.close();
    await signaling.close();
    throw ConnectException(
      ConnectFailure.noRoute,
      config.hasTurn
          ? 'Connecting took too long. The networks may block it; try again or use the same Wi-Fi.'
          : 'Connecting took too long. Strict networks need a TURN relay; try again or use the same Wi-Fi.',
    );
  } catch (_) {
    await channel.close();
    await signaling.close();
    rethrow;
  }

  try {
    final binding = await _sessionBinding(pc);
    final remote = await initiateHandshake(channel, frames, me, mode: mode, prove: (nonce) => computeProof(secret, nonce, binding));
    await _bindVerification(pc, channel);
    established = true;
    return InternetConnection(channel, frames, remote);
  } on HandshakeException catch (e) {
    await channel.close();
    throw ConnectException(ConnectFailure.rejected, e.message);
  } finally {
    // The signaling peer is temporary: once connected (or failed) it is destroyed.
    await sub.cancel();
    await signaling.close();
  }
}

/// Receiver side: registers [peerId] with PeerJS and accepts authenticated connections.
class InternetHost {
  InternetHost({
    required this.config,
    required this.peerId,
    required this.me,
    required this.verify,
    required this.onConnection,
    this.onFailedAttempt,
  });

  final AppConfig config;
  final String peerId;
  final LocalIdentity me;

  /// Checks the sender's proof; returns the resume id to hand out or throws HandshakeException.
  final String Function(String mode, String proof, String nonce, String binding) verify;
  final void Function(InternetConnection connection) onConnection;

  /// Called after a failed handshake (wrong proof / protocol abuse).
  final void Function(HandshakeException error)? onFailedAttempt;

  PeerJsSignaling? _signaling;
  final Map<String, RTCPeerConnection> _pending = {};
  bool _stopped = false;

  bool get isListening => _signaling?.isOpen ?? false;

  Future<void> start() async {
    final signaling = PeerJsSignaling(config: config, peerId: peerId);
    _signaling = signaling;
    await signaling.open();
    if (_stopped) {
      await signaling.close();
      return;
    }
    debugPrint('[QuickShare] Host registered successfully with PeerJS ID: $peerId');

    // Keep host online while Ready to Receive: auto-reconnect if signaling drops
    unawaited(signaling.closed.then((_) {
      if (!_stopped) {
        debugPrint('[QuickShare] Host signaling dropped for peer $peerId. Reconnecting in 2 seconds...');
        Timer(const Duration(seconds: 2), () {
          if (!_stopped) {
            start().catchError((e) {
              debugPrint('[QuickShare] Host auto-reconnect error: $e');
            });
          }
        });
      }
    }));

    final buffers = <String, _CandidateBuffer>{};
    signaling.messages.listen((m) async {
      final id = m.connectionId;
      final src = m.src;
      if (id == null || src == null || _stopped) return;
      if (m.type == 'OFFER' && m.sdp != null && !_pending.containsKey(id)) {
        debugPrint('[QuickShare] Host received incoming connection offer from $src (connectionId: $id)');
        if (_pending.length >= 4) return; // a burst of strangers; ignore the excess
        final pc = await _newPeerConnection(config);
        _pending[id] = pc;
        final buffer = buffers[id] = _CandidateBuffer(pc);
        pc.onIceCandidate = (c) {
          if (c.candidate != null && c.candidate!.isNotEmpty) {
            final cand = c.candidate!;
            final typeMatch = RegExp(r'typ (\w+)').firstMatch(cand);
            final candType = typeMatch?.group(1) ?? 'unknown';
            debugPrint('[QuickShare] Host generated ICE candidate: type=$candType');
            signaling.sendCandidate(src, connectionId: id, candidate: _candidateJson(c));
          }
        };
        pc.onIceConnectionState = (s) {
          debugPrint('[QuickShare] Host ICE state: $s');
        };
        pc.onConnectionState = (s) {
          debugPrint('[QuickShare] Host PeerConnection state: $s');
        };
        pc.onDataChannel = (dc) => _accept(id, pc, dc);
        // Give up on half-open attempts.
        Timer(config.internetConnectTimeout + const Duration(seconds: 15), () {
          final stale = _pending.remove(id);
          if (stale != null) stale.close();
        });
        await pc.setRemoteDescription(RTCSessionDescription(m.sdp, 'offer'));
        await buffer.flush();
        final answer = await pc.createAnswer({});
        await pc.setLocalDescription(answer);
        signaling.sendAnswer(src, connectionId: id, sdp: answer.sdp!);
      } else if (m.type == 'CANDIDATE' && m.candidate != null) {
        final cand = m.candidate!['candidate']?.toString() ?? '';
        final typeMatch = RegExp(r'typ (\w+)').firstMatch(cand);
        final candType = typeMatch?.group(1) ?? 'unknown';
        debugPrint('[QuickShare] Host received remote candidate type: $candType');
        await buffers[id]?.add(_candidateFrom(m.candidate!));
      }
    });
  }

  void _accept(String id, RTCPeerConnection pc, RTCDataChannel dc) {
    final channel = DataChannelFrameChannel(pc, dc);
    final frames = StreamQueue(channel.frames);
    final previous = dc.onDataChannelState;
    var started = false;
    var challengeSent = false;
    Timer? probe;
    Future<void> run() async {
      if (started) return;
      started = true;
      try {
        final binding = await _sessionBinding(pc);
        final remote = await acceptHandshake(
          channel,
          frames,
          me,
          verify: (mode, proof, nonce) => verify(mode, proof, nonce, binding),
          onChallengeSent: () => challengeSent = true,
        );
        probe?.cancel();
        await _bindVerification(pc, channel);
        _pending.remove(id);
        onConnection(InternetConnection(channel, frames, remote));
      } on HandshakeException catch (e) {
        probe?.cancel();
        _pending.remove(id);
        await channel.close();
        if (e.countsAsFailedAttempt) onFailedAttempt?.call(e);
      } catch (_) {
        if (!challengeSent && channel.isOpen) {
          // The channel was not open yet (sending throws until it is): try again shortly.
          started = false;
          return;
        }
        probe?.cancel();
        _pending.remove(id);
        await channel.close();
      }
    }

    dc.onDataChannelState = (s) {
      previous?.call(s);
      if (s == RTCDataChannelState.RTCDataChannelOpen) run();
    };
    if (dc.state == RTCDataChannelState.RTCDataChannelOpen) run();
    // On the web, dart_webrtc reports a remotely created channel as `connecting` whatever its
    // real state and relies on the `open` event, which can be missed when the browser
    // announces the channel as already open (seen on a slow CI runner): the sender then waits
    // for a challenge that never comes. Keep trying to start until the challenge goes out.
    probe = Timer.periodic(const Duration(milliseconds: 250), (t) {
      if (challengeSent || !channel.isOpen || t.tick > 120) {
        t.cancel();
        return;
      }
      run();
    });
  }

  /// Destroys the peer: the code stops being reachable over the internet immediately.
  Future<void> stop() async {
    _stopped = true;
    await _signaling?.close();
    _signaling = null;
    for (final pc in _pending.values) {
      try {
        await pc.close();
      } catch (_) {}
    }
    _pending.clear();
  }
}
