import 'dart:io';

import 'package:window_manager/window_manager.dart';

bool _windowManagerReady = false;

/// 在 main 中调用一次；在此之前不触碰窗口 API，避免插件尚未绑定窗口时崩溃。
Future<void> initAppWindow() async {
  if (!Platform.isMacOS && !Platform.isWindows) return;
  await windowManager.ensureInitialized();
  _windowManagerReady = true;
}

/// 窗口标题描述当前内容，而不是应用名。
Future<void> setAppWindowTitle(String title) async {
  if (!_windowManagerReady) return;
  try {
    await windowManager.setTitle(title);
  } catch (_) {
    // 单元测试或窗口插件不可用时忽略。
  }
}

Future<void> closeAppWindow() async {
  if (!_windowManagerReady) return;
  try {
    await windowManager.close();
  } catch (_) {
    // 由调用方/关闭守卫处理失败。
  }
}
