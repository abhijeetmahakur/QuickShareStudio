import 'package:uuid/uuid.dart';

class LayoutTemplate {
  final String id;
  final String name;
  final String description;
  final String paperSize; // 'a4', 'a3', 'a5', 'letter'
  final bool isLandscape;
  final int imagesPerPage; // 1, 2, 3, 4, 6, 8, 10 or 0 for custom
  final int customRows;
  final int customCols;
  final double marginPoints; // 0, 18, 36, etc.
  final double spacingPoints;
  final String fitMode; // 'contain', 'cropFill'
  final bool showCaptions;
  final bool showPageNumbers;
  final bool isBuiltIn;

  LayoutTemplate({
    String? id,
    required this.name,
    required this.description,
    this.paperSize = 'a4',
    this.isLandscape = false,
    this.imagesPerPage = 4,
    this.customRows = 2,
    this.customCols = 2,
    this.marginPoints = 24.0,
    this.spacingPoints = 8.0,
    this.fitMode = 'contain',
    this.showCaptions = false,
    this.showPageNumbers = true,
    this.isBuiltIn = false,
  }) : id = id ?? const Uuid().v4();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'paperSize': paperSize,
        'isLandscape': isLandscape,
        'imagesPerPage': imagesPerPage,
        'customRows': customRows,
        'customCols': customCols,
        'marginPoints': marginPoints,
        'spacingPoints': spacingPoints,
        'fitMode': fitMode,
        'showCaptions': showCaptions,
        'showPageNumbers': showPageNumbers,
        'isBuiltIn': isBuiltIn,
      };

  factory LayoutTemplate.fromJson(Map<String, dynamic> json) => LayoutTemplate(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String? ?? '',
        paperSize: json['paperSize'] as String? ?? 'a4',
        isLandscape: json['isLandscape'] as bool? ?? false,
        imagesPerPage: json['imagesPerPage'] as int? ?? 4,
        customRows: json['customRows'] as int? ?? 2,
        customCols: json['customCols'] as int? ?? 2,
        marginPoints: (json['marginPoints'] as num?)?.toDouble() ?? 24.0,
        spacingPoints: (json['spacingPoints'] as num?)?.toDouble() ?? 8.0,
        fitMode: json['fitMode'] as String? ?? 'contain',
        showCaptions: json['showCaptions'] as bool? ?? false,
        showPageNumbers: json['showPageNumbers'] as bool? ?? true,
        isBuiltIn: json['isBuiltIn'] as bool? ?? false,
      );

  static List<LayoutTemplate> getStarterTemplates() {
    return [
      LayoutTemplate(
        id: 'starter_lab_4up',
        name: 'Lab 4-Up Grid (Recommended)',
        description: 'Perfect for lab code, terminals, and output screenshots',
        paperSize: 'a4',
        isLandscape: false,
        imagesPerPage: 4,
        customRows: 2,
        customCols: 2,
        marginPoints: 24.0,
        spacingPoints: 8.0,
        fitMode: 'contain',
        showCaptions: true,
        showPageNumbers: true,
        isBuiltIn: true,
      ),
      LayoutTemplate(
        id: 'starter_single_presentation',
        name: 'Single Large Slide (1-Up)',
        description: 'Maximum resolution for single full-page diagram or code listing',
        paperSize: 'a4',
        isLandscape: true,
        imagesPerPage: 1,
        customRows: 1,
        customCols: 1,
        marginPoints: 18.0,
        spacingPoints: 0.0,
        fitMode: 'contain',
        showCaptions: false,
        showPageNumbers: true,
        isBuiltIn: true,
      ),
      LayoutTemplate(
        id: 'starter_dual_compare',
        name: 'Dual Split (2-Up)',
        description: 'Ideal for before/after or code alongside terminal output',
        paperSize: 'a4',
        isLandscape: false,
        imagesPerPage: 2,
        customRows: 2,
        customCols: 1,
        marginPoints: 24.0,
        spacingPoints: 12.0,
        fitMode: 'contain',
        showCaptions: true,
        showPageNumbers: true,
        isBuiltIn: true,
      ),
      LayoutTemplate(
        id: 'starter_compact_6up',
        name: 'Compact 6-Up Notes',
        description: 'High-density contact sheet for reviewing numerous steps',
        paperSize: 'a4',
        isLandscape: false,
        imagesPerPage: 6,
        customRows: 3,
        customCols: 2,
        marginPoints: 20.0,
        spacingPoints: 6.0,
        fitMode: 'contain',
        showCaptions: false,
        showPageNumbers: true,
        isBuiltIn: true,
      ),
      LayoutTemplate(
        id: 'starter_dense_10up',
        name: 'Ultra-Dense 10-Up Overview',
        description: 'Thumbnail summary sheet for 10 screenshots per page',
        paperSize: 'a4',
        isLandscape: false,
        imagesPerPage: 10,
        customRows: 5,
        customCols: 2,
        marginPoints: 16.0,
        spacingPoints: 6.0,
        fitMode: 'contain',
        showCaptions: false,
        showPageNumbers: true,
        isBuiltIn: true,
      ),
    ];
  }
}
