import 'package:flutter/material.dart';
import '../../../core/constants.dart';
import '../../../core/widgets/glass_text_field.dart';
import '../../../core/widgets/lime_button.dart';

class StepDeviceName extends StatelessWidget {
  final TextEditingController controller;
  final String? errorText;
  final IconData deviceIcon;
  final ValueChanged<String> onChanged;
  final VoidCallback onContinue;

  const StepDeviceName({
    super.key,
    required this.controller,
    this.errorText,
    this.deviceIcon = Icons.laptop_mac_rounded,
    required this.onChanged,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Set up your device',
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
          'Give your device a name and personality.',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: AppColors.softGray,
          ),
        ),
        const SizedBox(height: 28),
        GlassTextField(
          controller: controller,
          label: 'Device Name',
          hintText: 'My Laptop',
          helperText: 'This name will be visible to other devices.',
          errorText: errorText,
          prefixIcon: deviceIcon,
          maxLength: 32,
          onChanged: onChanged,
          onSubmitted: onContinue,
        ),
        const SizedBox(height: 36),
        SizedBox(
          width: double.infinity,
          child: LimeButton(
            text: 'Continue',
            trailingIcon: const Icon(Icons.arrow_forward_rounded, size: 18),
            onPressed: onContinue,
          ),
        ),
      ],
    );
  }
}
