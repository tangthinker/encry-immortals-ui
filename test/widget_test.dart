import 'package:encry_immortals_ui/app.dart';
import 'package:encry_immortals_ui/app/bootstrap.dart';
import 'package:encry_immortals_ui/core/core_gateway.dart';
import 'package:encry_immortals_ui/core/core_locator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

BootstrapInfo _fakeBootstrap() {
  const binary = CoreBinary(
    path: '/test/eimmortal',
    source: CoreBinarySource.development,
  );
  return BootstrapInfo(
    binary: binary,
    integrity: const CoreIntegrityResult(
      status: CoreIntegrityStatus.notPinned,
      actualSha256: 'deadbeef',
      expectedSha256: null,
    ),
    gateway: CoreGateway(binary: binary),
    version: '0.1.0-dev',
  );
}

void main() {
  testWidgets('应用壳层渲染概览与核心状态', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bootstrapProvider.overrideWith((ref) async => _fakeBootstrap()),
        ],
        child: const EncryImmortalsApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Encry Immortals'), findsWidgets);
    expect(find.text('概览'), findsWidgets);
    expect(find.text('核心就绪 · 0.1.0-dev'), findsOneWidget);
    expect(find.text('运行垂直切片自检'), findsOneWidget);
    expect(find.text('M0 进度'), findsOneWidget);
  });

  testWidgets('导航到自检页并显示空日志状态', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bootstrapProvider.overrideWith((ref) async => _fakeBootstrap()),
        ],
        child: const EncryImmortalsApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('自检').first);
    await tester.pumpAndSettle();

    expect(find.text('开始自检'), findsOneWidget);
    expect(find.text('运行自检后，这里会显示 13 个步骤的实时日志'), findsOneWidget);
    expect(find.textContaining('还没有步骤结果'), findsOneWidget);
  });

  testWidgets('核心不可用时显示错误引导', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bootstrapProvider.overrideWith(
            (ref) async => const BootstrapInfo(
              error: '找不到核心 sidecar。已查找：/test/eimmortal',
              searchedPaths: ['/test/eimmortal'],
            ),
          ),
        ],
        child: const EncryImmortalsApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('无法启动核心 sidecar'), findsOneWidget);
    expect(find.text('核心不可用'), findsWidgets);
  });
}
