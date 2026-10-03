import 'package:flutter/material.dart';
import '../../../data/models/pdf_project.dart';
import '../../pdf_layout/models/layout_preset.dart';
import '../../pdf_layout/models/page_geometry.dart';
import '../../../core/constants.dart';

class LayoutSettingsPanel extends StatelessWidget {
  final PdfPageModel page;
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

  const LayoutSettingsPanel({
    super.key,
    required this.page,
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
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).cardColor,
      child: Container(
        width: 290,
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
            ),
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.all(16),
        children: [
          // Section Title
          const Row(
            children: [
              Icon(Icons.tune, size: 18, color: AppColors.primary),
              SizedBox(width: 8),
              Text(
                'Layout & Page Settings',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Presets (7 exact presets)
          const Text(
            'IMAGES PER PAGE PRESET',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey),
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
                  onSelected: (selected) {
                    if (selected) onPresetChanged(p.type);
                  },
                  selectedColor: AppColors.primary.withValues(alpha: 0.2),
                  labelStyle: TextStyle(
                    fontSize: 12,
                    fontWeight: page.presetType == p.type ? FontWeight.bold : FontWeight.normal,
                    color: page.presetType == p.type ? AppColors.primary : null,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // Custom Grid Rows & Cols (if Custom is selected)
          if (page.presetType == LayoutPresetType.custom) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Custom Rows & Columns', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue: page.customRows,
                          decoration: const InputDecoration(labelText: 'Rows', isDense: true),
                          items: [1, 2, 3, 4, 5, 6].map((r) => DropdownMenuItem(value: r, child: Text('$r'))).toList(),
                          onChanged: (val) {
                            if (val != null) onCustomGridChanged(val, page.customCols);
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue: page.customCols,
                          decoration: const InputDecoration(labelText: 'Columns', isDense: true),
                          items: [1, 2, 3, 4, 5].map((c) => DropdownMenuItem(value: c, child: Text('$c'))).toList(),
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

          const Divider(),
          const SizedBox(height: 8),

          // Paper Size & Orientation
          const Text(
            'PAPER FORMAT & GEOMETRY',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<PaperSize>(
            initialValue: page.geometry.paperSize,
            decoration: const InputDecoration(labelText: 'Paper Size', isDense: true),
            items: const [
              DropdownMenuItem(value: PaperSize.a4, child: Text('A4 (Standard 210 x 297 mm)')),
              DropdownMenuItem(value: PaperSize.a3, child: Text('A3 (Large 297 x 420 mm)')),
              DropdownMenuItem(value: PaperSize.a5, child: Text('A5 (Compact 148 x 210 mm)')),
              DropdownMenuItem(value: PaperSize.letter, child: Text('US Letter (8.5 x 11 in)')),
            ],
            onChanged: (val) {
              if (val != null) onPaperSizeChanged(val);
            },
          ),
          const SizedBox(height: 12),

          // Orientation Toggle
          Row(
            children: [
              Expanded(
                child: ChoiceChip(
                  avatar: const Icon(Icons.crop_portrait, size: 16),
                  label: const Text('Portrait'),
                  selected: !page.geometry.isLandscape,
                  onSelected: (val) {
                    if (val) onOrientationChanged(false);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ChoiceChip(
                  avatar: const Icon(Icons.crop_landscape, size: 16),
                  label: const Text('Landscape'),
                  selected: page.geometry.isLandscape,
                  onSelected: (val) {
                    if (val) onOrientationChanged(true);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Margins & Spacing
          const Text(
            'MARGINS & SPACING',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final m in [
                ('None (0pt)', 0.0),
                ('Small (18pt)', 18.0),
                ('Normal (24pt)', 24.0),
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(m.$1, style: const TextStyle(fontSize: 11)),
                    selected: page.geometry.marginPoints == m.$2,
                    onSelected: (s) {
                      if (s) onMarginChanged(m.$2);
                    },
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Cell Spacing: ${page.spacingPoints.round()} pt',
            style: const TextStyle(fontSize: 12),
          ),
          Slider(
            value: page.spacingPoints,
            min: 0.0,
            max: 24.0,
            divisions: 6,
            label: '${page.spacingPoints.round()} pt',
            onChanged: onSpacingChanged,
          ),

          const Divider(),
          const SizedBox(height: 8),

          // Image Fit Mode (Contain vs Crop-to-Fill)
          const Text(
            'IMAGE PROPORTIONS',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ChoiceChip(
                  avatar: const Icon(Icons.aspect_ratio, size: 16),
                  label: const Text('Contain (Keep Ratio)', style: TextStyle(fontSize: 11)),
                  selected: page.fitMode == ImageFitMode.contain,
                  onSelected: (val) {
                    if (val) onFitModeChanged(ImageFitMode.contain);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ChoiceChip(
                  avatar: const Icon(Icons.crop, size: 16),
                  label: const Text('Crop Fill', style: TextStyle(fontSize: 11)),
                  selected: page.fitMode == ImageFitMode.cropFill,
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
            title: const Text('Show Captions / Figure Titles', style: TextStyle(fontSize: 13)),
            subtitle: const Text('Prints filename & number below screenshot', style: TextStyle(fontSize: 11)),
            value: page.showCaptions,
            onChanged: onCaptionsChanged,
            contentPadding: EdgeInsets.zero,
          ),
          SwitchListTile(
            title: const Text('Auto-Continue Pages', style: TextStyle(fontSize: 13)),
            subtitle: const Text('Creates extra pages when images overflow', style: TextStyle(fontSize: 11)),
            value: autoContinue,
            onChanged: onAutoContinueChanged,
            contentPadding: EdgeInsets.zero,
          ),

          const SizedBox(height: 16),
          // Clear Page Images Action
          OutlinedButton.icon(
            icon: const Icon(Icons.cleaning_services, size: 16, color: Colors.red),
            label: const Text('Clear Images from This Page', style: TextStyle(color: Colors.red, fontSize: 12)),
            onPressed: page.images.isEmpty ? null : onClearPageImages,
          ),
        ],
      ),
    ),
  );
}
}
