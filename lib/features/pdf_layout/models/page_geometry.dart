import 'package:pdf/pdf.dart' as pw_pdf;
import '../../../core/constants.dart';

enum PaperSize {
  a4,
  a3,
  a5,
  letter,
}

enum MarginPreset {
  zero,
  small,
  normal,
  wide,
  custom,
}

class PageGeometry {
  final PaperSize paperSize;
  final bool isLandscape;
  final double marginPoints; // in 72 DPI PDF points
  final double safeAreaPoints; // Xerox safe margin guide

  const PageGeometry({
    this.paperSize = PaperSize.a4,
    this.isLandscape = false,
    this.marginPoints = 24.0,
    this.safeAreaPoints = 14.17, // ~5mm Xerox hardware edge margin
  });

  /// Base dimensions in PDF points (72 pt per inch)
  double get rawWidth {
    switch (paperSize) {
      case PaperSize.a4:
        return AppConstants.a4Width;
      case PaperSize.a3:
        return AppConstants.a3Width;
      case PaperSize.a5:
        return AppConstants.a5Width;
      case PaperSize.letter:
        return AppConstants.letterWidth;
    }
  }

  double get rawHeight {
    switch (paperSize) {
      case PaperSize.a4:
        return AppConstants.a4Height;
      case PaperSize.a3:
        return AppConstants.a3Height;
      case PaperSize.a5:
        return AppConstants.a5Height;
      case PaperSize.letter:
        return AppConstants.letterHeight;
    }
  }

  /// Width accounting for orientation
  double get pageWidth => isLandscape ? rawHeight : rawWidth;

  /// Height accounting for orientation
  double get pageHeight => isLandscape ? rawWidth : rawHeight;

  /// Printable width inside outer margins
  double get printableWidth => (pageWidth - (marginPoints * 2)).clamp(50.0, pageWidth);

  /// Printable height inside outer margins
  double get printableHeight => (pageHeight - (marginPoints * 2)).clamp(50.0, pageHeight);

  /// Aspect ratio of the physical sheet (width / height)
  double get pageAspectRatio => pageWidth / pageHeight;

  /// Returns the corresponding `pdf` package PageFormat with 0 margins so positioning is exact
  pw_pdf.PdfPageFormat toPdfPageFormat() {
    pw_pdf.PdfPageFormat baseFormat;
    switch (paperSize) {
      case PaperSize.a4:
        baseFormat = isLandscape ? pw_pdf.PdfPageFormat.a4.landscape : pw_pdf.PdfPageFormat.a4;
        break;
      case PaperSize.a3:
        baseFormat = isLandscape ? pw_pdf.PdfPageFormat.a3.landscape : pw_pdf.PdfPageFormat.a3;
        break;
      case PaperSize.a5:
        baseFormat = isLandscape ? pw_pdf.PdfPageFormat.a5.landscape : pw_pdf.PdfPageFormat.a5;
        break;
      case PaperSize.letter:
        baseFormat = isLandscape ? pw_pdf.PdfPageFormat.letter.landscape : pw_pdf.PdfPageFormat.letter;
        break;
    }
    return baseFormat.copyWith(
      marginLeft: 0,
      marginTop: 0,
      marginRight: 0,
      marginBottom: 0,
    );
  }

  String get paperDisplayName {
    switch (paperSize) {
      case PaperSize.a4:
        return 'A4 (${pageWidth.round()} x ${pageHeight.round()} pt)';
      case PaperSize.a3:
        return 'A3 (${pageWidth.round()} x ${pageHeight.round()} pt)';
      case PaperSize.a5:
        return 'A5 (${pageWidth.round()} x ${pageHeight.round()} pt)';
      case PaperSize.letter:
        return 'US Letter (${pageWidth.round()} x ${pageHeight.round()} pt)';
    }
  }

  PageGeometry copyWith({
    PaperSize? paperSize,
    bool? isLandscape,
    double? marginPoints,
    double? safeAreaPoints,
  }) {
    return PageGeometry(
      paperSize: paperSize ?? this.paperSize,
      isLandscape: isLandscape ?? this.isLandscape,
      marginPoints: marginPoints ?? this.marginPoints,
      safeAreaPoints: safeAreaPoints ?? this.safeAreaPoints,
    );
  }
}
