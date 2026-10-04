import 'dart:io' show File;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../../../core/constants.dart';
import '../../../data/services/device_profile_service.dart';
import '../models/predefined_avatar.dart';

class AvatarSelectionGrid extends StatefulWidget {
  final String selectedAvatarId;
  final String? customAvatarPath;
  final ValueChanged<String> onAvatarSelected;
  final ValueChanged<String?> onCustomAvatarChanged;

  const AvatarSelectionGrid({
    super.key,
    required this.selectedAvatarId,
    this.customAvatarPath,
    required this.onAvatarSelected,
    required this.onCustomAvatarChanged,
  });

  @override
  State<AvatarSelectionGrid> createState() => _AvatarSelectionGridState();
}

class _AvatarSelectionGridState extends State<AvatarSelectionGrid> {
  bool _isUploading = false;
  String? _uploadError;

  Future<void> _pickCustomAvatar() async {
    setState(() {
      _isUploading = true;
      _uploadError = null;
    });

    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['png', 'jpg', 'jpeg', 'webp'],
      );

      if (result.isEmpty) {
        setState(() => _isUploading = false);
        return;
      }

      final file = result.first;
      final fileBytes = await file.readAsBytes();
      final error = DeviceProfileService.validateCustomAvatar(
        byteLength: fileBytes.length,
        fileName: file.name,
      );

      if (error != null) {
        setState(() {
          _uploadError = error;
          _isUploading = false;
        });
        return;
      }

      final savedPath = await DeviceProfileService().persistCustomAvatar(
        originalFileName: file.name,
        bytes: fileBytes,
        sourcePath: file.path,
      );


      if (savedPath != null) {
        widget.onCustomAvatarChanged(savedPath);
        widget.onAvatarSelected('custom');
      } else {
        setState(() {
          _uploadError = 'Failed to save avatar image to local storage.';
        });
      }
    } catch (e) {
      setState(() {
        _uploadError = 'Error selecting file: $e';
      });
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  void _removeCustomAvatar() {
    widget.onCustomAvatarChanged(null);
    if (widget.selectedAvatarId == 'custom') {
      widget.onAvatarSelected('laptop');
    }
    setState(() {
      _uploadError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasCustomAvatar = widget.customAvatarPath != null && widget.customAvatarPath!.isNotEmpty;
    final isCustomSelected = widget.selectedAvatarId == 'custom' && hasCustomAvatar;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Choose an avatar',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.white,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            // Adaptive columns: 4 on wider widths, 3 on smaller
            final cols = constraints.maxWidth >= 380 ? 4 : 3;
            const spacing = 12.0;

            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: PredefinedAvatar.all.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                crossAxisSpacing: spacing,
                mainAxisSpacing: spacing,
                childAspectRatio: 1.0,
              ),
              itemBuilder: (context, index) {
                final avatar = PredefinedAvatar.all[index];
                final isSelected = widget.selectedAvatarId == avatar.id;

                return _AvatarCircleItem(
                  avatar: avatar,
                  isSelected: isSelected,
                  onTap: () {
                    widget.onAvatarSelected(avatar.id);
                  },
                );
              },
            );
          },
        ),
        const SizedBox(height: 16),

        // Custom Avatar Upload Row
        _buildCustomUploadRow(context, hasCustomAvatar, isCustomSelected),

        if (_uploadError != null) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.error_outline_rounded, size: 14, color: AppColors.error),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _uploadError!,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    color: AppColors.error,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildCustomUploadRow(
    BuildContext context,
    bool hasCustomAvatar,
    bool isCustomSelected,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: isCustomSelected
            ? AppColors.limeGreen.withValues(alpha: 0.08)
            : AppColors.glassInputBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isCustomSelected ? AppColors.limeGreen : AppColors.glassBorder,
          width: isCustomSelected ? 1.8 : 1.0,
        ),
        boxShadow: isCustomSelected
            ? [
                BoxShadow(
                  color: AppColors.limeGreen.withValues(alpha: 0.2),
                  blurRadius: 12,
                  offset: const Offset(0, 2),
                ),
              ]
            : [],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: _isUploading
              ? null
              : () {
                  if (hasCustomAvatar) {
                    widget.onAvatarSelected('custom');
                  } else {
                    _pickCustomAvatar();
                  }
                },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                // Avatar preview or image icon
                if (hasCustomAvatar) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.overlay.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isCustomSelected ? AppColors.limeGreen : AppColors.glassBorder,
                          width: 1.5,
                        ),
                      ),
                      child: _buildAvatarImage(widget.customAvatarPath!),
                    ),
                  ),
                ] else ...[
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.overlay.withValues(alpha: 0.08),
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.glassBorder),
                    ),
                    child: Icon(
                      Icons.image_outlined,
                      size: 22,
                      color: AppColors.white,
                    ),
                  ),
                ],
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Text(
                            hasCustomAvatar ? 'Custom Avatar Selected' : 'Upload Custom Avatar',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: isCustomSelected ? AppColors.limeGreen : AppColors.white,
                            ),
                          ),
                          if (isCustomSelected) ...[
                            const SizedBox(width: 6),
                            Icon(
                              Icons.check_circle_rounded,
                              size: 16,
                              color: AppColors.limeGreen,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        hasCustomAvatar
                            ? 'Tap to select · PNG, JPG, WebP'
                            : 'Personalize with your own photo · max 5 MB',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 12,
                          color: AppColors.softGray.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_isUploading) ...[
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(AppColors.limeGreen),
                    ),
                  ),
                ] else if (hasCustomAvatar) ...[
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    color: AppColors.softGray,
                    tooltip: 'Change image',
                    onPressed: _pickCustomAvatar,
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    color: AppColors.error,
                    tooltip: 'Remove custom avatar',
                    onPressed: _removeCustomAvatar,
                  ),
                ] else ...[
                  Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.softGray,
                    size: 22,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAvatarImage(String path) {
    if (kIsWeb || path.startsWith('data:image')) {
      return Icon(Icons.person_rounded, size: 24, color: AppColors.limeGreen);
    }
    final file = File(path);
    if (file.existsSync()) {
      return Image.file(
        file,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) =>
            Icon(Icons.person_rounded, size: 24, color: AppColors.limeGreen),
      );
    }
    return Icon(Icons.person_rounded, size: 24, color: AppColors.limeGreen);
  }
}

