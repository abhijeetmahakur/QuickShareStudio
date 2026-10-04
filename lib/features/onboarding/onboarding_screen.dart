import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants.dart';
import '../../core/widgets/glass_container.dart';
import '../../core/widgets/step_progress_indicator.dart';
import '../../data/models/device_profile.dart';
import '../../data/services/device_profile_service.dart';
import '../../data/services/transfer_engine.dart';
import 'models/predefined_avatar.dart';
import 'widgets/branding_section.dart';
import 'widgets/step_device_name.dart';
import 'widgets/step_choose_avatar.dart';
import 'widgets/step_get_started.dart';

class OnboardingScreen extends StatefulWidget {
  final VoidCallback onComplete;
  final DeviceProfile? initialProfile;

  const OnboardingScreen({
    super.key,
    required this.onComplete,
    this.initialProfile,
  });

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _currentStep = 0; // 0: Device Setup, 1: Choose Avatar, 2: Get Started
  late final TextEditingController _deviceNameController;
  String _selectedAvatarId = 'laptop';
  String? _customAvatarPath;
  String? _nameError;
  bool _isSaving = false;
  String? _saveErrorMessage;
  late final String _platform;

  @override
  void initState() {
    super.initState();
    _platform = DeviceProfileService.detectPlatform();

    final profile = widget.initialProfile;
    final initialName = profile?.displayName ?? DeviceProfileService.getDefaultDeviceName();
    _selectedAvatarId = profile?.avatarId ?? DeviceProfileService.getDefaultAvatarId();
    _customAvatarPath = profile?.customAvatarPath;

    _deviceNameController = TextEditingController(text: initialName);
  }

  @override
  void dispose() {
    _deviceNameController.dispose();
    super.dispose();
  }

  void _validateAndProceedToStepTwo() {
    final rawName = _deviceNameController.text.trim();
    if (rawName.isEmpty) {
      setState(() {
        _nameError = 'Device name cannot be empty.';
      });
      return;
    }
    if (rawName.length > 32) {
      setState(() {
        _nameError = 'Device name must be 32 characters or fewer.';
      });
      return;
    }
    // Reject strings with only symbols or control chars
    if (RegExp(r'^[\x00-\x1F\x7F]+$').hasMatch(rawName)) {
      setState(() {
        _nameError = 'Device name contains invalid characters.';
      });
      return;
    }

    setState(() {
      _nameError = null;
      _currentStep = 1;
    });
  }

  void _proceedToStepThree() {
    setState(() {
      _currentStep = 2;
    });
  }

