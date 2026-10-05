import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

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

class _QrScannerPageState extends State<QrScannerPage>
    with WidgetsBindingObserver {
  final MobileScannerController _controller = MobileScannerController(
    autoStart: false,
    facing: CameraFacing.back,
    formats: const [BarcodeFormat.qrCode],
  );
  bool _done = false;
  bool _starting = false;
  bool _cameraReady = false;
  bool _cameraPermissionGranted = false;
  bool _permissionNeedsSettings = false;
  String? _cameraError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(_startCamera()),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_done) return;
    if (state == AppLifecycleState.resumed && _cameraPermissionGranted) {
      unawaited(_startCamera());
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      if (_cameraPermissionGranted && _cameraReady) {
        unawaited(_controller.stop());
      }
      if (mounted && _cameraReady) setState(() => _cameraReady = false);
    }
  }

  Future<void> _startCamera() async {
    if (!mounted || _starting || _done) return;
    setState(() {
      _starting = true;
      _cameraError = null;
      _permissionNeedsSettings = false;
    });

    try {
      if (!kIsWeb) {
        var permission = await Permission.camera.status;
        if (!permission.isGranted) {
          permission = await Permission.camera.request();
        }
        if (!permission.isGranted) {
          if (!mounted) return;
          setState(() {
            _starting = false;
            _permissionNeedsSettings =
                permission.isPermanentlyDenied || permission.isRestricted;
            _cameraError = 'Camera access is needed to scan a QR code.';
          });
          return;
        }
      }

      _cameraPermissionGranted = true;
      await _controller.start();
      if (!mounted) return;
      setState(() {
        _starting = false;
        _cameraReady = true;
        _cameraError = null;
      });
    } on MobileScannerException catch (error) {
      if (!mounted) return;
      setState(() {
        _starting = false;
        _cameraReady = false;
        _permissionNeedsSettings =
            error.errorCode == MobileScannerErrorCode.permissionDenied &&
            !kIsWeb;
        _cameraError =
            error.errorCode == MobileScannerErrorCode.permissionDenied
            ? 'Allow camera access for QuickShare in your device settings, then try again.'
            : "The camera couldn't start. Check that another app isn't using it, then try again.";
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _starting = false;
        _cameraReady = false;
        _cameraError = kIsWeb
            ? 'Allow camera access in your browser and make sure this page uses HTTPS or localhost.'
            : "The camera couldn't start. Check that another app isn't using it, then try again.";
      });
    }
  }

  Future<void> _openSettings() async {
    await openAppSettings();
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
      appBar: AppBar(
        title: const Text('Scan QR code'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final scanSize = math
                .max(
                  0.0,
                  math.min(
                    300.0,
                    math.min(
                      constraints.maxWidth - 48,
                      constraints.maxHeight * 0.44,
                    ),
                  ),
                )
                .toDouble();
            return Stack(
              fit: StackFit.expand,
              children: [
                MobileScanner(
                  controller: _controller,
                  onDetect: _onDetect,
                  errorBuilder: (context, error) => _cameraIssue(
                    title:
                        error.errorCode ==
                            MobileScannerErrorCode.permissionDenied
                        ? 'Camera access is off'
                        : 'Camera unavailable',
                    body:
                        error.errorCode ==
                            MobileScannerErrorCode.permissionDenied
                        ? 'Allow QuickShare to use the camera, then retry. You can also enter the six-digit code instead.'
                        : "The camera couldn't start. Close other camera apps and retry, or enter the six-digit code instead.",
                    showSettings:
                        error.errorCode ==
                            MobileScannerErrorCode.permissionDenied &&
                        !kIsWeb,
                  ),
                ),
                if (_cameraError != null)
                  _cameraIssue(
                    title: _permissionNeedsSettings
                        ? 'Camera access is off'
                        : 'Camera unavailable',
                    body: _cameraError!,
                    showSettings: _permissionNeedsSettings,
                  )
                else if (_starting)
                  ColoredBox(
                    color: Colors.black54,
                    child: Center(
                      child: CircularProgressIndicator(
                        color: AppColors.limeGreen,
                      ),
                    ),
                  )
                else if (_cameraReady) ...[
                  Center(
                    child: Container(
                      width: scanSize,
                      height: scanSize,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: AppColors.limeGreen,
                          width: 3,
                        ),
                        borderRadius: BorderRadius.circular(Radii.card),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.limeGreen.withValues(alpha: 0.18),
                            blurRadius: 24,
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 20,
                    right: 20,
                    bottom: 24,
                    child: Text(
                      "Point the camera at the QR code on the other device's Connect screen.",
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.white,
                        shadows: const [
                          Shadow(color: Colors.black, blurRadius: 8),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _cameraIssue({
    required String title,
    required String body,
    required bool showSettings,
  }) {
    return ColoredBox(
      color: Colors.black87,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Padding(
            padding: const EdgeInsets.all(Space.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.no_photography_outlined,
                  color: Colors.white70,
                  size: 44,
                ),
                const SizedBox(height: Space.l),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(color: Colors.white),
                ),
                const SizedBox(height: Space.s),
                Text(
                  body,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: Colors.white70, height: 1.4),
                ),
                const SizedBox(height: Space.l),
                FilledButton.icon(
                  onPressed: _starting ? null : _startCamera,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Try camera again'),
                ),
                if (showSettings) ...[
                  const SizedBox(height: Space.s),
                  TextButton.icon(
                    onPressed: _openSettings,
                    icon: const Icon(Icons.settings_outlined),
                    label: const Text('Open app settings'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
