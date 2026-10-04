import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../channel.dart';

/// [FrameChannel] over a WebSocket (one binary message per frame). Used for LAN sessions,
/// always wrapped in a SecureFrameChannel. WebSockets have no send-side backpressure API;
/// the transfer protocol's flow-control window bounds what is in flight.
class WebSocketFrameChannel implements FrameChannel {
  WebSocketFrameChannel(this._socket) {
    _socket.stream.listen(
      (message) {
        if (_incoming.isClosed) return;
        if (message is Uint8List) {
          _incoming.add(message);
        } else if (message is List<int>) {
          _incoming.add(Uint8List.fromList(message));
        } else if (message is String) {
          _incoming.add(Uint8List.fromList(utf8.encode(message)));
        }
      },
      onDone: _shutdown,
      onError: (_) => _shutdown(),
      cancelOnError: true,
    );
  }

  final WebSocketChannel _socket;
  final _incoming = StreamController<Uint8List>();
  final _closed = Completer<void>();

  @override
  Stream<Uint8List> get frames => _incoming.stream;

  @override
  bool get isOpen => !_closed.isCompleted;

  @override
  Future<void> get closed => _closed.future;

  @override
  Future<void> send(Uint8List frame) async {
    if (!isOpen) throw ChannelClosedException();
    _socket.sink.add(frame);
  }

  @override
  Future<void> close() async {
    if (!isOpen) return;
    _shutdown();
    try {
      await _socket.sink.close();
    } catch (_) {}
  }

  void _shutdown() {
    if (_closed.isCompleted) return;
    _closed.complete();
    _incoming.close();
  }
}
