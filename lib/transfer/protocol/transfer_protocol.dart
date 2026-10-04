import 'dart:async';
import 'dart:collection';
import 'dart:math';
import 'dart:typed_data';

import 'package:async/async.dart';

import '../app_config.dart';
import '../channel.dart';
import '../file_names.dart';
import '../file_source.dart';
import 'frames.dart';
import 'handshake.dart';
import 'streaming_sha256.dart';

enum TransferDirection { outgoing, incoming }

enum TransferPhase { waitingForAccept, transferring, completed, declined, cancelled, failed, interrupted }

extension TransferPhaseX on TransferPhase {
  bool get isFinal => this != TransferPhase.waitingForAccept && this != TransferPhase.transferring;
}

class TransferFileInfo {
  const TransferFileInfo(this.name, this.size);
  final String name;
  final int size;
}

/// A file the receiver saved and verified.
class ReceivedFile {
  const ReceivedFile({required this.name, required this.size, required this.sha256, this.path, this.bytes});
  final String name;
  final int size;
  final String sha256;

  /// Where it was written (native), if anywhere.
  final String? path;

  /// The content, for in-memory sinks (web).
  final Uint8List? bytes;
}

/// Progress of one transfer, as shown in the UI.
class TransferSnapshot {
  const TransferSnapshot({
    required this.transferId,
    required this.direction,
    required this.phase,
    required this.files,
    required this.peerName,
    this.bytesDone = 0,
    this.fileIndex = 0,
    this.bytesPerSecond = 0,
    this.error,
    this.resumable = false,
    this.received = const [],
  });

  final String transferId;
  final TransferDirection direction;
  final TransferPhase phase;
  final List<TransferFileInfo> files;
  final String peerName;
  final int bytesDone;
  final int fileIndex;
  final double bytesPerSecond;
  final String? error;
  final bool resumable;
  final List<ReceivedFile> received;

  int get totalBytes => files.fold(0, (sum, f) => sum + f.size);
  double get progress => totalBytes == 0 ? (phase == TransferPhase.completed ? 1 : 0) : bytesDone / totalBytes;

  Duration? get eta {
    if (bytesPerSecond <= 0 || phase != TransferPhase.transferring) return null;
    return Duration(milliseconds: ((totalBytes - bytesDone) / bytesPerSecond * 1000).round());
  }

  String get currentFileName => files.isEmpty ? '' : files[min(fileIndex, files.length - 1)].name;

  TransferSnapshot copyWith({
    TransferPhase? phase,
    int? bytesDone,
    int? fileIndex,
    double? bytesPerSecond,
    String? error,
    bool? resumable,
    List<ReceivedFile>? received,
  }) =>
      TransferSnapshot(
        transferId: transferId,
        direction: direction,
        phase: phase ?? this.phase,
        files: files,
        peerName: peerName,
        bytesDone: bytesDone ?? this.bytesDone,
        fileIndex: fileIndex ?? this.fileIndex,
        bytesPerSecond: bytesPerSecond ?? this.bytesPerSecond,
        error: error ?? this.error,
        resumable: resumable ?? this.resumable,
        received: received ?? this.received,
      );
}

/// What the receiver is asked to accept.
class IncomingOffer {
  const IncomingOffer({
    required this.transferId,
    required this.sender,
    required this.files,
    required this.isResume,
  });

  final String transferId;
  final RemoteIdentity sender;

  /// File names are already sanitized.
  final List<TransferFileInfo> files;
  final bool isResume;

  int get totalBytes => files.fold(0, (sum, f) => sum + f.size);
}

/// Where received bytes go. Nothing is written before the user accepts.
abstract class IncomingFileSink {
  Future<void> add(Uint8List data);

  /// Keeps the file (its hash matched).
  Future<ReceivedFile> commit(String sha256);

  /// Deletes whatever was written.
  Future<void> discard();
}

typedef SinkOpener = Future<IncomingFileSink> Function(IncomingOffer offer, int fileIndex);
typedef OfferHandler = Future<bool> Function(IncomingOffer offer);

/// Speed over the last few seconds.
class RateMeter {
  RateMeter({this.window = const Duration(seconds: 3)});
  final Duration window;
  final Queue<(int, int)> _samples = Queue();
  final Stopwatch _clock = Stopwatch()..start();

