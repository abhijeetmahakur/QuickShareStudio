import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../data/models/screenshot_item.dart';
import '../../data/models/pdf_project.dart';
import '../pdf_editor/pdf_editor_view.dart';
import '../../core/utils/sample_screenshot_generator.dart';
import '../../core/constants.dart';

class ScreenshotCollectionsView extends StatefulWidget {
  const ScreenshotCollectionsView({super.key});

  @override
  State<ScreenshotCollectionsView> createState() => _ScreenshotCollectionsViewState();
}

class _ScreenshotCollectionsViewState extends State<ScreenshotCollectionsView> {
  final Map<String, List<ScreenshotItem>> _sessions = {
    'Java Practical 1': [],
    'Python Lab': [],
    'Computer Networks Notes': [],
  };
  String _activeSessionName = 'Java Practical 1';

  @override
  void initState() {
    super.initState();
    _loadInitialSamples();
  }

  Future<void> _loadInitialSamples() async {
    final samples = await SampleScreenshotGenerator.generateLabSamples();
    setState(() {
      _sessions['Java Practical 1'] = samples;
    });
  }

  List<ScreenshotItem> get _activeScreenshots => _sessions[_activeSessionName] ?? [];

  void _createNewSession() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create New Screenshot Session'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'e.g. Web Development Lab 3',
            labelText: 'Session Name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                setState(() {
                  _sessions[name] = [];
                  _activeSessionName = name;
                });
                Navigator.pop(context);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  Future<void> _importImages() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg', 'webp', 'bmp'],
    );

    if (files.isNotEmpty) {
      final newItems = <ScreenshotItem>[];
      for (final f in files) {
        final bytes = await f.readAsBytes();
        newItems.add(ScreenshotItem(
          name: f.name,
          bytes: bytes,
          caption: f.name.replaceAll(RegExp(r'\.[^.]+$'), ''),
        ));
      }
      setState(() {
        _activeScreenshots.addAll(newItems);
      });
    }
  }

  void _openInPdfStudio() {
    final project = PdfProject(title: _activeSessionName.replaceAll(' ', '_'));
    project.autoDistributeScreenshots(_activeScreenshots);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PdfEditorView(initialProject: project),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Screenshot Sessions & Organization', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
            icon: const Icon(Icons.picture_as_pdf, size: 18),
            label: const Text('Open in PDF Studio'),
            onPressed: _activeScreenshots.isNotEmpty ? _openInPdfStudio : null,
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Row(
        children: [
          // Left Sidebar: Session List
          Container(
            width: 250,
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              border: Border(right: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.1))),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Sessions', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      IconButton(
                        icon: const Icon(Icons.add_circle, color: AppColors.primary),
                        tooltip: 'New Session',
                        onPressed: _createNewSession,
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    children: [
                      for (final sessionName in _sessions.keys)
                        Material(
                          color: Colors.transparent,
                          child: ListTile(
                            selected: sessionName == _activeSessionName,
                            selectedTileColor: AppColors.primary.withValues(alpha: 0.08),
                            leading: const Icon(Icons.folder_outlined, color: AppColors.primary),
                            title: Text(sessionName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                            subtitle: Text('${_sessions[sessionName]?.length ?? 0} screenshots', style: const TextStyle(fontSize: 11)),
                            onTap: () => setState(() => _activeSessionName = sessionName),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Main Area: Screenshots Grid
          Expanded(
            child: Column(
              children: [
                // Session Header
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  color: Theme.of(context).cardColor,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_activeSessionName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                          const SizedBox(height: 4),
                          Text('${_activeScreenshots.length} screenshots in this collection', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                        ],
                      ),
                      Row(
                        children: [
                          OutlinedButton.icon(
                            icon: const Icon(Icons.add_photo_alternate, size: 18),
                            label: const Text('Add Screenshots'),
                            onPressed: _importImages,
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.science, size: 18),
                            label: const Text('Load Demo Samples'),
                            onPressed: _loadInitialSamples,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),

                // Grid of Screenshots
                Expanded(
                  child: _activeScreenshots.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.collections_outlined, size: 48, color: Colors.grey),
                              const SizedBox(height: 12),
                              const Text('No screenshots in this session yet.'),
                              const SizedBox(height: 8),
                              ElevatedButton.icon(
                                icon: const Icon(Icons.add),
                                label: const Text('Import Screenshots'),
                                onPressed: _importImages,
                              ),
                            ],
                          ),
                        )
                      : GridView.builder(
                          padding: const EdgeInsets.all(24),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            childAspectRatio: 1.35,
                            crossAxisSpacing: 16,
                            mainAxisSpacing: 16,
                          ),
                          itemCount: _activeScreenshots.length,
                          itemBuilder: (context, idx) {
                            final item = _activeScreenshots[idx];
                            return Card(
                              elevation: 0,
                              clipBehavior: Clip.antiAlias,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                                side: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
                              ),
                              child: Stack(
                                children: [
                                  Positioned.fill(
                                    child: Image.memory(item.bytes, fit: BoxFit.cover),
                                  ),
                                  Positioned(
                                    bottom: 0,
                                    left: 0,
                                    right: 0,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      color: Colors.black.withValues(alpha: 0.75),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              item.name,
                                              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.delete, color: Colors.redAccent, size: 16),
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(),
                                            onPressed: () {
                                              setState(() => _activeScreenshots.removeAt(idx));
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    top: 8,
                                    left: 8,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(alpha: 0.65),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text('#${idx + 1}', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
