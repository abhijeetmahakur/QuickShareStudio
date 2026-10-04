import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

/// A reliable, ordered, message-based connection to one other device. Transports provide
/// one (WebRTC data channel, encrypted LAN WebSocket, encrypted Wi-Fi Direct socket); the
/// transfer protocol runs on top of it unchanged.
abstract class FrameChannel {
  /// Incoming frames. Single-subscription; done when the channel closes.
  Stream<Uint8List> get frames;

  /// Sends one frame. The returned future completes when the caller may send more, which
  /// is how transports apply backpressure.
  Future<void> send(Uint8List frame);

  /// Closes the channel (idempotent).
  Future<void> close();

  /// Completes when the channel is closed by either side or the connection is lost.
  Future<void> get closed;

  bool get isOpen;
}

class ChannelClosedException implements Exception {
  ChannelClosedException([this.message = 'The connection was closed.']);
  final String message;
  @override
  String toString() => message;
}

/// An in-process channel pair, used by tests (and to measure the protocol without a network).
class MemoryFrameChannel implements FrameChannel {
  MemoryFrameChannel._(this._highWaterMark, this._latency);

  /// Two connected ends. [highWaterMark] bytes may be queued before [send] waits.
  static (MemoryFrameChannel, MemoryFrameChannel) pair({int highWaterMark = 1 << 20, Duration? latency}) {
    final a = MemoryFrameChannel._(highWaterMark, latency);
    final b = MemoryFrameChannel._(highWaterMark, latency);
    a._peer = b;
    b._peer = a;
    return (a, b);
  }

  final int _highWaterMark;
  final Duration? _latency;
  late MemoryFrameChannel _peer;
  final _incoming = StreamController<Uint8List>();
  final _closed = Completer<void>();
  final Queue<Completer<void>> _drainWaiters = Queue();
  int _queuedBytes = 0;

  /// Optional hook to corrupt or drop frames in flight (returns null to drop).
  Uint8List? Function(Uint8List frame)? tamper;

  /// Number of frames this end has sent (for tests).
  int framesSent = 0;
  int bytesSent = 0;

  /// Frames still queued when the channel closes are dropped, like on a real lost connection.
  @override
  Stream<Uint8List> get frames => _incoming.stream.takeWhile((_) => isOpen);

  @override
  bool get isOpen => !_closed.isCompleted;

  @override
  Future<void> get closed => _closed.future;

  @override
  Future<void> send(Uint8List frame) async {
    if (!isOpen) throw ChannelClosedException();
    framesSent++;
    bytesSent += frame.length;
    final delivered = tamper == null ? frame : tamper!(frame);
    if (delivered == null) return;
    _queuedBytes += delivered.length;
    void deliver() {
      _queuedBytes -= delivered.length;
      if (_peer.isOpen) _peer._incoming.add(Uint8List.fromList(delivered));
      while (_queuedBytes <= _highWaterMark ~/ 2 && _drainWaiters.isNotEmpty) {
        _drainWaiters.removeFirst().complete();
      }
    }

    if (_latency != null) {
      Timer(_latency, deliver);
    } else {
      scheduleMicrotask(deliver);
    }
    if (_queuedBytes > _highWaterMark) {
      final waiter = Completer<void>();
      _drainWaiters.add(waiter);
      await Future.any([waiter.future, closed]);
      if (!isOpen) throw ChannelClosedException();
    }
  }

  @override
  Future<void> close() async {
    if (!isOpen) return;
    _shutdown();
    _peer._shutdown();
  }

  /// Simulates the network disappearing: both ends see the connection drop.
  void sever() => close();

  /// Only this end notices the drop; the other end still believes it is connected (as
  /// happens on real networks until a timeout fires).
  void dropLocally() => _shutdown();

  void _shutdown() {
    if (!isOpen) return;
    _closed.complete();
    for (final w in _drainWaiters) {
      if (!w.isCompleted) w.complete();
    }
    _drainWaiters.clear();
    _incoming.close();
  }
}