  void add(int totalBytes) {
    final now = _clock.elapsedMilliseconds;
    _samples.addLast((now, totalBytes));
    while (_samples.length > 2 && now - _samples.first.$1 > window.inMilliseconds) {
      _samples.removeFirst();
    }
  }

  double get bytesPerSecond {
    if (_samples.length < 2) return 0;
    final (t0, b0) = _samples.first;
    final (t1, b1) = _samples.last;
    if (t1 <= t0) return 0;
    return (b1 - b0) * 1000 / (t1 - t0);
  }
}

/// Receiver-side transfers interrupted by a dropped connection, kept for a while so the
/// sender can resume instead of starting over.
class PartialTransferStore {
  final Map<String, (_IncomingRun, Timer)> _runs = {};

  /// Accepted transfers currently attached to a connection.
  final Map<String, _IncomingRun> _live = {};

  void _keep(_IncomingRun run, Duration grace) {
    _live.remove(run.offer.transferId);
    _runs.remove(run.offer.transferId)?.$2.cancel();
    _runs[run.offer.transferId] = (
      run,
      Timer(grace, () {
        _runs.remove(run.offer.transferId);
        run.discard();
      }),
    );
  }

  /// Hands an interrupted transfer to [into]. Also takes it over from a connection that has
  /// not noticed yet that it is dead (the sender has evidently reconnected).
  Future<_IncomingRun?> _take(String transferId, String senderId, PeerSession into) async {
    _IncomingRun? run;
    final kept = _runs[transferId];
    if (kept != null && kept.$1.offer.sender.id == senderId) {
      _runs.remove(transferId);
      kept.$2.cancel();
      run = kept.$1;
    } else {
      final live = _live[transferId];
      if (live != null && live.offer.sender.id == senderId && !identical(live._session, into)) {
        live._session?._incoming.remove(live.tag);
        live.detach();
        run = live;
      }
    }
    // Let any chunk still being written finish, so the resume offset is exact.
    await run?._idle;
    return run;
  }

  void _track(_IncomingRun run) => _live[run.offer.transferId] = run;
  void _untrack(_IncomingRun run) {
    if (identical(_live[run.offer.transferId], run)) _live.remove(run.offer.transferId);
  }

  /// Whether [transferId] can still be resumed (interrupted, or live on another connection).
  bool contains(String transferId) => _runs.containsKey(transferId) || _live.containsKey(transferId);

  void discardAll() {
    for (final entry in _runs.values) {
      entry.$2.cancel();
      entry.$1.discard();
    }
    _runs.clear();
    _live.clear();
  }
}

class _Abort implements Exception {
  _Abort(this.phase, this.message);
  final TransferPhase phase;
  final String message;
}

/// One live connection to another device, carrying transfers in both directions.
class PeerSession {
  PeerSession({
    required this.channel,
    required this.frames,
    required this.remote,
    required this.config,
    required this.onOffer,
    required this.openSink,
    PartialTransferStore? partials,
  }) : partials = partials ?? PartialTransferStore();

  final FrameChannel channel;
  final StreamQueue<Uint8List> frames;
  final RemoteIdentity remote;
  final AppConfig config;
  final OfferHandler onOffer;
  final SinkOpener openSink;
  final PartialTransferStore partials;

  final Map<int, OutgoingTransfer> _outgoing = {};
  final Map<int, _IncomingRun> _incoming = {};
  final _updates = StreamController<TransferSnapshot>.broadcast();
  final _closed = Completer<void>();
  bool _started = false;
  int _strayChunks = 0;

  /// Progress of every incoming transfer on this connection.
  Stream<TransferSnapshot> get incomingUpdates => _updates.stream;

  Future<void> get closed => _closed.future;
  bool get isOpen => !_closed.isCompleted && channel.isOpen;

  void start() {
    if (_started) return;
    _started = true;
    unawaited(_pump());
  }

  Future<void> close() async {
    if (channel.isOpen) {
      try {
        await channel.send(Frame.encodeControl(FrameType.bye, {'reason': 'closed'}));
      } catch (_) {}
    }
    await channel.close();
  }

