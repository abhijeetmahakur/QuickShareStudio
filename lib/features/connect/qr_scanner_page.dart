import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/constants.dart';
import '../../core/design/tokens.dart';

/// What a QuickShare QR code carries.
class PairingQr {
  const PairingQr({required this.code, this.nonce, this.host, this.port});
  final String code;

  /// One-time secret proving the scanner saw this QR (internet connections).
  final String? nonce;

  /// LAN address for direct pairing on the same network.
  final String? host;
  final int? port;

  /// Accepts `quickshare://pair?...`, a bare query string or a 6-digit code.
  static PairingQr? parse(String raw) {
    final text = raw.trim();
    if (RegExp(r'^\d{6}$').hasMatch(text)) return PairingQr(code: text);
    Uri uri;
    try {
      uri = text.startsWith('quickshare://') ? Uri.parse(text) : Uri.parse('quickshare://pair?$text');
    } on FormatException {
      return null;
    }
    final code = (uri.queryParameters['code'] ?? '').replaceAll(RegExp(r'\D'), '');
    if (code.length != 6) return null;
    final port = int.tryParse(uri.queryParameters['port'] ?? '');
    return PairingQr(
      code: code,
      nonce: uri.queryParameters['n'],
      host: uri.queryParameters['host'],
      port: port,
    );
  }
}

/// Phones and tablets can scan with the camera; the desktop app pastes the QR link instead.
bool get cameraScanSupported =>
    !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

/// Full-screen camera scanner. Pops with the scanned text.
class QrScannerPage extends StatefulWidget {
  const QrScannerPage({super.key});

  @override
  State<QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends State<QrScannerPage> {
  final MobileScannerController _controller = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final b in capture.barcodes) {
      final value = b.rawValue;
      if (value != null && PairingQr.parse(value) != null) {
        _done = true;
        HapticFeedback.mediumImpact();
        Navigator.of(context).pop(value);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text('Scan QR code'), backgroundColor: Colors.black, foregroundColor: Colors.white),
      body: Stack(children: [
        MobileScanner(
          controller: _controller,
          onDetect: _onDetect,
          errorBuilder: (context, error) => Center(
            child: Padding(
              padding: const EdgeInsets.all(Space.xl),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.no_photography_outlined, color: Colors.white70, size: 48),
                const SizedBox(height: Space.l),
                Text(
                  error.errorCode == MobileScannerErrorCode.permissionDenied
                      ? 'QuickShare needs the camera to scan the code. Allow camera access in Settings, or type the 6-digit code instead.'
                      : "The camera couldn't start. Type the 6-digit code instead.",
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontFamily: 'Poppins', color: Colors.white),
                ),
              ]),
            ),
          ),
        ),
        Center(
          child: Container(
            width: 240,
            height: 240,
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.limeGreen, width: 3),
              borderRadius: BorderRadius.circular(Radii.card),
            ),
          ),
        ),
        const Positioned(
          left: 0,
          right: 0,
          bottom: 48,
          child: Text(
            "Point the camera at the QR code on the other device's Device Pairing screen.",
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Poppins', color: Colors.white),
          ),
        ),
      ]),
    );
  }
}
