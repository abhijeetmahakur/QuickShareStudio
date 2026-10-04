import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../channel.dart';

/// [FrameChannel] over a TCP socket (the Wi-Fi Direct link): frames are length-prefixed
/// (`[u32 length][bytes]`). Always wrapped in a SecureFrameChannel.
class SocketFrameChannel implements FrameChannel {
  SocketFrameChannel(this._socket) {
    try {
      _socket.setOption(SocketOption.tcpNoDelay, true);
    } catch (_) {}
    _socket.listen(_onData, onDone: _shutdown, onError: (_) => _shutdown(), cancelOnError: true);
  }

  static const int maxFrame = 8 * 1024 * 1024;

  final Socket _socket;
  final _incoming = StreamController<Uint8List>();
  final _closed = Completer<void>();
  final BytesBuilder _buffer = BytesBuilder(copy: false);
  int _unflushed = 0;

  @override
  Stream<Uint8List> get frames => _incoming.stream;

  @override
  bool get isOpen => !_closed.isCompleted;

  @override
  Future<void> get closed => _closed.future;

  void _onData(Uint8List data) {
    _buffer.add(data);
    var bytes = _buffer.takeBytes();
    var offset = 0;
    while (bytes.length - offset >= 4) {
      final length = ByteData.sublistView(bytes, offset, offset + 4).getUint32(0);
      if (length > maxFrame) {
        _shutdown();
        _socket.destroy();
        return;
      }
      if (bytes.length - offset - 4 < length) break;
      _incoming.add(Uint8List.fromList(Uint8List.sublistView(bytes, offset + 4, offset + 4 + length)));
      offset += 4 + length;
    }
    if (offset < bytes.length) _buffer.add(Uint8List.sublistView(bytes, offset));
  }

  @override
  Future<void> send(Uint8List frame) async {
    if (!isOpen) throw ChannelClosedException();
    final header = Uint8List(4);
    ByteData.sublistView(header).setUint32(0, frame.length);
    _socket.add(header);
    _socket.add(frame);
    _unflushed += frame.length;
    // Let the socket drain now and then so its buffer stays bounded.
    if (_unflushed > 512 * 1024) {
      _unflushed = 0;
      try {
        await _socket.flush();
      } catch (_) {
        _shutdown();
        throw ChannelClosedException();
      }
    }
  }

  @override
  Future<void> close() async {
    if (!isOpen) return;
    _shutdown();
    try {
      await _socket.close();
    } catch (_) {}
    _socket.destroy();
  }

  void _shutdown() {
    if (_closed.isCompleted) return;
    _closed.complete();
    _incoming.close();
  }
}
