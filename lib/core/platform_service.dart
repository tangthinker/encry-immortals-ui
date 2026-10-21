import 'dart:io';

typedef ProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
);

class PlatformService {
  const PlatformService({this.runner = _defaultRunner});

  final ProcessRunner runner;

  static Future<ProcessResult> _defaultRunner(
    String executable,
    List<String> arguments,
  ) {
    return Process.run(executable, arguments, runInShell: false);
  }

  Future<void> revealPath(String path) async {
    if (Platform.isMacOS) {
      await runner('open', [path]);
    } else if (Platform.isWindows) {
      await runner('explorer', [path]);
    } else {
      await runner('xdg-open', [path]);
    }
  }

  Future<void> openUrl(String url) async {
    if (Platform.isMacOS) {
      await runner('open', [url]);
    } else if (Platform.isWindows) {
      await runner('rundll32', ['url.dll,FileProtocolHandler', url]);
    } else {
      await runner('xdg-open', [url]);
    }
  }

  String get platformLabel {
    if (Platform.isMacOS) return 'macOS ${Platform.operatingSystemVersion}';
    if (Platform.isWindows) return 'Windows ${Platform.operatingSystemVersion}';
    return '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
  }
}
