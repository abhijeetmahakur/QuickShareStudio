import '../../core/constants.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/widgets/demo_mode_notice.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../data/services/transfer_engine.dart';
import '../../data/models/device_model.dart';
import '../../core/widgets/hover_card.dart';
import '../../core/utils/format_utils.dart';
import '../../data/models/transfer_item.dart';
import '../../transfer/connection_manager.dart';
import '../../transfer/transfer_method.dart';
import '../connect/qr_scanner_page.dart';
import '../connect/widgets/code_status_bar.dart';
import '../connect/widgets/connect_status_panel.dart';
import '../connect/widgets/methods_intro.dart';
import '../connect/widgets/transfer_widgets.dart';

enum PairingDisplayMode { qrCode, sixDigitCode }
enum ConnectMode { sixDigitCode, scanQrCode }

class PairingView extends StatefulWidget {
  final VoidCallback? onNavigateToReceived;

  const PairingView({super.key, this.onNavigateToReceived});

  @override
  State<PairingView> createState() => _PairingViewState();
}

class _PairingViewState extends State<PairingView> {
  final TextEditingController _codeController = TextEditingController();
  PairingDisplayMode _activeMode = PairingDisplayMode.qrCode;
  ConnectMode _connectMode = ConnectMode.sixDigitCode;
  TransferMethod _pairingMethod = TransferMethod.internet;

  bool _isConnecting = false;
  String? _statusError;
  String? _statusSuccess;

