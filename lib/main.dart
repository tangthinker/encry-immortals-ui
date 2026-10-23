import 'dart:async';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'app/app_controller.dart';
import 'app/window_title.dart';
import 'core/app_paths.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final paths = AppPaths.resolve();
  final controller = AppController(paths: paths);
  final navigatorKey = GlobalKey<NavigatorState>();
  runApp(EncryImmortalsApp(controller: controller, navigatorKey: navigatorKey));
  unawaited(controller.initialize());
  unawaited(_configureWindow(controller, navigatorKey));
}

Future<void> _configureWindow(
  AppController controller,
  GlobalKey<NavigatorState> navigatorKey,
) async {
  try {
    await initAppWindow();
    const options = WindowOptions(
      size: Size(1240, 840),
      minimumSize: Size(1000, 680),
      center: true,
      title: 'Encry Immortals',
      titleBarStyle: TitleBarStyle.normal,
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
    await windowManager.setPreventClose(true);
    windowManager.addListener(_CloseGuard(controller, navigatorKey));
  } catch (_) {
    // 窗口插件不可用时仍可运行；单实例锁仍由 AppController 保证。
  }
}

class _CloseGuard extends WindowListener {
  _CloseGuard(this.controller, this.navigatorKey);

  final AppController controller;
  final GlobalKey<NavigatorState> navigatorKey;

  @override
  void onWindowClose() async {
    if (!controller.queue.isBusy) {
      await controller.quit();
      return;
    }
    final context = navigatorKey.currentContext;
    if (context == null) return;
    final quit = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('命令仍在运行，退出？'),
        content: const Text(
          '退出会取消当前 sidecar。写入被中断时可能留下 TargetDir 写锁，'
          '下次备份可能需要 --break-lock。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('继续等待'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('取消并退出'),
          ),
        ],
      ),
    );
    if (quit == true) {
      await controller.queue.cancelCurrent();
      await controller.quit(force: true);
    }
  }
}
