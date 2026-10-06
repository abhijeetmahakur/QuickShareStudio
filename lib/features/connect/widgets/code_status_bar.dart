import 'dart:async';

import 'package:flutter/material.dart';
import '../../../core/constants.dart';
import '../../../core/design/tokens.dart';
import '../../../data/models/pairing_session.dart';

/// Countdown to the code's expiry plus where this device can be reached with it.
class CodeStatusBar extends StatefulWidget {
  const CodeStatusBar({super.key, required this.session});
  final PairingSession? session;

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

    return Wrap(spacing: Space.s, runSpacing: Space.s, children: [
      if (session != null)
        pill(
          Icons.timer_outlined,
          expired ? 'Expired' : 'Expires in ${_mmss(remaining)}',
          expired || lowTime ? AppColors.warning : AppColors.secondaryText,
          expired ? 'Code expired' : 'Code expires in ${remaining.inMinutes} minutes ${remaining.inSeconds % 60} seconds',
        ),
    ]);
  }
}