  /// Cancels a transfer this device is receiving.
  Future<void> cancelIncoming(String transferId) async {
    final run = _incoming.values.where((r) => r.offer.transferId == transferId).firstOrNull;
    if (run == null) return;
    await _send(FrameType.cancel, {'tag': run.tag, 'reason': 'cancelled'});
    await run.finish(TransferPhase.cancelled, 'Cancelled.');
    _incoming.remove(run.tag);
  }

  Future<void> _send(FrameType type, Map<String, dynamic> body) async {
    if (!channel.isOpen) return;
    try {
      await channel.send(Frame.encodeControl(type, body));
    } on ChannelClosedException {
      // Reported through [closed].
    }
  }

  Future<void> _pump() async {
    try {
      while (await frames.hasNext) {
        final frame = Frame.decode(await frames.next);
        await _dispatch(frame);
      }
    } on ProtocolException {
      await channel.close();
    } catch (_) {
      await channel.close();
    } finally {
      await _onClosed();
    }
  }

  Future<void> _dispatch(Frame f) async {
    switch (f.type) {
      case FrameType.offer:
        await _handleOffer(f.json);
      case FrameType.accept || FrameType.decline || FrameType.ack || FrameType.fileResult:
        _outgoing[_tagOf(f.json)]?._onFrame(f);
      case FrameType.fileStart || FrameType.fileEnd:
        final run = _incoming[_tagOf(f.json)];
        if (run == null) return;
        await run.handle(f, this);
        if (run.phase.isFinal) _incoming.remove(run.tag);
      case FrameType.chunk:
        final run = _incoming[f.tag];
        if (run == null || !run.accepted) {
          // Bytes before Accept are never written; a peer that keeps pushing them is broken.
          if (++_strayChunks > 64) throw ProtocolException('data sent without acceptance');
          return;
        }
        await run.handle(f, this);
        if (run.phase.isFinal) _incoming.remove(run.tag);
      case FrameType.cancel:
        final tag = _tagOf(f.json);
        _outgoing[tag]?._onFrame(f);
        final run = _incoming.remove(tag);
        if (run != null) await run.finish(TransferPhase.cancelled, 'The sender cancelled the transfer.');
      case FrameType.bye:
        await channel.close();
      case FrameType.challenge || FrameType.hello || FrameType.welcome || FrameType.reject:
        throw ProtocolException('handshake frame after handshake');
    }
  }

  static int _tagOf(Map<String, dynamic> json) => (json['tag'] as num?)?.toInt() ?? -1;

  Future<void> _handleOffer(Map<String, dynamic> json) async {
    final tag = _tagOf(json);
    final transferId = json['transferId']?.toString() ?? '';
    final rawFiles = json['files'];
    String? problem;
    final files = <TransferFileInfo>[];
    if (tag < 0 || !RegExp(r'^[A-Za-z0-9_-]{6,64}$').hasMatch(transferId)) problem = 'invalid offer';
    if (rawFiles is! List || rawFiles.isEmpty) {
      problem ??= 'no files offered';
    } else if (rawFiles.length > config.maxFilesPerTransfer) {
      problem ??= 'too many files (max ${config.maxFilesPerTransfer})';
    } else {
      final names = <String>{};
      for (final raw in rawFiles) {
        final size = raw is Map ? (raw['size'] as num?)?.toInt() ?? -1 : -1;
        if (size < 0) {
          problem ??= 'invalid file size';
          break;
        }
        var name = sanitizeIncomingFileName(raw is Map ? raw['name']?.toString() ?? '' : '');
        name = uniqueFileName(name, names.contains);
        names.add(name);
        files.add(TransferFileInfo(name, size));
      }
    }
    final total = files.fold<int>(0, (s, f) => s + f.size);
    if (total > config.maxTransferBytes) problem ??= 'transfer is larger than the ${config.maxTransferBytes ~/ (1 << 30)} GB limit';
    if ((json['chunkSize'] as num?)?.toInt() != config.chunkSize) problem ??= 'unsupported chunk size';
    if (problem != null) {
      await _send(FrameType.decline, {'tag': tag, 'reason': problem});
      return;
    }
    if (_incoming.containsKey(tag)) return;

    final offer = IncomingOffer(
      transferId: transferId,
      sender: remote,
      files: files,
      isResume: json['resume'] == true,
    );

    if (offer.isResume) {
      final run = await partials._take(transferId, remote.id, this);
      if (run == null || run.offer.files.length != files.length) {
        await _send(FrameType.decline, {'tag': tag, 'reason': 'resume-unavailable'});
        return;
      }
      run.attach(this, tag);
      _incoming[tag] = run;
      partials._track(run);
      await _send(FrameType.accept, {'tag': tag, 'resumeFile': run.resumeFile, 'resumeOffset': run.resumeOffset});
      return;
    }

    final run = _IncomingRun(this, offer, tag);
    _incoming[tag] = run;
    run.emit();
    // The decision can take a while (the user reads the dialog); keep handling frames.
    unawaited(() async {
      bool ok;
      try {
        ok = await onOffer(offer);
      } catch (_) {
        ok = false;
      }
      if (!_incoming.containsKey(tag) || run.phase.isFinal) return;
      if (ok && channel.isOpen) {
        run.accepted = true;
        partials._track(run);
        run.phase = TransferPhase.transferring;
        run.emit();
        await _send(FrameType.accept, {'tag': tag, 'resumeFile': 0, 'resumeOffset': 0});
      } else {
        _incoming.remove(tag);
        await _send(FrameType.decline, {'tag': tag, 'reason': 'declined'});
        await run.finish(TransferPhase.declined, 'Declined.');
      }
    }());
  }

