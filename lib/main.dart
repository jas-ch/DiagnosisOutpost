import 'package:flutter/material.dart';

import 'screens/diagnosis_history_screen.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/self_diagnosis_screen.dart';
import 'services/onboarding_service.dart';

void main() {
  runApp(const DiagnosisOdysseyApp());
}

class DiagnosisOdysseyApp extends StatefulWidget {
  const DiagnosisOdysseyApp({super.key});

  @override
  State<DiagnosisOdysseyApp> createState() => _DiagnosisOdysseyAppState();
}

class _DiagnosisOdysseyAppState extends State<DiagnosisOdysseyApp> {
  Future<bool>? _onboardingCheck;

  @override
  void initState() {
    super.initState();
    _onboardingCheck = OnboardingService.isComplete();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Diagnosis Outpost',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.light,
        ),
        cardTheme: CardThemeData(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: Colors.grey.shade100,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: Colors.teal.shade700,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        appBarTheme: AppBarTheme(
          centerTitle: true,
          backgroundColor: Colors.teal.shade700,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        scaffoldBackgroundColor: Colors.white,
      ),
      home: FutureBuilder<bool>(
        future: _onboardingCheck,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          final complete = snapshot.data ?? false;
          return complete ? const HomeScreen() : const OnboardingScreen();
        },
      ),
      routes: {
        '/home': (context) => const HomeScreen(),
        '/self-diagnosis': (context) => const SelfDiagnosisScreen(),
        '/history': (context) => const DiagnosisHistoryScreen(),
      },
    );
  }
}
