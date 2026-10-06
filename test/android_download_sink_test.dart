import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickshare/core/services/android_downloads.dart';
import 'package:quickshare/transfer/sink_factory_io.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const downloads = MethodChannel('quickshare/downloads');
  const system = MethodChannel('quickshare/system');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  /// Records calls to the Android Downloads bridge and answers them like DownloadsBridge.kt.
  List<MethodCall> mockDownloads({
    Map<String, Object?>? keep,
    String finishName = 'photo.jpg',
    bool failWrites = false,
  }) {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(system, (call) async => call.method == 'sdkInt' ? 34 : null);
    messenger.setMockMethodCallHandler(downloads, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'begin':
          return 'content://media/external/downloads/42';
        case 'write':
          if (failWrites) throw PlatformException(code: 'failed', message: 'No space left on device');
          return null;
        case 'finish':
          return finishName;
        case 'keep':
          return keep;
      }
      return null;
    });
    return calls;
  }

  tearDown(() {
    messenger.setMockMethodCallHandler(downloads, null);
    messenger.setMockMethodCallHandler(system, null);
  });

  group('AndroidDownloadsSink', () {
    test('streams received data into Downloads and commits the verified file', () async {
      final calls = mockDownloads(finishName: 'photo (1).jpg');

      final sink = await AndroidDownloadsSink.open('photo.jpg', 3);
      final data = Uint8List.fromList([1, 2, 3]);
      await sink.add(data);
      final received = await sink.commit('verified-sha256');

      expect(calls.map((c) => c.method), ['begin', 'write', 'finish']);
      expect((calls[0].arguments as Map)['name'], 'photo.jpg');
      expect((calls[1].arguments as Map)['data'], data);
      expect(received.path, 'content://media/external/downloads/42');
      // Android renames clashes; the received file reports the name it really got.
      expect(received.name, 'photo (1).jpg');
      expect(received.bytes, data);
      expect(received.sha256, 'verified-sha256');
    });

    test('batches 16 KiB transfer chunks into large writes', () async {
      final calls = mockDownloads();
      const chunk = 16 * 1024;
      const chunks = AndroidDownloads.blockSize ~/ chunk + 3;

      final sink = await AndroidDownloadsSink.open('video.mp4', chunk * chunks);
      for (var i = 0; i < chunks; i++) {
        await sink.add(Uint8List(chunk)..fillRange(0, chunk, i));
      }
      await sink.commit('sha');

      final writes = calls.where((c) => c.method == 'write').map((c) => (c.arguments as Map)['data'] as Uint8List).toList();
      expect(writes.map((w) => w.length), [AndroidDownloads.blockSize, 3 * chunk]);
      // Order is preserved: the last write starts with the chunk after the first block.
      expect(writes.last.first, AndroidDownloads.blockSize ~/ chunk);
    });

    test('discards an interrupted Downloads entry', () async {
      final calls = mockDownloads();

      final sink = await AndroidDownloadsSink.open('partial.zip', 10);
      await sink.add(Uint8List(4));
      await sink.discard();

      expect(calls.map((c) => c.method), ['begin', 'discard']);
    });

    test('deletes the entry when the final write fails', () async {
      final calls = mockDownloads(failWrites: true);

      final sink = await AndroidDownloadsSink.open('photo.jpg', 3);
      await sink.add(Uint8List(3));

      await expectLater(sink.commit('sha'), throwsA(isA<PlatformException>()));
      expect(calls.map((c) => c.method), ['begin', 'write', 'discard']);
    });
  });

  group('AndroidDownloads.saveReceived', () {
    test('leaves a file that is already in Downloads alone', () async {
      final calls = mockDownloads(keep: {
        'path': 'content://media/external/downloads/42',
        'name': 'report.pdf',
        'copied': false,
      });

      final saved = await AndroidDownloads.saveReceived(
        fileName: 'report.pdf',
        path: 'content://media/external/downloads/42',
        bytes: Uint8List.fromList([1, 2, 3]),
      );

      expect(saved!.copied, isFalse);
      expect(saved.path, 'content://media/external/downloads/42');
      expect(calls.map((c) => c.method), ['keep']);
    });

    test('reports a file copied in from app storage', () async {
      mockDownloads(keep: {
        'path': 'content://media/external/downloads/43',
        'name': 'report.pdf',
        'copied': true,
      });

      final saved = await AndroidDownloads.saveReceived(
        fileName: 'report.pdf',
        path: '/storage/emulated/0/Android/data/com.quickshare.quickshare/files/QuickShare/report.pdf',
      );

      expect(saved!.copied, isTrue);
      expect(saved.path, 'content://media/external/downloads/43');
    });

    test('writes the kept contents when the file itself is gone', () async {
      final calls = mockDownloads(finishName: 'notes.txt');
      final bytes = Uint8List.fromList(List.filled(AndroidDownloads.blockSize + 10, 7));

      final saved = await AndroidDownloads.saveReceived(fileName: 'notes.txt', path: '/gone/notes.txt', bytes: bytes);

      expect(saved!.copied, isTrue);
      expect(saved.name, 'notes.txt');
      expect(calls.map((c) => c.method), ['keep', 'begin', 'write', 'write', 'finish']);
    });

    test('returns null when neither the file nor its contents are left', () async {
      mockDownloads();

      final saved = await AndroidDownloads.saveReceived(fileName: 'old.zip', path: '/gone/old.zip');

      expect(saved, isNull);
    });
  });
}
