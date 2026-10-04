import 'dart:convert';

/// Represents a published application update package and its release metadata.
class AppUpdateInfo {
  final String version;
  final String currentVersion;
  final String title;
  final String description;
  final List<String> releaseNotes;
  final DateTime publishedAt;
  final int packageSizeBytes;
  final String packageSha256;
  final String minSupportedVersion;
  final String downloadUrl;
  final bool isMandatory;

  const AppUpdateInfo({
    required this.version,
    required this.currentVersion,
    required this.title,
    required this.description,
    required this.releaseNotes,
    required this.publishedAt,
    required this.packageSizeBytes,
    required this.packageSha256,
    this.minSupportedVersion = '1.0.0',
    this.downloadUrl = 'https://updates.quickshare.local/releases',
    this.isMandatory = false,
  });

  bool get isNewerVersion {
    return compareVersions(version, currentVersion) > 0;
  }

  /// Compares dotted versions: negative if [v1] < [v2], 0 if equal, positive if [v1] > [v2].
  static int compareVersions(String v1, String v2) {
    final p1 = v1.replaceAll(RegExp(r'[^0-9.]'), '').split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final p2 = v2.replaceAll(RegExp(r'[^0-9.]'), '').split('.').map((s) => int.tryParse(s) ?? 0).toList();

    for (var i = 0; i < 3; i++) {
      final a = i < p1.length ? p1[i] : 0;
      final b = i < p2.length ? p2[i] : 0;
      if (a != b) return a.compareTo(b);
    }
    return 0;
  }

  Map<String, dynamic> toJson() => {
    'version': version,
    'currentVersion': currentVersion,
    'title': title,
    'description': description,
    'releaseNotes': releaseNotes,
    'publishedAt': publishedAt.toIso8601String(),
    'packageSizeBytes': packageSizeBytes,
    'packageSha256': packageSha256,
    'minSupportedVersion': minSupportedVersion,
    'downloadUrl': downloadUrl,
    'isMandatory': isMandatory,
  };

  factory AppUpdateInfo.fromJson(Map<String, dynamic> json) => AppUpdateInfo(
    version: json['version'] as String? ?? '1.0.0',
    currentVersion: json['currentVersion'] as String? ?? '1.0.0',
    title: json['title'] as String? ?? 'QuickShare Studio Update',
    description: json['description'] as String? ?? '',
    releaseNotes: (json['releaseNotes'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
    publishedAt: json['publishedAt'] != null
        ? DateTime.tryParse(json['publishedAt'] as String) ?? DateTime.now()
        : DateTime.now(),
    packageSizeBytes: json['packageSizeBytes'] as int? ?? 15728640,
    packageSha256: json['packageSha256'] as String? ?? '',
    minSupportedVersion: json['minSupportedVersion'] as String? ?? '1.0.0',
    downloadUrl: json['downloadUrl'] as String? ?? 'https://updates.quickshare.local/releases',
    isMandatory: json['isMandatory'] as bool? ?? false,
  );

  String serialize() => jsonEncode(toJson());

  static AppUpdateInfo? deserialize(String? data) {
    if (data == null || data.trim().isEmpty) return null;
    try {
      return AppUpdateInfo.fromJson(jsonDecode(data) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }
}
