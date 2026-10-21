import 'dart:convert';
import 'dart:io';

import 'package:encry_immortals_ui/core/core_command.dart';
import 'package:encry_immortals_ui/core/core_exit_code.dart';
import 'package:encry_immortals_ui/core/core_gateway.dart';
import 'package:encry_immortals_ui/core/core_locator.dart';
import 'package:encry_immortals_ui/core/core_process.dart';
import 'package:encry_immortals_ui/core/core_result.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support/fake_core_process.dart';

void main() {
  late Directory tempDir;
  late FakeCoreProcess process;
  late FakeCoreLauncher launcher;
  late CoreGateway gateway;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('eimmortal_gateway_test_');
    final file = File(p.join(tempDir.path, 'eimmortal'))
      ..writeAsStringSync('');
    process = FakeCoreProcess();
    launcher = FakeCoreLauncher(process);
    gateway = CoreGateway(
      binary: CoreBinary(
        path: file.path,
        source: CoreBinarySource.development,
      ),
      launcher: launcher,
    );
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  Future<CoreResult> execute(
    CoreRequest request, {
    String stdout = '',
    String stderr = '',
    int exitCode = 0,
  }) async {
    final future = gateway.run(request);
    await launcher.launched.future;
    await Future<void>.delayed(Duration.zero);
    if (stdout.isNotEmpty) process.emitStdout(stdout);
    if (stderr.isNotEmpty) process.emitStderrLine(stderr);
    await process.finish(exitCode);
    return future;
  }

  group('buildArguments', () {
    test('全局参数在命令之前，密码不进 argv', () {
      final args = gateway.buildArguments(
        const CoreRequest(
          command: CoreCommand.backup,
          configPath: '/tmp/config.toml',
          password: 'secret-should-not-appear',
          args: ['--source', '/tmp/src'],
        ),
      );
      expect(args, [
        '--config',
        '/tmp/config.toml',
        '--json',
        '--password-fd',
        '0',
        'backup',
        '--source',
        '/tmp/src',
      ]);
      expect(args, isNot(contains('secret-should-not-appear')));
    });

    test('init 不加 --json，但通过 stdin 传密码', () {
      final args = gateway.buildArguments(
        const CoreRequest(
          command: CoreCommand.init,
          configPath: '/tmp/config.toml',
          password: 'pw',
        ),
      );
      expect(args, [
        '--config',
        '/tmp/config.toml',
        '--password-fd',
        '0',
        'init',
      ]);
    });

    test('status 无 --chain 时不传密码 fd', () {
      final args = gateway.buildArguments(
        const CoreRequest(
          command: CoreCommand.status,
          password: 'pw',
        ),
      );
      expect(args, ['--json', 'status']);
    });

    test('import-key 直接读 stdin，不使用 --password-fd', () {
      final args = gateway.buildArguments(
        const CoreRequest(
          command: CoreCommand.importKey,
          armorKey: 'EIMMORTAL-KEY-V2-TEST',
        ),
      );
      expect(args, ['import-key']);
    });
  });

  group('run', () {
    test('写 stdin 并解析 JSON 数组', () async {
      final result = await execute(
        const CoreRequest(
          command: CoreCommand.log,
          password: 'correct horse battery staple',
        ),
        stdout: '[]\n',
      );

      expect(result.isSuccess, isTrue);
      expect(result.jsonParsed, isTrue);
      expect(result.jsonList, isEmpty);
      expect(
        utf8.decode(process.stdinBytes.takeBytes()),
        'correct horse battery staple\n',
      );
      expect(process.stdinClosed, isTrue);
    });

    test('import-key 把 Armor Key 写入 stdin 且不加换行以外的内容', () async {
      final result = await execute(
        const CoreRequest(
          command: CoreCommand.importKey,
          armorKey: '  EIMMORTAL-KEY-V2-TEST  ',
        ),
        stdout: 'imported\n',
      );

      expect(result.isSuccess, isTrue);
      expect(utf8.decode(process.stdinBytes.takeBytes()), 'EIMMORTAL-KEY-V2-TEST\n');
    });

    test('非零退出仍解析 JSON（doctor FAIL）', () async {
      final result = await execute(
        const CoreRequest(command: CoreCommand.doctor, args: ['--chain']),
        stdout:
            '[{"name":"哈希链","status":"FAIL","detail":"无法解锁 vault.meta"}]',
        stderr: 'E12 doctor 检出至少一项 FAIL。',
        exitCode: 12,
      );

      expect(result.isSuccess, isFalse);
      expect(result.exit, CoreExitCode.corrupt);
      expect(result.jsonParsed, isTrue);
      expect(result.jsonList, hasLength(1));
      expect(result.errorSummary, contains('E12'));
    });

    test('成功但 stdout 不是 JSON 时标记协议错误', () async {
      final result = await execute(
        const CoreRequest(command: CoreCommand.status),
        stdout: 'not-json',
      );

      expect(result.isSuccess, isTrue);
      expect(result.protocolError, isTrue);
      expect(result.jsonParsed, isFalse);
    });

    test('version 是文本输出，不做 JSON 解析', () async {
      final result = await execute(
        const CoreRequest(command: CoreCommand.version),
        stdout: 'eimmortal 0.1.0-dev\n',
      );

      expect(result.isSuccess, isTrue);
      expect(result.jsonParsed, isFalse);
      expect(result.protocolError, isFalse);
      expect(result.stdout.trim(), 'eimmortal 0.1.0-dev');
    });

    test('敏感命令 redacted() 不保留 stdout', () async {
      final result = await execute(
        const CoreRequest(command: CoreCommand.exportKey),
        stdout: '{"armor":"EIMMORTAL-KEY-V2-SECRET","grouped":"SECRET"}',
      );

      expect(result.sensitive, isTrue);
      expect(result.stdout, contains('EIMMORTAL-KEY-V2-SECRET'));
      final redacted = result.redacted();
      expect(redacted.stdout, isNot(contains('SECRET')));
      expect(redacted.stdout, contains('<redacted:'));
      expect(redacted.safeSummary, isNot(contains('SECRET')));
    });

    test('取消会终止子进程并标记 cancelled', () async {
      final run = gateway.start(
        const CoreRequest(command: CoreCommand.log, password: 'pw'),
      );
      await launcher.launched.future;
      await run.cancel();
      final result = await run.result;

      expect(process.killed, isTrue);
      expect(result.cancelled, isTrue);
      expect(result.exitCode, 130);
    });

    test('密码含换行直接拒绝', () {
      expect(
        () => gateway.start(
          const CoreRequest(command: CoreCommand.log, password: 'a\nb'),
        ),
        throwsArgumentError,
      );
    });

    test('import-key 缺少 Armor Key 直接拒绝', () {
      expect(
        () => gateway.start(const CoreRequest(command: CoreCommand.importKey)),
        throwsArgumentError,
      );
    });

    test('环境下传只保留白名单变量', () {
      final env = buildCoreEnvironment({
        'PATH': '/usr/bin',
        'HOME': '/Users/test',
        'EIMMORTAL_SECRET': 'leak',
        'AWS_SECRET_ACCESS_KEY': 'leak',
      });
      expect(env['PATH'], '/usr/bin');
      expect(env['HOME'], '/Users/test');
      expect(env.containsKey('EIMMORTAL_SECRET'), isFalse);
      expect(env.containsKey('AWS_SECRET_ACCESS_KEY'), isFalse);
    });
  });
}
