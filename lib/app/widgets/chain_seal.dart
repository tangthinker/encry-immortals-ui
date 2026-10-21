import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// 产品的签名元素：把本地锚点做成“封印”。
/// 它不是装饰——中心显示的是 status --chain 返回的 anchor_short 和校验状态。
class ChainSeal extends StatelessWidget {
  const ChainSeal({
    required this.anchor,
    required this.verified,
    this.size = 82,
    super.key,
  });

  final String anchor;
  final bool verified;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = verified ? AppColors.success : AppColors.amber;
    final displayAnchor = anchor.trim().isEmpty ? '未锚定' : anchor.trim();
    return Semantics(
      label: verified ? '锚点 $displayAnchor，已验证' : '锚点 $displayAnchor，未验证',
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _SealPainter(color: color, tickColor: AppColors.border),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '锚点',
                  style: TextStyle(
                    fontSize: 10,
                    height: 1.2,
                    letterSpacing: 1.2,
                    color: AppColors.faint,
                  ),
                ),
                const SizedBox(height: 3),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    displayAnchor,
                    style: TextStyle(
                      fontFamily: 'Menlo',
                      fontFamilyFallback: const ['Consolas', 'Courier New'],
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: color.withValues(alpha: 0.35)),
                  ),
                  child: Text(
                    verified ? '已验证' : '未验证',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SealPainter extends CustomPainter {
  const _SealPainter({required this.color, required this.tickColor});

  final Color color;
  final Color tickColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2 - 1;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = color;
    canvas.drawCircle(center, radius, ring);
    canvas.drawCircle(
      center,
      radius - 5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = color.withValues(alpha: 0.35),
    );

    // 类似封印的刻度：只画 24 个短刻线，避免成为装饰性噪点。
    final tick = Paint()
      ..strokeWidth = 1
      ..color = tickColor;
    for (var index = 0; index < 24; index++) {
      final angle = index * math.pi / 12;
      final outer = radius - 1.5;
      final inner = radius - (index % 2 == 0 ? 4.5 : 3.5);
      canvas.drawLine(
        center + Offset(math.cos(angle) * inner, math.sin(angle) * inner),
        center + Offset(math.cos(angle) * outer, math.sin(angle) * outer),
        tick,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SealPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.tickColor != tickColor;
  }
}
