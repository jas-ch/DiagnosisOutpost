import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:diagnosis_odyssey/services/onboarding_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('OnboardingService', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('isComplete returns false by default', () async {
      final complete = await OnboardingService.isComplete();
      expect(complete, isFalse);
    });

    test('markComplete persists completion', () async {
      await OnboardingService.markComplete();
      final complete = await OnboardingService.isComplete();
      expect(complete, isTrue);
    });

    test('reset clears completion', () async {
      await OnboardingService.markComplete();
      await OnboardingService.reset();
      final complete = await OnboardingService.isComplete();
      expect(complete, isFalse);
    });
  });
}