  Future<void> _onClosed() async {
    if (_closed.isCompleted) return;
    for (final t in _outgoing.values.toList()) {
      t._onChannelClosed(this);
    }
    for (final run in _incoming.values.toList()) {
      if (run.accepted && !run.phase.isFinal && run.canResume) {
        run.phase = TransferPhase.interrupted;
        run.error = 'Connection lost. The sender can resume.';
        run.emit();
        run.detach();
        partials._keep(run, config.resumeGracePeriod);
      } else if (!run.phase.isFinal) {
        await run.finish(TransferPhase.interrupted, 'Connection lost.');
      }
    }
    _incoming.clear();
    _closed.complete();
    await _updates.close();
  }
}

/// Receiver-side state of one transfer.
class _IncomingRun {
  _IncomingRun(PeerSession session, this.offer, this.tag) : _session = session;

  PeerSession? _session;
  final IncomingOffer offer;
  int tag;
  bool accepted = false;
  TransferPhase phase = TransferPhase.waitingForAccept;
  String? error;

  int _file = -1;
  int _expectedSeq = 0;
  int _fileBytes = 0;
  int _written = 0;
  int _lastAck = 0;
  IncomingFileSink? _sink;
  StreamingSha256? _hasher;
  final List<ReceivedFile> _results = [];
  final RateMeter _meter = RateMeter();
  DateTime _lastEmit = DateTime.fromMillisecondsSinceEpoch(0);

  int get resumeFile => max(_file, 0);
  int get resumeOffset => _file < 0 ? 0 : _fileBytes;
  bool get canResume => _sink != null || _file < 0 || _results.length == _file + 1;

  void attach(PeerSession session, int newTag) {
    _session = session;
    tag = newTag;
    phase = TransferPhase.transferring;
    error = null;
    accepted = true;
    emit();
  }

  void detach() => _session = null;

  TransferSnapshot snapshot() => TransferSnapshot(
        transferId: offer.transferId,
        direction: TransferDirection.incoming,
        phase: phase,
        files: offer.files,
        peerName: offer.sender.name,
        bytesDone: _written,
        fileIndex: max(_file, 0),
        bytesPerSecond: _meter.bytesPerSecond,
        error: error,
        resumable: phase == TransferPhase.interrupted,
        received: List.unmodifiable(_results),
      );

  void emit({bool force = true}) {
    final session = _session;
    if (session == null || session._updates.isClosed) return;
    final now = DateTime.now();
    if (!force && now.difference(_lastEmit).inMilliseconds < 100) return;
    _lastEmit = now;
    session._updates.add(snapshot());
  }

  Future<void> _ack() async {
    _lastAck = _written;
    await _session?._send(FrameType.ack, {'tag': tag, 'received': _written});
  }

  Future<void> _queue = Future<void>.value();

  /// Completes once no frame is being processed.
  Future<void> get _idle => _queue;

