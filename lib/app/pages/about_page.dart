import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bootstrap.dart';
import '../theme.dart';
import '../widgets/page_header.dart';
import '../widgets/section_card.dart';

class AboutPage extends ConsumerWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(bootstrapProvider).value;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(36, 30, 36, 52),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const PageHeader(
                title: '关于',
                subtitle: '薄客户端 + 固定版本 sidecar；所有数据事实以 CLI 的 JSON 为准',
              ),
              const SizedBox(height: 24),
              _BrandCard(info: info),
              const SizedBox(height: 20),
              const _DocsCard(),
              const SizedBox(height: 20),
              const _BoundaryCard(),
            ],
          ),
        ),
      ),
    );
  }
}

class _BrandCard extends StatelessWidget {
  const _BrandCard({required this.info});

  final BootstrapInfo? info;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(15),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.accent, AppColors.accentDeep],
                  ),
                ),
                child: const Icon(
                  Icons.shield_moon_outlined,
                  color: Color(0xFF04140D),
                  size: 29,
                ),
              ),
              const SizedBox(width: 18),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Encry Immortals',
                      style: TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                        color: AppColors.text,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'eimmortal 的 macOS / Windows 桌面控制台',
                      style: TextStyle(fontSize: 12.5, color: AppColors.faint),
                    ),
                  ],
                ),
              ),
              const StatusPill(
                label: 'M0 · 0.1.0',
                color: AppColors.blue,
                dense: true,
              ),
            ],
          ),
          const SizedBox(height: 22),
          const Divider(),
          const SizedBox(height: 8),
          InfoRow(label: '客户端版本', value: '0.1.0+1 · M0', mono: true),
          const Divider(),
          InfoRow(label: '核心版本', value: info?.version ?? '不可用', mono: true),
          const Divider(),
          InfoRow(
            label: 'sidecar',
            value: info?.binary?.path ?? '未找到',
            mono: true,
            selectable: true,
          ),
          const Divider(),
          InfoRow(
            label: '完整性',
            value: info?.integrityLabel ?? '未检查',
            valueColor: info?.integrityOk == false ? AppColors.danger : null,
          ),
          const Divider(),
          InfoRow(
            label: '构建宿主',
            value: '${Platform.operatingSystem} · ${Platform.operatingSystemVersion}',
          ),
          const Divider(),
          const InfoRow(
            label: '技术栈',
            value: 'Flutter 3.47 / Dart 3.13 + Go sidecar（CGO_ENABLED=0）',
          ),
        ],
      ),
    );
  }
}

class _DocsCard extends StatelessWidget {
  const _DocsCard();

  @override
  Widget build(BuildContext context) {
    const docs = [
      ('docs/tech-selection.md', '技术选型与架构决策：为什么是 Flutter + sidecar，而不是 FFI / Electron。'),
      ('docs/integration-contract.md', '逐命令契约：stdin、JSON、退出码、锁、取消与测试清单。'),
      ('docs/devlog.md', '开发日志：每个里程碑的目标、操作、结果、决策与风险。'),
    ];
    return SectionCard(
      title: '项目文档',
      subtitle: '仓库内文档是行为的唯一来源；代码只实现已冻结的契约',
      child: Column(
        children: [
          for (var index = 0; index < docs.length; index++) ...[
            if (index > 0) const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.description_outlined,
                    size: 17,
                    color: AppColors.blue,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SelectableText(
                          docs[index].$1,
                          style: const TextStyle(
                            fontFamily: 'Menlo',
                            fontSize: 12,
                            color: AppColors.text,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          docs[index].$2,
                          style: const TextStyle(
                            fontSize: 11.5,
                            height: 1.55,
                            color: AppColors.faint,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BoundaryCard extends StatelessWidget {
  const _BoundaryCard();

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: '设计边界',
      subtitle: 'M0 刻意不做的事',
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: const [
          KeyValueChip(label: '不做', value: '自动更新'),
          KeyValueChip(label: '不做', value: '无人值守定时备份'),
          KeyValueChip(label: '不做', value: '多 vault / 多 profile'),
          KeyValueChip(label: '不做', value: '文件预览'),
          KeyValueChip(label: '不做', value: 'compact / gc 图形化'),
          KeyValueChip(label: '暂不', value: 'macOS 公证 / Windows 签名'),
        ],
      ),
    );
  }
}
