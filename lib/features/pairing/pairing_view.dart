import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../data/services/transfer_engine.dart';
import '../../data/models/device_model.dart';
import '../../core/constants.dart';

class PairingView extends StatefulWidget {
  const PairingView({super.key});

  @override
  State<PairingView> createState() => _PairingViewState();
}

class _PairingViewState extends State<PairingView> {
  final TextEditingController _codeController = TextEditingController();
  bool _isConnecting = false;
  String? _statusError;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _connectWithCode() async {
    final code = _codeController.text.trim();
    if (code.length < 6) {
      setState(() => _statusError = 'Please enter a valid 6-digit connection code');
      return;
    }

    setState(() {
      _isConnecting = true;
      _statusError = null;
    });

    final engine = context.read<TransferEngine>();
    final success = await engine.pairWithNumericCode(code);

    setState(() => _isConnecting = false);

    if (mounted) {
      if (success) {
        _codeController.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Device paired successfully! Added to Trusted Devices.')),
        );
      } else {
        setState(() => _statusError = 'Pairing code is invalid or expired.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<TransferEngine>();
    final session = engine.currentPairingSession;

    final secondsRemaining = session != null
        ? session.expiresAt.difference(DateTime.now()).inSeconds.clamp(0, 300)
        : 0;
    final mins = secondsRemaining ~/ 60;
    final secs = secondsRemaining % 60;
    final timerText = '$mins:${secs.toString().padLeft(2, '0')}';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Device Pairing & Security', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Description
            Text(
              'Pair devices using an expiring numeric connection code or temporary QR code.',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
            ),
            const SizedBox(height: 24),

            // Two main cards: Host Pairing (QR & Code) vs Connect to Remote
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 768;
                return Flex(
                  direction: isWide ? Axis.horizontal : Axis.vertical,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Card 1: My Device's Pairing Code & QR
                    Expanded(
                      flex: isWide ? 1 : 0,
                      child: Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.15)),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'This Device\'s Pairing Code',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: session != null && !session.isExpired
                                          ? AppColors.success.withValues(alpha: 0.15)
                                          : AppColors.error.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      session != null && !session.isExpired ? 'Active ($timerText)' : 'Expired',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: session != null && !session.isExpired
                                            ? AppColors.success
                                            : AppColors.error,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 20),

                              // Numeric Code Big Display
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                                ),
                                child: Text(
                                  session?.formattedCode ?? '--- ---',
                                  style: const TextStyle(
                                    fontSize: 32,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 4,
                                    fontFamily: 'monospace',
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Enter this 6-digit code on the other device',
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                              ),
                              const SizedBox(height: 20),

                              // QR Code
                              if (session != null)
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(10),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.05),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: QrImageView(
                                    data: session.qrPayload,
                                    version: QrVersions.auto,
                                    size: 160.0,
                                    backgroundColor: Colors.white,
                                  ),
                                ),
                              const SizedBox(height: 12),
                              Text(
                                'Or scan this temporary QR code',
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                              ),
                              const SizedBox(height: 16),

                              OutlinedButton.icon(
                                icon: const Icon(Icons.refresh, size: 18),
                                label: const Text('Generate New Code'),
                                onPressed: () => engine.regeneratePairingCode(),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    if (isWide) const SizedBox(width: 24) else const SizedBox(height: 24),

                    // Card 2: Connect to Remote Device
                    Expanded(
                      flex: isWide ? 1 : 0,
                      child: Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.15)),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Connect to Another Device',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Type the 6-digit code shown on the target device:',
                                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                              ),
                              const SizedBox(height: 20),

                              TextField(
                                controller: _codeController,
                                keyboardType: TextInputType.number,
                                maxLength: 6,
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 4,
                                  fontFamily: 'monospace',
                                ),
                                decoration: InputDecoration(
                                  hintText: '123456',
                                  labelText: 'Enter 6-Digit Code',
                                  prefixIcon: const Icon(Icons.key),
                                  errorText: _statusError,
                                  border: const OutlineInputBorder(),
                                ),
                              ),
                              const SizedBox(height: 12),

                              SizedBox(
                                width: double.infinity,
                                height: 46,
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primary,
                                    foregroundColor: Colors.white,
                                  ),
                                  icon: _isConnecting
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                        )
                                      : const Icon(Icons.link),
                                  label: Text(_isConnecting ? 'Verifying...' : 'Pair & Connect'),
                                  onPressed: _isConnecting ? null : _connectWithCode,
                                ),
                              ),
                              const SizedBox(height: 24),

                              const Divider(),
                              const SizedBox(height: 16),

                              const Row(
                                children: [
                                  Icon(Icons.shield_outlined, size: 18, color: AppColors.success),
                                  SizedBox(width: 8),
                                  Text(
                                    'Pairing Security Guarantees',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '• Codes expire automatically after 5 minutes.\n'
                                '• Rate-limiting prevents brute-force guessing.\n'
                                '• No reusable credentials or permanent secrets exposed.\n'
                                '• Explicit receiver approval required for transfers.',
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade600, height: 1.5),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),

            const SizedBox(height: 32),

            // Section: Trusted & Paired Devices
            const Text(
              'TRUSTED PAIRED DEVICES',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 12),

            if (engine.pairedDevices.isEmpty)
              Card(
                elevation: 0,
                color: Theme.of(context).cardColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(color: Colors.grey.withValues(alpha: 0.15)),
                ),
                child: const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                    child: Text('No devices paired yet. Use the code above to connect with a phone or lab PC.'),
                  ),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: engine.pairedDevices.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final dev = engine.pairedDevices[index];
                  return Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(color: Colors.grey.withValues(alpha: 0.15)),
                    ),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                        child: Icon(
                          dev.deviceType == DeviceType.mobile ? Icons.phone_android : Icons.computer,
                          color: AppColors.primary,
                        ),
                      ),
                      title: Text(dev.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('${dev.ip}:${dev.port} • Fingerprint: ${dev.fingerprint}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.success.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text('Trusted', style: TextStyle(color: AppColors.success, fontSize: 12)),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                            tooltip: 'Revoke Trust & Disconnect',
                            onPressed: () => engine.disconnectDevice(dev.id),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
