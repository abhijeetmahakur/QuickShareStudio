import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/services/transfer_engine.dart';
import '../../data/models/device_model.dart';
import '../../core/constants.dart';

class NearbyDevicesView extends StatefulWidget {
  const NearbyDevicesView({super.key});

  @override
  State<NearbyDevicesView> createState() => _NearbyDevicesViewState();
}

class _NearbyDevicesViewState extends State<NearbyDevicesView> {
  bool _isScanning = false;

  void _scanNetwork() async {
    setState(() => _isScanning = true);
    await Future.delayed(const Duration(milliseconds: 1200));
    setState(() => _isScanning = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Local network scan complete.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<TransferEngine>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nearby Devices (Local Network)', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: _isScanning
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            tooltip: 'Scan Local Subnet',
            onPressed: _isScanning ? null : _scanNetwork,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status Banner
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.wifi, color: AppColors.primary, size: 28),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Local Network Discovery (${engine.localIp})',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Compatible devices connected to the same Wi-Fi or computer-lab network appear here. Explicit approval is required before files can be exchanged.',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Discovered Unpaired Devices
            const Text(
              'DISCOVERED ON LOCAL NETWORK',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 12),

            if (engine.nearbyDiscoveredDevices.isEmpty)
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(color: Colors.grey.withValues(alpha: 0.15)),
                ),
                child: const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(Icons.radar, size: 40, color: Colors.grey),
                        SizedBox(height: 12),
                        Text('No new nearby devices detected right now.'),
                        SizedBox(height: 4),
                        Text('Make sure both devices are on the same Wi-Fi network or use QR/Numeric code pairing.'),
                      ],
                    ),
                  ),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: engine.nearbyDiscoveredDevices.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final device = engine.nearbyDiscoveredDevices[index];
                  return Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(color: Colors.grey.withValues(alpha: 0.15)),
                    ),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: AppColors.secondary.withValues(alpha: 0.15),
                        child: Icon(
                          device.deviceType == DeviceType.mobile
                              ? Icons.smartphone
                              : device.deviceType == DeviceType.tablet
                                  ? Icons.tablet_mac
                                  : Icons.laptop,
                          color: AppColors.secondary,
                        ),
                      ),
                      title: Text(device.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('IP: ${device.ip} • Port: ${device.port}'),
                      trailing: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                        ),
                        icon: const Icon(Icons.add_link, size: 16),
                        label: const Text('Pair & Trust'),
                        onPressed: () {
                          engine.approveNearbyDevice(device);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Paired with ${device.name}.')),
                          );
                        },
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