  /// Frames are processed one at a time, and only from the connection the run belongs to.
  Future<void> handle(Frame f, PeerSession from) {
    final next = _queue.then((_) => _handle(f, from));
    _queue = next.then((_) {}, onError: (_) {});
    return next;
  }

  Future<void> _handle(Frame f, PeerSession from) async {
    final session = _session;
    if (session == null || !identical(session, from) || !accepted || phase.isFinal) return;
    final chunkSize = session.config.chunkSize;
    switch (f.type) {
      case FrameType.fileStart:
        final index = (f.json['file'] as num?)?.toInt() ?? -1;
        final offset = (f.json['offset'] as num?)?.toInt() ?? -1;
        final resumingThisFile = _sink != null && index == _file && offset == _fileBytes;
        if (resumingThisFile) {
          _expectedSeq = offset ~/ chunkSize;
          return;
        }
        if (index != _file + 1 || index >= offer.files.length || offset != 0 || _sink != null) {
          throw ProtocolException('unexpected file start');
        }
        _file = index;
        _fileBytes = 0;
        _expectedSeq = 0;
        _hasher = StreamingSha256();
        _sink = await session.openSink(offer, index);
        emit();
      case FrameType.chunk:
        final data = f.data!;
        final size = offer.files[_file].size;
        if (_sink == null || f.fileIndex != _file || f.sequence != _expectedSeq) {
          throw ProtocolException('chunk out of order (expected #$_expectedSeq, got #${f.sequence})');
        }
        if (data.length > chunkSize || _fileBytes + data.length > size) throw ProtocolException('chunk too large');
        _hasher!.add(data);
        await _sink!.add(data);
        _expectedSeq++;
        _fileBytes += data.length;
        _written += data.length;
        _meter.add(_written);
        if (_written - _lastAck >= 256 * 1024) await _ack();
        emit(force: false);
      case FrameType.fileEnd:
        final index = (f.json['file'] as num?)?.toInt() ?? -1;
        if (index != _file || _sink == null) throw ProtocolException('unexpected file end');
        final expected = (f.json['sha256']?.toString() ?? '').toLowerCase();
        final actual = _hasher!.finish();
        final sink = _sink!;
        _sink = null;
        final complete = _fileBytes == offer.files[_file].size;
        if (complete && constantTimeEquals(actual, expected)) {
          _results.add(await sink.commit(actual));
          await session._send(FrameType.fileResult, {'tag': tag, 'file': index, 'ok': true});
          await _ack();
          if (index == offer.files.length - 1) {
            phase = TransferPhase.completed;
            session.partials._untrack(this);
          }
          emit();
        } else {
          await sink.discard();
          await session._send(FrameType.fileResult, {'tag': tag, 'file': index, 'ok': false, 'error': 'corrupted'});
          await finish(TransferPhase.failed, 'File corrupted, retry.');
        }
      default:
        break;
    }
  }

  Future<void> finish(TransferPhase result, String message) async {
    if (phase.isFinal && phase != TransferPhase.interrupted) return;
    phase = result;
    error = result == TransferPhase.completed ? null : message;
    _session?.partials._untrack(this);
    await discard();
    emit();
  }

  Future<void> discard() async {
    final sink = _sink;
    _sink = null;
    if (sink != null) {
      try {
        await sink.discard();
      } catch (_) {}
    }
  }
}

/// Sender-side transfer of one or more files. Can be re-run on a new session to resume.
class OutgoingTransfer {
  OutgoingTransfer({required this.files, required this.config, required this.peerName, String? transferId})
      : transferId = transferId ?? randomToken(12),
        tag = Random.secure().nextInt(1 << 32);

  final List<FileSource> files;
  final AppConfig config;
  final String peerName;
  final String transferId;
  final int tag;

  final _updates = StreamController<TransferSnapshot>.broadcast();
  final RateMeter _meter = RateMeter();
  late TransferSnapshot _snapshot = TransferSnapshot(
    transferId: transferId,
    direction: TransferDirection.outgoing,
    phase: TransferPhase.waitingForAccept,
    files: [for (final f in files) TransferFileInfo(f.name, f.size)],
    peerName: peerName,
  );

  Stream<TransferSnapshot> get updates => _updates.stream;
  TransferSnapshot get snapshot => _snapshot;

