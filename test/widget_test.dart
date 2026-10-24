import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:diagnosis_odyssey/main.dart';

void main() {
  testWidgets('App shows onboarding then home screen', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const DiagnosisOdysseyApp());
    await tester.pumpAndSettle();

    // Onboarding splash is shown first.
    expect(find.text('Diagnosis Outpost'), findsOneWidget);
    expect(find.text('Get Started'), findsNothing);

    // Advance through splash, privacy, disclaimer, and opt-in.
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
    }

    await tester.tap(find.text('Get Started'));
    await tester.pumpAndSettle();

    // Home screen should now be visible.
    expect(find.text('Outbreak Intel'), findsOneWidget);
  });
}
