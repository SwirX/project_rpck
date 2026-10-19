import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Onboarding state, persisted so a step survives a restart.
class OnboardingProgress {
  static const _key = 'onboarding';

  static Future<OnboardingProgress> load() async {
    final prefs = await SharedPreferences.getInstance();
    return OnboardingProgress._(
      completed: prefs.getBool('$_key.completed') ?? false,
      seenGuide: prefs.getBool('$_key.guide') ?? false,
      folder: prefs.getString('$_key.folder'),
    );
  }

  final bool completed;
  final bool seenGuide;
  final String? folder;

  const OnboardingProgress._({
    required this.completed,
    required this.seenGuide,
    required this.folder,
  });

  Future<void> complete({String? folder}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_key.completed', true);
    if (folder != null) await prefs.setString('$_key.folder', folder);
  }

  Future<void> markGuideSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_key.guide', true);
  }

  Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_key.completed');
    await prefs.remove('$_key.guide');
    await prefs.remove('$_key.folder');
  }
}

/// The steps the first run walks through.
enum OnboardingStep {
  welcome,
  downloadFolder,
  buildIndex,
  ready,
}

/// Shared progress widgets so the wizard and the guide read as one system.
class OnboardingScaffold extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  final List<Widget> actions;
  final int stepIndex;
  final int stepCount;

  const OnboardingScaffold({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.actions = const [],
    this.stepIndex = 0,
    this.stepCount = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFF000000),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (stepCount > 1) _StepDots(count: stepCount, active: stepIndex),
              if (stepCount > 1) const SizedBox(height: 26),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 30,
                  height: 1.15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.6,
                  color: Colors.white,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 10),
                Text(
                  subtitle!,
                  style: const TextStyle(
                    fontSize: 15,
                    height: 1.5,
                    color: Color(0xFF9A9A9A),
                  ),
                ),
              ],
              const SizedBox(height: 26),
              Expanded(child: child),
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 18),
                Row(children: actions),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StepDots extends StatelessWidget {
  final int count;
  final int active;

  const _StepDots({required this.count, required this.active});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var index = 0; index < count; index++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            margin: const EdgeInsets.only(right: 6),
            width: index == active ? 26 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: index <= active ? const Color(0xFF3D8BFF) : const Color(0x22FFFFFF),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
      ],
    );
  }
}

/// A labelled card used throughout onboarding and the guide.
class OnboardingCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final Widget? trailing;

  const OnboardingCard({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x1AFFFFFF)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0x1F3D8BFF),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: const Color(0xFF3D8BFF), size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  body,
                  style: const TextStyle(
                    color: Color(0xFF9A9A9A),
                    fontSize: 13.5,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 10), trailing!],
        ],
      ),
    );
  }
}