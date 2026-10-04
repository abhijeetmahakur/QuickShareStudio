import '../../../core/constants.dart';
import 'package:flutter/material.dart';
import '../../../data/models/pdf_project.dart';
import '../../pdf_layout/models/layout_preset.dart';
import '../../pdf_layout/models/page_geometry.dart';

class LayoutSettingsPanel extends StatelessWidget {
  final PdfPageModel page;
  final int totalPages;
  final bool autoContinue;
  final Function(LayoutPresetType preset) onPresetChanged;
  final Function(PaperSize size) onPaperSizeChanged;
  final Function(bool isLandscape) onOrientationChanged;
  final Function(double margin) onMarginChanged;
  final Function(double spacing) onSpacingChanged;
  final Function(ImageFitMode mode) onFitModeChanged;
  final Function(bool show) onCaptionsChanged;
  final Function(bool auto) onAutoContinueChanged;
  final Function(int rows, int cols) onCustomGridChanged;
  final VoidCallback onClearPageImages;
  final VoidCallback? onApplyToAllPages;
  final VoidCallback? onToggleCollapse;
  final bool isCollapsed;

  // Official Dark Lime Design Palette Tokens
  static Color get panelBg => AppColors.charcoalSurface;
  static Color get cardBg => AppColors.cardBg;
  static Color get limeAccent => AppColors.primaryAccent;
  static Color get softGray => AppColors.secondaryText;
  static Color get primaryWhite => AppColors.primaryText;
  static const Color darkText = AppColors.nearBlack;
  static Color get subtleBorder => AppColors.subtleBorder;
  static Color get subtleBorderLight => AppColors.subtleBorderLight;

