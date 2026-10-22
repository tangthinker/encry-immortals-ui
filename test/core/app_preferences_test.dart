import 'dart:io';

import 'package:encry_immortals_ui/core/app_paths.dart';
import 'package:encry_immortals_ui/core/app_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;
  late AppPaths paths;
  late AppPreferencesStore store;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('eimmortal_prefs_');
    paths = AppPaths(root: p.join(temp.path, 'app'));
    await paths.ensure();
    store = AppPreferencesStore(paths);
  });

  tearDown(() async {
    await temp.delete(recursive: true);
  });

  test('缺少偏好文件时默认浅色', () async {
    expect((await store.load()).themeMode, AppThemeMode.light);
  });

  test('保存并恢复主题，文件权限为 0600', () async {
    await store.save(const AppPreferences(themeMode: AppThemeMode.dark));
    expect((await store.load()).themeMode, AppThemeMode.dark);
    if (!Platform.isWindows) {
      final mode = File(paths.preferencesFile).statSync().mode & 0x1FF;
      expect(mode, 0x180);
    }
    await store.save(const AppPreferences(themeMode: AppThemeMode.system));
    expect((await store.load()).themeMode, AppThemeMode.system);
  });

  test('损坏的偏好文件回退浅色', () async {
    await File(paths.preferencesFile).writeAsString('not json');
    expect((await store.load()).themeMode, AppThemeMode.light);
    await File(paths.preferencesFile).writeAsString('{"theme_mode":"neon"}');
    expect((await store.load()).themeMode, AppThemeMode.light);
  });
}
