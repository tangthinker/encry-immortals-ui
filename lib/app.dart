import 'package:flutter/material.dart';

import 'app/app_controller.dart';
import 'app/app_info.dart';
import 'app/screens/already_running_screen.dart';
import 'app/screens/main_shell.dart';
import 'app/screens/onboarding/onboarding_screen.dart';
import 'app/screens/startup_screen.dart';
import 'app/screens/unlock_screen.dart';
import 'app/theme.dart';
import 'core/app_preferences.dart';

class EncryImmortalsApp extends StatefulWidget {
  const EncryImmortalsApp({
    required this.controller,
    this.navigatorKey,
    super.key,
  });

  final AppController controller;
  final GlobalKey<NavigatorState>? navigatorKey;

  @override
  State<EncryImmortalsApp> createState() => _EncryImmortalsAppState();
}

class _EncryImmortalsAppState extends State<EncryImmortalsApp>
    with WidgetsBindingObserver {
  late Brightness _platformBrightness;
  late AppThemeMode _themeMode;

  @override
  void initState() {
    super.initState();
    _platformBrightness =
        WidgetsBinding.instance.platformDispatcher.platformBrightness;
    _themeMode = widget.controller.themeMode;
    widget.controller.addListener(_onControllerChanged);
    WidgetsBinding.instance.addObserver(this);
  }

  void _onControllerChanged() {
    if (!mounted) return;
    final next = widget.controller.themeMode;
    if (next == _themeMode) return;
    setState(() => _themeMode = next);
  }

  @override
  void didChangePlatformBrightness() {
    final next = WidgetsBinding.instance.platformDispatcher.platformBrightness;
    if (next != _platformBrightness) {
      setState(() => _platformBrightness = next);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brightness = switch (_themeMode) {
      AppThemeMode.light => Brightness.light,
      AppThemeMode.dark => Brightness.dark,
      AppThemeMode.system => _platformBrightness,
    };
    AppColors.apply(brightness);
    return MaterialApp(
      navigatorKey: widget.navigatorKey,
      title: appName,
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: AppRoot(controller: widget.controller),
    );
  }
}

class AppRoot extends StatelessWidget {
  const AppRoot({required this.controller, super.key});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    // 依赖 Theme，系统外观切换时重建整棵页面树（State 保留）。
    final theme = Theme.of(context);
    return ColoredBox(
      color: theme.scaffoldBackgroundColor,
      child: AnimatedBuilder(
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
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 180),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            child: KeyedSubtree(key: ValueKey(controller.phase), child: screen),
          );
        },
      ),
    );
  }
}