  PeerSession? _session;
  bool _accepted = false;
  bool _cancelRequested = false;
  int _completedFiles = 0;
  int _acked = 0;
  Completer<Frame>? _reply;
  Completer<void>? _ackWaiter;
  final Map<int, Completer<Frame>> _results = {};
  Completer<_Abort>? _abort;
  DateTime _lastEmit = DateTime.fromMillisecondsSinceEpoch(0);

  int get _totalBytes => _snapshot.totalBytes;

  void _emit(TransferSnapshot s, {bool force = true}) {
    _snapshot = s;
    final now = DateTime.now();
    if (!force && now.difference(_lastEmit).inMilliseconds < 100) return;
    _lastEmit = now;
    if (!_updates.isClosed) _updates.add(s);
  }

  /// Stops the transfer and tells the receiver.
  Future<void> cancel() async {
    _cancelRequested = true;
    final session = _session;
    if (session != null) await session._send(FrameType.cancel, {'tag': tag, 'reason': 'cancelled'});
    _fail(TransferPhase.cancelled, 'Cancelled.');
    if (session == null && !_snapshot.phase.isFinal) {
      _emit(_snapshot.copyWith(phase: TransferPhase.cancelled, error: 'Cancelled.', resumable: false));
    }
  }

  void _fail(TransferPhase phase, String message) {
    final abort = _abort;
    if (abort != null && !abort.isCompleted) abort.complete(_Abort(phase, message));
  }

  void _onFrame(Frame f) {
    switch (f.type) {
      case FrameType.accept || FrameType.decline:
        final reply = _reply;
        if (reply != null && !reply.isCompleted) reply.complete(f);
      case FrameType.ack:
        _acked = max(_acked, (f.json['received'] as num?)?.toInt() ?? 0);
        _meter.add(_acked);
        final waiter = _ackWaiter;
        _ackWaiter = null;
        waiter?.complete();
        _emit(_snapshot.copyWith(bytesDone: min(_acked, _totalBytes), bytesPerSecond: _meter.bytesPerSecond), force: false);
      case FrameType.fileResult:
        final index = (f.json['file'] as num?)?.toInt() ?? -1;
        final c = _results.remove(index);
        if (c != null && !c.isCompleted) c.complete(f);
      case FrameType.cancel:
        final reason = f.json['reason']?.toString();
        _fail(TransferPhase.cancelled, reason == 'timeout' ? 'The receiver timed out.' : 'The receiver cancelled the transfer.');
      default:
        break;
    }
  }

  /// Only the connection this run is using may interrupt it (an older one closing late
  /// must not abort a resumed run).
  void _onChannelClosed(PeerSession from) {
    if (identical(_session, from)) _fail(TransferPhase.interrupted, 'Connection lost.');
  }

  Future<T> _race<T>(Future<T> work, {Duration? timeout, String? timeoutMessage}) async {
    final abort = _abort!.future.then<T>((a) => throw a);
    var f = Future.any([work, abort]);
    if (timeout != null) {
      f = f.timeout(timeout, onTimeout: () => throw _Abort(TransferPhase.failed, timeoutMessage ?? 'Timed out.'));
    }
    return f;
  }

