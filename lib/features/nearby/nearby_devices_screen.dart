import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/constants.dart';
import '../../core/design/tokens.dart';
import '../../transfer/bluetooth/bluetooth_support.dart';
import '../../data/services/transfer_engine.dart';
import '../../transfer/bluetooth/bluetooth_transport.dart';
import '../../transfer/transfer_method.dart';
import '../connect/widgets/transfer_widgets.dart';

/// Everything the screen needs from the platform, so the permission flow can be tested.
abstract class NearbyEnvironment {
  bool get platformSupported;
  String? get unsupportedReason;
  Future<BluetoothCapabilities> capabilities();
  Future<PermissionState> status(PermissionStep step);
  Future<PermissionState> request(PermissionStep step);
  Future<bool> openSettings();
  Future<bool> requestEnable();
  Future<bool> locationServiceOff(int sdk);
  BluetoothTransport? get transport;
}

class PlatformNearbyEnvironment implements NearbyEnvironment {
  const PlatformNearbyEnvironment();
  @override
  bool get platformSupported => BluetoothSupport.platformSupported;
  @override
  String? get unsupportedReason => BluetoothSupport.unsupportedReason;
  @override
  Future<BluetoothCapabilities> capabilities() => BluetoothSupport.capabilities();
  @override
  Future<PermissionState> status(PermissionStep step) => BluetoothPermissions.status(step);
  @override
  Future<PermissionState> request(PermissionStep step) => BluetoothPermissions.request(step);
  @override
  Future<bool> openSettings() => openAppSettings();
  @override
  Future<bool> requestEnable() => BluetoothSupport.requestEnable();
  @override
  Future<bool> locationServiceOff(int sdk) => BluetoothPermissions.locationServiceNeededAndOff(sdk);
  @override
  BluetoothTransport? get transport => BluetoothTransport.instance;
}

enum _Gate { checking, unsupported, rationale, denied, permanentlyDenied, bluetoothOff, locationOff, ready }

/// "Nearby devices": offline transfers over Bluetooth (handshake) + Wi-Fi Direct (data).
class NearbyDevicesScreen extends StatefulWidget {
  const NearbyDevicesScreen({super.key, this.environment = const PlatformNearbyEnvironment()});
  final NearbyEnvironment environment;

  @override
  State<NearbyDevicesScreen> createState() => _NearbyDevicesScreenState();
}

class _NearbyDevicesScreenState extends State<NearbyDevicesScreen> with WidgetsBindingObserver {
  _Gate _gate = _Gate.checking;
  String? _reason;
  BluetoothCapabilities? _caps;
  List<PermissionStep> _steps = const [];
  PermissionStep? _step;
  String? _error;
  String? _connectingTo;
  bool _requesting = false;

  /// Steps whose system prompt was already shown on this visit: a "denied" answer then
  /// means "explain and offer Try again", not "show the rationale again".
  final Set<String> _asked = {};

  /// Denials per step on this visit. Android 11+ stops showing the dialog after the second
  /// one, while permission_handler may still report a plain "denied" for some permission
  /// groups (seen with the Bluetooth trio on Android 14), so the second denial is treated
  /// as "don't ask again".
  final Map<String, int> _denials = {};

