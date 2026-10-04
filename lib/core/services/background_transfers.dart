import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../data/models/transfer_item.dart';
import '../../data/services/transfer_engine.dart';
import '../utils/format_utils.dart';

/// Keeps real transfers running when the app is in the background or the screen turns off
/// (Android): while any transfer is active, a foreground service shows its progress and holds
/// a partial wake lock and a Wi-Fi lock. It stops as soon as nothing is transferring.
class BackgroundTransferGuard {
  BackgroundTransferGuard._();

  static const _channel = MethodChannel('quickshare/system');
  static bool _running = false;
  static DateTime _lastUpdate = DateTime.fromMillisecondsSinceEpoch(0);

  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static void attach(TransferEngine engine) {
    if (!supported) return;
    engine.addListener(() => _update(engine));
  }

  static void _update(TransferEngine engine) {
    final active = engine.activeTransfers
        .where((t) => t.method != null && (t.status == TransferStatus.transferring || t.status == TransferStatus.queued))
        .toList();
    if (active.isEmpty) {
      if (_running) {
        _running = false;
        _channel.invokeMethod('transferServiceStop').catchError((_) {});
      }
      return;
    }
    final now = DateTime.now();
    if (_running && now.difference(_lastUpdate) < const Duration(seconds: 1)) return;
    _lastUpdate = now;
    _running = true;
    final total = active.fold<int>(0, (s, t) => s + t.fileSizeBytes);
    final done = active.fold<double>(0, (s, t) => s + t.fileSizeBytes * t.progress);
    final speed = active.fold<double>(0, (s, t) => s + t.speedBytesPerSec);
    final sending = active.where((t) => t.isSender).length;
    final title = active.length == 1
        ? '${active.first.isSender ? 'Sending' : 'Receiving'} ${active.first.fileName}'
        : '${sending > 0 ? 'Sending' : 'Receiving'} ${active.length} transfers';
    final percent = total == 0 ? 0 : (done / total * 100).floor();
    _channel.invokeMethod('transferServiceUpdate', {
      'title': title,
      'text': speed > 0 ? '$percent% · ${FormatUtils.formatSpeed(speed)}' : '$percent%',
      'progress': percent,
    }).catchError((_) {});
  }
}
