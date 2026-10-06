import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickshare/features/connect/widgets/connect_status_panel.dart';
import 'package:quickshare/features/nearby/nearby_devices_screen.dart';
import 'package:quickshare/transfer/bluetooth/ble_handshake.dart';
import 'package:quickshare/transfer/bluetooth/bluetooth_support.dart';
import 'package:quickshare/transfer/bluetooth/bluetooth_transport.dart';
import 'package:quickshare/transfer/connect_flow.dart';

/// Fake platform for the Nearby screen: no Bluetooth hardware is needed to test the flows.
class FakeNearby implements NearbyEnvironment {
  FakeNearby({
    this.supported = true,
    this.caps,
    Map<String, PermissionState>? statuses,
    this.answers = const {},
  }) : statuses = statuses ?? {};

  final bool supported;
  BluetoothCapabilities? caps;
  final Map<String, PermissionState> statuses;

  /// What the system dialog answers for each step.
  final Map<String, List<PermissionState>> answers;
  final List<String> requested = [];
  int settingsOpened = 0;
  int enablePrompts = 0;
  bool enableResult = true;

  @override
  bool get platformSupported => supported;
  @override
  String? get unsupportedReason => 'Bluetooth transfers need the Android app.';
  @override
  Future<BluetoothCapabilities> capabilities() async => caps!;
  @override
  Future<PermissionState> status(PermissionStep step) async =>
      statuses[step.id] ?? PermissionState.denied;
  @override
  Future<PermissionState> request(PermissionStep step) async {
    requested.add(step.id);
    final queue = answers[step.id] ?? [PermissionState.granted];
    final answer = queue.isEmpty ? PermissionState.granted : queue.removeAt(0);
    statuses[step.id] = answer;
    return answer;
  }

  @override
  Future<bool> openSettings() async {
    settingsOpened++;
    return true;
  }

  @override
  Future<bool> requestEnable() async {
    enablePrompts++;
    if (enableResult) {
      caps = BluetoothCapabilities(
        sdk: caps!.sdk,
        ble: true,
        wifiDirect: true,
        advertise: true,
        enabled: true,
      );
    }
    return enableResult;
  }

  @override
  Future<bool> locationServiceOff(int sdk) async => false;

  @override
  BluetoothTransport? get transport => null;
}

BluetoothCapabilities _caps({
  int sdk = 34,
  bool enabled = true,
  bool wifiDirect = true,
}) => BluetoothCapabilities(
  sdk: sdk,
  ble: true,
  wifiDirect: wifiDirect,
  advertise: true,
  enabled: enabled,
);

Widget _app(Widget child) => MaterialApp(home: child);

