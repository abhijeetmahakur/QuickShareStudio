import 'dart:js_interop';
import 'dart:typed_data';

@JS('window.quicksharePdfPageCount')
external JSPromise<JSNumber> _jsPageCount(JSUint8Array bytes);

@JS('window.quicksharePdfExtractPages')
external JSPromise<JSUint8Array> _jsExtractPages(JSUint8Array bytes, JSArray<JSNumber> pageIndices);

@JS('window.quicksharePdfMerge')
external JSPromise<JSUint8Array> _jsMerge(JSArray<JSUint8Array> documents);

Future<int> pageCount(Uint8List bytes) async =>
    (await _jsPageCount(bytes.toJS).toDart).toDartInt;

Future<Uint8List> extractPages(Uint8List bytes, List<int> pageNumbers) async {
  final indices = [for (final p in pageNumbers) (p - 1).toJS].toJS;
  return (await _jsExtractPages(bytes.toJS, indices).toDart).toDart;
}

Future<Uint8List> merge(List<Uint8List> documents) async {
  final docs = [for (final d in documents) d.toJS].toJS;
  return (await _jsMerge(docs).toDart).toDart;
}
