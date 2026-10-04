import 'dart:typed_data';
import 'pdf_pages_io.dart' if (dart.library.js_interop) 'pdf_pages_web.dart' as impl;

/// Page-level PDF operations used by PDF Tools (page count, split, merge).
///
/// On web (the desktop app) pages are copied losslessly with pdf-lib. Native builds fall
/// back to re-rendering pages. Either way, failures throw: a page that cannot be read is
/// never replaced by made-up content.
class PdfPages {
  static Future<int> pageCount(Uint8List bytes) => impl.pageCount(bytes);

  /// Builds a new PDF from [pageNumbers] (1-based, in output order) of [bytes].
  static Future<Uint8List> extractPages(Uint8List bytes, List<int> pageNumbers) =>
      impl.extractPages(bytes, pageNumbers);

  /// Concatenates all pages of [documents] in order.
  static Future<Uint8List> merge(List<Uint8List> documents) => impl.merge(documents);
}
