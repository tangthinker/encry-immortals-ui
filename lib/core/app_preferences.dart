import 'dart:convert';
import 'dart:io';

import 'app_paths.dart';
import 'private_file.dart';

/// 首次启动默认浅色；用户可在设置页改为跟随系统或固定深色。
enum AppThemeMode {
  light,
  system,
  dark;

  String get label => switch (this) {
    AppThemeMode.light => '浅色',
    AppThemeMode.system => '跟随系统',
    AppThemeMode.dark => '深色',
  };

  static AppThemeMode parse(Object? value) {
    return switch (value) {
      'light' => AppThemeMode.light,
      'system' => AppThemeMode.system,
      'dark' => AppThemeMode.dark,
      _ => AppThemeMode.light,
    };
  }
}

class AppPreferences {
  const AppPreferences({this.themeMode = AppThemeMode.light});

  static const int currentSchema = 1;

  final AppThemeMode themeMode;

  Map<String, Object?> toJson() => {
    'schema': currentSchema,
    'theme_mode': themeMode.name,
  };

  factory AppPreferences.fromJson(Map<String, Object?> json) {
    return AppPreferences(themeMode: AppThemeMode.parse(json['theme_mode']));
  }
}

/// 应用级外观偏好，独立于 vault profile；移除本地配置不会重置主题。
class AppPreferencesStore {
  AppPreferencesStore(this.paths);

  final AppPaths paths;

  Future<AppPreferences> load() async {
    final file = File(paths.preferencesFile);
    if (!await file.exists()) return const AppPreferences();
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return const AppPreferences();
      return AppPreferences.fromJson(
        decoded.map((key, value) => MapEntry('$key', value)),
      );
    } catch (_) {
      // 外观偏好损坏不应阻止应用启动；回退到默认浅色。
      return const AppPreferences();
    }
  }

  Future<void> save(AppPreferences preferences) async {
    final tmp = File('${paths.preferencesFile}.tmp');
    await tmp.parent.create(recursive: true);
    await tmp.writeAsString(
      const JsonEncoder.withIndent('  ').convert(preferences.toJson()),
      flush: true,
    );
    await makePrivateFile(tmp.path);
    if (Platform.isWindows && await File(paths.preferencesFile).exists()) {
      await File(paths.preferencesFile).delete();
    }
    await tmp.rename(paths.preferencesFile);
  }
}
