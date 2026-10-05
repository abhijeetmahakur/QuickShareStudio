import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/constants.dart';

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
      uri = text.startsWith('quickshare://')
          ? Uri.parse(text)
          : Uri.parse('quickshare://pair?$text');
    } on FormatException {
      return null;
    }
    final code = (uri.queryParameters['code'] ?? '').replaceAll(
      RegExp(r'\D'),
      '',
    );
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

/// Camera scanning is available on mobile, macOS, and secure-context browsers.
bool get cameraScanSupported =>
    kIsWeb ||
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS ||
    defaultTargetPlatform == TargetPlatform.macOS;

/// Full-screen camera scanner. Pops with the scanned text.
class QrScannerPage extends StatefulWidget {
  const QrScannerPage({super.key});

  @override
  State<QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends State<QrScannerPage> {
  late final MobileScannerController _controller;
  bool _done = false;
  bool _permissionDenied = false;
  bool _permanentlyDenied = false;
  String? _errorMessage;
  String? _invalidQrMessage;
  Timer? _invalidQrTimer;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      autoStart: true,
      facing: CameraFacing.back,
      detectionSpeed: DetectionSpeed.noDuplicates,
      formats: const [BarcodeFormat.qrCode],
    );
    _checkInitialPermission();
  }

  Future<void> _checkInitialPermission() async {
    if (kIsWeb) return;
    try {
      final status = await Permission.camera.status;
      if (status.isPermanentlyDenied) {
        if (mounted) {
          setState(() {
            _permanentlyDenied = true;
            _permissionDenied = true;
          });
        }
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _invalidQrTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _retryPermission() async {
    try {
      final status = await Permission.camera.request();
      if (!mounted) return;
      if (status.isGranted) {
        setState(() {
          _permissionDenied = false;
          _permanentlyDenied = false;
          _errorMessage = null;
        });
        await _controller.start();
      } else if (status.isPermanentlyDenied) {
        setState(() {
          _permanentlyDenied = true;
          _permissionDenied = true;
        });
        await openAppSettings();
      } else {
        setState(() {
          _permissionDenied = true;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = "Could not request camera permission: $e");
    }
  }

  Future<void> _retryStart() async {
    setState(() {
      _errorMessage = null;
      _permissionDenied = false;
    });
    try {
      await _controller.start();
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = "Could not start camera: $e");
      }
    }
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final b in capture.barcodes) {
      final value = b.rawValue;
      if (value == null || value.trim().isEmpty) continue;
      final raw = value.trim();

      final parsed = PairingQr.parse(raw);
      if (parsed != null) {
        _done = true;
        HapticFeedback.mediumImpact();
        Navigator.of(context).pop(raw);
        return;
      } else {
        _handleInvalidQr(raw);
      }
    }
  }

  void _handleInvalidQr(String raw) {
    HapticFeedback.lightImpact();
    setState(() {
      _invalidQrMessage =
          "Not a QuickShare pairing QR code. Please scan the QR code from the other device's pairing screen.";
    });
    _invalidQrTimer?.cancel();
    _invalidQrTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _invalidQrMessage = null);
    });
  }

  Widget _buildErrorView({
    required IconData icon,
    required String title,
    required String message,
    required Widget primaryAction,
    Widget? secondaryAction,
  }) {
    return ColoredBox(
      color: const Color(0xFF0C0C0B),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1C),
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.limeGreen.withValues(alpha: 0.3)),
                  ),
                  child: Icon(icon, color: AppColors.limeGreen, size: 30),
                ),
                const SizedBox(height: 20),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    color: Color(0xFFC0C2B8),
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: primaryAction,
                ),
                if (secondaryAction != null) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: secondaryAction,
                  ),
                ],
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text(
                    'Cancel and enter 6-digit code',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      color: Color(0xFF7A7D73),
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_permanentlyDenied) {
      return Scaffold(
        backgroundColor: const Color(0xFF0C0C0B),
        appBar: AppBar(
          title: const Text('Scan QR Code', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: _buildErrorView(
          icon: Icons.settings_outlined,
          title: 'Camera Access Disabled',
          message:
              'Camera permission is permanently denied in your device settings. To scan pairing QR codes, enable camera permission in App Settings.',
          primaryAction: ElevatedButton.icon(
            onPressed: () => openAppSettings(),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.limeGreen,
              foregroundColor: AppColors.nearBlack,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.settings, size: 18),
            label: const Text('Open App Settings', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
          ),
        ),
      );
    }

    if (_permissionDenied) {
      return Scaffold(
        backgroundColor: const Color(0xFF0C0C0B),
        appBar: AppBar(
          title: const Text('Scan QR Code', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: _buildErrorView(
          icon: Icons.camera_alt_outlined,
          title: 'Camera Permission Required',
          message:
              'QuickShare Studio needs camera access to scan pairing QR codes from other devices. Please allow camera permission to proceed.',
          primaryAction: ElevatedButton.icon(
            onPressed: _retryPermission,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.limeGreen,
              foregroundColor: AppColors.nearBlack,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
            label: const Text('Grant Camera Permission', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
          ),
          secondaryAction: OutlinedButton.icon(
            onPressed: () => openAppSettings(),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white70,
              side: const BorderSide(color: Color(0xFF333333)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.settings_outlined, size: 16),
            label: const Text('Open App Settings', style: TextStyle(fontFamily: 'Poppins')),
          ),
        ),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        backgroundColor: const Color(0xFF0C0C0B),
        appBar: AppBar(
          title: const Text('Scan QR Code', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: _buildErrorView(
          icon: Icons.error_outline_rounded,
          title: 'Camera Error',
          message: _errorMessage!,
          primaryAction: ElevatedButton.icon(
            onPressed: _retryStart,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.limeGreen,
              foregroundColor: AppColors.nearBlack,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Try Camera Again', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Scan QR Code', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 16)),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            tooltip: 'Toggle Flashlight',
            icon: ValueListenableBuilder<MobileScannerState>(
              valueListenable: _controller,
              builder: (context, state, _) {
                final isTorchOn = state.torchState == TorchState.on;
                return Icon(
                  isTorchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                  color: isTorchOn ? AppColors.limeGreen : Colors.white70,
                );
              },
            ),
            onPressed: () => _controller.toggleTorch(),
          ),
          IconButton(
            tooltip: 'Switch Camera',
            icon: const Icon(Icons.flip_camera_ios_rounded, color: Colors.white70),
            onPressed: () => _controller.switchCamera(),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final scanSize = math.min(
              260.0,
              math.min(constraints.maxWidth - 48, constraints.maxHeight * 0.45),
            );

            return Stack(
              fit: StackFit.expand,
              children: [
                MobileScanner(
                  controller: _controller,
                  onDetect: _onDetect,
                  errorBuilder: (context, error) {
                    final isPerm = error.errorCode == MobileScannerErrorCode.permissionDenied;
                    return _buildErrorView(
                      icon: isPerm ? Icons.no_photography_outlined : Icons.videocam_off_outlined,
                      title: isPerm ? 'Camera Access Required' : 'Camera Unavailable',
                      message: isPerm
                          ? 'Allow QuickShare Studio to use the camera to scan pairing QR codes.'
                          : (error.errorDetails?.message ?? "The device camera could not be opened. Check that no other app is using it."),
                      primaryAction: ElevatedButton.icon(
                        onPressed: isPerm ? _retryPermission : _retryStart,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.limeGreen,
                          foregroundColor: AppColors.nearBlack,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: Text(
                          isPerm ? 'Grant Permission' : 'Try Camera Again',
                          style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700),
                        ),
                      ),
                      secondaryAction: isPerm
                          ? OutlinedButton.icon(
                              onPressed: () => openAppSettings(),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white70,
                                side: const BorderSide(color: Color(0xFF333333)),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              icon: const Icon(Icons.settings_outlined, size: 16),
                              label: const Text('Open App Settings', style: TextStyle(fontFamily: 'Poppins')),
                            )
                          : null,
                    );
                  },
                ),

                // Targeting Viewfinder frame
                Center(
                  child: Container(
                    width: scanSize,
                    height: scanSize,
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.limeGreen, width: 2.5),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.limeGreen.withValues(alpha: 0.16),
                          blurRadius: 24,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  ),
                ),

                // Subtitle Instruction
                Positioned(
                  left: 24,
                  right: 24,
                  bottom: 28,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Point camera at the pairing QR code on the other device',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12.5,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),

                // Invalid QR warning banner
                if (_invalidQrMessage != null)
                  Positioned(
                    top: 16,
                    left: 20,
                    right: 20,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF261414),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFF87171)),
                        boxShadow: const [
                          BoxShadow(color: Colors.black54, blurRadius: 10, offset: Offset(0, 4)),
                        ],
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded, color: Color(0xFFF87171), size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _invalidQrMessage!,
                              style: const TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 12,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, size: 16, color: Colors.white70),
                            onPressed: () => setState(() => _invalidQrMessage = null),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
