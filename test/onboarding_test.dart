import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:quickshare/main.dart';
import 'package:quickshare/data/models/device_profile.dart';
import 'package:quickshare/data/services/device_profile_service.dart';
import 'package:quickshare/data/services/transfer_engine.dart';
import 'package:quickshare/data/services/app_update_service.dart';
import 'package:quickshare/features/onboarding/models/predefined_avatar.dart';
import 'package:quickshare/features/onboarding/onboarding_screen.dart';
import 'package:quickshare/features/onboarding/widgets/step_device_name.dart';
import 'package:quickshare/features/onboarding/widgets/step_choose_avatar.dart';
import 'package:quickshare/features/onboarding/widgets/step_get_started.dart';
import 'package:quickshare/features/security/widgets/edit_profile_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('A. DeviceProfile Model & Serialization Tests', () {
    test('DeviceProfile correctly serializes and deserializes from JSON', () {
      final now = DateTime.now();
      final profile = DeviceProfile(
        id: 'test-device-uuid-1234',
        displayName: 'My Workstation Alpha',
        avatarId: 'robot',
        customAvatarPath: null,
        platform: 'windows',
        createdAt: now,
        updatedAt: now,
        isOnboardingComplete: true,
      );

      final jsonString = profile.toJson();
      final deserialized = DeviceProfile.fromJson(jsonString);

      expect(deserialized.id, 'test-device-uuid-1234');
      expect(deserialized.displayName, 'My Workstation Alpha');
      expect(deserialized.avatarId, 'robot');
      expect(deserialized.customAvatarPath, isNull);
      expect(deserialized.platform, 'windows');
      expect(deserialized.isOnboardingComplete, isTrue);
      expect(deserialized.isCustomAvatar, isFalse);
    });

    test('DeviceProfile copyWith modifies fields and updates timestamp', () {
      final profile = DeviceProfile(
        displayName: 'Initial Name',
        avatarId: 'laptop',
      );

      final updated = profile.copyWith(
        displayName: 'Updated Name',
        avatarId: 'cat',
        isOnboardingComplete: true,
      );

      expect(updated.id, profile.id); // Stable internal identity
      expect(updated.displayName, 'Updated Name');
      expect(updated.avatarId, 'cat');
      expect(updated.isOnboardingComplete, isTrue);
    });

    test('DeviceProfile isCustomAvatar reports true only when custom and path set', () {
      final p1 = DeviceProfile(displayName: 'Test', avatarId: 'laptop');
      expect(p1.isCustomAvatar, isFalse);

      final p2 = DeviceProfile(
        displayName: 'Test',
        avatarId: 'custom',
        customAvatarPath: '/path/to/avatar.png',
      );
      expect(p2.isCustomAvatar, isTrue);
    });
  });

  group('B. DeviceProfileService Logic & Validation Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('Default device naming and avatar matching host platform', () {
      final defaultName = DeviceProfileService.getDefaultDeviceName();
      expect(defaultName, isNotEmpty);

      final defaultAvatar = DeviceProfileService.getDefaultAvatarId();
      expect(defaultAvatar, isNotEmpty);
      expect(PredefinedAvatar.findById(defaultAvatar).id, defaultAvatar);
    });

    test('Custom avatar validation enforces 5 MB limit and valid file extensions', () {
      // Valid PNG (2 MB)
      final validPng = DeviceProfileService.validateCustomAvatar(
        byteLength: 2 * 1024 * 1024,
        fileName: 'avatar.png',
      );
      expect(validPng, isNull);

      // Valid WebP
      final validWebp = DeviceProfileService.validateCustomAvatar(
        byteLength: 500 * 1024,
        fileName: 'photo.webp',
      );
      expect(validWebp, isNull);

      // Oversized (> 5 MB)
      final oversized = DeviceProfileService.validateCustomAvatar(
        byteLength: 6 * 1024 * 1024,
        fileName: 'large.jpg',
      );
      expect(oversized, contains('exceeds the 5 MB limit'));

      // Unsupported extension
      final badExt = DeviceProfileService.validateCustomAvatar(
        byteLength: 1024,
        fileName: 'script.exe',
      );
      expect(badExt, contains('Unsupported format'));
    });

    test('PredefinedAvatar collection contains all 12 required options', () {
      expect(PredefinedAvatar.all.length, 12);
      final ids = PredefinedAvatar.all.map((a) => a.id).toSet();
      expect(ids.contains('laptop'), isTrue);
      expect(ids.contains('desktop'), isTrue);
      expect(ids.contains('smartphone'), isTrue);
      expect(ids.contains('tablet'), isTrue);
      expect(ids.contains('game_controller'), isTrue);
      expect(ids.contains('headphones'), isTrue);
      expect(ids.contains('robot'), isTrue);
      expect(ids.contains('futuristic_robot'), isTrue);
      expect(ids.contains('fox'), isTrue);
      expect(ids.contains('cat'), isTrue);
      expect(ids.contains('leaf'), isTrue);
      expect(ids.contains('default_person'), isTrue);
    });

    test('DeviceProfileService persistence lifecycle (save, load, complete, reset)', () async {
      final service = DeviceProfileService();

      // Fresh install check
      final initialComplete = await service.hasCompletedOnboarding();
      expect(initialComplete, isFalse);

      final initialProfile = await service.loadProfile();
      expect(initialProfile.displayName, isNotEmpty);
      expect(initialProfile.isOnboardingComplete, isFalse);

      // Complete onboarding
      final saved = await service.completeOnboarding(
        initialProfile.copyWith(displayName: 'Enterprise Workstation'),
      );
      expect(saved, isTrue);

      final completedCheck = await service.hasCompletedOnboarding();
      expect(completedCheck, isTrue);

      final loaded = await service.loadProfile();
      expect(loaded.displayName, 'Enterprise Workstation');
      expect(loaded.isOnboardingComplete, isTrue);

      // Reset onboarding
      final resetSuccess = await service.resetOnboarding();
      expect(resetSuccess, isTrue);

      final afterResetCheck = await service.hasCompletedOnboarding();
      expect(afterResetCheck, isFalse);
    });
  });

  group('C. Onboarding Flow & Step Navigation Widget Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('Step 1: Validates empty and valid device name input', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = TextEditingController(text: 'Initial PC');
      String? currentError;
      bool continued = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return StepDeviceName(
                  controller: controller,
                  errorText: currentError,
                  onChanged: (_) {},
                  onContinue: () {
                    final text = controller.text.trim();
                    if (text.isEmpty) {
                      setState(() => currentError = 'Device name cannot be empty.');
                    } else {
                      continued = true;
                    }
                  },
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Set up your device'), findsOneWidget);
      expect(find.text('Device Name'), findsOneWidget);

      // Test empty input validation
      controller.clear();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.text('Device name cannot be empty.'), findsOneWidget);
      expect(continued, isFalse);

      // Test valid input
      controller.text = 'My Production PC';
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(continued, isTrue);
    });

    testWidgets('Step 2: Displays avatar grid and allows selecting avatar', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      String selectedAvatar = 'laptop';
      String? customPath;
      bool backClicked = false;
      bool continueClicked = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: StatefulBuilder(
                builder: (context, setState) {
                  return StepChooseAvatar(
                    selectedAvatarId: selectedAvatar,
                    customAvatarPath: customPath,
                    onAvatarSelected: (id) => setState(() => selectedAvatar = id),
                    onCustomAvatarChanged: (p) => setState(() => customPath = p),
                    onBack: () => backClicked = true,
                    onContinue: () => continueClicked = true,
                  );
                },
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Choose your avatar'), findsOneWidget);
      expect(find.text('Upload Custom Avatar'), findsOneWidget);

      // Tap on Robot avatar
      final robotFinder = find.byTooltip('Robot');
      expect(robotFinder, findsOneWidget);
      await tester.tap(robotFinder);
      await tester.pumpAndSettle();

      expect(selectedAvatar, 'robot');

      // Test buttons
      await tester.ensureVisible(find.text('Back'));
      await tester.tap(find.text('Back'));
      expect(backClicked, isTrue);

      await tester.ensureVisible(find.text('Continue'));
      await tester.tap(find.text('Continue'));
      expect(continueClicked, isTrue);
    });

    testWidgets('Step 3: Confirmation summary and start button', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      bool started = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: StepGetStarted(
                deviceName: 'Studio Workstation 99',
                selectedAvatarId: 'laptop',
                customAvatarPath: null,
                platform: 'windows',
                onBack: () {},
                onStart: () => started = true,
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Studio Workstation 99'), findsWidgets);
      expect(find.text("You're all set!"), findsOneWidget);
      expect(find.text('Start Using QuickShare Studio'), findsOneWidget);

      await tester.ensureVisible(find.text('Start Using QuickShare Studio'));
      await tester.tap(find.text('Start Using QuickShare Studio'));
      expect(started, isTrue);
    });


  });

  group('D. Complete OnboardingScreen Responsive Integration Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('OnboardingScreen renders 2-column layout on desktop', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final engine = TransferEngine();
      engine.stopTimers();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<TransferEngine>.value(value: engine),
            ChangeNotifierProvider<AppUpdateService>.value(value: AppUpdateService()),
          ],
          child: MaterialApp(
            home: OnboardingScreen(
              onComplete: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check Branding Section elements
      expect(find.text('QuickShare Studio'), findsWidgets);
      expect(find.text('Fast · Secure · Everywhere'), findsOneWidget);
      expect(find.text('Local Transfer'), findsOneWidget);
      expect(find.text('Internet Transfer'), findsOneWidget);
      expect(find.text('Your Data'), findsOneWidget);

      // Check Step Progress
      expect(find.text('Device Setup'), findsOneWidget);
      expect(find.text('Choose Avatar'), findsOneWidget);
      expect(find.text('Get Started'), findsOneWidget);

      // Step 1 input
      expect(find.text('Set up your device'), findsOneWidget);
    });

    testWidgets('OnboardingScreen completes full 3-step flow to completion', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final engine = TransferEngine();
      engine.stopTimers();
      bool onboardingDone = false;

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<TransferEngine>.value(value: engine),
            ChangeNotifierProvider<AppUpdateService>.value(value: AppUpdateService()),
          ],
          child: MaterialApp(
            home: OnboardingScreen(
              onComplete: () => onboardingDone = true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Step 1: Device Name
      final textField = find.byType(TextField);
      expect(textField, findsOneWidget);
      await tester.enterText(textField, 'Quantum Rig');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      // Step 2: Choose Avatar
      expect(find.text('Choose your avatar'), findsOneWidget);
      final catAvatar = find.byTooltip('Cat');
      expect(catAvatar, findsOneWidget);
      await tester.tap(catAvatar);
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Continue'));
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      // Step 3: Get Started
      expect(find.text('Quantum Rig'), findsWidgets);
      expect(find.text("You're all set!"), findsOneWidget);

      await tester.ensureVisible(find.text('Start Using QuickShare Studio'));
      await tester.tap(find.text('Start Using QuickShare Studio'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(onboardingDone, isTrue);
      expect(engine.localDeviceName, 'Quantum Rig');
    });


    testWidgets('OnboardingScreen adapts to mobile portrait screen without overflow', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(380, 840);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final engine = TransferEngine();
      engine.stopTimers();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<TransferEngine>.value(value: engine),
            ChangeNotifierProvider<AppUpdateService>.value(value: AppUpdateService()),
          ],
          child: MaterialApp(
            home: OnboardingScreen(
              onComplete: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('QuickShare Studio'), findsWidgets);
      expect(find.text('Set up your device'), findsOneWidget);
      expect(tester.takeException(), isNull); // No RenderFlex overflow
    });
  });

  group('E. Returning User Navigation & Edit Profile in Settings Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('QuickShareApp launches OnboardingScreen on fresh install and transitions to Dashboard', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final engine = TransferEngine();
      engine.stopTimers();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<TransferEngine>.value(value: engine),
            ChangeNotifierProvider<AppUpdateService>.value(value: AppUpdateService()),
          ],
          child: const QuickShareApp(initialOnboardingComplete: false),
        ),
      );
      await tester.pumpAndSettle();

      // Fresh install shows onboarding
      expect(find.text('Set up your device'), findsOneWidget);

      // Complete onboarding Step 1
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      // Complete Step 2
      await tester.ensureVisible(find.text('Continue'));
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      // Complete Step 3
      await tester.ensureVisible(find.text('Start Using QuickShare Studio'));
      await tester.tap(find.text('Start Using QuickShare Studio'));
      await tester.pumpAndSettle();

      // Now on Dashboard!
      expect(find.text('HISTORY'), findsWidgets);
    });


    testWidgets('EditProfileDialog allows updating device name and avatar from settings', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final engine = TransferEngine();
      engine.stopTimers();
      bool saved = false;

      final testProfile = DeviceProfile(
        displayName: 'Old Name',
        avatarId: 'laptop',
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<TransferEngine>.value(value: engine),
            ChangeNotifierProvider<AppUpdateService>.value(value: AppUpdateService()),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: EditProfileDialog(
                initialProfile: testProfile,
                onSaved: () => saved = true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Edit Device Profile'), findsOneWidget);

      // Change name
      final nameField = find.byType(TextField).first;
      await tester.enterText(nameField, 'Renamed Device');
      await tester.pumpAndSettle();

      // Tap Save
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();

      expect(saved, isTrue);
      expect(engine.localDeviceName, 'Renamed Device');
    });
  });
}
