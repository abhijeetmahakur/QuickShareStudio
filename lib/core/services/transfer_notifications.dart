import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/app_navigation.dart';
import '../../data/models/transfer_item.dart';
import '../../data/services/transfer_engine.dart';
import '../../transfer/connection_manager.dart';
import '../utils/format_utils.dart';
import 'desktop_integration.dart';

/// Turns transfer events into OS notifications while QuickShare is not in front: an incoming
/// offer waiting for Accept, and transfers that finished or failed. The two switches under
/// Settings > Notifications control them.
class TransferNotifications {
  TransferNotifications._(this._engine, this._manager);

  static const incomingKey = 'notify_incoming_transfers';
  static const completedKey = 'notify_completed_failed';

  static TransferNotifications? _instance;

  final TransferEngine _engine;
  final ConnectionManager _manager;
  final Set<String> _announcedOffers = {};
  final Map<String, TransferStatus> _lastStatus = {};

  /// Overridable in tests; by default "in front" means the window is focused and visible.
  static bool Function() isInForeground =
      () => WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  /// Overridable in tests.
  static Future<bool> Function(String title, String body, {bool urgent, int? openSection}) show =
      DesktopIntegration.notify;

  static void attach(TransferEngine engine, ConnectionManager manager) {
    if (_instance != null) return;
    final n = _instance = TransferNotifications._(engine, manager);
    for (final t in engine.activeTransfers) {
      n._lastStatus[t.transferId] = t.status;
    }
    manager.addListener(n._onOffers);
    engine.addListener(n._onTransfers);
  }

  @visibleForTesting
  static void detach() {
    final n = _instance;
    if (n == null) return;
    n._manager.removeListener(n._onOffers);
    n._engine.removeListener(n._onTransfers);
    _instance = null;
  }

  Future<bool> _enabled(String key) async {
    try {
      return (await SharedPreferences.getInstance()).getBool(key) ?? true;
    } catch (_) {
      return true;
    }
  }

  void _onOffers() {
    for (final pending in _manager.pendingOffers) {
      final offer = pending.offer;
      if (pending.isDecided || !_announcedOffers.add(offer.transferId)) continue;
      if (isInForeground()) continue;
      final files = offer.files.length == 1 ? offer.files.first.name : '${offer.files.length} files';
      _notifyIf(
        incomingKey,
        '${offer.sender.name} wants to send you $files',
        '${FormatUtils.formatBytes(offer.totalBytes)}. Open QuickShare Studio to check the code and accept.',
        urgent: true,
      );
    }
  }

  void _onTransfers() {
    for (final t in _engine.activeTransfers) {
      final previous = _lastStatus[t.transferId];
      _lastStatus[t.transferId] = t.status;
      if (previous == t.status || isInForeground()) continue;
      if (t.status == TransferStatus.completed) {
        _notifyIf(
          completedKey,
          t.isSender ? 'Sent ${t.fileName}' : 'Received ${t.fileName}',
          t.isSender
              ? 'Delivered to ${t.peerDeviceName} (${FormatUtils.formatBytes(t.fileSizeBytes)}).'
              : 'From ${t.peerDeviceName}, ${FormatUtils.formatBytes(t.fileSizeBytes)}, checksum verified.',
          openSection: t.isSender ? AppNavigation.history : AppNavigation.received,
        );
      } else if (t.status == TransferStatus.failed || (t.status == TransferStatus.paused && t.resumable)) {
        _notifyIf(
          completedKey,
          t.status == TransferStatus.failed ? 'Transfer failed: ${t.fileName}' : 'Transfer interrupted: ${t.fileName}',
          t.errorMessage ?? (t.isSender ? 'Open QuickShare Studio to resume or retry.' : 'The sender can resume it.'),
          openSection: AppNavigation.history,
        );
      }
    }
  }

  Future<void> _notifyIf(String key, String title, String body, {bool urgent = false, int? openSection}) async {
    if (!await _enabled(key)) return;
    await show(title, body, urgent: urgent, openSection: openSection);
  }
}
