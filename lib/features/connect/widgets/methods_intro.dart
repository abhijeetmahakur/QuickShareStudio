import 'package:flutter/material.dart';

import '../../../core/constants.dart';
import '../../../core/design/tokens.dart';
import '../../../transfer/bluetooth/bluetooth_support.dart';
import '../../../transfer/connection_manager.dart';
import '../../../transfer/transfer_method.dart';
import '../../../transfer/transfer_settings.dart';

/// First-run introduction to the three ways devices connect.
class MethodsIntroCard extends StatelessWidget {
  const MethodsIntroCard({super.key, required this.onDone});
  final VoidCallback onDone;

  static const _items = [
    (
      TransferMethod.lan,
      'Same Wi-Fi',
      'Fastest. Both devices on the same Wi-Fi or hotspot: enter the other device’s 6-digit code or scan its QR code.',
    ),
    (
      TransferMethod.internet,
      'Over the internet',
      'Different networks (home and office, mobile data). The same code works; QuickShare tries this automatically '
          'when the device is not on your Wi-Fi.',
    ),
    (
      TransferMethod.bluetooth,
      'Bluetooth, no internet',
      'Two Android phones close together, no Wi-Fi or data needed. Bluetooth pairs them and Wi-Fi Direct carries the files.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Semantics(
        scopesRoute: true,
        namesRoute: true,
        label: 'Three ways to connect',
        child: Container(
          constraints: const BoxConstraints(maxWidth: 480),
          margin: const EdgeInsets.all(Space.l),
          padding: const EdgeInsets.all(Space.xl),
          decoration: cardDecoration(border: AppColors.limeGreen.withValues(alpha: 0.45)),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Three ways to connect', style: TextStyles.title.copyWith(fontSize: 18)),
              const SizedBox(height: Space.xs),
              Text('QuickShare picks the right one for you. Everything is end-to-end encrypted, and you accept every file.',
                  style: TextStyles.caption),
              const SizedBox(height: Space.l),
              for (final (method, title, body) in _items) ...[
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(color: AppColors.surfaceElevated, borderRadius: BorderRadius.circular(Radii.control)),
                    child: Icon(method.icon, color: AppColors.limeGreen),
                  ),
                  const SizedBox(width: Space.m),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(title, style: TextStyles.label),
                      const SizedBox(height: 2),
                      Text(
                        method == TransferMethod.bluetooth && !BluetoothSupport.platformSupported
                            ? '$body (Android app only.)'
                            : body,
                        style: TextStyles.caption,
                      ),
                    ]),
                  ),
                ]),
                const SizedBox(height: Space.m),
              ],
              const SizedBox(height: Space.s),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  autofocus: true,
                  onPressed: onDone,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.limeGreen,
                    foregroundColor: AppColors.nearBlack,
                    minimumSize: const Size.fromHeight(minTapTarget),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.control)),
                  ),
                  child: const Text('Got it', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Shows [MethodsIntroCard] once, the first time the (live) app runs.
class MethodsIntroOverlay extends StatelessWidget {
  const MethodsIntroOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([TransferSettings.instance, ConnectionManager.instance]),
      builder: (context, _) {
        final settings = TransferSettings.instance;
        if (!ConnectionManager.instance.isStarted || settings.methodsIntroSeen) return const SizedBox.shrink();
        return Stack(children: [
          const ModalBarrier(dismissible: false, color: Color(0x99000000)),
          Center(child: MethodsIntroCard(onDone: settings.setMethodsIntroSeen)),
        ]);
      },
    );
  }
}

/// Reopens the introduction (e.g. from a help button).
Future<void> showMethodsIntro(BuildContext context) => showDialog<void>(
      context: context,
      builder: (ctx) => Center(child: MethodsIntroCard(onDone: () => Navigator.of(ctx).pop())),
    );
