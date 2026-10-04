/// Output formats offered by the File Converter, and which inputs can produce them.
///
/// Every conversion runs offline inside the app (pure Dart), so only formats that can be
/// parsed and written without native codecs are offered. Anything else can still be
/// packed into a ZIP so whole folders go through the converter without errors.
enum ConversionFormat {
  pdf('PDF Document (.pdf)', '.pdf', 'Documents', 'application/pdf'),
  codePdf('PDF Code Listing (.pdf)', '.pdf', 'Documents', 'application/pdf'),
  docx('Word Document (.docx)', '.docx', 'Documents',
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document'),
  odt('OpenDocument Text (.odt)', '.odt', 'Documents', 'application/vnd.oasis.opendocument.text'),
  rtf('Rich Text (.rtf)', '.rtf', 'Documents', 'application/rtf'),
  txt('Plain Text (.txt)', '.txt', 'Documents', 'text/plain'),
  html('Web Page (.html)', '.html', 'Documents', 'text/html'),
  md('Markdown (.md)', '.md', 'Documents', 'text/markdown'),
  xlsx('Excel Workbook (.xlsx)', '.xlsx', 'Spreadsheets & Data',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'),
  ods('OpenDocument Sheet (.ods)', '.ods', 'Spreadsheets & Data', 'application/vnd.oasis.opendocument.spreadsheet'),
  csv('CSV Table (.csv)', '.csv', 'Spreadsheets & Data', 'text/csv'),
  json('JSON Data (.json)', '.json', 'Spreadsheets & Data', 'application/json'),
  png('PNG Image (.png)', '.png', 'Images', 'image/png'),
  jpg('JPEG Image (.jpg)', '.jpg', 'Images', 'image/jpeg'),
  bmp('Bitmap Image (.bmp)', '.bmp', 'Images', 'image/bmp'),
  gif('GIF Image (.gif)', '.gif', 'Images', 'image/gif'),
  tiff('TIFF Image (.tiff)', '.tiff', 'Images', 'image/tiff'),
  pdfPagesPng('PDF Pages as PNG (.zip)', '.zip', 'Images', 'application/zip'),
  stl('STL Mesh (.stl)', '.stl', '3D Models', 'model/stl'),
  obj('Wavefront OBJ (.obj)', '.obj', '3D Models', 'model/obj'),
  threeMf('3MF Model (.3mf)', '.3mf', '3D Models', 'model/3mf'),
  zip('ZIP Archive (.zip)', '.zip', 'Archives', 'application/zip'),
  tar('TAR Archive (.tar)', '.tar', 'Archives', 'application/x-tar'),
  tarGz('Gzipped TAR (.tar.gz)', '.tar.gz', 'Archives', 'application/gzip');

  final String label;
  final String outputExtension;
  final String category;
  final String mimeType;

  const ConversionFormat(this.label, this.outputExtension, this.category, this.mimeType);
}

/// What kind of file an input is, decided by its extension.
enum SourceKind {
  pdf('PDF Document'),
  docx('Word Document'),
  doc('Word 97-2003 Document'),
  odt('OpenDocument Text'),
  rtf('Rich Text'),
  text('Plain Text'),
  markdown('Markdown'),
  html('Web Page'),
  code('Source Code'),
  json('JSON Data'),
  xml('XML Data'),
  xlsx('Excel Workbook'),
  ods('OpenDocument Sheet'),
  csv('CSV Table'),
  tsv('TSV Table'),
  pptx('PowerPoint Presentation'),
  odp('OpenDocument Presentation'),
  image('Image'),
  svg('SVG Vector Image'),
  stl('STL Mesh'),
  obj('OBJ Mesh'),
  threeMf('3MF Model'),
  zip('ZIP Archive'),
  tar('TAR Archive'),
  tarGz('Gzipped TAR'),
  gzip('Gzip File'),
  other('File');

  final String label;
  const SourceKind(this.label);
}

class ConversionFormats {
  static const _codeExtensions = {
    'css', 'scss', 'less', 'js', 'mjs', 'cjs', 'ts', 'tsx', 'jsx', 'py', 'java', 'dart', 'c', 'h', 'cpp', 'cc',
    'cxx', 'hpp', 'cs', 'go', 'rs', 'kt', 'kts', 'swift', 'php', 'rb', 'sh', 'bash', 'ps1', 'bat', 'cmd', 'sql',
    'yaml', 'yml', 'toml', 'ini', 'cfg', 'conf', 'gradle', 'r', 'scala', 'lua', 'pl', 'vue', 'svelte', 'm',
    'ipynb', 'properties', 'env', 'dockerfile', 'makefile',
  };
  static const _imageExtensions = {'png', 'jpg', 'jpeg', 'webp', 'gif', 'bmp', 'tif', 'tiff', 'ico', 'tga', 'pnm', 'pbm', 'pgm', 'ppm'};

  /// Detects the [SourceKind] of [fileName] from its extension.
  static SourceKind detect(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.tar.gz') || lower.endsWith('.tgz')) return SourceKind.tarGz;
    final dot = lower.lastIndexOf('.');
    final ext = dot == -1 ? lower.split('/').last : lower.substring(dot + 1);
    if (_codeExtensions.contains(ext)) return SourceKind.code;
    if (_imageExtensions.contains(ext)) return SourceKind.image;
    switch (ext) {
      case 'pdf':
        return SourceKind.pdf;
      case 'docx':
        return SourceKind.docx;
      case 'doc':
        return SourceKind.doc;
      case 'odt':
        return SourceKind.odt;
      case 'rtf':
        return SourceKind.rtf;
      case 'txt':
      case 'log':
      case 'text':
        return SourceKind.text;
      case 'md':
      case 'markdown':
        return SourceKind.markdown;
      case 'html':
      case 'htm':
      case 'xhtml':
        return SourceKind.html;
      case 'json':
        return SourceKind.json;
      case 'xml':
        return SourceKind.xml;
      case 'xlsx':
      case 'xlsm':
        return SourceKind.xlsx;
      case 'ods':
        return SourceKind.ods;
      case 'csv':
        return SourceKind.csv;
      case 'tsv':
      case 'tab':
        return SourceKind.tsv;
      case 'pptx':
        return SourceKind.pptx;
      case 'odp':
        return SourceKind.odp;
      case 'svg':
        return SourceKind.svg;
      case 'stl':
        return SourceKind.stl;
      case 'obj':
        return SourceKind.obj;
      case '3mf':
        return SourceKind.threeMf;
      case 'zip':
        return SourceKind.zip;
      case 'tar':
        return SourceKind.tar;
      case 'gz':
        return SourceKind.gzip;
      default:
        return SourceKind.other;
    }
  }

  /// Output formats available for [fileName]; the first one is the suggested default.
  static List<ConversionFormat> targetsFor(String fileName) {
    final kind = detect(fileName);
    final lower = fileName.toLowerCase();
    final List<ConversionFormat> targets;
    switch (kind) {
      case SourceKind.pdf:
        targets = const [
          ConversionFormat.docx, ConversionFormat.txt, ConversionFormat.odt, ConversionFormat.rtf,
          ConversionFormat.html, ConversionFormat.md, ConversionFormat.xlsx, ConversionFormat.csv,
          ConversionFormat.pdfPagesPng,
        ];
      case SourceKind.docx:
      case SourceKind.doc:
      case SourceKind.odt:
      case SourceKind.rtf:
      case SourceKind.text:
      case SourceKind.markdown:
        targets = const [
          ConversionFormat.pdf, ConversionFormat.docx, ConversionFormat.odt, ConversionFormat.rtf,
          ConversionFormat.txt, ConversionFormat.html, ConversionFormat.md,
        ];
      case SourceKind.html:
        targets = const [
          ConversionFormat.pdf, ConversionFormat.codePdf, ConversionFormat.docx, ConversionFormat.odt,
          ConversionFormat.rtf, ConversionFormat.txt, ConversionFormat.md,
        ];
      case SourceKind.code:
      case SourceKind.xml:
        targets = const [ConversionFormat.codePdf, ConversionFormat.txt, ConversionFormat.docx, ConversionFormat.html];
      case SourceKind.json:
        targets = const [
          ConversionFormat.codePdf, ConversionFormat.xlsx, ConversionFormat.csv, ConversionFormat.ods,
          ConversionFormat.txt, ConversionFormat.docx, ConversionFormat.html,
        ];
      case SourceKind.xlsx:
      case SourceKind.ods:
      case SourceKind.csv:
      case SourceKind.tsv:
        targets = const [
          ConversionFormat.pdf, ConversionFormat.xlsx, ConversionFormat.ods, ConversionFormat.csv,
          ConversionFormat.json, ConversionFormat.html,
        ];
      case SourceKind.pptx:
      case SourceKind.odp:
        targets = const [
          ConversionFormat.pdf, ConversionFormat.docx, ConversionFormat.txt, ConversionFormat.md,
          ConversionFormat.html,
        ];
      case SourceKind.image:
        targets = const [
          ConversionFormat.pdf, ConversionFormat.png, ConversionFormat.jpg, ConversionFormat.bmp,
          ConversionFormat.gif, ConversionFormat.tiff,
        ];
      case SourceKind.svg:
        targets = const [ConversionFormat.pdf, ConversionFormat.png, ConversionFormat.jpg];
      case SourceKind.stl:
      case SourceKind.obj:
      case SourceKind.threeMf:
        targets = const [ConversionFormat.stl, ConversionFormat.obj, ConversionFormat.threeMf];
      case SourceKind.zip:
        return const [ConversionFormat.tarGz, ConversionFormat.tar];
      case SourceKind.tar:
        return const [ConversionFormat.zip, ConversionFormat.tarGz];
      case SourceKind.tarGz:
        return const [ConversionFormat.zip, ConversionFormat.tar];
      case SourceKind.gzip:
      case SourceKind.other:
        return const [ConversionFormat.zip];
    }
    // Drop "convert to the same format", then always allow packing into a ZIP.
    final sameExt = {
      ConversionFormat.jpg: ['.jpg', '.jpeg'],
      ConversionFormat.tiff: ['.tif', '.tiff'],
      ConversionFormat.md: ['.md', '.markdown'],
      ConversionFormat.html: ['.html', '.htm'],
      ConversionFormat.txt: ['.txt'],
      ConversionFormat.xlsx: ['.xlsx', '.xlsm'],
    };
    return [
      ...targets.where((t) {
        if (t == ConversionFormat.pdf && kind == SourceKind.pdf) return false;
        final exts = sameExt[t] ?? [t.outputExtension];
        return !exts.any(lower.endsWith);
      }),
      ConversionFormat.zip,
    ];
  }

  /// Human-readable list of what the converter accepts, for the empty state.
  static const supportedSummary = [
    'Documents: PDF, DOCX, DOC, ODT, RTF, TXT, MD',
    'Spreadsheets: XLSX, ODS, CSV, TSV, JSON',
    'Presentations: PPTX, ODP',
    'Images: JPG, PNG, WEBP, GIF, BMP, TIFF, SVG',
    'Code: HTML, CSS, JS, PY, JAVA, DART, C/C++, XML…',
    '3D: STL, OBJ, 3MF',
    'Archives: ZIP, TAR, TAR.GZ',
    'Anything else: packed into ZIP',
  ];
}
