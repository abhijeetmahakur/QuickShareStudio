import 'package:flutter/material.dart';
import '../constants.dart';

class StepProgressIndicator extends StatelessWidget {
  final int currentStep; // 0, 1, 2
  final ValueChanged<int>? onStepTapped;

  const StepProgressIndicator({
    super.key,
    required this.currentStep,
    this.onStepTapped,
  });

  static const List<String> stepLabels = [
    'Device Setup',
    'Choose Avatar',
    'Get Started',
  ];

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Step ${currentStep + 1} of 3: ${stepLabels[currentStep]}',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              for (int i = 0; i < stepLabels.length; i++) ...[
                _buildStepNode(context, i),
                if (i < stepLabels.length - 1) _buildConnector(i),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (int i = 0; i < stepLabels.length; i++)
                Expanded(
                  child: Text(
                    stepLabels[i],
                    textAlign: i == 0
                        ? TextAlign.left
                        : (i == stepLabels.length - 1 ? TextAlign.right : TextAlign.center),
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12,
                      fontWeight: i == currentStep ? FontWeight.w600 : FontWeight.w400,
                      color: i == currentStep
                          ? AppColors.limeGreen
                          : (i < currentStep ? AppColors.white : AppColors.softGray.withValues(alpha: 0.6)),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStepNode(BuildContext context, int index) {
    final isCompleted = index < currentStep;
    final isActive = index == currentStep;
    final canTap = onStepTapped != null && index <= currentStep;

    Color circleBg;
    Color circleBorder;
    Widget content;

    if (isCompleted) {
      circleBg = AppColors.limeGreen.withValues(alpha: 0.2);
      circleBorder = AppColors.limeGreen;
      content = Icon(
        Icons.check_rounded,
        size: 16,
        color: AppColors.limeGreen,
      );
    } else if (isActive) {
      circleBg = AppColors.limeGreen;
      circleBorder = AppColors.limeGreen;
      content = Text(
        '${index + 1}',
        style: const TextStyle(
          fontFamily: 'Poppins',
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: AppColors.nearBlack,
        ),
      );
    } else {
      circleBg = AppColors.overlay.withValues(alpha: 0.10);
      circleBorder = AppColors.glassBorder;
      content = Text(
        '${index + 1}',
        style: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.softGray.withValues(alpha: 0.6),
        ),
      );
    }

    return GestureDetector(
      onTap: canTap ? () => onStepTapped!(index) : null,
      child: MouseRegion(
        cursor: canTap ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: circleBg,
            shape: BoxShape.circle,
            border: Border.all(color: circleBorder, width: isActive ? 2.0 : 1.2),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: AppColors.limeGreen.withValues(alpha: 0.4),
                      blurRadius: 12,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : [],
          ),
          child: Center(child: content),
        ),
      ),
    );
  }

  Widget _buildConnector(int index) {
    final isCompleted = index < currentStep;

    return Expanded(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        height: 2,
        margin: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: isCompleted ? AppColors.limeGreen : AppColors.glassBorder,
          borderRadius: BorderRadius.circular(1),
          boxShadow: isCompleted
              ? [
                  BoxShadow(
                    color: AppColors.limeGreen.withValues(alpha: 0.3),
                    blurRadius: 6,
                  ),
                ]
              : [],
        ),
      ),
    );
  }
}
