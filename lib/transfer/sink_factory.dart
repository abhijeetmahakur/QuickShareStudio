import 'protocol/transfer_protocol.dart';
import 'sink_factory_io.dart' if (dart.library.js_interop) 'sink_factory_web.dart' as impl;

/// Received files at most this big also stay in memory (previews in Received Items).
const int keepInMemoryLimit = 8 * 1024 * 1024;

/// Opens where an accepted incoming file is written: straight to disk on native builds,
/// streamed to the launcher server on the desktop (web) app, so large files never have to
/// fit in memory.
Future<IncomingFileSink> openIncomingSink({required String fileName, required int size, required String directory}) =>
    impl.openSink(fileName: fileName, size: size, directory: directory);
