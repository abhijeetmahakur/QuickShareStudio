import 'package:flutter/material.dart';
import '../../../data/models/pdf_project.dart';
import '../../../core/constants.dart';

class PageThumbnailsBar extends StatelessWidget {
  final List<PdfPageModel> pages;
  final int selectedPageIndex;
  final Function(int index) onSelectPage;
  final VoidCallback onAddPage;
  final Function(int index) onDuplicatePage;
  final Function(int index) onDeletePage;
  final Function(int oldIndex, int newIndex) onReorderPage;

  const PageThumbnailsBar({
    super.key,
    required this.pages,
    required this.selectedPageIndex,
    required this.onSelectPage,
    required this.onAddPage,
    required this.onDuplicatePage,
    required this.onDeletePage,
    required this.onReorderPage,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(
          right: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
          ),
        ),
      ),
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.pages_outlined, size: 18, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Text(
                      'Pages (${pages.length})',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle, color: AppColors.primary, size: 22),
                  tooltip: 'Add Blank Page',
                  onPressed: onAddPage,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Scrollable list of page cards
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: pages.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final page = pages[index];
                final isSelected = index == selectedPageIndex;

                return InkWell(
                  onTap: () => onSelectPage(index),
                  borderRadius: BorderRadius.circular(8),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.primary.withValues(alpha: 0.08)
                          : Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSelected ? AppColors.primary : Colors.grey.withValues(alpha: 0.25),
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Page thumbnail representation
                        AspectRatio(
                          aspectRatio: page.geometry.isLandscape ? 1.414 : (1 / 1.414),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.grey.shade300),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.05),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: page.images.isEmpty
                                ? Center(
                                    child: Text(
                                      'Empty',
                                      style: TextStyle(color: Colors.grey.shade400, fontSize: 10),
                                    ),
                                  )
                                : ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: GridView.builder(
                                      physics: const NeverScrollableScrollPhysics(),
                                      padding: const EdgeInsets.all(2),
                                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: page.customCols > 0 ? page.customCols : 2,
                                        mainAxisSpacing: 2,
                                        crossAxisSpacing: 2,
                                      ),
                                      itemCount: page.images.length,
                                      itemBuilder: (context, imgIdx) {
                                        return Image.memory(
                                          page.images[imgIdx].bytes,
                                          fit: BoxFit.cover,
                                        );
                                      },
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 8),

                        // Page details and actions
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Page ${page.pageNumber}',
                              style: TextStyle(
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                fontSize: 12,
                                color: isSelected ? AppColors.primary : null,
                              ),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${page.images.length} imgs',
                                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                ),
                                const SizedBox(width: 4),
                                PopupMenuButton<String>(
                                  icon: const Icon(Icons.more_vert, size: 16),
                                  padding: EdgeInsets.zero,
                                  itemBuilder: (context) => [
                                    const PopupMenuItem(
                                      value: 'duplicate',
                                      child: Row(
                                        children: [
                                          Icon(Icons.copy, size: 16),
                                          SizedBox(width: 8),
                                          Text('Duplicate Page'),
                                        ],
                                      ),
                                    ),
                                    if (index > 0)
                                      const PopupMenuItem(
                                        value: 'move_up',
                                        child: Row(
                                          children: [
                                            Icon(Icons.arrow_upward, size: 16),
                                            SizedBox(width: 8),
                                            Text('Move Up'),
                                          ],
                                        ),
                                      ),
                                    if (index < pages.length - 1)
                                      const PopupMenuItem(
                                        value: 'move_down',
                                        child: Row(
                                          children: [
                                            Icon(Icons.arrow_downward, size: 16),
                                            SizedBox(width: 8),
                                            Text('Move Down'),
                                          ],
                                        ),
                                      ),
                                    const PopupMenuItem(
                                      value: 'delete',
                                      child: Row(
                                        children: [
                                          Icon(Icons.delete_outline, color: Colors.red, size: 16),
                                          SizedBox(width: 8),
                                          Text('Delete Page', style: TextStyle(color: Colors.red)),
                                        ],
                                      ),
                                    ),
                                  ],
                                  onSelected: (val) {
                                    if (val == 'duplicate') {
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
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
