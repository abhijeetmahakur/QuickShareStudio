import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/constants.dart';

class DeviceIllustrationWidget extends StatelessWidget {
  final double height;

  const DeviceIllustrationWidget({
    super.key,
    this.height = 280,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;

          return Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              // Radial lime ambient illumination
              Positioned(
                top: h * 0.15,
                left: w * 0.2,
                right: w * 0.2,
                bottom: h * 0.15,
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.limeGreen.withValues(alpha: 0.12),
                        blurRadius: 70,
                        spreadRadius: 20,
                      ),
                    ],
                  ),
                ),
              ),

              // Glowing connection lines painter
              CustomPaint(
                size: Size(w, h),
                painter: _DeviceConnectionPainter(),
              ),

              // Central Laptop
              Positioned(
                bottom: h * 0.12,
                child: _buildLaptop(w * 0.52, h * 0.58),
              ),

              // Left Smartphone
              Positioned(
                left: math.max(10, w * 0.08),
                bottom: h * 0.18,
                child: _buildSmartphone(w * 0.22, h * 0.52),
              ),

              // Right Tablet
              Positioned(
                right: math.max(10, w * 0.08),
                bottom: h * 0.22,
                child: _buildTablet(w * 0.26, h * 0.50),
              ),

              // Floating Document Bubble
              Positioned(
                top: h * 0.06,
                left: w * 0.30,
                child: _buildFloatingIconBubble(
                  Icons.description_rounded,
                  AppColors.limeGreen,
                  'PDF Document',
                ),
              ),

              // Floating Image / Media Bubble
              Positioned(
                top: h * 0.14,
                right: w * 0.24,
                child: _buildFloatingIconBubble(
                  Icons.photo_library_rounded,
                  AppColors.white,
                  'Media Share',
                ),
              ),

              // Floating Lock / Security Bubble
              Positioned(
                bottom: h * 0.02,
                right: w * 0.38,
                child: _buildFloatingIconBubble(
                  Icons.lock_outline_rounded,
                  AppColors.limeGreen,
                  'Encrypted',
                  mini: true,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildLaptop(double width, double height) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Laptop Screen
        Container(
          width: width,
          height: height * 0.72,
          decoration: BoxDecoration(
            color: AppColors.dashboardBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.glassBorder, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.6),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.dashboardBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppColors.limeGreen.withValues(alpha: 0.2),
                  width: 0.8,
                ),
              ),
              child: Stack(
                children: [
                  // Top bar dots
                  Positioned(
                    top: 6,
                    left: 8,
                    child: Row(
                      children: [
                        _buildDot(AppColors.error.withValues(alpha: 0.8)),
                        const SizedBox(width: 4),
                        _buildDot(AppColors.warning.withValues(alpha: 0.8)),
                        const SizedBox(width: 4),
                        _buildDot(AppColors.limeGreen.withValues(alpha: 0.8)),
                      ],
                    ),
                  ),
                  // Center file transfer illustration
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.limeGreen.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppColors.limeGreen.withValues(alpha: 0.35),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.bolt_rounded,
                            size: 14,
                            color: AppColors.limeGreen,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              width > 220 ? 'QuickShare' : 'Active',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: AppColors.white,
                              ),
                            ),
                          ),
                        ],
                      ),

                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Laptop Base
        Container(
          width: width * 1.25,
          height: 8,
          decoration: BoxDecoration(
            color: AppColors.surfaceElevated,
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(6)),
            border: Border.all(color: AppColors.glassBorder, width: 0.8),
          ),
        ),
      ],
    );
  }

  Widget _buildSmartphone(double width, double height) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.dashboardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.glassBorder, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(5.0),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.dashboardBg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Dynamic island / notch
              Container(
                margin: const EdgeInsets.only(top: 6),
                width: 24,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.subtleBorderLight,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Screen content
              Icon(
                Icons.phone_android_rounded,
                size: 24,
                color: AppColors.limeGreen.withValues(alpha: 0.8),
              ),
              // Home indicator
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                width: 20,
                height: 3,
                decoration: BoxDecoration(
                  color: AppColors.softGray.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(1.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTablet(double width, double height) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.dashboardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.glassBorder, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(6.0),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.dashboardBg,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Center(
            child: Icon(
              Icons.tablet_mac_rounded,
              size: 30,
              color: AppColors.white.withValues(alpha: 0.7),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFloatingIconBubble(
    IconData icon,
    Color color,
    String tooltip, {
    bool mini = false,
  }) {
    final size = mini ? 32.0 : 40.0;
    final iconSize = mini ? 16.0 : 20.0;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.cardBg.withValues(alpha: 0.9),
        shape: BoxShape.circle,
        border: Border.all(
          color: color.withValues(alpha: 0.4),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.25),
            blurRadius: 12,
            spreadRadius: -1,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Center(
        child: Icon(icon, size: iconSize, color: color),
      ),
    );
  }

  Widget _buildDot(Color color) {
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }
}

class _DeviceConnectionPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.limeGreen.withValues(alpha: 0.45)
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;

    final glowPaint = Paint()
      ..color = AppColors.limeGreen.withValues(alpha: 0.15)
      ..strokeWidth = 4.0
      ..style = PaintingStyle.stroke;

    final p1 = Offset(size.width * 0.22, size.height * 0.55);
    final p2 = Offset(size.width * 0.50, size.height * 0.48);
    final p3 = Offset(size.width * 0.78, size.height * 0.52);

    // Left phone to laptop curve
    final path1 = Path()
      ..moveTo(p1.dx, p1.dy)
      ..quadraticBezierTo(
        (p1.dx + p2.dx) / 2,
        p1.dy - 35,
        p2.dx,
        p2.dy,
      );

    // Laptop to right tablet curve
    final path2 = Path()
      ..moveTo(p2.dx, p2.dy)
      ..quadraticBezierTo(
        (p2.dx + p3.dx) / 2,
        p2.dy - 30,
        p3.dx,
        p3.dy,
      );

    canvas.drawPath(path1, glowPaint);
    canvas.drawPath(path1, paint);

    canvas.drawPath(path2, glowPaint);
    canvas.drawPath(path2, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
