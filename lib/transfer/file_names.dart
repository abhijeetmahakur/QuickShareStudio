/// File names arriving from another device are untrusted. [sanitizeIncomingFileName] turns
/// any name into a single, safe path component for every OS we save to.
library;

const _windowsReserved = {
  'CON', 'PRN', 'AUX', 'NUL', //
  'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9',
  'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9',
};

const int maxFileNameLength = 180;

String sanitizeIncomingFileName(String raw, {String fallback = 'file'}) {
  // Keep only the last path component, whichever separator the sender used.
  var name = raw.replaceAll('\\', '/').split('/').last;
  // Control characters (incl. NUL), bidi overrides that disguise extensions, and characters
  // that are invalid on Windows/Android storage.
  name = name.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '');
  name = name.replaceAll(RegExp(r'[\u202A-\u202E\u2066-\u2069\u200E\u200F]'), '');
  name = name.replaceAll(RegExp(r'[<>:"|?*]'), '_');
  name = name.trim();
  // No "..", no hidden dot-files, no trailing dots/spaces (Windows strips them silently).
  name = name.replaceAll(RegExp(r'^[. ]+'), '').replaceAll(RegExp(r'[. ]+$'), '');
  if (name.isEmpty) name = fallback;

  final dot = name.lastIndexOf('.');
  var stem = dot > 0 ? name.substring(0, dot) : name;
  var ext = dot > 0 ? name.substring(dot) : '';
  if (_windowsReserved.contains(stem.toUpperCase())) stem = '_$stem';
  if (ext.length > 16) {
    stem = '$stem$ext';
    ext = '';
  }
  if (stem.length + ext.length > maxFileNameLength) {
    stem = stem.substring(0, maxFileNameLength - ext.length);
  }
  return '$stem$ext';
}

/// Picks "name (2).ext", "name (3).ext"... when [taken] already contains [name].
String uniqueFileName(String name, bool Function(String candidate) taken) {
  if (!taken(name)) return name;
  final dot = name.lastIndexOf('.');
  final stem = dot > 0 ? name.substring(0, dot) : name;
  final ext = dot > 0 ? name.substring(dot) : '';
  for (var n = 2;; n++) {
    final candidate = '$stem ($n)$ext';
    if (!taken(candidate)) return candidate;
  }
}