  Future<void> _completeOnboarding() async {
    setState(() {
      _isSaving = true;
      _saveErrorMessage = null;
    });

    try {
      final name = _deviceNameController.text.trim();
      final profile = DeviceProfile(
        id: widget.initialProfile?.id,
        displayName: name,
        avatarId: _selectedAvatarId,
        customAvatarPath: _customAvatarPath,
        platform: _platform,
        createdAt: widget.initialProfile?.createdAt,
        isOnboardingComplete: true,
      );

      final success = await DeviceProfileService().completeOnboarding(profile);
      if (!success) {
        setState(() {
          _isSaving = false;
          _saveErrorMessage = 'Failed to persist device profile. Please try again.';
        });
        return;
      }

      // Sync name with TransferEngine so pairing and networking immediately reflect the new identity
      if (mounted) {
        final engine = context.read<TransferEngine>();
        await engine.setCustomDeviceName(name);
      }

      if (mounted) {
        setState(() => _isSaving = false);
        widget.onComplete();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _saveErrorMessage = 'An unexpected error occurred: $e';
        });
      }
    }

  }

  IconData _getDeviceIcon() {
    final avatar = PredefinedAvatar.findById(_selectedAvatarId);
    return avatar.icon;
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final isDesktop = media.size.width >= 960;
    final isTablet = media.size.width >= 600 && media.size.width < 960;

    return Scaffold(
      backgroundColor: AppColors.dashboardBg,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          color: AppColors.dashboardBg,
          gradient: RadialGradient(
            center: const Alignment(-0.8, -0.7),
            radius: 1.3,
            colors: [
              AppColors.limeGreen.withValues(alpha: 0.16), // Subtle lime reflection
              AppColors.limeGreen.withValues(alpha: 0.08),
              AppColors.dashboardBg,
            ],
            stops: const [0.0, 0.35, 1.0],
          ),
        ),
        child: SafeArea(
          child: isDesktop
              ? _buildDesktopLayout(context)
              : (isTablet ? _buildTabletLayout(context) : _buildMobileLayout(context)),
        ),
      ),
    );
  }

  Widget _buildDesktopLayout(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1200),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40.0, vertical: 32.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Left Branding Section
              const Expanded(
                flex: 5,
                child: Padding(
                  padding: EdgeInsets.only(right: 48.0),
                  child: BrandingSection(),
                ),
              ),

              // Right Setup Panel (Liquid Glass Card)
              Expanded(
                flex: 6,
                child: Center(
                  child: _buildSetupCard(context, maxHeight: 720),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabletLayout(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 24.0),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const BrandingSection(isMobile: true),
              const SizedBox(height: 28),
              _buildSetupCard(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMobileLayout(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 18.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const BrandingSection(isMobile: true),
          const SizedBox(height: 20),
          _buildSetupCard(context),
        ],
      ),
    );
  }

  Widget _buildSetupCard(BuildContext context, {double? maxHeight}) {
    return GlassContainer(
      borderRadius: 28,
      blur: 24,
      surfaceColor: AppColors.charcoalSurface.withValues(alpha: 0.9),
      borderColor: AppColors.glassBorder,
      borderWidth: 1.2,
      enableGlow: true,
      glowColor: AppColors.limeGreen,
      glowRadius: 28,
      padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 28.0),
      constraints: BoxConstraints(
        maxWidth: 580,
        maxHeight: maxHeight ?? double.infinity,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Three-step Progress Indicator
          StepProgressIndicator(
            currentStep: _currentStep,
            onStepTapped: (target) {
              if (target < _currentStep) {
                setState(() => _currentStep = target);
              } else if (target == 1 && _currentStep == 0) {
                _validateAndProceedToStepTwo();
              }
            },
          ),
          const SizedBox(height: 28),

          // Step Content with smooth AnimatedSwitcher and internal scrolling
          if (maxHeight != null)
            Flexible(
              child: SingleChildScrollView(
                child: _buildAnimatedStepContent(context),
              ),
            )
          else
            _buildAnimatedStepContent(context),
        ],
      ),
    );
  }

  Widget _buildAnimatedStepContent(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.04, 0),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      child: _buildCurrentStepContent(context),
    );
  }


  Widget _buildCurrentStepContent(BuildContext context) {
    switch (_currentStep) {
      case 0:
        return StepDeviceName(
          key: const ValueKey('step_0_device_name'),
          controller: _deviceNameController,
          errorText: _nameError,
          deviceIcon: _getDeviceIcon(),
          onChanged: (_) {
            if (_nameError != null) {
              setState(() => _nameError = null);
            }
          },
          onContinue: _validateAndProceedToStepTwo,
        );

      case 1:
        return StepChooseAvatar(
          key: const ValueKey('step_1_choose_avatar'),
          selectedAvatarId: _selectedAvatarId,
          customAvatarPath: _customAvatarPath,
          onAvatarSelected: (id) => setState(() => _selectedAvatarId = id),
          onCustomAvatarChanged: (path) => setState(() => _customAvatarPath = path),
          onBack: () => setState(() => _currentStep = 0),
          onContinue: _proceedToStepThree,
        );

      case 2:
      default:
        return StepGetStarted(
          key: const ValueKey('step_2_get_started'),
          deviceName: _deviceNameController.text.trim(),
          selectedAvatarId: _selectedAvatarId,
          customAvatarPath: _customAvatarPath,
          platform: _platform,
          isSaving: _isSaving,
          errorMessage: _saveErrorMessage,
          onBack: () => setState(() => _currentStep = 1),
          onStart: _completeOnboarding,
        );
    }
  }
}