  NearbyEnvironment get env => widget.environment;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    env.transport?.addListener(_onTransport);
    _evaluate();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    env.transport?.removeListener(_onTransport);
    // Scanning and advertising stop when the screen closes.
    env.transport?.shutdown();
    super.dispose();
  }

  void _onTransport() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from Settings / the Bluetooth prompt: check again.
    // The system permission dialog itself pauses/resumes the activity; don't race it.
    if (state == AppLifecycleState.resumed && _gate != _Gate.ready && !_requesting) _evaluate();
  }

  Future<void> _evaluate() async {
    if (!env.platformSupported) {
      setState(() {
        _gate = _Gate.unsupported;
        _reason = env.unsupportedReason;
      });
      return;
    }
    try {
      _caps ??= await env.capabilities();
    } catch (_) {
      setState(() {
        _gate = _Gate.unsupported;
        _reason = "Couldn't read this phone's Bluetooth capabilities.";
      });
      return;
    }
    final caps = _caps!;
    if (!caps.supported) {
      setState(() {
        _gate = _Gate.unsupported;
        _reason = caps.unsupportedReason;
      });
      return;
    }
    _steps = BluetoothPermissions.stepsFor(caps.sdk);
    for (final step in _steps) {
      final s = await env.status(step);
      if (s == PermissionState.granted || (step.optional && s == PermissionState.permanentlyDenied)) continue;
      if (!mounted) return;
      setState(() {
        _step = step;
        _gate = _gateFor(step, s);
      });
      return;
    }
    final fresh = await env.capabilities();
    _caps = fresh;
    if (!fresh.enabled) {
      setState(() => _gate = _Gate.bluetoothOff);
      return;
    }
    if (await env.locationServiceOff(fresh.sdk)) {
      setState(() => _gate = _Gate.locationOff);
      return;
    }
    if (!mounted) return;
    setState(() => _gate = _Gate.ready);
    await _startScanning();
  }

  Future<void> _startScanning() async {
    try {
      await env.transport?.startScan();
      setState(() => _error = null);
    } on BluetoothException catch (e) {
      setState(() => _error = e.message);
    }
  }

  /// One verdict for a not-granted step, whether it comes from a request or from the
  /// re-check when the app resumes (Android's permission activity pauses/resumes the app
  /// after the request returns, so both paths must agree).
  _Gate _gateFor(PermissionStep step, PermissionState state) {
    if (state == PermissionState.permanentlyDenied || (_denials[step.id] ?? 0) >= 2) return _Gate.permanentlyDenied;
    return _asked.contains(step.id) ? _Gate.denied : _Gate.rationale;
  }

  Future<void> _requestStep() async {
    final step = _step;
    if (step == null || _requesting) return;
    setState(() => _requesting = true);
    _asked.add(step.id);
    final result = await env.request(step);
    if (!mounted) return;
    setState(() => _requesting = false);
    if (result == PermissionState.granted || step.optional) {
      _step = null;
      await _evaluate();
    } else {
      _denials[step.id] = (_denials[step.id] ?? 0) + 1;
      setState(() => _gate = _gateFor(step, result));
    }
  }

  Future<void> _enableBluetooth() async {
    final on = await env.requestEnable();
    if (!mounted) return;
    if (on) {
      _caps = null;
      await _evaluate();
    } else {
      setState(() => _error = 'Bluetooth is still off.');
    }
  }

  Future<void> _connect(NearbyDevice device) async {
    final transport = env.transport;
    if (transport == null) return;
    HapticFeedback.selectionClick();
    setState(() {
      _connectingTo = device.address;
      _error = null;
    });
    try {
      final link = await transport.connect(device);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Connected to ${link.device.name} over Bluetooth. Verification code ${link.verificationCode}.'),
      ));
      Navigator.of(context).maybePop();
    } on BluetoothException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
      await _startScanning();
    } finally {
      if (mounted) setState(() => _connectingTo = null);
    }
  }

  Future<void> _toggleVisible(bool on) async {
    final transport = env.transport;
    if (transport == null) return;
    try {
      if (on) {
        await transport.becomeVisible();
      } else {
        await transport.stopVisible();
      }
      setState(() => _error = null);
    } on BluetoothException catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.dashboardBg,
      appBar: AppBar(title: const Text('Nearby devices (Bluetooth)')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(padding: const EdgeInsets.all(Space.l), children: [
              _intro(),
              const SizedBox(height: Space.l),
              _gateCard(),
              if (_error != null) ...[const SizedBox(height: Space.m), _errorBanner(_error!)],
            ]),
          ),
        ),
      ),
    );
  }

  Widget _intro() => Text(
        'No Wi-Fi or internet? Two Android phones can still share files: Bluetooth finds the other phone and '
        'exchanges an encryption key, then the files travel over a direct Wi-Fi link (Wi-Fi Direct) for speed.',
        style: TextStyles.caption,
      );

  Widget _gateCard() {
    switch (_gate) {
      case _Gate.checking:
        return const Center(child: Padding(padding: EdgeInsets.all(Space.xl), child: CircularProgressIndicator()));
      case _Gate.unsupported:
        return _card(
          icon: Icons.bluetooth_disabled_rounded,
          title: "Bluetooth transfers aren't available here",
          body: _reason ?? '',
        );
      case _Gate.rationale:
        return _card(
          icon: Icons.privacy_tip_outlined,
          title: _step!.title,
          body: _step!.rationale,
          primary: (_requesting ? 'Waiting...' : 'Continue', _requesting ? null : _requestStep),
        );
      case _Gate.denied:
        return _card(
          icon: Icons.block_rounded,
          title: 'Permission needed',
          body: '${_step!.rationale}\n\nWithout it, QuickShare can’t use Bluetooth transfers. You can still use the same Wi-Fi or the internet.',
          primary: ('Try again', _requestStep),
          secondary: ('Open app settings', () => env.openSettings()),
        );
      case _Gate.permanentlyDenied:
        return _card(
          icon: Icons.settings_rounded,
          title: 'Turn on the permission in Settings',
          body: '${_step!.rationale}\n\nAndroid won’t ask again, so open Settings → Permissions and allow it, then come back.',
          primary: ('Open app settings', () => env.openSettings()),
        );
      case _Gate.bluetoothOff:
        return _card(
          icon: Icons.bluetooth_disabled_rounded,
          title: 'Bluetooth is off',
          body: 'Turn on Bluetooth to find nearby QuickShare devices.',
          primary: ('Turn on Bluetooth', _enableBluetooth),
        );
      case _Gate.locationOff:
        return _card(
          icon: Icons.location_off_outlined,
          title: 'Turn on Location',
          body: 'On this Android version, Bluetooth scanning only works with Location switched on (quick settings). '
              'QuickShare does not use your location.',
          primary: ('I turned it on', _evaluate),
        );
      case _Gate.ready:
        return _ready();
    }
  }

  Widget _ready() {
    final transport = env.transport;
    if (transport == null) {
      return _card(icon: Icons.bluetooth_connected_rounded, title: 'Bluetooth is ready', body: 'All permissions are granted.');
    }
    final devices = transport.devices;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.all(Space.l),
        decoration: cardDecoration(),
        child: Row(children: [
          Icon(Icons.wifi_tethering_rounded, color: AppColors.limeGreen),
          const SizedBox(width: Space.m),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Receive: make this phone visible', style: TextStyles.label),
              const SizedBox(height: 2),
              Text(
                transport.visible
                    ? 'Nearby phones can see "${TransferEngine().localDeviceName}" and connect. You still accept each transfer.'
                    : (_caps?.advertise ?? true)
                        ? 'Turn on so a nearby phone can connect to this one.'
                        : "This phone can't advertise over Bluetooth, but it can still connect to others.",
                style: TextStyles.caption,
              ),
            ]),
          ),
          Semantics(
            label: 'Make this phone visible over Bluetooth',
            child: Switch(
              value: transport.visible,
              onChanged: (_caps?.advertise ?? true) ? _toggleVisible : null,
            ),
          ),
        ]),
      ),
      if (transport.stage != BluetoothStage.idle && transport.stage != BluetoothStage.failed) ...[
        const SizedBox(height: Space.m),
        _stageBanner(transport),
      ],
      const SizedBox(height: Space.l),
      Row(children: [
        Text('Send: nearby devices', style: TextStyles.title),
        const SizedBox(width: Space.s),
        if (transport.scanning)
          SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.limeGreen)),
        const Spacer(),
        TextButton(
          onPressed: () async {
            await transport.stopScan();
            await _startScanning();
          },
          style: TextButton.styleFrom(minimumSize: const Size(minTapTarget, minTapTarget)),
          child: const Text('Rescan'),
        ),
      ]),
      const SizedBox(height: Space.s),
      if (devices.isEmpty)
        Container(
          padding: const EdgeInsets.all(Space.xl),
          decoration: cardDecoration(),
          child: Column(children: [
            Icon(Icons.bluetooth_searching_rounded, size: 36, color: AppColors.mutedText),
            const SizedBox(height: Space.m),
            Text('Looking for nearby phones...', style: TextStyles.label),
            const SizedBox(height: Space.xs),
            Text('On the other phone, open Nearby devices and turn on "make this phone visible".',
                style: TextStyles.caption, textAlign: TextAlign.center),
          ]),
        )
      else
        for (final d in devices)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.s),
            child: _deviceTile(d),
          ),
    ]);
  }

  String? _stageText(BluetoothTransport t) => switch (t.stage) {
        BluetoothStage.connecting => 'Connecting over Bluetooth...',
        BluetoothStage.exchangingKeys => 'Exchanging encryption keys...',
        BluetoothStage.startingWifi => 'Starting Wi-Fi Direct...',
        BluetoothStage.joiningWifi => 'Joining Wi-Fi Direct...',
        BluetoothStage.securing => 'Securing the connection...',
        BluetoothStage.connected => 'Connected',
        _ => null,
      };

  Widget _stageBanner(BluetoothTransport t) => Semantics(
        liveRegion: true,
        child: Container(
          padding: const EdgeInsets.all(Space.m),
          decoration: BoxDecoration(color: AppColors.surfaceElevated, borderRadius: BorderRadius.circular(Radii.control)),
          child: Row(children: [
            if (t.stage == BluetoothStage.connected)
              Icon(Icons.check_circle_rounded, color: AppColors.success, size: 18)
            else
              SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.limeGreen)),
            const SizedBox(width: Space.m),
            Expanded(child: Text(_stageText(t) ?? '', style: TextStyles.label)),
          ]),
        ),
      );

  Widget _deviceTile(NearbyDevice d) {
    final busy = _connectingTo == d.address;
    return Semantics(
      label: '${d.name}, signal ${d.bars} of 4',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.m),
        decoration: cardDecoration(),
        child: Row(children: [
          _SignalBars(d.bars),
          const SizedBox(width: Space.m),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(d.name, style: TextStyles.label, maxLines: 1, overflow: TextOverflow.ellipsis),
              Text('${d.rssi} dBm', style: TextStyles.caption),
            ]),
          ),
          const MethodBadge(TransferMethod.bluetooth, compact: true),
          const SizedBox(width: Space.s),
          ElevatedButton(
            onPressed: _connectingTo == null ? () => _connect(d) : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.limeGreen,
              foregroundColor: AppColors.nearBlack,
              minimumSize: const Size(88, minTapTarget),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.control)),
            ),
            child: busy
                ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.nearBlack))
                : const Text('Connect', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
          ),
        ]),
      ),
    );
  }

  Widget _card({
    required IconData icon,
    required String title,
    required String body,
    (String, VoidCallback?)? primary,
    (String, VoidCallback?)? secondary,
  }) {
    return Container(
      padding: const EdgeInsets.all(Space.xl),
      decoration: cardDecoration(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 32, color: AppColors.limeGreen),
        const SizedBox(height: Space.m),
        Text(title, style: TextStyles.title),
        const SizedBox(height: Space.s),
        Text(body, style: TextStyles.body),
        if (primary != null) ...[
          const SizedBox(height: Space.xl),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: primary.$2,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.limeGreen,
                foregroundColor: AppColors.nearBlack,
                minimumSize: const Size.fromHeight(minTapTarget),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.control)),
              ),
              child: Text(primary.$1, style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
            ),
          ),
        ],
        if (secondary != null) ...[
          const SizedBox(height: Space.s),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: secondary.$2,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primaryText,
                minimumSize: const Size.fromHeight(minTapTarget),
              ),
              child: Text(secondary.$1, style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ]),
    );
  }

  Widget _errorBanner(String message) => Semantics(
        liveRegion: true,
        child: Container(
          padding: const EdgeInsets.all(Space.m),
          decoration: BoxDecoration(
            color: AppColors.errorContainer,
            borderRadius: BorderRadius.circular(Radii.control),
          ),
          child: Row(children: [
            Icon(Icons.error_outline_rounded, color: AppColors.error, size: 18),
            const SizedBox(width: Space.s),
            Expanded(child: Text(message, style: TextStyles.body.copyWith(color: AppColors.error))),
          ]),
        ),
      );
}

class _SignalBars extends StatelessWidget {
  const _SignalBars(this.bars);
  final int bars;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 22,
      height: 18,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (var i = 0; i < 4; i++)
          Container(
            width: 4,
            height: 5.0 + i * 4,
            margin: const EdgeInsets.only(right: 1.5),
            decoration: BoxDecoration(
              color: i < bars ? AppColors.limeGreen : AppColors.subtleBorderLight,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
      ]),
    );
  }
}
