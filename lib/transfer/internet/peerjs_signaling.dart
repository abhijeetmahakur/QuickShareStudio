import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../app_config.dart';

/// Minimal client for the PeerJS signaling protocol, so QuickShare can use the free PeerJS
/// Cloud (0.peerjs.com) without running a server.
///
/// Only the messages PeerJS itself uses are sent, in exactly its shape (OFFER / ANSWER /
/// CANDIDATE with `type: "data"` and a `connectionId`): PeerJS Cloud silently drops anything
/// else. Measured behaviour of the cloud (Oct 2026): `OPEN` arrives in < 1 s; an OFFER to an
/// unknown peer ID is answered with `EXPIRE` within about a second.
class PeerJsSignaling {
  PeerJsSignaling({required this.config, required this.peerId, WebSocketChannel Function(Uri uri)? connect})
      : _connect = connect ?? WebSocketChannel.connect,
        token = _randomId(10);

  final AppConfig config;
  final String peerId;
  final String token;
  final WebSocketChannel Function(Uri uri) _connect;

  static const String clientVersion = '1.5.5';

  WebSocketChannel? _socket;
  Timer? _heartbeat;
  final _messages = StreamController<SignalMessage>.broadcast();
  final _closed = Completer<void>();
  Completer<void>? _opening;
  bool _open = false;

  Stream<SignalMessage> get messages => _messages.stream;
  Future<void> get closed => _closed.future;
  bool get isOpen => _open && !_closed.isCompleted;

  static String _randomId(int length) {
    const alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final r = Random.secure();
    return List.generate(length, (_) => alphabet[r.nextInt(alphabet.length)]).join();
  }

  /// A random peer ID for a sender (senders are never looked up by ID).
  static String randomSenderId() => 'qs-s-${_randomId(12)}';

  Uri get uri => config.peerServerSocketUri.replace(queryParameters: {
        'id': peerId,
        'token': token,
        'version': clientVersion,
      });

  /// Registers [peerId] with the server. Throws [SignalingException].
  Future<void> open({Duration timeout = const Duration(seconds: 10)}) async {
    final opened = _opening = Completer<void>();
    final WebSocketChannel socket;
    try {
      socket = _connect(uri);
      _socket = socket;
      await socket.ready.timeout(timeout);
    } catch (e) {
      _finish();
      throw SignalingException(SignalingError.unreachable, 'Could not reach the connection service.');
    }

    socket.stream.listen(
      (raw) {
        Map<String, dynamic> msg;
        try {
          msg = jsonDecode(raw is String ? raw : utf8.decode(raw as List<int>)) as Map<String, dynamic>;
        } catch (_) {
          return;
        }
        final type = msg['type']?.toString() ?? '';
        switch (type) {
          case 'OPEN':
            _open = true;
            if (!opened.isCompleted) opened.complete();
          case 'ID-TAKEN':
            if (!opened.isCompleted) {
              opened.completeError(SignalingException(SignalingError.idTaken, 'That code is already in use.'));
            }
          case 'ERROR':
            final text = (msg['payload'] is Map ? msg['payload']['msg'] : null)?.toString() ?? 'Signaling error.';
            if (!opened.isCompleted) {
              opened.completeError(SignalingException(SignalingError.server, text));
            } else {
              _messages.add(SignalMessage(type, msg['src']?.toString(), msg['dst']?.toString(), const {}));
            }
          case 'HEARTBEAT':
            break;
          default:
            final payload = msg['payload'];
            _messages.add(SignalMessage(
              type,
              msg['src']?.toString(),
              msg['dst']?.toString(),
              payload is Map<String, dynamic> ? payload : const {},
            ));
        }
      },
      onError: (_) => _finish(),
      onDone: _finish,
      cancelOnError: true,
    );

    try {
      await opened.future.timeout(timeout);
    } on TimeoutException {
      await close();
      throw SignalingException(SignalingError.unreachable, 'The connection service did not respond.');
    } catch (_) {
      await close();
      rethrow;
    }
    _heartbeat = Timer.periodic(const Duration(seconds: 5), (_) => _sendRaw({'type': 'HEARTBEAT'}));
  }

  void _sendRaw(Map<String, dynamic> message) {
    if (!isOpen) return;
    try {
      _socket?.sink.add(jsonEncode(message));
    } catch (_) {}
  }

  void sendOffer(String dst, {required String connectionId, required String sdp}) => _sendRaw({
        'type': 'OFFER',
        'payload': {
          'sdp': {'sdp': sdp, 'type': 'offer'},
          'type': 'data',
          'connectionId': connectionId,
          'label': connectionId,
          'reliable': true,
          'serialization': 'binary',
        },
        'dst': dst,
      });

  void sendAnswer(String dst, {required String connectionId, required String sdp}) => _sendRaw({
        'type': 'ANSWER',
        'payload': {
          'sdp': {'sdp': sdp, 'type': 'answer'},
          'type': 'data',
          'connectionId': connectionId,
        },
        'dst': dst,
      });

  void sendCandidate(String dst, {required String connectionId, required Map<String, dynamic> candidate}) => _sendRaw({
        'type': 'CANDIDATE',
        'payload': {'candidate': candidate, 'type': 'data', 'connectionId': connectionId},
        'dst': dst,
      });

  /// Leaves the server: the peer ID stops existing immediately.
  Future<void> close() async {
    _heartbeat?.cancel();
    final socket = _socket;
    _socket = null;
    if (socket != null) {
      try {
        await socket.sink.close();
      } catch (_) {}
    }
    _finish();
  }

  void _finish() {
    _open = false;
    _heartbeat?.cancel();
    // close() during open(): fail the pending open right away instead of waiting it out.
    final opening = _opening;
    if (opening != null && !opening.isCompleted) {
      opening.completeError(SignalingException(SignalingError.unreachable, 'Closed.'));
    }
    if (!_closed.isCompleted) _closed.complete();
    if (!_messages.isClosed) _messages.close();
  }
}

class SignalMessage {
  const SignalMessage(this.type, this.src, this.dst, this.payload);
  final String type;
  final String? src;
  final String? dst;
  final Map<String, dynamic> payload;

  String? get connectionId => payload['connectionId']?.toString();

  String? get sdp {
    final s = payload['sdp'];
    return s is Map ? s['sdp']?.toString() : null;
  }

  Map<String, dynamic>? get candidate {
    final c = payload['candidate'];
    return c is Map<String, dynamic> ? c : null;
  }
}

enum SignalingError { unreachable, idTaken, server }

class SignalingException implements Exception {
  SignalingException(this.kind, this.message);
  final SignalingError kind;
  final String message;
  @override
  String toString() => message;
}
