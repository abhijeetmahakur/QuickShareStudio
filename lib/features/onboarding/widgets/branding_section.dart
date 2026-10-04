import 'package:flutter/material.dart';
import '../../../core/constants.dart';
import 'device_illustration_widget.dart';

class BrandingSection extends StatelessWidget {
  final bool isMobile;

  const BrandingSection({
    super.key,
    this.isMobile = false,
  });

  @override
  Widget build(BuildContext context) {
    if (isMobile) {
      return _buildMobileLayout(context);
    }
    return _buildDesktopLayout(context);
  }

  Widget _buildDesktopLayout(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Top Section: Header & Welcome Text
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildAppHeader(),
            const SizedBox(height: 36),
            _buildWelcomeHeadings(fontSize: 38),
            const SizedBox(height: 16),
            Text(
              'Share files across all your devices with speed, security and simplicity.',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 15,
                fontWeight: FontWeight.w400,
                color: AppColors.softGray,
                height: 1.5,
              ),
            ),
          ],
        ),

        // Middle Section: Polished Vector Device Illustration
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24.0),
          child: const DeviceIllustrationWidget(height: 250),
        ),

        // Bottom Section: 3 Glass Feature Indicators
        _buildFeatureIndicators(),
      ],
    );
  }

  Widget _buildMobileLayout(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildAppHeader(),
        const SizedBox(height: 20),
        _buildWelcomeHeadings(fontSize: 28),
        const SizedBox(height: 10),
        Text(
          'Share files across all your devices with speed, security and simplicity.',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: AppColors.softGray,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 16),
        const DeviceIllustrationWidget(height: 180),
        const SizedBox(height: 16),
        _buildFeatureIndicators(wrapOnSmall: true),
      ],
    );
  }

  Widget _buildAppHeader() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Lime-green rounded-square logo
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.limeGreen,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: AppColors.limeGreen.withValues(alpha: 0.35),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Center(
            child: Icon(
              Icons.bolt_rounded,
              size: 26,
              color: AppColors.nearBlack,
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'QuickShare Studio',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.white,
                  letterSpacing: -0.3,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                'Fast · Secure · Everywhere',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: AppColors.softGray.withValues(alpha: 0.8),
                  letterSpacing: 0.2,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );

  }

  Widget _buildWelcomeHeadings({required double fontSize}) {
    return RichText(
      text: TextSpan(
        style: TextStyle(
          fontFamily: 'Poppins',
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          height: 1.15,
          letterSpacing: -0.5,
        ),
        children: [
          TextSpan(
            text: 'Welcome to\n',
            style: TextStyle(color: AppColors.white),
          ),
          TextSpan(
            text: 'QuickShare Studio',
            style: TextStyle(color: AppColors.limeGreen),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureIndicators({bool wrapOnSmall = false}) {
    final items = [
      _FeatureItem(
        icon: Icons.wifi_off_rounded,
        title: 'Local Transfer',
        subtitle: 'Offline capable',
      ),
      _FeatureItem(
        icon: Icons.lock_outline_rounded,
        title: 'Internet Transfer',
        subtitle: 'Secure & encrypted',
      ),
      _FeatureItem(
        icon: Icons.shield_outlined,
        title: 'Your Data',
        subtitle: 'Privacy focused',
      ),
    ];

    if (wrapOnSmall) {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: items.map((item) => _buildFeaturePill(item)).toList(),
      );
    }

    return Row(
      children: items.map((item) {
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: _buildFeatureCard(item),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildFeatureCard(_FeatureItem item) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.glassInputBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.glassBorder, width: 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(item.icon, size: 20, color: AppColors.limeGreen),
          const SizedBox(height: 8),
          Text(
            item.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.white,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            item.subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 11,
              color: AppColors.softGray.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeaturePill(_FeatureItem item) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.glassInputBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.glassBorder, width: 1.0),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(item.icon, size: 16, color: AppColors.limeGreen),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                item.title,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.white,
                ),
              ),
              Text(
                item.subtitle,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 10,
                  color: AppColors.softGray.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FeatureItem {
  final IconData icon;
  final String title;
  final String subtitle;

  _FeatureItem({
    required this.icon,
    required this.title,
    required this.subtitle,
  });
}
