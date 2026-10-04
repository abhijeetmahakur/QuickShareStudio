import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants.dart';
import '../../../core/widgets/glass_text_field.dart';
import '../../../core/widgets/lime_button.dart';
import '../../../data/models/device_profile.dart';
import '../../../data/services/device_profile_service.dart';
import '../../../data/services/transfer_engine.dart';
import '../../onboarding/widgets/avatar_selection_grid.dart';
import '../../onboarding/models/predefined_avatar.dart';

class EditProfileDialog extends StatefulWidget {
  final DeviceProfile initialProfile;
  final VoidCallback onSaved;

  const EditProfileDialog({
    super.key,
    required this.initialProfile,
    required this.onSaved,
  });

  @override
  State<EditProfileDialog> createState() => _EditProfileDialogState();
}

class _EditProfileDialogState extends State<EditProfileDialog> {
  late final TextEditingController _nameController;
  late String _avatarId;
  String? _customAvatarPath;
  String? _error;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialProfile.displayName);
    _avatarId = widget.initialProfile.avatarId;
    _customAvatarPath = widget.initialProfile.customAvatarPath;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Device name cannot be empty.');
      return;
    }
    if (name.length > 32) {
      setState(() => _error = 'Device name must be 32 characters or fewer.');
      return;
    }

    setState(() {
      _isSaving = true;
      _error = null;
    });

    final updated = widget.initialProfile.copyWith(
      displayName: name,
      avatarId: _avatarId,
      customAvatarPath: _customAvatarPath,
      clearCustomAvatar: _avatarId != 'custom' && _customAvatarPath == null,
    );

    final success = await DeviceProfileService().saveProfile(updated);
    if (!success) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _error = 'Failed to save profile. Please try again.';
        });
      }
      return;
    }

    if (!mounted) return;
    final engine = context.read<TransferEngine>();
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    await engine.setCustomDeviceName(name);
    if (!mounted) return;
    widget.onSaved();
    nav.pop();
    messenger.showSnackBar(
      SnackBar(
        content: Text('Device profile updated successfully!'),
        backgroundColor: AppColors.dashboardBg,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final avatar = PredefinedAvatar.findById(_avatarId);

    return Dialog(
      backgroundColor: AppColors.charcoalSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: AppColors.glassBorder, width: 1.2),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Edit Device Profile',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppColors.white,
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: AppColors.softGray),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GlassTextField(
                        controller: _nameController,
                        label: 'Device Name',
                        prefixIcon: avatar.icon,
                        errorText: _error,
                        onChanged: (_) {
                          if (_error != null) setState(() => _error = null);
                        },
                      ),
                      const SizedBox(height: 20),
                      AvatarSelectionGrid(
                        selectedAvatarId: _avatarId,
                        customAvatarPath: _customAvatarPath,
                        onAvatarSelected: (id) => setState(() => _avatarId = id),
                        onCustomAvatarChanged: (p) => setState(() => _customAvatarPath = p),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  LimeButton.ghost(
                    text: 'Cancel',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 12),
                  LimeButton(
                    text: 'Save Changes',
                    isLoading: _isSaving,
                    onPressed: _save,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
