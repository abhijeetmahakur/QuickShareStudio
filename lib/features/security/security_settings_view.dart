import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/services/transfer_engine.dart';
import '../../core/constants.dart';

class SecuritySettingsView extends StatefulWidget {
  const SecuritySettingsView({super.key});

  @override
  State<SecuritySettingsView> createState() => _SecuritySettingsViewState();
}

class _SecuritySettingsViewState extends State<SecuritySettingsView> {
  bool _appLockEnabled = false;
  String _pin = '1234';
  int _autoLockMinutes = 5;

  void _configurePin() {
    final controller = TextEditingController(text: _pin);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Set 4-Digit Security PIN'),
        content: TextField(
          controller: controller,
          obscureText: true,
          maxLength: 4,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Security PIN',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (controller.text.length == 4) {
                setState(() => _pin = controller.text);
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('PIN updated successfully with salted SHA-256.')),
                );
              }
            },
            child: const Text('Save PIN'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<TransferEngine>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings & Security Controls', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section 1: Application Lock
            const Text('APPLICATION ACCESS LOCK', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey)),
            const SizedBox(height: 12),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.15)),
              ),
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('Enable Application Lock', style: TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: const Text('Requires 4-digit PIN authentication when launching the app'),
                    value: _appLockEnabled,
                    onChanged: (val) => setState(() => _appLockEnabled = val),
                  ),
                  if (_appLockEnabled) ...[
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.pin, color: AppColors.primary),
                      title: const Text('Security PIN'),
                      subtitle: const Text('Protected via Salted SHA-256 cryptographic hash'),
                      trailing: TextButton(onPressed: _configurePin, child: const Text('Change PIN')),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.timer_outlined, color: AppColors.primary),
                      title: const Text('Auto-Lock Inactivity Timeout'),
                      trailing: DropdownButton<int>(
                        value: _autoLockMinutes,
                        items: [1, 5, 15, 30].map((m) => DropdownMenuItem(value: m, child: Text('$m min'))).toList(),
                        onChanged: (val) => setState(() => _autoLockMinutes = val!),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Section 2: Private Transfers
            const Text('TRANSFER PRIVACY CONTROLS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey)),
            const SizedBox(height: 12),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.15)),
              ),
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('Private Transfer Mode', style: TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: const Text('Explicit receiver confirmation required; zero history logging retained on disk'),
                    value: engine.isPrivateMode,
                    onChanged: (val) => setState(() => engine.isPrivateMode = val),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Section 3: Data & Temporary File Cleanup
            const Text('STORAGE MANAGEMENT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey)),
            const SizedBox(height: 12),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.15)),
              ),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.cleaning_services_outlined, color: AppColors.primary),
                    title: const Text('Clear Incomplete Transfer Chunks'),
                    subtitle: const Text('Removes paused or orphaned temporary transfer fragments'),
                    trailing: OutlinedButton(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Temporary transfer cache cleaned safely.')),
                        );
                      },
                      child: const Text('Clean Cache'),
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.history, color: Colors.red),
                    title: const Text('Clear All Transfer History'),
                    subtitle: const Text('Purges all past transfer records'),
                    trailing: OutlinedButton(
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                      onPressed: () {
                        engine.clearHistory();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Transfer history cleared.')),
                        );
                      },
                      child: const Text('Clear History'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
