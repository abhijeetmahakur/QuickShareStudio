import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants.dart';
import '../../../core/design/tokens.dart';
import '../../../data/models/pairing_session.dart';
import '../../../transfer/connection_manager.dart';
import '../../../transfer/transfer_settings.dart';

/// Countdown to the code's expiry plus where this device can be reached with it.
class CodeStatusBar extends StatefulWidget {
  const CodeStatusBar({super.key, required this.session, this.lanAvailable = false});
  final PairingSession? session;
  final bool lanAvailable;

  @override
  State<CodeStatusBar> createState() => _CodeStatusBarState();
}

class _CodeStatusBarState extends State<CodeStatusBar> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  static String _mmss(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    ConnectionManager? manager;
    try {
      manager = context.watch<ConnectionManager>();
    } catch (_) {}
    final live = manager?.isStarted ?? false;
    final remaining = session?.remaining() ?? Duration.zero;
    final expired = session == null || session.isExpired;
    final lowTime = remaining.inSeconds < 60;

    Widget pill(IconData icon, String text, Color color, String semantics) => Semantics(
          label: semantics,
          excludeSemantics: true,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: Space.s, vertical: Space.xs),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(Radii.chip),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: Space.xs),
              Text(text, style: TextStyle(fontFamily: 'Poppins', fontSize: 11.5, fontWeight: FontWeight.w600, color: color)),
            ]),
          ),
        );

    final internetOk = manager?.isHostingInternet ?? false;
    final internetStarting = manager?.isStartingHost ?? false;
    return Wrap(spacing: Space.s, runSpacing: Space.s, children: [
      if (live)
        pill(
          Icons.timer_outlined,
          expired ? 'Expired' : 'Expires in ${_mmss(remaining)}',
          expired || lowTime ? AppColors.warning : AppColors.secondaryText,
          expired ? 'Code expired' : 'Code expires in ${remaining.inMinutes} minutes ${remaining.inSeconds % 60} seconds',
        ),
      if (widget.lanAvailable) pill(Icons.wifi_rounded, 'Same Wi-Fi', AppColors.limeGreen, 'Reachable on this Wi-Fi'),
      if (live)
        Tooltip(
          message: internetOk
              ? 'Devices on other networks can connect with this code.'
              : (manager?.hostStatus ?? 'Connecting to the internet service...'),
          child: pill(
            Icons.public_rounded,
            internetOk
                ? 'Internet'
                : internetStarting
                    ? 'Internet...'
                    : (TransferSettings.instance.internetEnabled ? 'Internet unavailable' : 'Internet off'),
            internetOk ? const Color(0xFF60A5FA) : AppColors.mutedText,
            internetOk ? 'Reachable over the internet' : 'Not reachable over the internet',
          ),
        ),
    ]);
  }
}