class _AvatarCircleItem extends StatefulWidget {
  final PredefinedAvatar avatar;
  final bool isSelected;
  final VoidCallback onTap;

  const _AvatarCircleItem({
    required this.avatar,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_AvatarCircleItem> createState() => _AvatarCircleItemState();
}

class _AvatarCircleItemState extends State<_AvatarCircleItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final borderColor = widget.isSelected
        ? AppColors.limeGreen
        : (_isHovered ? AppColors.limeGreen.withValues(alpha: 0.6) : AppColors.glassBorder);

    final bgColor = widget.isSelected
        ? AppColors.limeGreen.withValues(alpha: 0.16)
        : (_isHovered ? AppColors.overlay.withValues(alpha: 0.18) : AppColors.overlay.withValues(alpha: 0.10));

    return Tooltip(
      message: widget.avatar.label,
      waitDuration: const Duration(milliseconds: 400),
      child: Semantics(
        button: true,
        selected: widget.isSelected,
        label: widget.avatar.label,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: GestureDetector(
            onTap: widget.onTap,
            child: AnimatedScale(
              scale: widget.isSelected ? 1.05 : (_isHovered ? 1.03 : 1.0),
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    decoration: BoxDecoration(
                      color: bgColor,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: borderColor,
                        width: widget.isSelected ? 2.5 : 1.2,
                      ),
                      boxShadow: widget.isSelected
                          ? [
                              BoxShadow(
                                color: AppColors.limeGreen.withValues(alpha: 0.35),
                                blurRadius: 14,
                                spreadRadius: -1,
                              ),
                            ]
                          : (_isHovered
                              ? [
                                  BoxShadow(
                                    color: AppColors.white.withValues(alpha: 0.1),
                                    blurRadius: 8,
                                  ),
                                ]
                              : []),
                    ),
                    child: Center(
                      child: Icon(
                        widget.avatar.icon,
                        size: 28,
                        color: widget.isSelected ? AppColors.limeGreen : AppColors.white,
                      ),
                    ),
                  ),
                  if (widget.isSelected)
                    Positioned(
                      top: 2,
                      right: 2,
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: AppColors.limeGreen,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.check_rounded,
                          size: 13,
                          color: AppColors.nearBlack,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
