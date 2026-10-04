import 'dart:async';

import 'package:flutter/foundation.dart';

/// Lets a running connection attempt be stopped and its sockets, peers and scans released.
class CancelToken {
  final _cancelled = Completer<void>();
  final List<FutureOr<void> Function()> _cleanups = [];

  bool get isCancelled => _cancelled.isCompleted;
  Future<void> get whenCancelled => _cancelled.future;

  /// Registers cleanup to run on cancel (runs immediately if already cancelled).
  void onCancel(FutureOr<void> Function() cleanup) {
    if (isCancelled) {
      cleanup();
    } else {
      _cleanups.add(cleanup);
    }
  }

  Future<void> cancel() async {
    if (isCancelled) return;
    _cancelled.complete();
    for (final c in _cleanups.reversed) {
      try {
        await c();
      } catch (_) {}
    }
    _cleanups.clear();
  }
}

class CancelledException implements Exception {
  @override
  String toString() => 'Cancelled.';
}

/// A connection attempt that failed with a message meant for the user.
class ConnectException implements Exception {
  ConnectException(this.kind, this.message);
  final ConnectFailure kind;
  final String message;
  @override
  String toString() => message;
}

enum ConnectFailure {
  /// Nobody on this Wi-Fi answered / showed the code.
  notFoundOnLan,

  /// No device is online with that code (or it expired).
  wrongCode,

  /// This device has no internet connection.
  noInternet,

  /// The PeerJS signaling service cannot be reached.
  signalingUnavailable,

  /// Peers found each other but no network path worked (not even TURN).
  noRoute,

  /// Too many wrong codes; wait.
  lockedOut,

  /// The other device refused the handshake.
  rejected,
  other,
}

enum ConnectPhase { idle, searchingLan, tryingInternet, connected, failed, cancelled }

@immutable
class ConnectFlowState {
  const ConnectFlowState({
    this.phase = ConnectPhase.idle,
    this.lanFailed = false,
    this.online,
    this.failure,
    this.detail,
    this.startedAt,
  });

  final ConnectPhase phase;
  final bool lanFailed;
  final bool? online;
  final ConnectFailure? failure;

  /// Extra explanation of the last failure (e.g. what went wrong over the internet).
  final String? detail;
  final DateTime? startedAt;

  static const String lanNotFoundMessage =
      "Couldn't find the device on this Wi-Fi. If you're on different networks, try over the internet. "
      'No connection? Use Bluetooth.';

  bool get isBusy => phase == ConnectPhase.searchingLan || phase == ConnectPhase.tryingInternet;

  /// Whether the [Try over internet] / [Use Bluetooth] / [Retry] choices are shown.
  bool get showsOptions => phase == ConnectPhase.failed && lanFailed;

  String get statusText => switch (phase) {
        ConnectPhase.searchingLan => 'Looking on your network...',
        ConnectPhase.tryingInternet => 'Trying over internet...',
        ConnectPhase.connected => 'Connected',
        ConnectPhase.cancelled => 'Cancelled',
        ConnectPhase.failed => lanFailed ? lanNotFoundMessage : (detail ?? 'Could not connect.'),
        ConnectPhase.idle => '',
      };

  ConnectFlowState copyWith({
    ConnectPhase? phase,
    bool? lanFailed,
    bool? online,
    ConnectFailure? failure,
    String? detail,
    bool clearFailure = false,
  }) =>
      ConnectFlowState(
        phase: phase ?? this.phase,
        lanFailed: lanFailed ?? this.lanFailed,
        online: online ?? this.online,
        failure: clearFailure ? null : (failure ?? this.failure),
        detail: clearFailure ? null : (detail ?? this.detail),
        startedAt: startedAt,
      );
}

/// The fallback state machine: LAN first; if no device answers within [lanTimeout], try the
/// internet (when online and [autoInternet]); otherwise offer internet / Bluetooth / retry.
/// Bluetooth is always a manual choice. [cancel] stops whatever is running.
class ConnectFlow<T> {
  ConnectFlow({
    required this.lan,
    required this.internet,
    required this.isOnline,
    this.lanTimeout = const Duration(seconds: 5),
    this.autoInternet = true,
  });

  final Future<T> Function(CancelToken token) lan;
  final Future<T> Function(CancelToken token) internet;
  final Future<bool> Function() isOnline;
  final Duration lanTimeout;
  final bool autoInternet;

  final ValueNotifier<ConnectFlowState> state = ValueNotifier(const ConnectFlowState());
  CancelToken? _token;

