import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickshare/transfer/sink_factory_io.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('quickshare/system');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'streams received data into Downloads and commits the verified item',
    () async {
      final calls = <MethodCall>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return switch (call.method) {
          'beginDownload' => {
            'uri': 'content://media/external/downloads/42',
            'name': 'photo.jpg',
          },
          'finishDownload' => 'content://media/external/downloads/42',
          _ => null,
        };
      });

      final sink = await AndroidDownloadsSink.open('photo.jpg', 3);
      final data = Uint8List.fromList([1, 2, 3]);
      await sink.add(data);
      final received = await sink.commit('verified-sha256');

      expect(calls.map((call) => call.method), [
        'beginDownload',
        'writeDownloadChunk',
        'finishDownload',
      ]);
      expect((calls[1].arguments as Map)['data'], data);
      expect(received.path, 'content://media/external/downloads/42');
      expect(received.bytes, data);
      expect(received.sha256, 'verified-sha256');
    },
  );

  test('discards an interrupted Downloads entry', () async {
    final methods = <String>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      methods.add(call.method);
      if (call.method == 'beginDownload') {
        return {
          'uri': 'content://media/external/downloads/43',
          'name': 'partial.zip',
        };
      }
      return null;
    });

    final sink = await AndroidDownloadsSink.open('partial.zip', 10);
    await sink.discard();

    expect(methods, ['beginDownload', 'discardDownload']);
  });
}
