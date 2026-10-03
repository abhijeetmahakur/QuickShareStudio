enum ImageFitMode {
  contain, // Preserves complete image aspect ratio, no cropping
  cropFill, // Fills entire cell, crops overflowing parts
}

enum LayoutPresetType {
  one,
  two,
  three,
  four,
  six,
  eight,
  ten,
  custom,
}

class LayoutPreset {
  final LayoutPresetType type;
  final int imagesPerPage;
  final String label;
  final String description;

  const LayoutPreset({
    required this.type,
    required this.imagesPerPage,
    required this.label,
    required this.description,
  });

  static const List<LayoutPreset> allPresets = [
    LayoutPreset(
      type: LayoutPresetType.one,
      imagesPerPage: 1,
      label: '1 Image',
      description: 'Full-page single screenshot for maximum detail',
    ),
    LayoutPreset(
      type: LayoutPresetType.two,
      imagesPerPage: 2,
      label: '2 Images',
      description: 'Dual view (stacked in portrait, side-by-side in landscape)',
    ),
    LayoutPreset(
      type: LayoutPresetType.three,
      imagesPerPage: 3,
      label: '3 Images',
      description: 'Three step sequence with proportional distribution',
    ),
    LayoutPreset(
      type: LayoutPresetType.four,
      imagesPerPage: 4,
      label: '4 Images',
      description: '2x2 grid, standard for lab assignments & code outputs',
    ),
    LayoutPreset(
      type: LayoutPresetType.six,
      imagesPerPage: 6,
      label: '6 Images',
      description: '3x2 high-density overview of lab practicals',
    ),
    LayoutPreset(
      type: LayoutPresetType.eight,
      imagesPerPage: 8,
      label: '8 Images',
      description: '4x2 compact contact sheet for multi-step tasks',
    ),
    LayoutPreset(
      type: LayoutPresetType.ten,
      imagesPerPage: 10,
      label: '10 Images',
      description: '5x2 ultra-dense index sheet for rapid scanning',
    ),
    LayoutPreset(
      type: LayoutPresetType.custom,
      imagesPerPage: 0,
      label: 'Custom Grid',
      description: 'Configurable rows, columns, margins & spacing',
    ),
  ];

  /// Calculates the default (rows, columns) grid configuration given orientation
  static ({int rows, int cols}) getGridDimensions(LayoutPresetType type, bool isLandscape, {int customRows = 2, int customCols = 2}) {
    switch (type) {
      case LayoutPresetType.one:
        return (rows: 1, cols: 1);
      case LayoutPresetType.two:
        return isLandscape ? (rows: 1, cols: 2) : (rows: 2, cols: 1);
      case LayoutPresetType.three:
        return isLandscape ? (rows: 1, cols: 3) : (rows: 3, cols: 1);
      case LayoutPresetType.four:
        return (rows: 2, cols: 2);
      case LayoutPresetType.six:
        return isLandscape ? (rows: 2, cols: 3) : (rows: 3, cols: 2);
      case LayoutPresetType.eight:
        return isLandscape ? (rows: 2, cols: 4) : (rows: 4, cols: 2);
      case LayoutPresetType.ten:
        return isLandscape ? (rows: 2, cols: 5) : (rows: 5, cols: 2);
      case LayoutPresetType.custom:
        return (rows: customRows.clamp(1, 12), cols: customCols.clamp(1, 12));
    }
  }
}
