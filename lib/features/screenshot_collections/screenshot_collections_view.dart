import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../../data/services/transfer_engine.dart';
import '../../data/models/screenshot_session_model.dart';
import '../../data/models/screenshot_item.dart';
import '../../data/models/pdf_project.dart';
import '../../data/models/session_pdf.dart';
import '../pdf_editor/services/pdf_export_service.dart';
import '../pdf_editor/widgets/session_pdf_dialog.dart';
import '../../core/utils/format_utils.dart';
import '../../core/constants.dart';
import '../../core/widgets/hover_card.dart';

class ScreenshotCollectionsView extends StatefulWidget {
  const ScreenshotCollectionsView({super.key});

  @override
  State<ScreenshotCollectionsView> createState() => _ScreenshotCollectionsViewState();
}

class _ScreenshotCollectionsViewState extends State<ScreenshotCollectionsView> {
  int _currentTab = 0; // 0: Sessions List, 1: Active Workspace
  String? _activeSessionId;
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final engine = context.read<TransferEngine>();
        if (engine.screenshotSessions.isEmpty) {
          final s = engine.createScreenshotSession('Operating Systems Lab');
          setState(() {
            _activeSessionId = s.id;
          });
        } else {
          setState(() {
            _activeSessionId = engine.screenshotSessions.first.id;
          });
        }
      }
    });
  }

  void _showCreateSessionDialog(BuildContext context, TransferEngine engine) {
    final controller = TextEditingController(text: 'Lab_Session_${engine.screenshotSessions.length + 1}');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: AppColors.white.withValues(alpha: 0.15)),
        ),
        title: Row(
          children: [
            Icon(Icons.add_box_outlined, color: AppColors.primaryAccent),
            SizedBox(width: 10),
            Text('Create New Screenshot Session', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: AppColors.white),
          decoration: InputDecoration(
            labelText: 'Session Name',
            hintText: 'e.g. Physics Lab Experiments',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.nearBlack,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                final newSession = engine.createScreenshotSession(name);
                Navigator.pop(ctx);
                setState(() {
                  _activeSessionId = newSession.id;
                  _currentTab = 1;
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Created session "$name".')),
                );
              }
            },
            child: const Text('Create Session'),
          ),
        ],
      ),
    );
  }

  void _showRenameDialog(BuildContext context, TransferEngine engine, ScreenshotSessionModel session) {
    final controller = TextEditingController(text: session.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: AppColors.white.withValues(alpha: 0.15)),
        ),
        title: const Text('Rename Session', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: AppColors.white),
          decoration: InputDecoration(
            labelText: 'New Session Name',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.nearBlack,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              final newName = controller.text.trim();
              if (newName.isNotEmpty) {
                engine.renameScreenshotSession(session.id, newName);
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Session renamed to "$newName".')),
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteSession(BuildContext context, TransferEngine engine, ScreenshotSessionModel session) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: AppColors.white.withValues(alpha: 0.15)),
        ),
        title: const Text('Delete Screenshot Session?'),
        content: Text(
          'Are you sure you want to delete session "${session.name}" containing ${session.screenshotCount} screenshot(s)? This action cannot be undone.',
          style: TextStyle(color: AppColors.secondaryText),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: AppColors.white),
            onPressed: () {
              engine.deleteScreenshotSession(session.id);
              Navigator.pop(ctx);
              setState(() {
                if (_activeSessionId == session.id) {
                  _activeSessionId = engine.screenshotSessions.isNotEmpty
                      ? engine.screenshotSessions.first.id
                      : null;
                  _currentTab = 0;
                }
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Deleted session "${session.name}".')),
              );
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _importScreenshots(BuildContext context, TransferEngine engine, ScreenshotSessionModel session) async {
    try {
      final res = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['png', 'jpg', 'jpeg', 'webp', 'bmp'],
      );

      if (res.isNotEmpty) {
        final newItems = <ScreenshotItem>[];
        for (final f in res) {
          final bytes = await f.readAsBytes();
          final item = ScreenshotItem(
            name: f.name,
            bytes: bytes,
            caption: f.name.replaceAll(RegExp(r'\.[^.]+$'), ''),
          );
          newItems.add(item);
        }
        engine.addScreenshotsToSession(session.id, newItems);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Imported ${newItems.length} screenshot(s) to "${session.name}".')),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to import images: $e')),
        );
      }
    }
  }

  Future<void> _exportSessionToPdf(BuildContext context, TransferEngine engine, ScreenshotSessionModel session) async {
    if (session.screenshots.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot export an empty session. Please add screenshots first.')),
      );
      return;
    }

    setState(() => _isExporting = true);

    try {
      final project = PdfProject(title: session.name);
      project.autoDistributeScreenshots(session.screenshots);

      final pdfBytes = await PdfExportService.generatePdf(project: project);
      final pdfFileName = '${session.name.replaceAll(RegExp(r'\s+'), '_')}.pdf';

      final sessionPdf = SessionPdf(
        fileName: pdfFileName,
        bytes: pdfBytes,
        pageCount: project.pages.length,
        screenshotCount: session.screenshots.length,
        paperFormatDescription: 'A4 Portrait',
        sessionName: session.name,
      );

      session.status = 'Exported';
      engine.setSessionPdf(sessionPdf);

      setState(() => _isExporting = false);

      if (context.mounted) {
        SessionPdfDialog.show(context, sessionPdf: sessionPdf);
      }
    } catch (e) {
      setState(() => _isExporting = false);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to generate PDF: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<TransferEngine>();
    final activeSession = engine.screenshotSessions.firstWhere(
      (s) => s.id == _activeSessionId,
      orElse: () => engine.screenshotSessions.isNotEmpty
          ? engine.screenshotSessions.first
          : ScreenshotSessionModel(name: 'Default Session'),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Screenshot Sessions & PDF Workspace', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_box_outlined),
            tooltip: 'New Session',
            onPressed: () => _showCreateSessionDialog(context, engine),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Navigation Segmented Pills: Sessions List vs Active Workspace
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                _buildSegmentButton(
                  title: 'Sessions (${engine.screenshotSessions.length})',
                  icon: Icons.folder_special_outlined,
                  isSelected: _currentTab == 0,
                  onTap: () => setState(() => _currentTab = 0),
                ),
                _buildSegmentButton(
                  title: 'Workspace: ${activeSession.name}',
                  icon: Icons.collections_outlined,
                  isSelected: _currentTab == 1,
                  onTap: () => setState(() => _currentTab = 1),
                ),
              ],
            ),
            const SizedBox(height: 24),

            if (_currentTab == 0)
              _buildSessionsListTab(context, engine)
            else
              _buildWorkspaceTab(context, engine, activeSession),
          ],
        ),
      ),
    );
  }

  Widget _buildSegmentButton({
    required String title,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primaryAccent.withValues(alpha: 0.18) : AppColors.cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? AppColors.primaryAccent : AppColors.white.withValues(alpha: 0.12),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: isSelected ? AppColors.primaryAccent : AppColors.secondaryText),
              const SizedBox(width: 8),
              ConstrainedBox(
                // Long session names are shortened instead of overflowing on phones.
                constraints: const BoxConstraints(maxWidth: 260),
                child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isSelected ? AppColors.white : AppColors.secondaryText,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  fontSize: 13,
                ),
              ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------
  // TAB 0: SESSIONS LIST
  // -------------------------------------------------------------
  Widget _buildSessionsListTab(BuildContext context, TransferEngine engine) {
    if (engine.screenshotSessions.isEmpty) {
      return Center(
        child: Card(
          elevation: 0,
          color: AppColors.cardBg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: AppColors.white.withValues(alpha: 0.12)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.collections_bookmark_outlined, size: 48, color: AppColors.secondaryText),
                const SizedBox(height: 12),
                Text('No screenshot sessions yet', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.white)),
                const SizedBox(height: 6),
                Text(
                  'Create a dedicated session to organize laboratory screenshots into paginated PDFs.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.secondaryText, fontSize: 12),
                ),
                const SizedBox(height: 18),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.nearBlack,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Create First Session'),
                  onPressed: () => _showCreateSessionDialog(context, engine),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Flexible(
              child: Text(
                'AVAILABLE SESSIONS',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey),
              ),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.nearBlack,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('New Session', style: TextStyle(fontSize: 12)),
              onPressed: () => _showCreateSessionDialog(context, engine),
            ),
          ],
        ),
        const SizedBox(height: 14),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: engine.screenshotSessions.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, idx) {
            final session = engine.screenshotSessions[idx];
            final isCurrentActive = session.id == _activeSessionId;

            return HoverCard(
              borderRadius: BorderRadius.circular(16),
              padding: const EdgeInsets.all(18),
              liftOffset: 2.0,
              scale: 1.01,
              color: AppColors.cardBg,
              borderColor: isCurrentActive ? AppColors.primaryAccent : AppColors.white.withValues(alpha: 0.12),
              hoverBorderColor: AppColors.primaryAccent,
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.primaryAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(Icons.folder_shared, color: AppColors.primaryAccent, size: 24),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 10,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              session.name,
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.white),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: session.status == 'Exported'
                                    ? const Color(0xFF10B981).withValues(alpha: 0.2)
                                    : AppColors.white.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                session.status,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                  color: session.status == 'Exported' ? const Color(0xFF10B981) : AppColors.secondaryText,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${session.screenshotCount} screenshots • Total ${FormatUtils.formatBytes(session.totalSizeBytes)} • Created ${FormatUtils.formatDateTime(session.createdAt)}',
                          style: TextStyle(fontSize: 11.5, color: AppColors.secondaryText),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isCurrentActive ? AppColors.primaryAccent : AppColors.cardBg,
                          foregroundColor: isCurrentActive ? AppColors.nearBlack : AppColors.primaryText,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.open_in_new, size: 15),
                        label: Text(isCurrentActive ? 'Active' : 'Open', style: const TextStyle(fontSize: 12)),
                        onPressed: () {
                          setState(() {
                            _activeSessionId = session.id;
                            _currentTab = 1;
                          });
                        },
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: Icon(Icons.edit_outlined, size: 18, color: AppColors.secondaryText),
                        tooltip: 'Rename',
                        onPressed: () => _showRenameDialog(context, engine, session),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                        tooltip: 'Delete',
                        onPressed: () => _confirmDeleteSession(context, engine, session),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  // -------------------------------------------------------------
  // TAB 1: WORKSPACE
  // -------------------------------------------------------------
  Widget _buildWorkspaceTab(BuildContext context, TransferEngine engine, ScreenshotSessionModel session) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Workspace Header Card
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.cardBg,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.white.withValues(alpha: 0.12)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    session.name,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.white),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${session.screenshotCount} screenshots • Status: ${session.status}',
                    style: TextStyle(fontSize: 12, color: AppColors.secondaryText),
                  ),
                ],
              ),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primaryAccent,
                      side: BorderSide(color: AppColors.primaryAccent.withValues(alpha: 0.4)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.add_photo_alternate_outlined, size: 16),
                    label: const Text('Add Screenshots', style: TextStyle(fontSize: 12)),
                    onPressed: () => _importScreenshots(context, engine, session),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.nearBlack,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _isExporting ? null : () => _exportSessionToPdf(context, engine, session),
                    icon: _isExporting
                        ? SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.nearBlack))
                        : const Icon(Icons.picture_as_pdf, size: 16),
                    label: Text(_isExporting ? 'Exporting...' : 'Export to PDF', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        if (session.screenshots.isEmpty)
          Center(
            child: Card(
              elevation: 0,
              color: AppColors.cardBg,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: BorderSide(color: AppColors.white.withValues(alpha: 0.1)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: Column(
                  children: [
                    Icon(Icons.image_search, size: 40, color: AppColors.secondaryText),
                    const SizedBox(height: 12),
                    Text('No screenshots in this session', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.white)),
                    const SizedBox(height: 6),
                    Text('Click "Add Screenshots" to import lab images and generate your structured PDF.', style: TextStyle(color: AppColors.secondaryText, fontSize: 12)),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.nearBlack,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.file_upload_outlined, size: 16),
                      label: const Text('Import Lab Screenshots'),
                      onPressed: () => _importScreenshots(context, engine, session),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 1.15,
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
            ),
            itemCount: session.screenshots.length,
            itemBuilder: (context, i) {
              final item = session.screenshots[i];
              return HoverCard(
                borderRadius: BorderRadius.circular(14),
                padding: const EdgeInsets.all(10),
                color: AppColors.cardBg,
                borderColor: AppColors.white.withValues(alpha: 0.12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.memory(item.bytes, fit: BoxFit.cover, cacheWidth: 480),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            item.caption ?? item.name,
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.white),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 16, color: Colors.redAccent),
                          tooltip: 'Remove',
                          onPressed: () {
                            setState(() {
                              session.screenshots.removeAt(i);
                            });
                            engine.addScreenshotsToSession(session.id, []);
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }
}
