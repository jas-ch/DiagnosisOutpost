import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:diagnosis_odyssey/screens/home_screen.dart';
import 'package:diagnosis_odyssey/screens/onboarding_screen.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('OnboardingScreen shows splash and navigates through pages',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: OnboardingScreen()));

    expect(find.text('Diagnosis Outpost'), findsOneWidget);
    expect(find.text('Community Outbreak Sentinel'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Privacy First'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Medical Disclaimer'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Help the Community'), findsOneWidget);
    expect(find.text('Get Started'), findsOneWidget);

    await tester.tap(find.text('Get Started'));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('OnboardingScreen skip button finishes onboarding',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: OnboardingScreen()));

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
  });
}
