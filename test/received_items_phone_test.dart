import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:quickshare/data/models/received_item_model.dart';
import 'package:quickshare/data/services/transfer_engine.dart';
import 'package:quickshare/features/received_items/received_items_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Received Files on a phone (Android is the default test platform).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const downloads = MethodChannel('quickshare/downloads');
  const system = MethodChannel('quickshare/system');
  const fileName = 'Lab_Workstation_930_Network_Report.pdf';
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late TransferEngine engine;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    engine = TransferEngine()..stopTimers();
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(downloads, null);
    messenger.setMockMethodCallHandler(system, null);
  });

  ReceivedItemModel pdf({String path = 'content://media/external/downloads/42'}) => ReceivedItemModel(
        id: 'rx_pdf',
        fileName: fileName,
        fileSizeBytes: 318157,
        senderDeviceName: 'Lab_Workstation_930 (Windows)',
        savedToPath: path,
        fileType: ReceivedFileType.pdf,
        bytes: Uint8List.fromList([1, 2, 3]),
      );

  /// A 360 x 800 dp screen, like the phone in the bug report.
  Future<void> pumpPhone(WidgetTester tester, ReceivedItemModel item) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    engine.receivedItems
      ..clear()
      ..add(item);
    await tester.pumpWidget(
      ChangeNotifierProvider<TransferEngine>.value(
        value: engine,
        child: const MaterialApp(home: ReceivedItemsView()),
      ),
    );
    await tester.pump();
  }

  /// Answers like DownloadsBridge.kt; [keep] is its reply for a received file.
  List<String> mockDownloads(Map<String, Object?>? keep) {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(system, (call) async => call.method == 'sdkInt' ? 34 : null);
    messenger.setMockMethodCallHandler(downloads, (call) async {
      calls.add(call.method);
      return call.method == 'keep' ? keep : null;
    });
    return calls;
  }

  testWidgets('gives the file details the full card width, with actions underneath', (tester) async {
    await pumpPhone(tester, pdf());

    final name = find.text(fileName);
    expect(name, findsOneWidget);
    // The bug: the action buttons squeezed the details into a ~20 px column, one letter per line.
    expect(tester.getSize(name).width, greaterThan(150));

    final open = find.widgetWithText(OutlinedButton, 'Open');
    final download = find.widgetWithText(ElevatedButton, 'Download');
    expect(open, findsOneWidget);
    expect(download, findsOneWidget);
    expect(tester.getTopLeft(download).dy, greaterThan(tester.getBottomLeft(name).dy));
    expect(tester.getTopLeft(open).dy, tester.getTopLeft(download).dy);
    expect(tester.getSize(download).width, greaterThan(100));

    expect(find.text('Received Files'), findsOneWidget);
    // Android always receives into Downloads/QuickShare, so there is no path to change.
    expect(find.text('Target Destination: Downloads/QuickShare'), findsOneWidget);
    expect(find.text('Change Path'), findsNothing);
    expect(find.text('Pause Receiving'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Download confirms a file that is already in Downloads', (tester) async {
    final calls = mockDownloads({'path': 'content://media/external/downloads/42', 'name': fileName, 'copied': false});
    await pumpPhone(tester, pdf());

    await tester.tap(find.widgetWithText(ElevatedButton, 'Download'));
    await tester.pumpAndSettle();

    expect(calls, ['keep']);
    expect(find.text('In Downloads/QuickShare/$fileName'), findsOneWidget);
    expect(find.widgetWithText(SnackBarAction, 'Open'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Download copies an older file from app storage into Downloads', (tester) async {
    mockDownloads({'path': 'content://media/external/downloads/77', 'name': fileName, 'copied': true});
    await pumpPhone(
      tester,
      pdf(path: '/storage/emulated/0/Android/data/com.quickshare.quickshare/files/QuickShare/$fileName'),
    );

    await tester.tap(find.widgetWithText(ElevatedButton, 'Download'));
    await tester.pumpAndSettle();

    expect(find.text('Saved to Downloads/QuickShare/$fileName'), findsOneWidget);
    expect(engine.receivedItems.single.savedToPath, 'content://media/external/downloads/77');

    await tester.pumpWidget(const SizedBox());
  });
}