  // Design Tokens (Strict adherence to specification)
  static Color get _bgNearBlack => AppColors.dashboardBg;
  static Color get _panelCharcoal => AppColors.charcoalSurface;
  static Color get _cardSurface => AppColors.cardBg;
  static Color get _limeAccent => AppColors.primaryAccent;
  static Color get _softLightGray => AppColors.secondaryText;
  static Color get _primaryText => AppColors.primaryText;
  static Color get _borderSubtle => AppColors.subtleBorder;
  static Color get _borderSubtleLight => AppColors.subtleBorderLight;
  static const Color _errorCoral = Color(0xFFF87171);
  static Color get _errorBg => AppColors.errorContainer;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _connectWithCode() async {
    final rawText = _codeController.text.trim();
    final isSixDigits = RegExp(r'^\d{6}$').hasMatch(rawText);
    final cleanCode = isSixDigits ? rawText : '';

    setState(() {
      _statusError = null;
      _statusSuccess = null;
    });

    if (!isSixDigits) {
      setState(() {
        _statusError = 'Please enter a valid 6-digit pairing code.';
      });
      return;
    }

    final engine = context.read<TransferEngine>();

    // Check if user is attempting to enter this device's own code
    if (engine.currentPairingSession != null &&
        engine.currentPairingSession!.numericCode == cleanCode) {
      setState(() {
        _statusError = 'Cannot pair with this device\'s own code. Enter the code from the other device.';
      });
      return;
    }

    // Check if the code was previously invalidated or regenerated
    if (engine.isCodeInvalidated(cleanCode)) {
      setState(() {
        _statusError = 'This pairing code has been invalidated or expired. Please ask the sender to regenerate a new code.';
      });
      return;
    }

    if (_isLive(engine)) {
      await _connectLive(cleanCode);
      return;
    }

    setState(() => _isConnecting = true);

    final success = await engine.pairWithNumericCode(cleanCode);

    if (!mounted) return;

    setState(() => _isConnecting = false);

    if (success) {
      _codeController.clear();
      setState(() {
        _statusSuccess = 'Device paired successfully! It has been added to Connected Devices below.';
        _statusError = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: _panelCharcoal,
          content: Row(
            children: [
              Icon(Icons.check_circle, color: _limeAccent, size: 20),
              SizedBox(width: 10),
              Text(
                'Device paired successfully!',
                style: TextStyle(fontFamily: 'Poppins', color: _primaryText, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    } else {
      setState(() {
        _statusError = engine.lastPairingError ?? 'Pairing failed. The code is invalid, expired, or was already used.';
        _statusSuccess = null;
      });
    }
  }

  Future<void> _connectWithQrPayload(String rawPayload) async {
    final payload = rawPayload.trim();

    setState(() {
      _statusError = null;
      _statusSuccess = null;
    });

    if (payload.isEmpty) {
      setState(() {
        _statusError = 'Please scan a valid QR code.';
      });
      return;
    }

    final engine = context.read<TransferEngine>();

    if (_isLive(engine)) {
      final qr = PairingQr.parse(payload);
      if (qr == null) {
        setState(() => _statusError = 'Not a QuickShare code');
        return;
      }
      if (engine.currentPairingSession?.numericCode == qr.code) {
        setState(() => _statusError = "That's this device's own QR code. Scan the one on the other device.");
        return;
      }
      await _connectLive(
        qr.code,
        qrNonce: qr.nonce,
        host: qr.host,
        port: qr.port,
        preferredMethod: qr.preferredMethod,
      );
      return;
    }

    setState(() => _isConnecting = true);

    final success = await engine.pairWithQrPayload(payload);

    if (!mounted) return;

    setState(() => _isConnecting = false);

    if (success) {
      setState(() {
        _statusSuccess = 'Device paired successfully from QR code! Added to Connected Devices.';
        _statusError = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: _panelCharcoal,
          content: Row(
            children: [
              Icon(Icons.qr_code_2_rounded, color: _limeAccent, size: 20),
              SizedBox(width: 10),
              Text(
                'QR Device paired successfully!',
                style: TextStyle(fontFamily: 'Poppins', color: _primaryText, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    } else {
      setState(() {
        _statusError = engine.lastPairingError ?? 'Pairing failed. The QR code is invalid, expired, or was already used.';
        _statusSuccess = null;
      });
    }
  }

  /// Real networking is running (not the demo used by tests and static previews).
  bool _isLive(TransferEngine engine) => engine.peerLink != null || ConnectionManager.instance.isStarted;

  Future<void> _connectLive(
    String code, {
    String? qrNonce,
    String? host,
    int? port,
    TransferMethod preferredMethod = TransferMethod.internet,
  }) async {
    final manager = ConnectionManager.instance;
    setState(() {
      _statusError = null;
      _statusSuccess = null;
      _isConnecting = true;
    });
    final device = await manager.connectWithCode(
      code,
      qrNonce: qrNonce,
      host: host,
      port: port,
      preferredMethod: preferredMethod,
    );
    if (!mounted) return;
    setState(() => _isConnecting = false);
    _onLiveResult(device);
  }

  void _onLiveResult(DeviceModel? device) {
    if (device == null || !mounted) return;
    _codeController.clear();
    HapticFeedback.mediumImpact();
    final methodLabel = ConnectionManager.instance.connectState.connectionMethod;
    setState(() {
      _statusSuccess = 'Connected via $methodLabel';
    });
  }

  Future<void> _scanWithCamera() async {
    final value = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const QrScannerPage()));
    if (value == null || !mounted) return;
    await _connectWithQrPayload(value);
  }

  void _handleRegenerate() {
    final engine = context.read<TransferEngine>();
    engine.regeneratePairingCode();

    setState(() {
      _statusError = null;
      _statusSuccess = null;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: _panelCharcoal,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: _borderSubtle),
        ),
        content: Row(
          children: [
            Icon(Icons.refresh, color: _limeAccent, size: 18),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'New pairing credentials generated. Previous QR and 6-digit codes have been invalidated.',
                style: TextStyle(fontFamily: 'Poppins', color: _primaryText, fontSize: 13),
              ),
            ),
          ],
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  IconData _getPlatformIcon(String? platform, DeviceType type) {
    final p = platform?.toLowerCase() ?? '';
    if (p.contains('win')) return Icons.laptop_windows_rounded;
    if (p.contains('mac')) return Icons.laptop_mac_rounded;
    if (p.contains('ios') || p.contains('apple') || p.contains('iphone')) return Icons.phone_iphone_rounded;
    if (p.contains('android')) return Icons.phone_android_rounded;
    if (p.contains('linux')) return Icons.terminal_rounded;
    return type == DeviceType.desktop ? Icons.desktop_windows_rounded : Icons.smartphone_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<TransferEngine>();
    final session = engine.currentPairingSession;
    final isSessionActive = session != null && session.isActive;
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final horizontalPadding = viewportWidth < 380
        ? 16.0
        : viewportWidth < 720
            ? 20.0
            : 28.0;

    return Scaffold(
      backgroundColor: _bgNearBlack,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: horizontalPadding,
            vertical: viewportWidth < 600 ? 16 : 24,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              // Screen Header
              _buildHeader(engine, isSessionActive),
              const SizedBox(height: 24),
              const DemoModeNotice(),

              // Two Main Functional Sections: Side-by-side on wide screens, stacked on small screens
              LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 860;
                  return Flex(
                    direction: isWide ? Axis.horizontal : Axis.vertical,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Section 1: Show My QR Code / Show My 6-Digit Code (Two ways to pair)
                      Expanded(
                        flex: isWide ? 6 : 0,
                        child: _buildShareCredentialsCard(session, isSessionActive),
                      ),
                      if (isWide) const SizedBox(width: 20) else const SizedBox(height: 20),

                      // Section 2: Connect to Another Device (Enter 6-digit code)
                      Expanded(
                        flex: isWide ? 5 : 0,
                        child: _buildConnectRemoteCard(engine),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 32),

              // Section 3: Connected Devices List
              _buildConnectedDevicesSection(engine),
              const SizedBox(height: 24),
              _buildActiveTransfers(engine),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(TransferEngine engine, bool isSessionActive) {
    final compact = MediaQuery.sizeOf(context).width < 380;
    return Container(
      padding: EdgeInsets.all(compact ? 14 : 20),
      decoration: BoxDecoration(
        color: _panelCharcoal,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _borderSubtle),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: compact ? 40 : 48,
            height: compact ? 40 : 48,
            decoration: BoxDecoration(
              color: _cardSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _limeAccent.withValues(alpha: 0.35)),
            ),
            child: Icon(Icons.phonelink_ring_rounded, color: _limeAccent, size: 26),
          ),
          SizedBox(width: compact ? 12 : 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'Device Pairing',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: compact ? 18 : 20,
                        fontWeight: FontWeight.w700,
                        color: _primaryText,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: isSessionActive
                            ? _limeAccent.withValues(alpha: 0.12)
                            : _errorCoral.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSessionActive
                              ? _limeAccent.withValues(alpha: 0.4)
                              : _errorCoral.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: isSessionActive ? _limeAccent : _errorCoral,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            isSessionActive ? 'Active Session' : 'Session Inactive',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isSessionActive ? _limeAccent : _errorCoral,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Connect with a QR code or six-digit code. Each code works once and expires after 5 minutes.',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12.5,
                    color: _softLightGray,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Section 1: Two Ways to Pair (Show QR Code OR Show Six-Digit Code)
  Widget _codeStatus(dynamic session) {
    final engine = context.read<TransferEngine>();
    if (!_isLive(engine)) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: CodeStatusBar(session: session),
    );
  }

  void _selectPairingMethod(TransferMethod method) {
    if (_pairingMethod == method) return;
    setState(() {
      _pairingMethod = method;
      _statusError = null;
      _statusSuccess = null;
    });
    context.read<TransferEngine>().regeneratePairingCode(preferredMethod: method);
  }

  Widget _buildPairingMethodSwitch() {
    final description = _pairingMethod == TransferMethod.internet
        ? 'Recommended across different networks. The six-digit code is the PeerJS ID and uses WebRTC with STUN and TURN.'
        : 'Faster when both devices share Wi-Fi. QR tries the local route first, then falls back to Internet.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Connection method',
          style: TextStyle(fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w600, color: _primaryText),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<TransferMethod>(
            key: const Key('pairing_method_switch'),
            segments: const [
              ButtonSegment<TransferMethod>(
                value: TransferMethod.internet,
                icon: Icon(Icons.public_rounded),
                label: Text('Internet'),
              ),
              ButtonSegment<TransferMethod>(
                value: TransferMethod.lan,
                icon: Icon(Icons.wifi_rounded),
                label: Text('Same Wi-Fi'),
              ),
            ],
            selected: {_pairingMethod},
            showSelectedIcon: false,
            onSelectionChanged: (selection) => _selectPairingMethod(selection.single),
            style: ButtonStyle(
              foregroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected) ? _bgNearBlack : _primaryText,
              ),
              backgroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected) ? _limeAccent : _cardSurface,
              ),
              side: WidgetStateProperty.resolveWith(
                (states) => BorderSide(color: states.contains(WidgetState.selected) ? _limeAccent : _borderSubtleLight),
              ),
              textStyle: WidgetStateProperty.resolveWith(
                (states) => TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12.5,
                  fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 12, vertical: 12)),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          description,
          style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: _softLightGray, height: 1.35),
        ),
      ],
    );
  }

  Widget _buildShareCredentialsCard(dynamic session, bool isSessionActive) {
    ConnectionManager? manager;
    try {
      manager = context.watch<ConnectionManager>();
    } catch (_) {
      manager = ConnectionManager.instance;
    }
    final hostStatus = manager.hostStatus;
    return Container(
      decoration: BoxDecoration(
        color: _panelCharcoal,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _borderSubtle),
      ),
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section Title
          Text(
            'Pair My Device',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: _primaryText,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Select how you want to present your pairing credentials to the other device:',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12,
              color: _softLightGray,
            ),
          ),
          const SizedBox(height: 16),
          _codeStatus(session),
          if (hostStatus != null) ...[
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.errorContainer,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.error.withValues(alpha: 0.4)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.cloud_off_outlined, size: 18, color: AppColors.error),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        hostStatus,
                        style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: _primaryText, height: 1.35),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          _buildPairingMethodSwitch(),
          const SizedBox(height: 16),

          // Two Ways to Pair Switcher Tabs
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: _cardSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _borderSubtleLight),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _buildModeTab(
                    title: 'Show my QR code',
                    icon: Icons.qr_code_2_rounded,
                    isSelected: _activeMode == PairingDisplayMode.qrCode,
                    onTap: () => setState(() => _activeMode = PairingDisplayMode.qrCode),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _buildModeTab(
                    title: 'Show my six-digit code',
                    icon: Icons.pin_outlined,
                    isSelected: _activeMode == PairingDisplayMode.sixDigitCode,
                    onTap: () => setState(() => _activeMode = PairingDisplayMode.sixDigitCode),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Conditional display based on selected mode
          if (_activeMode == PairingDisplayMode.qrCode)
            _buildQrCodeContent(session, isSessionActive)
          else
            _buildSixDigitCodeContent(session, isSessionActive),
        ],
      ),
    );
  }

  Widget _buildModeTab({
    required String title,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected ? _limeAccent : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected ? _bgNearBlack : _softLightGray,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                title,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12.5,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? _bgNearBlack : _softLightGray,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 1. Show my QR code
  Widget _buildQrCodeContent(dynamic session, bool isSessionActive) {
    return Column(
      children: [
        // QR Code Container
        Center(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _cardSurface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _borderSubtleLight),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (session != null && isSessionActive)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white, // QR codes need a white quiet zone in every theme
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: QrImageView(
                      data: session.qrPayload,
                      version: QrVersions.auto,
                      size: 180.0,
                      backgroundColor: Colors.white,
                    ),
                  )
                else
                  Container(
                    width: 180,
                    height: 180,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _cardSurface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _borderSubtle),
                    ),
                    child: Text(
                      'Session Inactive\nTap Regenerate below',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        color: _softLightGray,
                        fontSize: 12,
                      ),
                    ),
                  ),
                const SizedBox(height: 14),
                Text(
                  'Scan this QR code with another QuickShare Studio device',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    color: _softLightGray,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),

        // QR Controls: Regenerate QR Code & Copy
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 12,
          runSpacing: 8,
          children: [
            // Prominent Regenerate control for QR Code
            ElevatedButton.icon(
              onPressed: _handleRegenerate,
              style: ElevatedButton.styleFrom(
                backgroundColor: _cardSurface,
                foregroundColor: _limeAccent,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(color: _limeAccent, width: 1.2),
                ),
              ),
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text(
                'Regenerate QR Code',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (session != null && isSessionActive)
              OutlinedButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: session.qrPayload));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: _panelCharcoal,
                      content: Text('QR payload copied to clipboard!', style: TextStyle(fontFamily: 'Poppins', color: _primaryText)),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: _softLightGray,
                  side: BorderSide(color: _borderSubtleLight),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.copy_rounded, size: 15),
                label: const Text(
                  'Copy Payload',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 12),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Regenerating immediately invalidates the previous QR code and pairing session.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 11,
            color: _softLightGray,
          ),
        ),
      ],
    );
  }

  /// 2. Show my six-digit pairing code
  Widget _buildSixDigitCodeContent(dynamic session, bool isSessionActive) {
    final formatted = (session != null && isSessionActive) ? session.formattedCode : '---  ---';
    final rawCode = (session != null && isSessionActive) ? session.numericCode : '';

    return Column(
      children: [
        // 6-digit Code Box
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
          decoration: BoxDecoration(
            color: _cardSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _limeAccent.withValues(alpha: 0.3)),
            boxShadow: [
              BoxShadow(
                color: _limeAccent.withValues(alpha: 0.05),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              Text(
                'YOUR 6-DIGIT PAIRING CODE',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                  color: _softLightGray,
                ),
              ),
              const SizedBox(height: 14),
              SelectableText(
                formatted,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 4.0,
                  color: _limeAccent,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Enter this code on another device in the "Connect to another device" section.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  color: _softLightGray,
                ),
              ),
              // Devices that cannot discover others (e.g. iPhones) pair with this address + code.
              if (context.watch<TransferEngine>().hasRealNetwork) ...[
                const SizedBox(height: 6),
                SelectableText(
                  'This device: ${context.watch<TransferEngine>().localIp}:${context.watch<TransferEngine>().localPort}',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w600, color: _primaryText),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 18),

        // 6-Digit Controls: Regenerate & Copy
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Prominent Regenerate control for Six-Digit Code
            ElevatedButton.icon(
              onPressed: _handleRegenerate,
              style: ElevatedButton.styleFrom(
                backgroundColor: _cardSurface,
                foregroundColor: _limeAccent,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(color: _limeAccent, width: 1.2),
                ),
              ),
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text(
                'Regenerate 6-Digit Code',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 12),
            if (rawCode.isNotEmpty)
              OutlinedButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: rawCode));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: _panelCharcoal,
                      content: Text('6-digit code copied to clipboard!', style: TextStyle(fontFamily: 'Poppins', color: _primaryText)),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: _softLightGray,
                  side: BorderSide(color: _borderSubtleLight),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.copy_rounded, size: 15),
                label: const Text(
                  'Copy Code',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 12),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Regenerating immediately invalidates this code. Previous codes cannot be reused.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 11,
            color: _softLightGray,
          ),
        ),
      ],
    );
  }

  /// Section 2: Connect to another device (Enter 6-digit code)
  Widget _buildConnectRemoteCard(TransferEngine engine) {
    return Container(
      decoration: BoxDecoration(
        color: _panelCharcoal,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _borderSubtle),
      ),
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.link_rounded, color: _limeAccent, size: 20),
              SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Connect to another device',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: _primaryText,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'How connecting works',
                onPressed: () => showMethodsIntro(context),
                icon: Icon(Icons.help_outline_rounded, color: _softLightGray, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Enter the six-digit code displayed on the other device to connect and authenticate:',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12,
              color: _softLightGray,
            ),
          ),
          const SizedBox(height: 24),

          // Connect Mode Switcher Tabs
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: _cardSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _borderSubtleLight),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _buildModeTab(
                    title: 'Enter 6-digit code',
                    icon: Icons.pin_outlined,
                    isSelected: _connectMode == ConnectMode.sixDigitCode,
                    onTap: () => setState(() => _connectMode = ConnectMode.sixDigitCode),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _buildModeTab(
                    title: 'Scan QR code',
                    icon: Icons.qr_code_scanner_rounded,
                    isSelected: _connectMode == ConnectMode.scanQrCode,
                    onTap: () => setState(() => _connectMode = ConnectMode.scanQrCode),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          if (_connectMode == ConnectMode.sixDigitCode) ...[
            // Code Input Field
            TextField(
              controller: _codeController,
              keyboardType: TextInputType.number,
              maxLength: 6,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 26,
                letterSpacing: 10,
                fontWeight: FontWeight.w700,
                color: _primaryText,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
              ],
              decoration: InputDecoration(
                counterText: '',
                hintText: '000000',
                hintStyle: TextStyle(
                  fontFamily: 'Poppins',
                  color: _softLightGray.withValues(alpha: 0.3),
                  letterSpacing: 10,
                ),
                filled: true,
                fillColor: _cardSurface,
                suffixIcon: _codeController.text.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear_rounded, color: _softLightGray, size: 18),
                        onPressed: () {
                          setState(() {
                            _codeController.clear();
                            _statusError = null;
                          });
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(vertical: 16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: _borderSubtleLight),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: _borderSubtleLight),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: _limeAccent, width: 1.5),
                ),
              ),
              onChanged: (_) {
                if (_statusError != null || _statusSuccess != null) {
                  setState(() {
                    _statusError = null;
                    _statusSuccess = null;
                  });
                }
              },
              onSubmitted: (_) => _connectWithCode(),
            ),
            const SizedBox(height: 16),
            // Pair / Connect Action Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isConnecting ? null : _connectWithCode,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _limeAccent,
                  foregroundColor: _bgNearBlack,
                  disabledBackgroundColor: _limeAccent.withValues(alpha: 0.4),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                icon: _isConnecting
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: _bgNearBlack),
                      )
                    : const Icon(Icons.link_rounded, size: 20),
                label: Text(
                  'Pair / Connect',
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ] else ...[
            // QR Scanner
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              decoration: BoxDecoration(
                color: _cardSurface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _borderSubtleLight),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: _panelCharcoal,
                      shape: BoxShape.circle,
                      border: Border.all(color: _limeAccent.withValues(alpha: 0.3)),
                    ),
                    child: Icon(Icons.qr_code_scanner_rounded, color: _limeAccent, size: 28),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Scan Pairing QR Code',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: _primaryText,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Point your camera at the QR code shown on the other device to pair instantly.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12,
                      color: _softLightGray,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (cameraScanSupported)
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        key: const Key('scan_with_camera_button'),
                        onPressed: _isConnecting ? null : _scanWithCamera,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _limeAccent,
                          foregroundColor: _bgNearBlack,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.camera_alt_rounded, size: 18),
                        label: Text(
                          'Scan with Camera',
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    )
                  else
                    Text(
                      'Use the 6-digit code instead',
                      key: const Key('linux_camera_unavailable_hint'),
                      textAlign: TextAlign.center,
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w600, color: _softLightGray),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),

          // Error Feedback Banner
          if (_statusError != null)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _errorBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _errorCoral.withValues(alpha: 0.5)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.error_outline_rounded, color: _errorCoral, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _statusError!,
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        color: _errorCoral,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Success Feedback Banner
          if (_statusSuccess != null)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _limeAccent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _limeAccent.withValues(alpha: 0.4)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.check_circle_outline_rounded, color: _limeAccent, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _statusSuccess!,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        color: _limeAccent,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          if (_isLive(engine))
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: ListenableBuilder(
                listenable: ConnectionManager.instance,
                builder: (context, _) {
                  final manager = ConnectionManager.instance;
                  return ConnectStatusPanel(
                    state: manager.connectState,
                    onRetry: () async {
                      setState(() => _isConnecting = true);
                      final device = await manager.retryConnect();
                      if (!mounted) return;
                      setState(() => _isConnecting = false);
                      _onLiveResult(device);
                    },
                  );
                },
              ),
            ),

          // Security & Expiration Info Note
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _cardSurface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _borderSubtle),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.shield_outlined, color: _limeAccent, size: 18),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Temporary code: it works once and expires after 5 minutes (or 5 failed attempts). '
                    'Connections are end-to-end encrypted, and files are only received after you tap Accept.',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 11.5,
                      color: _softLightGray,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Section 3: Connected Devices List
  Widget _buildConnectedDevicesSection(TransferEngine engine) {
    final devices = engine.pairedDevices;

    return Container(
      decoration: BoxDecoration(
        color: _panelCharcoal,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _borderSubtle),
      ),
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section Title & Actions
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Row(
                  children: [
                    Icon(Icons.devices_rounded, color: _limeAccent, size: 20),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Connected Devices',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: _primaryText,
                        ),
                      ),
                    ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: _cardSurface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _borderSubtleLight),
                    ),
                    child: Text(
                      '${devices.length}',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: _limeAccent,
                      ),
                    ),
                  ),
                  ],
                ),
              ),
              if (devices.isNotEmpty)
                TextButton.icon(
                  onPressed: () {
                    engine.disconnectAllDevices();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        backgroundColor: _panelCharcoal,
                        content: Text('All devices disconnected.', style: TextStyle(fontFamily: 'Poppins', color: _primaryText)),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: _errorCoral,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  ),
                  icon: const Icon(Icons.link_off_rounded, size: 16),
                  label: const Text(
                    'Disconnect All',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Devices currently paired with this QuickShare Studio session. Disconnecting revokes access immediately.',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12,
              color: _softLightGray,
            ),
          ),
          const SizedBox(height: 18),

          // Devices List or Empty State
          if (devices.isEmpty)
            _buildEmptyDevicesCard(engine)
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: devices.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final device = devices[index];
                return _buildDeviceItem(device, engine);
              },
            ),
        ],
      ),
    );
  }

  /// Real transfers (with method, speed, ETA and Cancel / Resume / Retry).
  Widget _buildActiveTransfers(TransferEngine engine) {
    final transfers = engine.activeTransfers.where((t) => t.method != null).take(8).toList();
    if (transfers.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.swap_vert_rounded, color: _limeAccent, size: 20),
            const SizedBox(width: 8),
            Text('Transfers', style: TextStyle(fontFamily: 'Poppins', fontSize: 16, fontWeight: FontWeight.w700, color: _primaryText)),
            const Spacer(),
            if (transfers.any((t) => t.status == TransferStatus.completed || t.status == TransferStatus.cancelled))
              TextButton(
                onPressed: engine.clearFinishedTransfers,
                child: const Text('Clear finished', style: TextStyle(fontFamily: 'Poppins', fontSize: 12)),
              ),
          ]),
          const SizedBox(height: 12),
          for (final t in transfers) ...[
            TransferProgressTile(item: t, engine: engine),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyDevicesCard(TransferEngine engine) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
      decoration: BoxDecoration(
        color: _cardSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _borderSubtleLight),
      ),
      child: Column(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _panelCharcoal,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _borderSubtle),
            ),
            child: Icon(Icons.devices_other_rounded, color: _softLightGray, size: 24),
          ),
          const SizedBox(height: 12),
          Text(
            'No Devices Connected Yet',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: _primaryText,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Pair your smartphone, tablet, or another computer using the QR code or six-digit code above.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12,
              color: _softLightGray,
            ),
          ),
          const SizedBox(height: 18),

          // Demo mode only: these add simulated devices, which would mislead in the real app.
          if (!_isLive(engine)) Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: () async {
                  await engine.simulateInstantPair(deviceName: 'Pixel 8', platform: 'Android');
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        backgroundColor: _panelCharcoal,
                        content: Text('Paired test device "Pixel 8" (Android)', style: TextStyle(fontFamily: 'Poppins', color: _primaryText)),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  }
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: _softLightGray,
                  side: BorderSide(color: _borderSubtleLight),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: Icon(Icons.phone_android_rounded, size: 15, color: _limeAccent),
                label: const Text('Simulate Android', style: TextStyle(fontFamily: 'Poppins', fontSize: 11)),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  await engine.simulateInstantPair(deviceName: 'Surface Laptop', platform: 'Windows');
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        backgroundColor: _panelCharcoal,
                        content: Text('Paired test device "Surface Laptop" (Windows)', style: TextStyle(fontFamily: 'Poppins', color: _primaryText)),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  }
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: _softLightGray,
                  side: BorderSide(color: _borderSubtleLight),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: Icon(Icons.laptop_windows_rounded, size: 15, color: _limeAccent),
                label: const Text('Simulate Windows', style: TextStyle(fontFamily: 'Poppins', fontSize: 11)),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  await engine.simulateInstantPair(deviceName: 'iPhone 15 Pro', platform: 'iOS');
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        backgroundColor: _panelCharcoal,
                        content: Text('Paired test device "iPhone 15 Pro" (iOS)', style: TextStyle(fontFamily: 'Poppins', color: _primaryText)),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  }
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: _softLightGray,
                  side: BorderSide(color: _borderSubtleLight),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: Icon(Icons.phone_iphone_rounded, size: 15, color: _limeAccent),
                label: const Text('Simulate iOS', style: TextStyle(fontFamily: 'Poppins', fontSize: 11)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceItem(DeviceModel device, TransferEngine engine) {
    final platformName = device.platform ?? (device.deviceType == DeviceType.desktop ? 'Desktop' : 'Mobile');
    final platformIcon = _getPlatformIcon(device.platform, device.deviceType);
    final isOnline = device.isOnline;

    return HoverCard(
      borderRadius: BorderRadius.circular(14),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      liftOffset: 1.5,
      scale: 1.008,
      color: _cardSurface,
      hoverColor: AppColors.surfaceElevated,
      borderColor: _borderSubtleLight,
      hoverBorderColor: _limeAccent.withValues(alpha: 0.6),
      child: Row(
        children: [
          // Platform Avatar Icon
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _panelCharcoal,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _borderSubtle),
            ),
            child: Icon(platformIcon, color: _limeAccent, size: 20),
          ),
          const SizedBox(width: 14),

          // Device Info: Name, Platform Badge & IP
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        device.name,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: _primaryText,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Platform badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: _panelCharcoal,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: _borderSubtle),
                      ),
                      child: Text(
                        platformName,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: _softLightGray,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: isOnline ? _limeAccent : _softLightGray,
                        shape: BoxShape.circle,
                      ),
                    ),
                    if (device.method != TransferMethod.lan || device.verificationCode != null) ...[
                      MethodBadge(device.method, compact: true, relayed: ConnectionManager.instance.links[device.id]?.relayed ?? false),
                      if (device.verificationCode != null) VerificationCodeChip(device.verificationCode!),
                    ],
                    Text(
                      isOnline ? 'Online • Connected' : 'Offline',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: isOnline ? _limeAccent : _softLightGray,
                      ),
                    ),
                    if ((ConnectionManager.instance.links[device.id]?.bytesPerSecond ?? 0) > 0)
                      Text(
                        '•  ${FormatUtils.formatSpeed(ConnectionManager.instance.links[device.id]!.bytesPerSecond)}',
                        style: TextStyle(fontFamily: 'Poppins', fontSize: 11, fontWeight: FontWeight.w600, color: _limeAccent),
                      ),
                    if (device.method == TransferMethod.lan) Text(
                      '•  ${device.ip}:${device.port}',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 11,
                        color: _softLightGray,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),

          // Disconnect Action
          OutlinedButton.icon(
            onPressed: () {
              engine.disconnectDevice(device.id);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: _panelCharcoal,
                  content: Text(
                    'Disconnected ${device.name}.',
                    style: TextStyle(fontFamily: 'Poppins', color: _primaryText),
                  ),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: _errorCoral,
              side: BorderSide(color: _errorCoral.withValues(alpha: 0.4)),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.link_off_rounded, size: 15),
            label: const Text(
              'Disconnect',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 11.5, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
