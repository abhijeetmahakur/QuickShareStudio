import 'package:flutter/foundation.dart';

// The browser shows its own notifications and has no tray; nothing to integrate.

final ValueNotifier<bool> _trayVisible = ValueNotifier(false);

ValueListenable<bool> get trayVisible => _trayVisible;

bool get supportsTray => false;

void configure() {}

Future<void> start() async {}

Future<void> applyCloseToTray() async {}

Future<bool> notify(String title, String body, {bool urgent = false, int? openSection}) async => false;
