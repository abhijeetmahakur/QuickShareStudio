import 'dart:io' show File;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../../../core/constants.dart';
import '../../../core/widgets/lime_button.dart';
import '../models/predefined_avatar.dart';

class StepGetStarted extends StatelessWidget {
  final String deviceName;
  final String selectedAvatarId;
  final String? customAvatarPath;
  final String platform;
  final bool isSaving;
  final String? errorMessage;
  final VoidCallback onBack;
  final VoidCallback onStart;

  const StepGetStarted({
    super.key,
    required this.deviceName,
    required this.selectedAvatarId,
    this.customAvatarPath,
    required this.platform,
    this.isSaving = false,
    this.errorMessage,
    required this.onBack,
    required this.onStart,
  });

  @override
  Widget build(BuildContext context) {
    final avatar = PredefinedAvatar.findById(selectedAvatarId);
    final hasCustomAvatar = selectedAvatarId == 'custom' &&
        customAvatarPath != null &&
        customAvatarPath!.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Large Glowing Avatar Preview
        _buildAvatarPreview(hasCustomAvatar, avatar),
        const SizedBox(height: 20),

        // Device Name Heading
        Text(
          deviceName,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: AppColors.white,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 6),

        // Welcome Tagline
        Text(
          "You're all set!",
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.limeGreen,
          ),
        ),
        const SizedBox(height: 8),

        Text(
          'Your device profile is saved and ready for private, blazing-fast file sharing across all your devices.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 13,
            fontWeight: FontWeight.w400,
            color: AppColors.softGray,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 24),

        // Profile Details Summary Card
        _buildSummaryCard(hasCustomAvatar, avatar),
        const SizedBox(height: 28),

        if (errorMessage != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.error, width: 1.0),
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline_rounded, size: 18, color: AppColors.error),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    errorMessage!,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12,
                      color: AppColors.error,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],

        // Action Buttons Row
        Row(
          children: [
            Expanded(
              flex: 1,
              child: LimeButton.secondary(
                text: 'Back',
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
                onPressed: isSaving ? null : onBack,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              flex: 2,
              child: LimeButton(
                text: 'Start Using QuickShare Studio',
                trailingIcon: const Icon(Icons.bolt_rounded, size: 20),
                isLoading: isSaving,
                onPressed: isSaving ? null : onStart,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAvatarPreview(bool hasCustomAvatar, PredefinedAvatar avatar) {
    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        color: AppColors.cardBg.withValues(alpha: 0.9),
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.limeGreen, width: 3.0),
        boxShadow: [
          BoxShadow(
            color: AppColors.limeGreen.withValues(alpha: 0.4),
            blurRadius: 24,
            spreadRadius: 2,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Center(
        child: hasCustomAvatar
            ? ClipRRect(
                borderRadius: BorderRadius.circular(50),
                child: _buildAvatarImage(customAvatarPath!),
              )
            : Icon(
                avatar.icon,
                size: 48,
                color: AppColors.limeGreen,
              ),
      ),
    );
  }

  Widget _buildAvatarImage(String path) {
    if (kIsWeb || path.startsWith('data:image')) {
      return Icon(Icons.person_rounded, size: 48, color: AppColors.limeGreen);
    }
    final file = File(path);
    if (file.existsSync()) {
      return Image.file(
        file,
        width: 94,
        height: 94,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) =>
            Icon(Icons.person_rounded, size: 48, color: AppColors.limeGreen),
      );
    }
    return Icon(Icons.person_rounded, size: 48, color: AppColors.limeGreen);
  }

  Widget _buildSummaryCard(bool hasCustomAvatar, PredefinedAvatar avatar) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.glassInputBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.glassBorder, width: 1.0),
      ),
      child: Column(
        children: [
          _buildSummaryRow(
            icon: Icons.badge_outlined,
            label: 'Display Name',
            value: deviceName,
          ),
          Divider(color: AppColors.glassBorder, height: 18),
          _buildSummaryRow(
            icon: Icons.face_rounded,
            label: 'Avatar Profile',
            value: hasCustomAvatar ? 'Custom Photo' : avatar.label,
          ),
          Divider(color: AppColors.glassBorder, height: 18),
          _buildSummaryRow(
            icon: Icons.computer_rounded,
            label: 'Platform Detected',
            value: platform.toUpperCase(),
          ),
          Divider(color: AppColors.glassBorder, height: 18),
          _buildSummaryRow(
            icon: Icons.security_rounded,
            label: 'Network Security',
            value: 'Local & Zero-Trust Encrypted',
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: AppColors.limeGreen),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: AppColors.softGray.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.white,
            ),
          ),
        ),
      ],
    );
  }
}
