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

  void removeOnCancel(FutureOr<void> Function() cleanup) {
    _cleanups.remove(cleanup);
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

enum ConnectPhase { idle, connecting, searchingLan, tryingInternet, connected, failed, cancelled }

@immutable
class ConnectFlowState {
  const ConnectFlowState({
    this.phase = ConnectPhase.idle,
    this.connectionMethod = 'Wi-Fi',
    this.lanFailed = false,
    this.online,
    this.failure,
    this.detail,
    this.startedAt,
  });

  final ConnectPhase phase;
  final String connectionMethod; // 'Wi-Fi', 'Internet', 'Relay', 'Bluetooth'
  final bool lanFailed;
  final bool? online;
  final ConnectFailure? failure;

  /// Extra explanation of the failure.
  final String? detail;
  final DateTime? startedAt;

  static const String lanNotFoundMessage =
      "Couldn't connect to device. Ensure both devices are on, have pairing open, and retry.";

  bool get isBusy =>
      phase == ConnectPhase.connecting ||
      phase == ConnectPhase.searchingLan ||
      phase == ConnectPhase.tryingInternet;

  /// Always false: connection is fully automatic, never prompting manual choice buttons.
  bool get showsOptions => false;

  String get statusText => switch (phase) {
        ConnectPhase.connecting ||
        ConnectPhase.searchingLan ||
        ConnectPhase.tryingInternet =>
          'Connecting...',
        ConnectPhase.connected => 'Connected via $connectionMethod',
        ConnectPhase.cancelled => 'Cancelled',
        ConnectPhase.failed => detail ?? lanNotFoundMessage,
        ConnectPhase.idle => '',
      };

  ConnectFlowState copyWith({
    ConnectPhase? phase,
    String? connectionMethod,
    bool? lanFailed,
    bool? online,
    ConnectFailure? failure,
    String? detail,
    bool clearFailure = false,
  }) =>
      ConnectFlowState(
        phase: phase ?? this.phase,
        connectionMethod: connectionMethod ?? this.connectionMethod,
        lanFailed: lanFailed ?? this.lanFailed,
        online: online ?? this.online,
        failure: clearFailure ? null : (failure ?? this.failure),
        detail: clearFailure ? null : (detail ?? this.detail),
        startedAt: startedAt,
      );
}

class _RaceTask<T> {
  _RaceTask({
    required this.token,
    required this.label,
    required this.timeout,
    required this.action,
  });

  final CancelToken token;
  final String label;
  final Duration timeout;
  final Future<T> Function() action;
}

class _Winner<T> {
  _Winner(this.result, this.label);
  final T result;
  final String label;
}

/// The automatic connection flow:
/// 1. Same Wi-Fi / LAN direct connection (timeout ~4s)
/// 2. PeerJS + WebRTC with STUN servers (timeout ~8s)
/// 3. WebRTC with TURN relay (forced relay, timeout ~8s)
/// Runs attempts 1-3 in parallel, uses the first that connects, and cancels the rest.
/// 4. Bluetooth fallback (only if 1-3 all fail).
class ConnectFlow<T> {
  ConnectFlow({
    required this.lan,
    Future<T> Function(CancelToken token)? internet,
    Future<T> Function(CancelToken token)? internetStun,
    this.internetRelay,
    this.bluetooth,
    required this.isOnline,
    this.lanTimeout = const Duration(seconds: 4),
    this.stunTimeout = const Duration(seconds: 8),
    this.relayTimeout = const Duration(seconds: 8),
    this.autoInternet = true,
  })  : internetStun = internetStun ?? internet;

  final Future<T> Function(CancelToken token) lan;
  final Future<T> Function(CancelToken token)? internetStun;
  final Future<T> Function(CancelToken token)? internetRelay;
  final Future<T> Function(CancelToken token)? bluetooth;
  final Future<bool> Function() isOnline;
  final Duration lanTimeout;
  final Duration stunTimeout;
  final Duration relayTimeout;
  final bool autoInternet;

  final ValueNotifier<ConnectFlowState> state = ValueNotifier(const ConnectFlowState());
  CancelToken? _token;

  bool get isBusy => state.value.isBusy;

  void _set(ConnectFlowState s) => state.value = s;

  /// Full automated flow:
  /// Attempts 1-3 are raced in parallel; first one to connect wins and the others are cancelled.
  /// If 1-3 all fail, Attempt 4 (Bluetooth fallback) is executed silently.
  Future<T?> run() async {
    await cancel(silent: true);
    final token = _token = CancelToken();
    _set(ConnectFlowState(phase: ConnectPhase.connecting, startedAt: DateTime.now()));

    final online = await isOnline();
    if (token.isCancelled) return null;

    final tasks = <_RaceTask<T>>[];
    Object? lastError;

    // Attempt 1: Same Wi-Fi / LAN direct connection (timeout ~4s)
    final lanToken = CancelToken();
    token.onCancel(lanToken.cancel);
    tasks.add(_RaceTask<T>(
      token: lanToken,
      label: 'Wi-Fi',
      timeout: lanTimeout,
      action: () => lan(lanToken),
    ));

    // Race WebRTC STUN and TURN relay alongside LAN when an internet path is available.
    if (online && autoInternet) {
      // Attempt 2: PeerJS + WebRTC with STUN servers (timeout ~8s)
      final stunConnector = internetStun;
      if (stunConnector != null) {
        final stunToken = CancelToken();
        token.onCancel(stunToken.cancel);
        tasks.add(_RaceTask<T>(
          token: stunToken,
          label: 'Internet',
          timeout: stunTimeout,
          action: () => stunConnector(stunToken),
        ));
      }

      // Attempt 3: WebRTC with TURN relay (forced relay, timeout ~8s)
      final relayConnector = internetRelay;
      if (relayConnector != null) {
        final relayToken = CancelToken();
        token.onCancel(relayToken.cancel);
        tasks.add(_RaceTask<T>(
          token: relayToken,
          label: 'Relay',
          timeout: relayTimeout,
          action: () => relayConnector(relayToken),
        ));
      }
    }

    try {
      final winner = await _raceTasks(tasks, token);
      if (token.isCancelled) return null;
      return _connected(token, winner.result, winner.label);
    } on CancelledException {
      return null;
    } catch (e) {
      if (token.isCancelled) return null;
      lastError = e;
    }

    if (token.isCancelled) return null;

    // Attempt 4: Bluetooth fallback (only if 1-3 all fail)
    if (bluetooth != null && !token.isCancelled) {
      final btToken = CancelToken();
      token.onCancel(btToken.cancel);
      try {
        final btResult = await _runTimed(
          _RaceTask<T>(
            token: btToken,
            label: 'Bluetooth',
            timeout: const Duration(seconds: 8),
            action: () => bluetooth!(btToken),
          ),
        );
        return _connected(token, btResult, 'Bluetooth');
      } on CancelledException {
        return null;
      } catch (e) {
        if (e is ConnectException &&
            (e.kind == ConnectFailure.wrongCode ||
                e.kind == ConnectFailure.lockedOut ||
                e.kind == ConnectFailure.rejected)) {
          lastError = e;
        }
        await btToken.cancel();
      }
    }

    if (token.isCancelled) return null;

    // ALL methods failed
    _set(state.value.copyWith(
      phase: ConnectPhase.failed,
      failure: lastError is ConnectException ? lastError.kind : ConnectFailure.noRoute,
      detail: lastError is ConnectException &&
              (lastError.kind == ConnectFailure.wrongCode ||
                  lastError.kind == ConnectFailure.lockedOut ||
                  lastError.kind == ConnectFailure.rejected)
          ? lastError.message
          : "Couldn't connect to device. Ensure both devices are on, have pairing open, and retry.",
    ));
    return null;
  }

  Future<_Winner<T>> _raceTasks(List<_RaceTask<T>> tasks, CancelToken masterToken) {
    final completer = Completer<_Winner<T>>();
    var remaining = tasks.length;
    final errors = <Object>[];

    if (tasks.isEmpty) {
      completer.completeError(ConnectException(ConnectFailure.noRoute, 'No connection methods available.'));
      return completer.future;
    }

    for (final task in tasks) {
      _runTimed(task).then((res) async {
        if (!completer.isCompleted && !masterToken.isCancelled) {
          await Future.wait([
            for (final other in tasks)
              if (!identical(other, task)) other.token.cancel(),
          ]);
          if (!completer.isCompleted && !masterToken.isCancelled) {
            completer.complete(_Winner(res, task.label));
          }
        }
      }, onError: (Object err) {
        errors.add(err);
        remaining--;
        if (remaining == 0 && !completer.isCompleted) {
          final definitive = errors.whereType<ConnectException>().where((e) =>
              e.kind == ConnectFailure.wrongCode ||
              e.kind == ConnectFailure.lockedOut ||
              e.kind == ConnectFailure.rejected);
          completer.completeError(definitive.firstOrNull ?? errors.first);
        }
      });
    }

    return Future.any([
      completer.future,
      masterToken.whenCancelled.then<_Winner<T>>((_) => throw CancelledException()),
    ]);
  }

  Future<T> _runTimed(_RaceTask<T> task) async {
    try {
      return await Future.any([
        Future<T>.sync(task.action),
        task.token.whenCancelled.then<T>((_) => throw CancelledException()),
      ]).timeout(task.timeout);
    } on TimeoutException {
      await task.token.cancel();
      throw ConnectException(ConnectFailure.noRoute, 'Connection attempt timed out.');
    }
  }

  T? _connected(CancelToken token, T result, String label) {
    if (token.isCancelled) return null;
    _set(state.value.copyWith(
      phase: ConnectPhase.connected,
      connectionMethod: label,
      clearFailure: true,
    ));
    return result;
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