  bool get isBusy => state.value.isBusy;

  void _set(ConnectFlowState s) => state.value = s;

  /// Full flow: LAN, then (maybe) internet. Returns null on failure or cancel.
  Future<T?> run() async {
    await cancel(silent: true);
    final token = _token = CancelToken();
    _set(ConnectFlowState(phase: ConnectPhase.searchingLan, startedAt: DateTime.now()));

    ConnectException? lanError;
    // The LAN step gets its own token so a timeout also releases its sockets.
    final lanToken = CancelToken();
    token.onCancel(lanToken.cancel);
    try {
      final result = await _withCancel(token, lan(lanToken).timeout(lanTimeout));
      return _connected(token, result);
    } on CancelledException {
      return null;
    } on ConnectException catch (e) {
      lanError = e;
    } on TimeoutException {
      lanError = ConnectException(ConnectFailure.notFoundOnLan, 'No device answered on this network.');
    } catch (e) {
      lanError = ConnectException(ConnectFailure.notFoundOnLan, 'No device answered on this network.');
    }
    await lanToken.cancel();
    if (token.isCancelled) return null;
    // A wrong code on the LAN is final; anything else may simply be a different network.
    if (lanError.kind == ConnectFailure.wrongCode || lanError.kind == ConnectFailure.lockedOut) {
      _set(state.value.copyWith(phase: ConnectPhase.failed, failure: lanError.kind, detail: lanError.message));
      return null;
    }

    final online = await isOnline();
    if (token.isCancelled) return null;
    _set(state.value.copyWith(lanFailed: true, online: online));
    if (!online) {
      _set(state.value.copyWith(
        phase: ConnectPhase.failed,
        failure: ConnectFailure.noInternet,
        detail: "You're offline, so the internet option isn't available. Use Bluetooth, or join the same Wi-Fi.",
      ));
      return null;
    }
    if (!autoInternet) {
      _set(state.value.copyWith(phase: ConnectPhase.failed, failure: ConnectFailure.notFoundOnLan));
      return null;
    }
    return _runInternet(token);
  }

  /// [Try over internet]: skips the LAN search.
  Future<T?> tryInternet() async {
    await cancel(silent: true);
    final token = _token = CancelToken();
    final lanFailed = state.value.lanFailed;
    _set(ConnectFlowState(phase: ConnectPhase.tryingInternet, lanFailed: lanFailed, startedAt: DateTime.now()));
    final online = await isOnline();
    if (token.isCancelled) return null;
    if (!online) {
      _set(state.value.copyWith(
        phase: ConnectPhase.failed,
        online: false,
        failure: ConnectFailure.noInternet,
        detail: 'No internet connection. Use Bluetooth, or join the same Wi-Fi.',
      ));
      return null;
    }
    return _runInternet(token);
  }

  Future<T?> _runInternet(CancelToken token) async {
    _set(state.value.copyWith(phase: ConnectPhase.tryingInternet, online: true, clearFailure: true));
    try {
      final result = await _withCancel(token, internet(token));
      return _connected(token, result);
    } on CancelledException {
      return null;
    } on ConnectException catch (e) {
      if (token.isCancelled) return null;
      _set(state.value.copyWith(phase: ConnectPhase.failed, failure: e.kind, detail: e.message));
    } catch (e) {
      if (token.isCancelled) return null;
      _set(state.value.copyWith(
        phase: ConnectPhase.failed,
        failure: ConnectFailure.other,
        detail: 'Could not connect over the internet. Please try again.',
      ));
    }
    return null;
  }

  T? _connected(CancelToken token, T result) {
    if (token.isCancelled) return null;
    _set(state.value.copyWith(phase: ConnectPhase.connected, clearFailure: true));
    return result;
  }

  Future<R> _withCancel<R>(CancelToken token, Future<R> work) {
    return Future.any([work, token.whenCancelled.then<R>((_) => throw CancelledException())]);
  }

  /// Stops the running attempt and releases its resources.
  Future<void> cancel({bool silent = false}) async {
    final token = _token;
    _token = null;
    if (token == null || token.isCancelled) return;
    final wasBusy = isBusy;
    await token.cancel();
    if (!silent && wasBusy) _set(state.value.copyWith(phase: ConnectPhase.cancelled));
  }

  void reset() {
    cancel(silent: true);
    _set(const ConnectFlowState());
  }

  void dispose() {
    cancel(silent: true);
    state.dispose();
  }
}