  const LayoutSettingsPanel({
    super.key,
    required this.page,
    this.totalPages = 1,
    required this.autoContinue,
    required this.onPresetChanged,
    required this.onPaperSizeChanged,
    required this.onOrientationChanged,
    required this.onMarginChanged,
    required this.onSpacingChanged,
    required this.onFitModeChanged,
    required this.onCaptionsChanged,
    required this.onAutoContinueChanged,
    required this.onCustomGridChanged,
    required this.onClearPageImages,
    this.onApplyToAllPages,
    this.onToggleCollapse,
    this.isCollapsed = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: panelBg,
      child: SizedBox(
        width: 290,
        height: double.infinity,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(
                      color: subtleBorder,
                      width: 1.0,
                    ),
                  ),
                ),
                child: Scrollbar(
                  child: ListView(
                    key: ValueKey('layout_page_${page.id}'),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    children: [
                // Header Row: Title, Per-Page Badge, Collapse Button
                Row(
                  children: [
                    Icon(Icons.tune_rounded, size: 18, color: limeAccent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Page ${page.pageNumber} Layout',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: primaryWhite,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: limeAccent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'Per-Page',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: darkText,
                        ),
                      ),
                    ),
                    if (onToggleCollapse != null) ...[
                      const SizedBox(width: 8),
                      Tooltip(
                        message: 'Hide Page Layout',
                        child: InkWell(
                          key: const Key('collapse_layout_panel_header_button'),
                          onTap: onToggleCollapse,
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: cardBg,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: subtleBorderLight),
                            ),
                            child: Icon(
                              Icons.chevron_right,
                              color: softGray,
                              size: 18,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Each page has its own independent layout and preset.',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    color: softGray,
                  ),
                ),
                if (totalPages > 1 && onApplyToAllPages != null) ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: limeAccent,
                      backgroundColor: cardBg,
                      side: BorderSide(color: subtleBorderLight),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      visualDensity: VisualDensity.compact,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: Icon(Icons.copy_all, size: 14, color: limeAccent),
                    label: Text(
                      'Apply Page ${page.pageNumber} Layout to All Pages',
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onPressed: onApplyToAllPages,
                  ),
                ],
                const SizedBox(height: 16),

                // Presets Section
                Text(
                  'IMAGES PER PAGE PRESET',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: softGray,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final p in LayoutPreset.allPresets)
                      ChoiceChip(
                        label: Text(p.type == LayoutPresetType.custom ? 'Custom' : '${p.imagesPerPage}-Up'),
                        selected: page.presetType == p.type,
                        showCheckmark: true,
                        checkmarkColor: darkText,
                        selectedColor: limeAccent,
                        backgroundColor: cardBg,
                        surfaceTintColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                          side: BorderSide(
                            color: page.presetType == p.type ? limeAccent : subtleBorderLight,
                            width: 1.0,
                          ),
                        ),
                        labelStyle: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 12,
                          fontWeight: page.presetType == p.type ? FontWeight.bold : FontWeight.w500,
                          color: page.presetType == p.type ? darkText : softGray,
                        ),
                        onSelected: (selected) {
                          if (selected) onPresetChanged(p.type);
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 16),

                // Custom Grid Rows & Cols (if Custom is selected)
                if (page.presetType == LayoutPresetType.custom) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: subtleBorderLight),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Custom Rows & Columns',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: primaryWhite,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<int>(
                                key: ValueKey('dd_rows_${page.id}_${page.customRows}'),
                                initialValue: page.customRows,
                                dropdownColor: cardBg,
                                style: TextStyle(color: primaryWhite, fontFamily: 'Poppins', fontSize: 13),
                                decoration: InputDecoration(
                                  labelText: 'Rows',
                                  labelStyle: TextStyle(color: softGray, fontSize: 12),
                                  isDense: true,
                                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: subtleBorderLight)),
                                  focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: limeAccent)),
                                ),
                                items: [1, 2, 3, 4, 5, 6, 7, 8]
                                    .map((r) => DropdownMenuItem(value: r, child: Text('$r')))
                                    .toList(),
                                onChanged: (val) {
                                  if (val != null) onCustomGridChanged(val, page.customCols);
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: DropdownButtonFormField<int>(
                                key: ValueKey('dd_cols_${page.id}_${page.customCols}'),
                                initialValue: page.customCols,
                                dropdownColor: cardBg,
                                style: TextStyle(color: primaryWhite, fontFamily: 'Poppins', fontSize: 13),
                                decoration: InputDecoration(
                                  labelText: 'Columns',
                                  labelStyle: TextStyle(color: softGray, fontSize: 12),
                                  isDense: true,
                                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: subtleBorderLight)),
                                  focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: limeAccent)),
                                ),
                                items: [1, 2, 3, 4, 5, 6]
                                    .map((c) => DropdownMenuItem(value: c, child: Text('$c')))
                                    .toList(),
                                onChanged: (val) {
                                  if (val != null) onCustomGridChanged(page.customRows, val);
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                Divider(color: subtleBorder, height: 24),

                // Paper Format & Geometry
                Text(
                  'PAPER FORMAT & GEOMETRY',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: softGray,
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<PaperSize>(
                  key: ValueKey('dd_papersize_${page.id}_${page.geometry.paperSize.name}'),
                  isExpanded: true,
                  initialValue: page.geometry.paperSize,
                  dropdownColor: cardBg,
                  style: TextStyle(color: primaryWhite, fontFamily: 'Poppins', fontSize: 13),
                  decoration: InputDecoration(
                    labelText: 'Paper Size',
                    labelStyle: TextStyle(color: softGray, fontSize: 12),
                    isDense: true,
                    filled: true,
                    fillColor: cardBg,
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(8)),
                      borderSide: BorderSide(color: subtleBorderLight),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(8)),
                      borderSide: BorderSide(color: limeAccent),
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(value: PaperSize.a4, child: Text('A4 (210 x 297 mm)')),
                    DropdownMenuItem(value: PaperSize.a3, child: Text('A3 (297 x 420 mm)')),
                    DropdownMenuItem(value: PaperSize.a5, child: Text('A5 (148 x 210 mm)')),
                    DropdownMenuItem(value: PaperSize.letter, child: Text('Letter (8.5 x 11 in)')),
                  ],
                  onChanged: (val) {
                    if (val != null) onPaperSizeChanged(val);
                  },
                ),
                const SizedBox(height: 12),

                // Orientation Toggle Buttons with Checkmarks
                Row(
                  children: [
                    Expanded(
                      child: ChoiceChip(
                        avatar: Icon(
                          Icons.crop_portrait_rounded,
                          size: 16,
                          color: !page.geometry.isLandscape ? darkText : softGray,
                        ),
                        label: const Text('Portrait'),
                        selected: !page.geometry.isLandscape,
                        showCheckmark: true,
                        checkmarkColor: darkText,
                        selectedColor: limeAccent,
                        backgroundColor: cardBg,
                        surfaceTintColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: BorderSide(
                            color: !page.geometry.isLandscape ? limeAccent : subtleBorderLight,
                          ),
                        ),
                        labelStyle: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 12,
                          fontWeight: !page.geometry.isLandscape ? FontWeight.bold : FontWeight.w500,
                          color: !page.geometry.isLandscape ? darkText : softGray,
                        ),
                        onSelected: (val) {
                          if (val) onOrientationChanged(false);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ChoiceChip(
                        avatar: Icon(
                          Icons.crop_landscape_rounded,
                          size: 16,
                          color: page.geometry.isLandscape ? darkText : softGray,
                        ),
                        label: const Text('Landscape'),
                        selected: page.geometry.isLandscape,
                        showCheckmark: true,
                        checkmarkColor: darkText,
                        selectedColor: limeAccent,
                        backgroundColor: cardBg,
                        surfaceTintColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: BorderSide(
                            color: page.geometry.isLandscape ? limeAccent : subtleBorderLight,
                          ),
                        ),
                        labelStyle: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 12,
                          fontWeight: page.geometry.isLandscape ? FontWeight.bold : FontWeight.w500,
                          color: page.geometry.isLandscape ? darkText : softGray,
                        ),
                        onSelected: (val) {
                          if (val) onOrientationChanged(true);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                Divider(color: subtleBorder, height: 24),

                // Margins & Spacing
                Text(
                  'MARGINS & SPACING',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: softGray,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final m in [
                      ('None (0pt)', 0.0),
                      ('Small (18pt)', 18.0),
                      ('Normal (24pt)', 24.0),
                    ])
                      ChoiceChip(
                        label: Text(m.$1, style: const TextStyle(fontFamily: 'Poppins', fontSize: 11)),
                        selected: page.geometry.marginPoints == m.$2,
                        showCheckmark: true,
                        checkmarkColor: darkText,
                        selectedColor: limeAccent,
                        backgroundColor: cardBg,
                        surfaceTintColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                          side: BorderSide(
                            color: page.geometry.marginPoints == m.$2 ? limeAccent : subtleBorderLight,
                          ),
                        ),
                        labelStyle: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 11,
                          fontWeight: page.geometry.marginPoints == m.$2 ? FontWeight.bold : FontWeight.w500,
                          color: page.geometry.marginPoints == m.$2 ? darkText : softGray,
                        ),
                        onSelected: (s) {
                          if (s) onMarginChanged(m.$2);
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Cell Spacing: ${page.spacingPoints.round()} pt',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: primaryWhite,
                      ),
                    ),
                  ],
                ),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: limeAccent,
                    inactiveTrackColor: subtleBorderLight,
                    thumbColor: limeAccent,
                    overlayColor: limeAccent.withValues(alpha: 0.2),
                    valueIndicatorColor: cardBg,
                    valueIndicatorTextStyle: TextStyle(color: limeAccent, fontFamily: 'Poppins'),
                  ),
                  child: Slider(
                    value: page.spacingPoints,
                    min: 0.0,
                    max: 24.0,
                    divisions: 6,
                    label: '${page.spacingPoints.round()} pt',
                    onChanged: onSpacingChanged,
                  ),
                ),

                Divider(color: subtleBorder, height: 24),

                // Image Proportions
                Text(
                  'IMAGE PROPORTIONS',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: softGray,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ChoiceChip(
                        avatar: Icon(
                          Icons.aspect_ratio_rounded,
                          size: 16,
                          color: page.fitMode == ImageFitMode.contain ? darkText : softGray,
                        ),
                        label: const Text('Contain (Keep Ratio)', style: TextStyle(fontSize: 11)),
                        selected: page.fitMode == ImageFitMode.contain,
                        showCheckmark: true,
                        checkmarkColor: darkText,
                        selectedColor: limeAccent,
                        backgroundColor: cardBg,
                        surfaceTintColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: BorderSide(
                            color: page.fitMode == ImageFitMode.contain ? limeAccent : subtleBorderLight,
                          ),
                        ),
                        labelStyle: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 11,
                          fontWeight: page.fitMode == ImageFitMode.contain ? FontWeight.bold : FontWeight.w500,
                          color: page.fitMode == ImageFitMode.contain ? darkText : softGray,
                        ),
                        onSelected: (val) {
                          if (val) onFitModeChanged(ImageFitMode.contain);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ChoiceChip(
                        avatar: Icon(
                          Icons.crop_rounded,
                          size: 16,
                          color: page.fitMode == ImageFitMode.cropFill ? darkText : softGray,
                        ),
                        label: const Text('Crop Fill', style: TextStyle(fontSize: 11)),
                        selected: page.fitMode == ImageFitMode.cropFill,
                        showCheckmark: true,
                        checkmarkColor: darkText,
                        selectedColor: limeAccent,
                        backgroundColor: cardBg,
                        surfaceTintColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: BorderSide(
                            color: page.fitMode == ImageFitMode.cropFill ? limeAccent : subtleBorderLight,
                          ),
                        ),
                        labelStyle: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 11,
                          fontWeight: page.fitMode == ImageFitMode.cropFill ? FontWeight.bold : FontWeight.w500,
                          color: page.fitMode == ImageFitMode.cropFill ? darkText : softGray,
                        ),
                        onSelected: (val) {
                          if (val) onFitModeChanged(ImageFitMode.cropFill);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Captions & Auto-Continue Switches
                SwitchListTile(
                  title: Text(
                    'Show Captions / Figure Titles',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: primaryWhite,
                    ),
                  ),
                  subtitle: Text(
                    'Prints filename & number below screenshot',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 11,
                      color: softGray,
                    ),
                  ),
                  value: page.showCaptions,
                  activeThumbColor: limeAccent,
                  activeTrackColor: limeAccent.withValues(alpha: 0.4),
                  inactiveThumbColor: softGray,
                  inactiveTrackColor: subtleBorder,
                  onChanged: onCaptionsChanged,
                  contentPadding: EdgeInsets.zero,
                ),
                SwitchListTile(
                  title: Text(
                    'Auto-Continue Pages',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: primaryWhite,
                    ),
                  ),
                  subtitle: Text(
                    'Creates extra pages when images overflow',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 11,
                      color: softGray,
                    ),
                  ),
                  value: autoContinue,
                  activeThumbColor: limeAccent,
                  activeTrackColor: limeAccent.withValues(alpha: 0.4),
                  inactiveThumbColor: softGray,
                  inactiveTrackColor: subtleBorder,
                  onChanged: onAutoContinueChanged,
                  contentPadding: EdgeInsets.zero,
                ),

                const SizedBox(height: 16),
                // Clear Page Images Action
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    backgroundColor: cardBg,
                    foregroundColor: const Color(0xFFF87171),
                    side: BorderSide(
                      color: const Color(0xFFF87171).withValues(alpha: 0.4),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.cleaning_services_rounded, size: 16, color: Color(0xFFF87171)),
                  label: const Text(
                    'Clear Images from This Page',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      color: Color(0xFFF87171),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onPressed: page.images.isEmpty ? null : onClearPageImages,
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
      if (onToggleCollapse != null)
        Positioned(
          left: 0,
          top: 22,
          child: Tooltip(
            message: 'Hide Page Layout',
            child: InkWell(
              key: const Key('collapse_layout_panel_edge_handle'),
              onTap: onToggleCollapse,
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(10)),
              child: Container(
                width: 24,
                height: 44,
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: const BorderRadius.horizontal(left: Radius.circular(10)),
                  border: Border.all(
                    color: subtleBorderLight,
                    width: 1.1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.4),
                      blurRadius: 8,
                      offset: const Offset(-2, 1),
                    ),
                  ],
                ),
                child: Center(
                  child: Icon(
                    Icons.chevron_right,
                    color: limeAccent,
                    size: 16,
                  ),
                ),
              ),
            ),
          ),
        ),
    ],
  ),
),
);
}
}
