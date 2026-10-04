import 'dart:js_interop';
import 'dart:typed_data';
import 'ocr_service.dart';

extension type _JsOcrResult(JSObject _) implements JSObject {
  external String get text;
  external double get confidence;
  external JSArray<JSUint8Array> get pdfs;
}

@JS('window.quickshareOcr')
external JSPromise<_JsOcrResult> _jsOcr(JSArray<JSUint8Array> images, String lang, JSFunction onProgress);

const bool isSupported = true;

Future<OcrResult> recognize(
  List<Uint8List> images,
  String languageCode,
  void Function(int done, int total)? onProgress,
) async {
  final progress = ((int done, int total) => onProgress?.call(done, total)).toJS;
  final result = await _jsOcr([for (final i in images) i.toJS].toJS, languageCode, progress).toDart;
  return OcrResult(
    result.text,
    result.confidence,
    [for (final p in result.pdfs.toDart) p.toDart],
  );
}
