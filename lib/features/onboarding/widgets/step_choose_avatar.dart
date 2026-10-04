import 'package:flutter/material.dart';
import '../../../core/constants.dart';
import '../../../core/widgets/lime_button.dart';
import 'avatar_selection_grid.dart';

class StepChooseAvatar extends StatelessWidget {
  final String selectedAvatarId;
  final String? customAvatarPath;
  final ValueChanged<String> onAvatarSelected;
  final ValueChanged<String?> onCustomAvatarChanged;
  final VoidCallback onBack;
  final VoidCallback onContinue;

  const StepChooseAvatar({
    super.key,
    required this.selectedAvatarId,
    this.customAvatarPath,
    required this.onAvatarSelected,
    required this.onCustomAvatarChanged,
    required this.onBack,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Choose your avatar',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: AppColors.white,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Pick an icon or photo that represents your device on the network.',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: AppColors.softGray,
          ),
        ),
        const SizedBox(height: 24),
        AvatarSelectionGrid(
          selectedAvatarId: selectedAvatarId,
          customAvatarPath: customAvatarPath,
          onAvatarSelected: onAvatarSelected,
          onCustomAvatarChanged: onCustomAvatarChanged,
        ),
        const SizedBox(height: 32),
        Row(
          children: [
            Expanded(
              flex: 1,
              child: LimeButton.secondary(
                text: 'Back',
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
                onPressed: onBack,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              flex: 2,
              child: LimeButton(
                text: 'Continue',
                trailingIcon: const Icon(Icons.arrow_forward_rounded, size: 18),
                onPressed: onContinue,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
