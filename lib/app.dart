import 'package:flutter/material.dart';

import 'app/app_controller.dart';
import 'app/app_info.dart';
import 'app/screens/already_running_screen.dart';
import 'app/screens/main_shell.dart';
import 'app/screens/onboarding/onboarding_screen.dart';
import 'app/screens/startup_screen.dart';
import 'app/screens/unlock_screen.dart';
import 'app/theme.dart';

class EncryImmortalsApp extends StatelessWidget {
  const EncryImmortalsApp({
    required this.controller,
    this.navigatorKey,
    super.key,
  });

  final AppController controller;
  final GlobalKey<NavigatorState>? navigatorKey;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: appName,
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: AppRoot(controller: controller),
    );
  }
}

class AppRoot extends StatelessWidget {
  const AppRoot({required this.controller, super.key});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final screen = switch (controller.phase) {
          AppPhase.starting => const StartupScreen(),
          AppPhase.alreadyRunning => const AlreadyRunningScreen(),
          AppPhase.failed => StartupFailureScreen(controller: controller),
          AppPhase.onboarding => OnboardingScreen(controller: controller),
          AppPhase.locked => UnlockScreen(controller: controller),
          AppPhase.unlocked => MainShell(controller: controller),
        };
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          child: KeyedSubtree(key: ValueKey(controller.phase), child: screen),
        );
      },
    );
  }
}
