import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'transfer_method.dart';

/// User preferences for device-to-device transfers.
class TransferSettings extends ChangeNotifier {
  TransferSettings._();
  static final TransferSettings instance = TransferSettings._();
  factory TransferSettings() => instance;

  /// Accept incoming files without asking. Off by default: the receiver decides.
  bool autoAccept = false;

  /// Preferred way to connect; null = automatic (LAN, then internet, Bluetooth on request).
  TransferMethod? defaultMethod;

  /// After LAN finds nothing, try the internet automatically (when online).
  bool autoFallback = true;

  /// Make this device's code reachable over the internet (PeerJS).
  bool internetEnabled = true;

  /// The first-run walkthrough of the three methods has been shown.
  bool methodsIntroSeen = false;

  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      autoAccept = prefs.getBool('transfer_auto_accept') ?? false;
      defaultMethod = TransferMethod.tryParse(prefs.getString('transfer_default_method'));
      autoFallback = prefs.getBool('transfer_auto_fallback') ?? true;
      internetEnabled = prefs.getBool('transfer_internet_enabled') ?? true;
      methodsIntroSeen = prefs.getBool('transfer_methods_intro_seen') ?? false;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _save(Future<void> Function(SharedPreferences p) write) async {
    notifyListeners();
    try {
      await write(await SharedPreferences.getInstance());
    } catch (_) {}
  }

  Future<void> setAutoAccept(bool v) {
    autoAccept = v;
    return _save((p) => p.setBool('transfer_auto_accept', v));
  }

  Future<void> setDefaultMethod(TransferMethod? v) {
    defaultMethod = v;
    return _save((p) => v == null ? p.remove('transfer_default_method') : p.setString('transfer_default_method', v.name));
  }

  Future<void> setAutoFallback(bool v) {
    autoFallback = v;
    return _save((p) => p.setBool('transfer_auto_fallback', v));
  }

  Future<void> setInternetEnabled(bool v) {
    internetEnabled = v;
    return _save((p) => p.setBool('transfer_internet_enabled', v));
  }

  Future<void> setMethodsIntroSeen() {
    methodsIntroSeen = true;
    return _save((p) => p.setBool('transfer_methods_intro_seen', true));
  }

  @visibleForTesting
  void reset() {
    autoAccept = false;
    defaultMethod = null;
    autoFallback = true;
    internetEnabled = true;
    methodsIntroSeen = false;
    _loaded = true;
  }
}
