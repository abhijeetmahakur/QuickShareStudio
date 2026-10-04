import 'package:flutter/material.dart';

import '../../../core/constants.dart';
import '../../../core/design/tokens.dart';
import '../../../core/widgets/hover_card.dart';
import '../../../data/services/transfer_engine.dart';
import '../../../transfer/app_config.dart';
import '../../../transfer/bluetooth/bluetooth_support.dart';
import '../../../transfer/connection_manager.dart';
import '../../../transfer/transfer_method.dart';
import '../../../transfer/transfer_settings.dart';

/// Settings → Connections: how devices find each other and what happens with incoming files.
class ConnectionSettingsSection extends StatelessWidget {
  const ConnectionSettingsSection({super.key});

  @override
  Widget build(BuildContext context) =>
      ListenableBuilder(listenable: TransferSettings.instance, builder: (context, _) => _build(context));

  Widget _build(BuildContext context) {
    final settings = TransferSettings.instance;
    final engine = TransferEngine();
    final config = AppConfig.current;
    final methods = <TransferMethod?>[null, TransferMethod.lan, TransferMethod.internet];

    Widget switchTile({
      required IconData icon,
      required String title,
      required String subtitle,
      required bool value,
      required ValueChanged<bool> onChanged,
    }) =>
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: Icon(icon, color: AppColors.primaryAccent),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text(subtitle, style: TextStyle(fontSize: 12, color: AppColors.secondaryText)),
          value: value,
          onChanged: onChanged,
        );

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(
        'CONNECTIONS',
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.secondaryText, letterSpacing: 1.1),
      ),
      const SizedBox(height: Space.m),
      HoverCard(
        borderRadius: BorderRadius.circular(16),
        padding: const EdgeInsets.all(18),
        color: AppColors.charcoalSurface,
        borderColor: AppColors.white.withValues(alpha: 0.12),
        hoverBorderColor: AppColors.primaryAccent,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          switchTile(
            icon: Icons.mark_email_unread_outlined,
            title: 'Accept incoming files automatically',
            subtitle: settings.autoAccept
                ? 'On: files from connected devices are saved without asking. Turn off to approve each transfer.'
                : 'Off (recommended): you see who is sending what, and nothing is received until you tap Accept.',
            value: settings.autoAccept,
            onChanged: settings.setAutoAccept,
          ),
          const Divider(height: 1),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.route_rounded, color: AppColors.primaryAccent),
            title: const Text('Default connection method', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(
              'Automatic tries the same Wi-Fi first, then the internet.',
              style: TextStyle(fontSize: 12, color: AppColors.secondaryText),
            ),
            trailing: DropdownButton<TransferMethod?>(
              value: methods.contains(settings.defaultMethod) ? settings.defaultMethod : null,
              underline: const SizedBox.shrink(),
              items: [
                for (final m in methods)
                  DropdownMenuItem(value: m, child: Text(m == null ? 'Automatic' : m.description)),
              ],
              onChanged: settings.setDefaultMethod,
            ),
          ),
          const Divider(height: 1),
          switchTile(
            icon: Icons.public_rounded,
            title: 'Try the internet automatically',
            subtitle: 'When no device answers on this Wi-Fi within 5 seconds, connect over the internet instead.',
            value: settings.autoFallback,
            onChanged: settings.setAutoFallback,
          ),
          const Divider(height: 1),
          switchTile(
            icon: Icons.travel_explore_rounded,
            title: 'Reachable over the internet',
            subtitle: 'Devices on other networks can connect with this device’s code (via PeerJS Cloud signaling; '
                'files go directly between devices, encrypted).',
            value: settings.internetEnabled,
            onChanged: (v) async {
              await settings.setInternetEnabled(v);
              final session = engine.currentPairingSession;
              if (v && session != null) {
                await ConnectionManager.instance.hostCode(session);
              } else {
                await ConnectionManager.instance.stopHosting();
              }
            },
          ),
          const Divider(height: 1),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(config.hasTurn ? Icons.cloud_done_outlined : Icons.cloud_off_outlined, color: AppColors.primaryAccent),
            title: Text(config.hasTurn ? 'Relay (TURN) configured' : 'No relay (TURN) configured',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(
              config.hasTurn
                  ? 'If the networks block a direct link, data is relayed (still end-to-end encrypted).'
                  : 'Most networks connect directly. Strict ones (some mobile carriers, office Wi-Fi) need a TURN relay; '
                      'this build has none.',
              style: TextStyle(fontSize: 12, color: AppColors.secondaryText),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.bluetooth_rounded, color: AppColors.primaryAccent),
            title: const Text('Bluetooth (offline, nearby)', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(
              BluetoothSupport.platformSupported
                  ? 'Android 10+: open Device Pairing → Use Bluetooth. Files travel over Wi-Fi Direct.'
                  : BluetoothSupport.unsupportedReason ?? '',
              style: TextStyle(fontSize: 12, color: AppColors.secondaryText),
            ),
          ),
        ]),
      ),
    ]);
  }
}
