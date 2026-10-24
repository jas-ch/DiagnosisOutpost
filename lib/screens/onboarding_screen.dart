import 'package:flutter/material.dart';

import '../services/onboarding_service.dart';
import 'home_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _currentPage = 0;
  bool _analyticsOptIn = true;

  static const _pages = 4;

  void _next() {
    if (_currentPage < _pages - 1) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _finish();
    }
  }

  Future<void> _finish() async {
    await OnboardingService.markComplete();
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    }
  }

  void _skip() {
    _finish();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _skip,
                child: const Text('Skip'),
              ),
            ),
            Expanded(
              child: PageView(
                controller: _controller,
                onPageChanged: (index) => setState(() => _currentPage = index),
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _SplashPage(),
                  _PrivacyPage(),
                  _DisclaimerPage(),
                  _OptInPage(
                    value: _analyticsOptIn,
                    onChanged: (v) => setState(() => _analyticsOptIn = v),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Row(
                    children: List.generate(
                      _pages,
                      (index) => Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _currentPage == index
                              ? Theme.of(context).colorScheme.primary
                              : Colors.grey.shade300,
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  ElevatedButton(
                    onPressed: _next,
                    child: Text(_currentPage == _pages - 1 ? 'Get Started' : 'Next'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SplashPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.health_and_safety,
            size: 80,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 24),
          Text(
            'Diagnosis Outpost',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            'Community Outbreak Sentinel',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.grey.shade600,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          const Text(
            'Real-time outbreak intelligence, on-device risk checks, and civic health awareness — all in one place.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _PrivacyPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.privacy_tip_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 24),
          Text(
            'Privacy First',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Diagnosis Outpost is designed for civic awareness. We do not collect personal health data. '
            'On Android and iOS, audio recordings and photos stay on your device. On the web, you may opt in to send a photo or cough audio to our backend for processing; the file is analyzed in memory and not stored.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          const Text(
            'Your location is used only to show nearby outbreak signals and is never sold or shared with advertisers.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _DisclaimerPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.info_outline,
            size: 64,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 24),
          Text(
            'Medical Disclaimer',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 16),
          const Text(
            'This app is for educational and civic awareness purposes only. It is not a substitute for professional medical advice, diagnosis, or treatment.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          const Text(
            'If you have serious symptoms or are worried about your health, please contact a healthcare provider or emergency services.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _OptInPage extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _OptInPage({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.analytics_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 24),
          Text(
            'Help the Community',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 16),
          const Text(
            'You can anonymously share outbreak signal data to help public health agencies spot trends faster. No personal information is included.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          SwitchListTile(
            value: value,
            onChanged: onChanged,
            title: const Text('Share anonymous signals'),
            subtitle: const Text('You can change this later in settings.'),
          ),
        ],
      ),
    );
  }
}
