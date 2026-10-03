import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:quickshare/main.dart';
import 'package:quickshare/data/services/transfer_engine.dart';
import 'package:quickshare/features/pdf_layout/models/layout_preset.dart';
import 'package:quickshare/features/pdf_layout/models/page_geometry.dart';
import 'package:quickshare/features/pdf_layout/engine/layout_calculator.dart';
import 'package:quickshare/core/utils/hash_utils.dart';
import 'package:quickshare/data/models/pairing_session.dart';
import 'dart:typed_data';

void main() {
  group('1. PDF Layout Preset Calculations Test', () {
    test('Verifies all 7 exact presets calculate valid grid dimensions', () {
      const geometry = PageGeometry();

      // Preset 1: 1 Image
      final p1 = LayoutPreset.getGridDimensions(LayoutPresetType.one, geometry.isLandscape);
      expect(p1.rows * p1.cols, 1);

      // Preset 2: 2 Images
      final p2 = LayoutPreset.getGridDimensions(LayoutPresetType.two, geometry.isLandscape);
      expect(p2.rows * p2.cols, 2);

      // Preset 3: 3 Images
      final p3 = LayoutPreset.getGridDimensions(LayoutPresetType.three, geometry.isLandscape);
      expect(p3.rows * p3.cols, 3);

      // Preset 4: 4 Images (2x2)
      final p4 = LayoutPreset.getGridDimensions(LayoutPresetType.four, geometry.isLandscape);
      expect(p4.rows * p4.cols, 4);

      // Preset 6: 6 Images (3x2 portrait)
      final p6 = LayoutPreset.getGridDimensions(LayoutPresetType.six, geometry.isLandscape);
      expect(p6.rows * p6.cols, 6);

      // Preset 8: 8 Images (4x2 portrait)
      final p8 = LayoutPreset.getGridDimensions(LayoutPresetType.eight, geometry.isLandscape);
      expect(p8.rows * p8.cols, 8);

      // Preset 10: 10 Images (5x2 portrait)
      final p10 = LayoutPreset.getGridDimensions(LayoutPresetType.ten, geometry.isLandscape);
      expect(p10.rows * p10.cols, 10);
    });

    test('LayoutCalculator produces correct cell rects and bounds', () {
      const geometry = PageGeometry(marginPoints: 24.0);
      final cells = LayoutCalculator.calculatePageLayout(
        geometry: geometry,
        presetType: LayoutPresetType.four,
        spacingPoints: 8.0,
      );

      expect(cells.length, 4);
      for (final c in cells) {
        expect(c.cellRect.left >= geometry.marginPoints, isTrue);
        expect(c.cellRect.top >= geometry.marginPoints, isTrue);
        expect(c.imageRect.width > 0, isTrue);
        expect(c.imageRect.height > 0, isTrue);
      }
    });
  });

  group('2. Cryptographic Integrity & Pairing Session Tests', () {
    test('SHA-256 hashing produces deterministic cryptographic fingerprints', () {
      final bytesA = Uint8List.fromList([1, 2, 3, 4, 5]);
      final bytesB = Uint8List.fromList([1, 2, 3, 4, 5]);
      final bytesC = Uint8List.fromList([1, 2, 3, 4, 6]);

      final hashA = HashUtils.computeSha256(bytesA);
      final hashB = HashUtils.computeSha256(bytesB);
      final hashC = HashUtils.computeSha256(bytesC);

      expect(hashA, hashB);
      expect(hashA != hashC, isTrue);
      expect(HashUtils.shortFingerprint(hashA).length, 8);
    });

    test('PairingSession generates valid 6-digit expiring code and QR payload', () {
      final session = PairingSession.create(
        hostDeviceName: 'LabPC',
        hostIp: '10.150.2.94',
        hostPort: 8088,
        durationMinutes: 5,
      );

      expect(session.numericCode.length, 6);
      expect(session.isExpired, isFalse);
      expect(session.qrPayload.contains('quickshare://pair'), isTrue);
      expect(session.qrPayload.contains('code='), isTrue);
    });
  });

  group('3. Main Application Widget Smoke Test', () {
    testWidgets('QuickShareApp launches with Dashboard and navigation items', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final engine = TransferEngine();

      await tester.pumpWidget(
        ChangeNotifierProvider<TransferEngine>.value(
          value: engine,
          child: const QuickShareApp(),
        ),
      );
      await tester.pump();

      expect(find.text('QuickShare Studio'), findsWidgets);
      expect(find.text('Create PDF'), findsWidgets);
      expect(find.text('Connect Device'), findsWidgets);

      // Clean up timers and widget tree before test completion
      engine.stopTimers();
      await tester.pumpWidget(const SizedBox());
    });
  });
}