  /// Runs (or resumes, when [resume]) the transfer over [session]. Completes with the final
  /// snapshot; never throws.
  Future<TransferSnapshot> run(PeerSession session, {bool resume = false}) async {
    if (_cancelRequested) return _snapshot;
    _session = session;
    _abort = Completer<_Abort>();
    session._outgoing[tag] = this;
    unawaited(session.closed.then((_) => _onChannelClosed(session)));
    final chunkSize = config.chunkSize;
    try {
      _reply = Completer<Frame>();
      await session.channel.send(Frame.encodeControl(FrameType.offer, {
        'transferId': transferId,
        'tag': tag,
        'files': [for (final f in files) {'name': f.name, 'size': f.size}],
        'total': _totalBytes,
        'chunkSize': chunkSize,
        'resume': resume,
      }));
      _emit(_snapshot.copyWith(phase: resume ? TransferPhase.transferring : TransferPhase.waitingForAccept, error: ''));

      final reply = await _race(
        _reply!.future,
        timeout: resume ? const Duration(seconds: 20) : config.acceptTimeout,
        timeoutMessage: '$peerName did not answer.',
      );
      if (reply.type == FrameType.decline) {
        final reason = reply.json['reason']?.toString() ?? 'declined';
        if (reason == 'declined') throw _Abort(TransferPhase.declined, '$peerName declined the transfer.');
        if (reason == 'resume-unavailable') throw _Abort(TransferPhase.failed, 'The transfer can no longer be resumed. Send it again.');
        throw _Abort(TransferPhase.failed, '$peerName refused the files: $reason.');
      }
      _accepted = true;
      final startFile = (reply.json['resumeFile'] as num?)?.toInt() ?? 0;
      final startOffset = (reply.json['resumeOffset'] as num?)?.toInt() ?? 0;
      if (startFile < 0 || startFile >= files.length || startOffset < 0 || startOffset > files[startFile].size || startOffset % chunkSize != 0) {
        throw _Abort(TransferPhase.failed, 'The receiver asked for an invalid resume point.');
      }
      _completedFiles = startFile;
      var sent = files.take(startFile).fold<int>(0, (s, f) => s + f.size) + startOffset;
      _acked = sent;
      _emit(_snapshot.copyWith(phase: TransferPhase.transferring, bytesDone: sent, fileIndex: startFile, error: ''));

      for (var i = startFile; i < files.length; i++) {
        final file = files[i];
        final offset = i == startFile ? startOffset : 0;
        await session.channel.send(Frame.encodeControl(FrameType.fileStart, {'tag': tag, 'file': i, 'offset': offset}));
        _emit(_snapshot.copyWith(fileIndex: i));

        final hasher = StreamingSha256();
        if (offset > 0) {
          // The receiver keeps its hash state; ours restarts, so re-read what it already has.
          var remaining = offset;
          await for (final piece in file.openRead(0)) {
            final take = min(piece.length, remaining);
            hasher.add(Uint8List.sublistView(piece, 0, take));
            remaining -= take;
            if (remaining == 0) break;
          }
        }
        var seq = offset ~/ chunkSize;
        await for (final chunk in rechunk(file.openRead(offset), chunkSize)) {
          if (_abort!.isCompleted) break;
          while (sent - _acked > config.flowControlWindow) {
            _ackWaiter ??= Completer<void>();
            await _race(_ackWaiter!.future, timeout: const Duration(seconds: 60), timeoutMessage: '$peerName stopped responding.');
          }
          hasher.add(chunk);
          await _race(session.channel.send(Frame.encodeChunk(tag: tag, fileIndex: i, sequence: seq, data: chunk)));
          seq++;
          sent += chunk.length;
        }
        if (_abort!.isCompleted) throw await _abort!.future;
        final result = Completer<Frame>();
        _results[i] = result;
        await session.channel.send(
          Frame.encodeControl(FrameType.fileEnd, {'tag': tag, 'file': i, 'size': file.size, 'sha256': hasher.finish()}),
        );
        final outcome = await _race(result.future, timeout: const Duration(seconds: 60), timeoutMessage: '$peerName did not confirm ${file.name}.');
        if (outcome.json['ok'] != true) {
          throw _Abort(TransferPhase.failed, '"${file.name}" was corrupted on the way. Please retry.');
        }
        _completedFiles = i + 1;
      }
      _emit(_snapshot.copyWith(phase: TransferPhase.completed, bytesDone: _totalBytes, fileIndex: files.length - 1, error: ''));
    } on _Abort catch (a) {
      final resumable = a.phase == TransferPhase.interrupted && _accepted && !_cancelRequested;
      _emit(_snapshot.copyWith(phase: a.phase, error: a.message, resumable: resumable));
    } on ChannelClosedException {
      _emit(_snapshot.copyWith(phase: TransferPhase.interrupted, error: 'Connection lost.', resumable: _accepted && !_cancelRequested));
    } catch (e) {
      _emit(_snapshot.copyWith(phase: TransferPhase.failed, error: 'Could not read the file to send.', resumable: false));
    } finally {
      session._outgoing.remove(tag);
      _session = null;
    }
    return _snapshot;
  }

  /// Files fully delivered and verified so far.
  int get completedFiles => _completedFiles;

  Future<void> dispose() => _updates.close();
}
