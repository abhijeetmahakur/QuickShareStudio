import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../../data/services/transfer_engine.dart';
import '../../data/services/cross_device_transfer_service.dart';
import '../../data/models/transfer_item.dart';
import '../../core/utils/format_utils.dart';
import '../../core/constants.dart';
import '../../core/widgets/hover_card.dart';

/// Item representing a selected file ready for transmission
class SelectedFileItem {
  final String id;
  final String name;
  final Uint8List bytes;
  final int sizeBytes;
  final String category; // 'pdf', 'photo', 'gif', 'video', 'document', 'other'

  SelectedFileItem({
    required this.id,
    required this.name,
    required this.bytes,
    required this.sizeBytes,
    required this.category,
  });

  static String detectCategory(String filename) {
    final lower = filename.toLowerCase();
    if (lower.endsWith('.pdf')) return 'pdf';
    if (lower.endsWith('.gif')) return 'gif';
    if (lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.bmp') ||
        lower.endsWith('.heic') ||
        lower.endsWith('.svg')) {
      return 'photo';
    }
    if (lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.avi') ||
        lower.endsWith('.mkv') ||
        lower.endsWith('.webm') ||
        lower.endsWith('.wmv')) {
      return 'video';
    }
    if (lower.endsWith('.doc') ||
        lower.endsWith('.docx') ||
        lower.endsWith('.txt') ||
        lower.endsWith('.csv') ||
        lower.endsWith('.xlsx') ||
        lower.endsWith('.xls') ||
        lower.endsWith('.ppt') ||
        lower.endsWith('.pptx') ||
        lower.endsWith('.md') ||
        lower.endsWith('.json') ||
        lower.endsWith('.xml') ||
        lower.endsWith('.rtf')) {
      return 'document';
    }
    return 'other';
  }
}

/// QuickShare Studio — Cross-Platform File Transfer View
/// Connects and transmits any file seamlessly across Windows, Android, macOS, iOS, and Linux.
/// Supports multi-file selection and sending to one or multiple paired recipients.
class SendFilesView extends StatefulWidget {
  final Uint8List? preloadedBytes;
  final String? preloadedName;
  final VoidCallback? onNavigateToPairing;

  const SendFilesView({
    super.key,
    this.preloadedBytes,
    this.preloadedName,
    this.onNavigateToPairing,
  });

  @override
  State<SendFilesView> createState() => _SendFilesViewState();
}

class _SendFilesViewState extends State<SendFilesView> {
  final List<SelectedFileItem> _selectedFiles = [];
  final Set<String> _selectedRecipientIds = {};
  bool _isSending = false;
  String? _errorMessage;
  String? _successMessage;

  // Direct IP connect fields
  final TextEditingController _ipController = TextEditingController();
  final TextEditingController _portController = TextEditingController(text: '8088');
  bool _showDirectConnect = false;
  bool _isProbing = false;

  @override
  void initState() {
    super.initState();
    if (widget.preloadedBytes != null && widget.preloadedName != null) {
      _selectedFiles.add(
        SelectedFileItem(
          id: 'preloaded_${DateTime.now().millisecondsSinceEpoch}',
          name: widget.preloadedName!,
          bytes: widget.preloadedBytes!,
          sizeBytes: widget.preloadedBytes!.length,
          category: SelectedFileItem.detectCategory(widget.preloadedName!),
        ),
      );
    }
  }

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------
  // File Picking Methods
  // -------------------------------------------------------------
  Future<void> _pickPdfFiles() async {
    try {
      final res = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
      if (res.isNotEmpty) {
        for (final f in res) {
          final bytes = await f.readAsBytes();
          _addOrReplaceFile(f.name, bytes, 'pdf');
        }
      }
    } catch (e) {
      setState(() => _errorMessage = 'Failed to load PDF file: $e');
    }
  }

