import 'package:flutter/foundation.dart';

/// Lets code outside the widget tree (the tray menu, notification clicks) open a section of
/// the dashboard. The indices match DashboardScreen's sections.
class AppNavigation {
  AppNavigation._();

  static const int dashboard = 0;
  static const int pairing = 2;
  static const int received = 4;
  static const int history = 7;

  /// The section to show next; DashboardScreen listens and switches to it.
  static final ValueNotifier<int?> requestedSection = ValueNotifier<int?>(null);

  static void open(int section) {
    // Reset first so asking for the same section twice still notifies.
    requestedSection.value = null;
    requestedSection.value = section;
  }
}