void main() {
  group('BLE handshake logic', () {
    test('messages survive chunking at the minimum and a large MTU', () {
      final message = utf8.encode(
        jsonEncode({
          't': 'hello',
          'pub': 'x' * 44,
          'name': 'Pixel 9 Pro of Abhijeet',
          'id': 'dev_123456',
        }),
      );
      for (final mtu in [23, 64, 247, 517]) {
        final pieces = chunkMessage(message, mtu);
        expect(
          pieces.every((p) => p.length <= mtu - 3),
          isTrue,
          reason: 'mtu $mtu',
        );
        final assembler = MessageAssembler();
        List<int>? out;
        for (final p in pieces) {
          out = assembler.add(p) ?? out;
        }
        expect(out, message);
      }
    });

    test(
      'both phones derive the same key; Wi-Fi credentials only open with it',
      () async {
        final sender = await BleKeyAgreement.create();
        final receiver = await BleKeyAgreement.create();
        final k1 = await sender.derive(
          peerPublicKey: receiver.publicKey,
          senderPub: sender.publicKey,
          receiverPub: receiver.publicKey,
        );
        final k2 = await receiver.derive(
          peerPublicKey: sender.publicKey,
          senderPub: sender.publicKey,
          receiverPub: receiver.publicKey,
        );
        expect(k1, k2);
        expect(k1.length, 32);

        const creds = WifiCredentials(
          ssid: 'DIRECT-qs-ab12cd',
          passphrase: 'pA55phrase123456',
          ip: '192.168.49.1',
          port: 40123,
        );
        final sealed = await creds.seal(k1);
        expect(sealed.contains('pA55phrase'), isFalse);
        final opened = await WifiCredentials.open(sealed, k2);
        expect(opened.ssid, creds.ssid);
        expect(opened.passphrase, creds.passphrase);
        expect(opened.port, 40123);

        final eavesdropper = await BleKeyAgreement.create();
        final wrong = await eavesdropper.derive(
          peerPublicKey: receiver.publicKey,
          senderPub: sender.publicKey,
          receiverPub: receiver.publicKey,
        );
        await expectLater(
          WifiCredentials.open(sealed, wrong),
          throwsA(anything),
        );
      },
    );

    test('oversized handshake messages are rejected', () {
      final assembler = MessageAssembler();
      expect(() {
        for (var i = 0; i < 100; i++) {
          assembler.add([0, ...List.filled(100, 1)]);
        }
      }, throwsFormatException);
    });
  });

  group('Permissions per Android version', () {
    test(
      'Android 13+: Bluetooth trio + nearby Wi-Fi + optional notifications',
      () {
        final steps = BluetoothPermissions.stepsFor(34);
        expect(steps.map((s) => s.id), ['bluetooth', 'wifi', 'notifications']);
        expect(steps.last.optional, isTrue);
      },
    );

    test('Android 12/12L: Bluetooth trio + location (for Wi-Fi Direct)', () {
      expect(BluetoothPermissions.stepsFor(31).map((s) => s.id), [
        'bluetooth',
        'location',
      ]);
      expect(BluetoothPermissions.stepsFor(32).map((s) => s.id), [
        'bluetooth',
        'location',
      ]);
    });

    test(
      'Android 10/11: location only (Bluetooth permissions are install-time)',
      () {
        expect(BluetoothPermissions.stepsFor(29).map((s) => s.id), [
          'location',
        ]);
        expect(BluetoothPermissions.stepsFor(30).map((s) => s.id), [
          'location',
        ]);
      },
    );

    test('Android 9 and older are not supported (no configurable Wi-Fi Direct groups)', () {
      expect(_caps(sdk: 28).supported, isFalse);
      expect(_caps(sdk: 28).unsupportedReason, contains('Android 10'));
      expect(_caps(wifiDirect: false).supported, isFalse);
    });
  });

  group('Nearby screen flows', () {
    testWidgets('web / iOS: Bluetooth is disabled with a clear explanation', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(NearbyDevicesScreen(environment: FakeNearby(supported: false))),
      );
      await tester.pumpAndSettle();
      expect(
        find.text("Bluetooth transfers aren't available here"),
        findsOneWidget,
      );
      expect(
        find.text('Bluetooth transfers need the Android app.'),
        findsOneWidget,
      );
    });

    testWidgets('rationale before each system prompt, then granted', (
      tester,
    ) async {
      final env = FakeNearby(
        caps: _caps(),
        statuses: {'notifications': PermissionState.granted},
      );
      await tester.pumpWidget(_app(NearbyDevicesScreen(environment: env)));
      await tester.pumpAndSettle();
      expect(find.text('Allow nearby Bluetooth devices'), findsOneWidget);
      expect(
        env.requested,
        isEmpty,
        reason: 'the rationale comes before the system dialog',
      );
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.text('Allow nearby Wi-Fi devices'), findsOneWidget);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(env.requested, ['bluetooth', 'wifi']);
      expect(find.text('Bluetooth is ready'), findsOneWidget);
      expect(find.text('Permission needed'), findsNothing);
    });

    testWidgets('denied -> explanation + Try again', (tester) async {
      final env = FakeNearby(
        caps: _caps(),
        answers: {
          'bluetooth': [PermissionState.denied, PermissionState.granted],
        },
      );
      await tester.pumpWidget(_app(NearbyDevicesScreen(environment: env)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.text('Permission needed'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(env.requested, ['bluetooth', 'bluetooth']);
      expect(find.text('Allow nearby Wi-Fi devices'), findsOneWidget);
    });

    testWidgets(
      'denied stays denied when the app resumes after the system dialog',
      (tester) async {
        final env = FakeNearby(
          caps: _caps(),
          answers: {
            'bluetooth': [PermissionState.denied],
          },
        );
        await tester.pumpWidget(_app(NearbyDevicesScreen(environment: env)));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();
        // Closing the system dialog resumes the activity (found on a real Android 14 device).
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        expect(find.text('Permission needed'), findsOneWidget);
        expect(find.text('Try again'), findsOneWidget);
      },
    );

    testWidgets(
      'a second denial leads to Settings (Android stops asking after two)',
      (tester) async {
        final env = FakeNearby(
          caps: _caps(),
          answers: {
            'bluetooth': [PermissionState.denied, PermissionState.denied],
          },
        );
        await tester.pumpWidget(_app(NearbyDevicesScreen(environment: env)));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();
        expect(
          find.text('Open app settings'),
          findsOneWidget,
          reason: 'never a dead end',
        );
        await tester.tap(find.text('Try again'));
        await tester.pumpAndSettle();
        expect(find.text('Turn on the permission in Settings'), findsOneWidget);
        // Android's (invisible) permission activity resumes the app afterwards: the verdict holds.
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        expect(find.text('Turn on the permission in Settings'), findsOneWidget);
      },
    );

    testWidgets('"never ask again" -> Open app settings', (tester) async {
      final env = FakeNearby(
        caps: _caps(),
        answers: {
          'bluetooth': [PermissionState.permanentlyDenied],
        },
      );
      await tester.pumpWidget(_app(NearbyDevicesScreen(environment: env)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.text('Turn on the permission in Settings'), findsOneWidget);
      await tester.tap(find.text('Open app settings'));
      await tester.pumpAndSettle();
      expect(env.settingsOpened, 1);
    });

    testWidgets(
      'already permanently denied: goes straight to the Settings card',
      (tester) async {
        final env = FakeNearby(
          caps: _caps(sdk: 30),
          statuses: {'location': PermissionState.permanentlyDenied},
        );
        await tester.pumpWidget(_app(NearbyDevicesScreen(environment: env)));
        await tester.pumpAndSettle();
        expect(find.text('Turn on the permission in Settings'), findsOneWidget);
        expect(env.requested, isEmpty);
      },
    );

    testWidgets('Bluetooth off -> prompt to turn it on', (tester) async {
      final env = FakeNearby(
        caps: _caps(enabled: false),
        statuses: {
          'bluetooth': PermissionState.granted,
          'wifi': PermissionState.granted,
          'notifications': PermissionState.granted,
        },
      );
      await tester.pumpWidget(_app(NearbyDevicesScreen(environment: env)));
      await tester.pumpAndSettle();
      expect(find.text('Bluetooth is off'), findsOneWidget);
      await tester.tap(find.text('Turn on Bluetooth'));
      await tester.pumpAndSettle();
      expect(env.enablePrompts, 1);
      expect(find.text('Bluetooth is off'), findsNothing);
      expect(find.text('Bluetooth is ready'), findsOneWidget);
    });

    testWidgets('Android 9: unsupported with the reason', (tester) async {
      await tester.pumpWidget(
        _app(
          NearbyDevicesScreen(environment: FakeNearby(caps: _caps(sdk: 28))),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Android 10 or newer'), findsOneWidget);
    });
  });

  group('Connect status panel', () {
    Future<List<String>> pump(
      WidgetTester tester,
      ConnectFlowState state,
    ) async {
      final taps = <String>[];
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: ConnectStatusPanel(
              state: state,
              onRetry: () => taps.add('retry'),
            ),
          ),
        ),
      );
      if (state.isBusy) {
        await tester.pump(const Duration(milliseconds: 300));
      } else {
        await tester.pumpAndSettle();
      }
      return taps;
    }

    testWidgets('connecting shows only the automatic connection status', (
      tester,
    ) async {
      await pump(
        tester,
        const ConnectFlowState(phase: ConnectPhase.connecting),
      );
      expect(find.text('Connecting...'), findsOneWidget);
      expect(find.text('Cancel'), findsNothing);
      expect(find.text('Try over internet'), findsNothing);
      expect(find.text('Use Bluetooth'), findsNothing);
    });

    testWidgets('failure shows one concise error and a single Retry button', (
      tester,
    ) async {
      final taps = await pump(
        tester,
        const ConnectFlowState(
          phase: ConnectPhase.failed,
          failure: ConnectFailure.noRoute,
        ),
      );
      expect(find.text(ConnectFlowState.lanNotFoundMessage), findsOneWidget);
      expect(find.text('Try over internet'), findsNothing);
      expect(find.text('Use Bluetooth'), findsNothing);
      expect(find.text('Retry'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      expect(taps, ['retry']);
    });

    testWidgets('manual transport choices never appear on ConnectStatusPanel', (
      tester,
    ) async {
      await pump(tester, const ConnectFlowState(phase: ConnectPhase.failed));
      expect(find.text('Use Bluetooth'), findsNothing);
      expect(find.text('Try over internet'), findsNothing);
    });
  });
}