  Future<void> _pickPhotosOrScreenshots() async {
    try {
      final res = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['png', 'jpg', 'jpeg', 'webp', 'bmp', 'heic', 'svg'],
      );
      if (res.isNotEmpty) {
        for (final f in res) {
          final bytes = await f.readAsBytes();
          _addOrReplaceFile(f.name, bytes, 'photo');
        }
      }
    } catch (e) {
      setState(() => _errorMessage = 'Failed to load photo: $e');
    }
  }

  Future<void> _pickGifFiles() async {
    try {
      final res = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['gif'],
      );
      if (res.isNotEmpty) {
        for (final f in res) {
          final bytes = await f.readAsBytes();
          _addOrReplaceFile(f.name, bytes, 'gif');
        }
      }
    } catch (e) {
      setState(() => _errorMessage = 'Failed to load GIF: $e');
    }
  }

  Future<void> _pickVideoFiles() async {
    try {
      final res = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp4', 'mov', 'avi', 'mkv', 'webm', 'wmv'],
      );
      if (res.isNotEmpty) {
        for (final f in res) {
          final bytes = await f.readAsBytes();
          _addOrReplaceFile(f.name, bytes, 'video');
        }
      }
    } catch (e) {
      setState(() => _errorMessage = 'Failed to load video: $e');
    }
  }

  Future<void> _pickDocumentFiles() async {
    try {
      final res = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['doc', 'docx', 'txt', 'csv', 'xlsx', 'xls', 'ppt', 'pptx', 'md', 'json', 'xml', 'rtf'],
      );
      if (res.isNotEmpty) {
        for (final f in res) {
          final bytes = await f.readAsBytes();
          _addOrReplaceFile(f.name, bytes, 'document');
        }
      }
    } catch (e) {
      setState(() => _errorMessage = 'Failed to load document: $e');
    }
  }

  Future<void> _pickAnyFiles() async {
    try {
      final res = await FilePicker.pickFiles(
        type: FileType.any,
      );
      if (res.isNotEmpty) {
        for (final f in res) {
          final bytes = await f.readAsBytes();
          _addOrReplaceFile(f.name, bytes, SelectedFileItem.detectCategory(f.name));
        }
      }
    } catch (e) {
      setState(() => _errorMessage = 'Failed to load file: $e');
    }
  }

  void _addOrReplaceFile(String name, Uint8List bytes, String category) {
    setState(() {
      _selectedFiles.removeWhere((file) => file.name == name);
      _selectedFiles.add(
        SelectedFileItem(
          id: 'file_${DateTime.now().millisecondsSinceEpoch}_${name.hashCode}',
          name: name,
          bytes: bytes,
          sizeBytes: bytes.length,
          category: category,
        ),
      );
      _errorMessage = null;
      _successMessage = null;
    });
  }

  // -------------------------------------------------------------
  // Test Sample File Generators
  // -------------------------------------------------------------
  void _addSampleFile(String type) {
    Uint8List sampleBytes;
    String sampleName;
    String category;

    switch (type) {
      case 'pdf':
        sampleBytes = Uint8List.fromList(List.filled(2048, 42));
        sampleName = 'Research_Report.pdf';
        category = 'pdf';
        break;
      case 'photo':
        sampleBytes = Uint8List.fromList(List.filled(4096, 77));
        sampleName = 'Screenshot_Capture_${DateTime.now().millisecondsSinceEpoch % 1000}.png';
        category = 'photo';
        break;
      case 'gif':
        sampleBytes = Uint8List.fromList(List.filled(1500, 55));
        sampleName = 'Animation_Demo.gif';
        category = 'gif';
        break;
      case 'video':
        sampleBytes = Uint8List.fromList(List.filled(8192, 99));
        sampleName = 'Screen_Recording_${DateTime.now().millisecondsSinceEpoch % 1000}.mp4';
        category = 'video';
        break;
      case 'document':
        sampleBytes = Uint8List.fromList(List.filled(1024, 65));
        sampleName = 'Project_Specs_${DateTime.now().millisecondsSinceEpoch % 1000}.docx';
        category = 'document';
        break;
      default:
        sampleBytes = Uint8List.fromList(List.filled(512, 88));
        sampleName = 'Data_Payload.bin';
        category = 'other';
    }

    _addOrReplaceFile(sampleName, sampleBytes, category);
  }

  // -------------------------------------------------------------
  // Direct IP Probe
  // -------------------------------------------------------------
  Future<void> _probeDirectDevice() async {
    final ip = _ipController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ?? AppConstants.defaultHttpPort;
    if (ip.isEmpty) {
      setState(() => _errorMessage = 'Please enter a target device IP address.');
      return;
    }

    setState(() {
      _isProbing = true;
      _errorMessage = null;
    });

    final crossService = CrossDeviceTransferService();
    final probed = await crossService.probeRemoteDevice(ip, port);
    if (!mounted) return;

    setState(() => _isProbing = false);

    if (probed != null) {
      final engine = context.read<TransferEngine>();
      engine.addPairedDevice(probed);
      setState(() {
        _selectedRecipientIds.add(probed.id);
        _showDirectConnect = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.surfaceElevated,
          content: Text('Connected to "${probed.name}" (${probed.platform ?? "Device"}) at $ip:$port'),
        ),
      );
    } else {
      setState(() {
        _errorMessage = 'Could not reach device at $ip:$port. Ensure QuickShare is active on the target device and both are on the same Wi-Fi / hotspot network.';
      });
    }
  }

  // -------------------------------------------------------------
  // Sending Logic (Single or Multiple Recipients)
  // -------------------------------------------------------------
  Future<void> _sendFilesToSelectedRecipients(TransferEngine engine) async {
    if (_selectedFiles.isEmpty) {
      setState(() => _errorMessage = 'Please select at least one file first.');
      return;
    }

    if (engine.pairedDevices.isEmpty) {
      setState(() => _errorMessage = 'No device is paired. Please pair a device before sending.');
      return;
    }

    if (_selectedRecipientIds.isEmpty) {
      setState(() => _errorMessage = 'Please select at least one connected recipient device.');
      return;
    }

    final targetDevices = engine.pairedDevices
        .where((d) => _selectedRecipientIds.contains(d.id))
        .toList();

    if (targetDevices.isEmpty) {
      setState(() => _errorMessage = 'No valid recipient devices selected.');
      return;
    }

    setState(() {
      _isSending = true;
      _errorMessage = null;
      _successMessage = null;
    });

    int sentCount = 0;
    try {
      for (final file in _selectedFiles) {
        for (final recipient in targetDevices) {
          await engine.sendFileToDevice(
            fileName: file.name,
            bytes: file.bytes,
            recipient: recipient,
          );
          sentCount++;
        }
      }

      if (!mounted) return;
      setState(() {
        _isSending = false;
        _successMessage = 'Dispatched $sentCount transfer(s) across ${targetDevices.length} recipient device(s).';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.charcoalSurface,
          content: Row(
            children: [
              Icon(Icons.check_circle_rounded, color: AppColors.primaryAccent, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Transmitted ${_selectedFiles.length} file(s) to ${targetDevices.length} device(s).',
                  style: TextStyle(fontFamily: 'Poppins', color: AppColors.primaryText, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSending = false;
        _errorMessage = e.toString();
      });
    }
  }

  IconData _getPlatformIcon(String? platform) {
    if (platform == null) return Icons.devices_rounded;
    final lower = platform.toLowerCase();
    if (lower.contains('android')) return Icons.phone_android_rounded;
    if (lower.contains('ios') || lower.contains('iphone')) return Icons.phone_iphone_rounded;
    if (lower.contains('mac') || lower.contains('apple')) return Icons.laptop_mac_rounded;
    if (lower.contains('windows')) return Icons.laptop_windows_rounded;
    if (lower.contains('linux')) return Icons.terminal_rounded;
    return Icons.devices_rounded;
  }

  IconData _getFileIcon(String category) {
    switch (category) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'photo':
        return Icons.image_rounded;
      case 'gif':
        return Icons.gif_box_rounded;
      case 'video':
        return Icons.video_file_rounded;
      case 'document':
        return Icons.description_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
  }

  Color _getFileColor(String category) {
    switch (category) {
      case 'pdf':
        return const Color(0xFFEF4444);
      case 'photo':
        return AppColors.primaryAccent;
      case 'gif':
        return const Color(0xFFA855F7);
      case 'video':
        return const Color(0xFFF97316);
      case 'document':
        return const Color(0xFFFBBF24);
      default:
        return AppColors.primaryAccent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<TransferEngine>();
    final crossService = CrossDeviceTransferService();

    // Auto-select first online device if none currently selected
    if (_selectedRecipientIds.isEmpty && engine.pairedDevices.isNotEmpty) {
      final preferred = engine.pairedDevices.firstWhere((d) => d.isOnline, orElse: () => engine.pairedDevices.first);
      _selectedRecipientIds.add(preferred.id);
    }

    final activeTransfers = engine.activeTransfers;

    return Scaffold(
      backgroundColor: AppColors.dashboardBg,
      appBar: AppBar(
        backgroundColor: AppColors.charcoalSurface,
        elevation: 0,
        title: Text(
          'Send Files',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w700,
            color: AppColors.primaryText,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top Info & Host Device Status Card
                _buildHostDeviceHeader(crossService, engine),
                const SizedBox(height: 20),

                // File Choosers Grid: PDFs, Photos, GIFs, Videos, Documents, Any File
                _buildFilePickersSection(),
                const SizedBox(height: 20),

                // Selected Files Preview List
                if (_selectedFiles.isNotEmpty) ...[
                  _buildSelectedFilesList(),
                  const SizedBox(height: 20),
                ],

                // Connected Recipients Selection List
                _buildRecipientsSection(engine),
                const SizedBox(height: 20),

                // Feedback Banners (Error / Success)
                if (_errorMessage != null) ...[
                  _buildErrorBanner(_errorMessage!),
                  const SizedBox(height: 16),
                ],
                if (_successMessage != null) ...[
                  _buildSuccessBanner(_successMessage!),
                  const SizedBox(height: 16),
                ],

                // Action Button: "Send to Paired Device" or "Send to N Paired Devices"
                _buildSendActionButton(engine),
                const SizedBox(height: 28),

                // Transfer Status & Progress Section (Active, Completed, Cancelled, Failed)
                if (activeTransfers.isNotEmpty) ...[
                  _buildTransferSectionHeader(engine),
                  const SizedBox(height: 10),
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: activeTransfers.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      return _buildTransferStatusCard(activeTransfers[index], engine);
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------
  // Header Widget
  // -------------------------------------------------------------
  Widget _buildHostDeviceHeader(CrossDeviceTransferService crossService, TransferEngine engine) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.charcoalSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.subtleBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.primaryAccent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.hub_rounded, color: AppColors.primaryAccent, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Cross-Platform File Sharing',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: AppColors.primaryText,
                      ),
                    ),
                    Text(
                      'Share files between Windows, Android, macOS, iOS, and Linux on your local Wi-Fi.',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 11.5,
                        color: AppColors.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
              // Ready pill
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.dashboardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.subtleBorder),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: AppColors.statusIndicator,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${crossService.currentPlatformName} Ready',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primaryText,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.cardBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(Icons.wifi_tethering_rounded, color: AppColors.primaryAccent, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Local IP: ${crossService.activeIp} · Port: ${crossService.activePort}',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12,
                      color: AppColors.secondaryText,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Name: ${engine.localDeviceName}',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryText,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // File Choosers Section
  // -------------------------------------------------------------
  Widget _buildFilePickersSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'SELECT FILES TO SEND',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                fontSize: 12,
                color: AppColors.secondaryText,
                letterSpacing: 1.1,
              ),
            ),
            // Quick preset menu for instant testing
            PopupMenuButton<String>(
              color: AppColors.charcoalSurface,
              icon: Icon(Icons.add_circle_outline_rounded, color: AppColors.primaryAccent, size: 18),
              tooltip: 'Add Quick Sample File',
              onSelected: _addSampleFile,
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'pdf',
                  child: Row(
                    children: [
                      Icon(Icons.picture_as_pdf, color: Color(0xFFEF4444), size: 16),
                      SizedBox(width: 8),
                      Text('Sample PDF', style: TextStyle(fontFamily: 'Poppins', color: AppColors.white, fontSize: 12)),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'photo',
                  child: Row(
                    children: [
                      Icon(Icons.image_rounded, color: AppColors.primaryAccent, size: 16),
                      SizedBox(width: 8),
                      Text('Sample Photo / Screenshot', style: TextStyle(fontFamily: 'Poppins', color: AppColors.white, fontSize: 12)),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'gif',
                  child: Row(
                    children: [
                      Icon(Icons.gif_box_rounded, color: Color(0xFFA855F7), size: 16),
                      SizedBox(width: 8),
                      Text('Sample GIF Animation', style: TextStyle(fontFamily: 'Poppins', color: AppColors.white, fontSize: 12)),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'video',
                  child: Row(
                    children: [
                      Icon(Icons.video_file_rounded, color: Color(0xFFF97316), size: 16),
                      SizedBox(width: 8),
                      Text('Sample Video', style: TextStyle(fontFamily: 'Poppins', color: AppColors.white, fontSize: 12)),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'document',
                  child: Row(
                    children: [
                      Icon(Icons.description_rounded, color: Color(0xFFFBBF24), size: 16),
                      SizedBox(width: 8),
                      Text('Sample Document (Word/Text)', style: TextStyle(fontFamily: 'Poppins', color: AppColors.white, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Row 1: PDF, Screenshot/Photo, GIFs
        Row(
          children: [
            Expanded(
              child: _buildPickerCard(
                title: 'PDF File',
                subtitle: 'Documents (.pdf)',
                icon: Icons.picture_as_pdf,
                iconColor: const Color(0xFFEF4444),
                onTap: _pickPdfFiles,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildPickerCard(
                title: 'Photo / Image',
                subtitle: 'PNG, JPG, WebP',
                icon: Icons.add_photo_alternate,
                iconColor: AppColors.primaryAccent,
                onTap: _pickPhotosOrScreenshots,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildPickerCard(
                title: 'GIF Animation',
                subtitle: 'Animated (.gif)',
                icon: Icons.gif_box_rounded,
                iconColor: const Color(0xFFA855F7),
                onTap: _pickGifFiles,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Row 2: Video, Document, Any File
        Row(
          children: [
            Expanded(
              child: _buildPickerCard(
                title: 'Video',
                subtitle: 'MP4, MOV, MKV',
                icon: Icons.video_file_rounded,
                iconColor: const Color(0xFFF97316),
                onTap: _pickVideoFiles,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildPickerCard(
                title: 'Document',
                subtitle: 'DOC, TXT, CSV, MD',
                icon: Icons.description_rounded,
                iconColor: const Color(0xFFFBBF24),
                onTap: _pickDocumentFiles,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildPickerCard(
                title: 'Any File',
                subtitle: 'All platform formats',
                icon: Icons.folder_open_rounded,
                iconColor: AppColors.primaryAccent,
                onTap: _pickAnyFiles,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPickerCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    return HoverCard(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      liftOffset: 1.5,
      scale: 1.01,
      color: AppColors.cardBg,
      borderColor: AppColors.subtleBorder,
      hoverBorderColor: iconColor.withValues(alpha: 0.8),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
              color: AppColors.primaryText,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 10,
              color: AppColors.secondaryText,
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // Selected Files List
  // -------------------------------------------------------------
  Widget _buildSelectedFilesList() {
    final totalBytes = _selectedFiles.fold<int>(0, (sum, f) => sum + f.sizeBytes);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Text(
                  'SELECTED FILES',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    color: AppColors.secondaryText,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.charcoalSurface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.subtleBorder),
                  ),
                  child: Text(
                    '${_selectedFiles.length} (${FormatUtils.formatBytes(totalBytes)})',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primaryAccent,
                    ),
                  ),
                ),
              ],
            ),
            if (_selectedFiles.isNotEmpty)
              TextButton(
                onPressed: () => setState(() => _selectedFiles.clear()),
                style: TextButton.styleFrom(foregroundColor: const Color(0xFFEF4444)),
                child: const Text('Clear All', style: TextStyle(fontFamily: 'Poppins', fontSize: 12)),
              ),
          ],
        ),
        const SizedBox(height: 8),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _selectedFiles.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final file = _selectedFiles[index];
            final color = _getFileColor(file.category);
            final icon = _getFileIcon(file.category);

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.cardBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: color.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: color.withValues(alpha: 0.3)),
                    ),
                    child: Icon(icon, color: color, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          file.name,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w700,
                            fontSize: 13.5,
                            color: AppColors.primaryText,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${FormatUtils.formatBytes(file.sizeBytes)} • ${file.category.toUpperCase()} File',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 11,
                            color: AppColors.secondaryText,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: AppColors.secondaryText, size: 18),
                    tooltip: 'Remove',
                    onPressed: () {
                      setState(() => _selectedFiles.removeAt(index));
                    },
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
  // Recipients Section (One or Multiple Selection)
  // -------------------------------------------------------------
  Widget _buildRecipientsSection(TransferEngine engine) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Row(
                children: [
                  Text(
                    'CONNECTED RECIPIENTS',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      color: AppColors.secondaryText,
                      letterSpacing: 1.1,
                    ),
                  ),
                  if (engine.pairedDevices.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.charcoalSurface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.subtleBorder),
                      ),
                      child: Text(
                        '${_selectedRecipientIds.length}/${engine.pairedDevices.length}',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primaryAccent,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (engine.pairedDevices.length > 1) ...[
                  TextButton(
                    onPressed: () {
                      setState(() {
                        if (_selectedRecipientIds.length == engine.pairedDevices.length) {
                          _selectedRecipientIds.clear();
                        } else {
                          _selectedRecipientIds.clear();
                          _selectedRecipientIds.addAll(engine.pairedDevices.map((d) => d.id));
                        }
                      });
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primaryAccent,
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    ),
                    child: Text(
                      _selectedRecipientIds.length == engine.pairedDevices.length
                          ? 'Deselect All'
                          : 'Select All',
                      style: const TextStyle(fontFamily: 'Poppins', fontSize: 11.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
                TextButton.icon(
                  onPressed: () => setState(() => _showDirectConnect = !_showDirectConnect),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  ),
                  icon: Icon(
                    _showDirectConnect ? Icons.close_rounded : Icons.add_link_rounded,
                    size: 15,
                    color: AppColors.primaryAccent,
                  ),
                  label: Text(
                    _showDirectConnect ? 'Cancel' : 'Direct IP',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 11.5,
                      color: AppColors.primaryAccent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Direct IP input block
        if (_showDirectConnect) ...[
          Container(
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              color: AppColors.charcoalSurface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.primaryAccent.withValues(alpha: 0.4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Connect to Device by IP & Port (Android, Windows, macOS, Linux, iOS)',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                    color: AppColors.primaryText,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _ipController,
                        style: TextStyle(color: AppColors.white, fontSize: 13, fontFamily: 'Poppins'),
                        decoration: InputDecoration(
                          hintText: 'e.g. 192.168.1.45',
                          hintStyle: TextStyle(color: AppColors.white.withValues(alpha: 0.38), fontSize: 12),
                          labelText: 'Remote Device IP',
                          labelStyle: TextStyle(color: AppColors.secondaryText, fontSize: 12),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 1,
                      child: TextField(
                        controller: _portController,
                        keyboardType: TextInputType.number,
                        style: TextStyle(color: AppColors.white, fontSize: 13, fontFamily: 'Poppins'),
                        decoration: InputDecoration(
                          hintText: '8088',
                          labelText: 'Port',
                          labelStyle: TextStyle(color: AppColors.secondaryText, fontSize: 12),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryAccent,
                        foregroundColor: AppColors.nearBlack,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: _isProbing ? null : _probeDirectDevice,
                      child: _isProbing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.nearBlack),
                            )
                          : const Text(
                              'Connect',
                              style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],

        // Paired devices list or clean empty state
        if (engine.pairedDevices.isEmpty)
          HoverCard(
            borderRadius: BorderRadius.circular(16),
            padding: const EdgeInsets.all(18),
            color: AppColors.cardBg,
            borderColor: AppColors.subtleBorder,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.link_off_rounded, color: Colors.orange, size: 22),
                    SizedBox(width: 12),
                    Text(
                      'No paired devices connected',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w600,
                        color: AppColors.primaryText,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                TextButton(
                  onPressed: widget.onNavigateToPairing,
                  child: Text(
                    'Go to Pairing',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      color: AppColors.primaryAccent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: engine.pairedDevices.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final device = engine.pairedDevices[index];
              final isSelected = _selectedRecipientIds.contains(device.id);

              return InkWell(
                onTap: () {
                  setState(() {
                    if (isSelected) {
                      _selectedRecipientIds.remove(device.id);
                    } else {
                      _selectedRecipientIds.add(device.id);
                    }
                  });
                },
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.charcoalSurface : AppColors.cardBg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isSelected ? AppColors.primaryAccent : AppColors.subtleBorder,
                      width: isSelected ? 1.4 : 1.0,
                    ),
                  ),
                  child: Row(
                    children: [
                      // Checkbox
                      Checkbox(
                        value: isSelected,
                        activeColor: AppColors.primaryAccent,
                        checkColor: AppColors.nearBlack,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                        onChanged: (val) {
                          setState(() {
                            if (val == true) {
                              _selectedRecipientIds.add(device.id);
                            } else {
                              _selectedRecipientIds.remove(device.id);
                            }
                          });
                        },
                      ),
                      const SizedBox(width: 8),
                      // Platform Icon
                      Icon(
                        _getPlatformIcon(device.platform),
                        size: 20,
                        color: device.isOnline ? AppColors.primaryAccent : AppColors.secondaryText,
                      ),
                      const SizedBox(width: 12),
                      // Name & Details
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              device.name,
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontWeight: FontWeight.w700,
                                fontSize: 13.5,
                                color: AppColors.primaryText,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${device.platform ?? "Universal"} • ${device.ip}:${device.port}',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 11,
                                color: AppColors.secondaryText,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Online Status Indicator Dot
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.cardBg,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.subtleBorder),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: device.isOnline ? AppColors.statusIndicator : Colors.grey,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              device.isOnline ? 'Online' : 'Offline',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: device.isOnline ? AppColors.statusIndicator : AppColors.secondaryText,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  // -------------------------------------------------------------
  // Feedback Banners
  // -------------------------------------------------------------
  Widget _buildErrorBanner(String message) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.errorContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded, color: Color(0xFFEF4444), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontFamily: 'Poppins',
                color: Color(0xFFFFB4B4),
                fontSize: 12.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessBanner(String message) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.successContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primaryAccent.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle_outline_rounded, color: AppColors.primaryAccent, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontFamily: 'Poppins',
                color: AppColors.primaryAccent,
                fontSize: 12.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // Send Action Button
  // -------------------------------------------------------------
  Widget _buildSendActionButton(TransferEngine engine) {
    final canSend = _selectedFiles.isNotEmpty &&
        engine.pairedDevices.isNotEmpty &&
        _selectedRecipientIds.isNotEmpty &&
        !_isSending;

    // Label formatting: preserve 'Send to Paired Device' when 1 recipient is selected (matches widget tests)
    final recipientCount = _selectedRecipientIds.length;
    final String labelText;
    if (_isSending) {
      labelText = 'Transmitting Files...';
    } else if (recipientCount > 1) {
      labelText = 'Send to $recipientCount Paired Devices';
    } else {
      labelText = 'Send to Paired Device';
    }

    return SizedBox(
      height: 52,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryAccent,
          foregroundColor: AppColors.nearBlack,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 0,
          disabledBackgroundColor: AppColors.primaryAccent.withValues(alpha: 0.35),
        ),
        onPressed: canSend ? () => _sendFilesToSelectedRecipients(engine) : null,
        icon: _isSending
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.nearBlack),
              )
            : const Icon(Icons.send_rounded, size: 20, color: AppColors.nearBlack),
        label: Text(
          labelText,
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w700,
            fontSize: 15,
            color: AppColors.nearBlack,
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------
  // Transfer Status Header & Cards
  // -------------------------------------------------------------
  Widget _buildTransferSectionHeader(TransferEngine engine) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'TRANSFER STATUS & PROGRESS',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w700,
            fontSize: 12,
            color: AppColors.secondaryText,
            letterSpacing: 1.1,
          ),
        ),
        TextButton.icon(
          onPressed: () => engine.clearFinishedTransfers(),
          icon: Icon(Icons.cleaning_services_rounded, size: 14, color: AppColors.secondaryText),
          label: Text(
            'Clear Finished',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 11.5, color: AppColors.secondaryText),
          ),
        ),
      ],
    );
  }

  Widget _buildTransferStatusCard(TransferItem transfer, TransferEngine engine) {
    final isCompleted = transfer.status == TransferStatus.completed;
    final isFailed = transfer.status == TransferStatus.failed;
    final isCancelled = transfer.status == TransferStatus.cancelled;
    final isTransferring = transfer.status == TransferStatus.transferring;

    final statusColor = isCompleted
        ? AppColors.statusIndicator
        : isFailed
            ? const Color(0xFFEF4444)
            : isCancelled
                ? Colors.orange
                : AppColors.primaryAccent;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: statusColor.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(
                      isCompleted
                          ? Icons.check_circle_rounded
                          : isFailed
                              ? Icons.error_rounded
                              : isCancelled
                                  ? Icons.cancel_rounded
                                  : Icons.sync_rounded,
                      color: statusColor,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        transfer.fileName,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
                          color: AppColors.primaryText,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  Text(
                    isCompleted
                        ? 'Delivered'
                        : isFailed
                            ? 'Failed'
                            : isCancelled
                                ? 'Cancelled'
                                : '${(transfer.progress * 100).round()}%',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: statusColor,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Actions: Cancel during transfer, Retry if failed/cancelled, Dismiss
                  if (isTransferring)
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18, color: Colors.orange),
                      tooltip: 'Cancel Transfer',
                      onPressed: () => engine.cancelTransfer(transfer.transferId),
                    )
                  else if (isFailed || isCancelled)
                    IconButton(
                      icon: Icon(Icons.refresh_rounded, size: 18, color: AppColors.primaryAccent),
                      tooltip: 'Retry Transfer',
                      onPressed: () => engine.retryTransfer(transfer.transferId),
                    ),
                  IconButton(
                    icon: Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.secondaryText),
                    tooltip: 'Remove',
                    onPressed: () => engine.removeTransfer(transfer.transferId),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(
            value: isCompleted
                ? 1.0
                : (isFailed || isCancelled)
                    ? transfer.progress
                    : transfer.progress,
            backgroundColor: AppColors.subtleBorder,
            valueColor: AlwaysStoppedAnimation<Color>(statusColor),
            minHeight: 6,
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Recipient: ${transfer.peerDeviceName} • ${FormatUtils.formatBytes((transfer.fileSizeBytes * transfer.progress).round())} / ${FormatUtils.formatBytes(transfer.fileSizeBytes)}',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11.5,
                    color: AppColors.secondaryText,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (transfer.speedBytesPerSec > 0 && isTransferring)
                Text(
                  '${(transfer.speedBytesPerSec / (1024 * 1024)).toStringAsFixed(1)} MB/s',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryAccent,
                  ),
                ),
            ],
          ),
          if ((isFailed || isCancelled) && transfer.errorMessage != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded, color: Color(0xFFEF4444), size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      transfer.errorMessage!,
                      style: const TextStyle(fontFamily: 'Poppins', fontSize: 11, color: Color(0xFFFFB4B4)),
                    ),
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primaryAccent,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    ),
                    onPressed: () => engine.retryTransfer(transfer.transferId),
                    icon: const Icon(Icons.refresh_rounded, size: 15),
                    label: const Text('Retry', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.bold, fontSize: 11.5)),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
