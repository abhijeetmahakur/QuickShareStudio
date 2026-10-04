import '../../../core/constants.dart';
import 'package:flutter/material.dart';
import '../../../data/models/pdf_project.dart';
import '../../pdf_layout/models/layout_preset.dart';
import '../../../core/widgets/hover_card.dart';

class PageThumbnailsBar extends StatelessWidget {
  final List<PdfPageModel> pages;
  final int selectedPageIndex;
  final Function(int index) onSelectPage;
  final VoidCallback onAddPage;
  final Function(int index) onDuplicatePage;
  final Function(int index) onDeletePage;
  final Function(int oldIndex, int newIndex) onReorderPage;
  final Function(int pageIndex, LayoutPresetType preset)? onPagePresetChanged;

  // Official Dark Lime Design Palette Tokens
  static Color get panelBg => AppColors.charcoalSurface;
  static Color get cardBg => AppColors.cardBg;
  static Color get limeAccent => AppColors.primaryAccent;
  static Color get softGray => AppColors.secondaryText;
  static Color get primaryWhite => AppColors.primaryText;
  static const Color darkText = AppColors.nearBlack;
  static Color get subtleBorder => AppColors.subtleBorder;
  static Color get subtleBorderLight => AppColors.subtleBorderLight;

  const PageThumbnailsBar({
    super.key,
    required this.pages,
    required this.selectedPageIndex,
    required this.onSelectPage,
    required this.onAddPage,
    required this.onDuplicatePage,
    required this.onDeletePage,
    required this.onReorderPage,
    this.onPagePresetChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 250,
      decoration: BoxDecoration(
        color: panelBg,
        border: Border(
          right: BorderSide(
            color: subtleBorder,
            width: 1.0,
          ),
        ),
      ),
      child: Column(
        children: [
          // Header: Pages (N) with - and + buttons
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.pages_outlined, size: 17, color: limeAccent),
                    const SizedBox(width: 8),
                    Text(
                      'Pages (${pages.length})',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: primaryWhite,
                      ),
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Tooltip(
                      message: pages.length > 1
                          ? 'Decrease Page Count (Delete Page)'
                          : 'At least one page required',
                      child: InkWell(
                        onTap: pages.length > 1 ? () => onDeletePage(selectedPageIndex) : null,
                        borderRadius: BorderRadius.circular(14),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(
                            Icons.remove_circle_outline,
                            color: pages.length > 1 ? const Color(0xFFF87171) : AppColors.mutedText,
                            size: 19,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Tooltip(
                      message: 'Add Blank Page',
                      child: InkWell(
                        onTap: onAddPage,
                        borderRadius: BorderRadius.circular(14),
                        child: Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(Icons.add_circle, color: limeAccent, size: 19),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Divider(color: subtleBorder, height: 1),

          // Scrollable list of page cards
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: pages.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final page = pages[index];
                final isSelected = index == selectedPageIndex;

                return HoverCard(
                  onTap: () => onSelectPage(index),
                  borderRadius: BorderRadius.circular(10),
                  padding: const EdgeInsets.all(10),
                  liftOffset: 2.0,
                  scale: 1.015,
                  color: cardBg,
                  hoverColor: cardBg,
                  borderColor: isSelected ? limeAccent : subtleBorder,
                  hoverBorderColor: isSelected ? limeAccent : subtleBorderLight,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Miniature Page Preview
                      AspectRatio(
                        aspectRatio: page.geometry.isLandscape ? 1.414 : (1 / 1.414),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white, // page paper
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: isSelected
                                  ? limeAccent.withValues(alpha: 0.5)
                                  : Colors.grey.shade400,
                              width: isSelected ? 1.2 : 0.8,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.25),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: _buildThumbnailContent(page),
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Page details and actions footer
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    'Page ${page.pageNumber}',
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                      fontSize: 12,
                                      color: isSelected ? limeAccent : primaryWhite,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: isSelected ? limeAccent : cardBg,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: isSelected ? limeAccent : subtleBorderLight,
                                    ),
                                  ),
                                  child: Text(
                                    _formatPresetBadge(page),
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      color: isSelected ? darkText : softGray,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${page.images.length} img',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 11,
                                  color: softGray,
                                ),
                              ),
                              PopupMenuButton<String>(
                                icon: Icon(Icons.more_vert, size: 16, color: softGray),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                color: cardBg,
                                itemBuilder: (context) => [
                                  if (onPagePresetChanged != null) ...[
                                    PopupMenuItem(
                                      enabled: false,
                                      height: 24,
                                      child: Text(
                                        'PAGE LAYOUT',
                                        style: TextStyle(
                                          fontFamily: 'Poppins',
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: softGray,
                                        ),
                                      ),
                                    ),
                                    for (final p in LayoutPreset.allPresets)
                                      PopupMenuItem(
                                        value: 'preset_${p.type.name}',
                                        height: 32,
                                        child: Row(
                                          children: [
                                            Icon(
                                              page.presetType == p.type
                                                  ? Icons.check_circle
                                                  : Icons.circle_outlined,
                                              size: 14,
                                              color: page.presetType == p.type
                                                  ? limeAccent
                                                  : softGray,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              p.type == LayoutPresetType.custom
                                                  ? 'Custom Grid'
                                                  : '${p.imagesPerPage}-Up',
                                              style: TextStyle(
                                                fontFamily: 'Poppins',
                                                fontSize: 12,
                                                color: page.presetType == p.type
                                                    ? limeAccent
                                                    : primaryWhite,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    const PopupMenuDivider(height: 1),
                                  ],
                                  PopupMenuItem(
                                    value: 'duplicate',
                                    child: Row(
                                      children: [
                                        Icon(Icons.copy_rounded, size: 15, color: softGray),
                                        SizedBox(width: 8),
                                        Text('Duplicate Page', style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: primaryWhite)),
                                      ],
                                    ),
                                  ),
                                  if (index > 0)
                                    PopupMenuItem(
                                      value: 'move_up',
                                      child: Row(
                                        children: [
                                          Icon(Icons.arrow_upward_rounded, size: 15, color: softGray),
                                          SizedBox(width: 8),
                                          Text('Move Up', style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: primaryWhite)),
                                        ],
                                      ),
                                    ),
                                  if (index < pages.length - 1)
                                    PopupMenuItem(
                                      value: 'move_down',
                                      child: Row(
                                        children: [
                                          Icon(Icons.arrow_downward_rounded, size: 15, color: softGray),
                                          SizedBox(width: 8),
                                          Text('Move Down', style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: primaryWhite)),
                                        ],
                                      ),
                                    ),
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Row(
                                      children: [
                                        Icon(Icons.delete_outline_rounded, color: Color(0xFFF87171), size: 15),
                                        SizedBox(width: 8),
                                        Text('Delete Page', style: TextStyle(fontFamily: 'Poppins', color: Color(0xFFF87171), fontSize: 12)),
                                      ],
                                    ),
                                  ),
                                ],
                                onSelected: (val) {
                                  if (val.startsWith('preset_')) {
                                    final presetName = val.substring('preset_'.length);
                                    final matched = LayoutPresetType.values.firstWhere(
                                      (p) => p.name == presetName,
                                      orElse: () => LayoutPresetType.four,
                                    );
                                    onPagePresetChanged?.call(index, matched);
                                  } else if (val == 'duplicate') {
                                    onDuplicatePage(index);
                                  } else if (val == 'move_up') {
                                    onReorderPage(index, index - 1);
                                  } else if (val == 'move_down') {
                                    onReorderPage(index, index + 1);
                                  } else if (val == 'delete') {
                                    onDeletePage(index);
                                  }
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _formatPresetBadge(PdfPageModel page) {
    switch (page.presetType) {
      case LayoutPresetType.one:
        return '1-Up';
      case LayoutPresetType.two:
        return '2-Up';
      case LayoutPresetType.three:
        return '3-Up';
      case LayoutPresetType.four:
        return '4-Up';
      case LayoutPresetType.six:
        return '6-Up';
      case LayoutPresetType.eight:
        return '8-Up';
      case LayoutPresetType.ten:
        return '10-Up';
      case LayoutPresetType.custom:
        return '${page.customRows}x${page.customCols}';
    }
  }

  Widget _buildThumbnailContent(PdfPageModel page) {
    final gridDims = LayoutPreset.getGridDimensions(
      page.presetType,
      page.geometry.isLandscape,
      customRows: page.customRows,
      customCols: page.customCols,
    );
    final totalSlots = gridDims.rows * gridDims.cols;

    if (page.images.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(3),
        child: GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: gridDims.cols.clamp(1, 10),
            mainAxisSpacing: 2,
            crossAxisSpacing: 2,
          ),
          itemCount: totalSlots.clamp(1, 12),
          itemBuilder: (context, _) => Container(
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(2),
              border: Border.all(color: Colors.grey.shade300, width: 0.5),
            ),
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(2),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: gridDims.cols.clamp(1, 10),
          mainAxisSpacing: 2,
          crossAxisSpacing: 2,
        ),
        itemCount: page.images.length,
        itemBuilder: (context, imgIdx) {
          return Image.memory(
            page.images[imgIdx].bytes,
            fit: BoxFit.cover,
            cacheWidth: 240,
          );
        },
      ),
    );
  }
}
