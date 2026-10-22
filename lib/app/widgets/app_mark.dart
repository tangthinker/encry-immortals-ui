import 'package:flutter/material.dart';

/// 应用内统一品牌标记：与 macOS/Windows 应用图标使用同一张封印图。
///
/// 图标总是紧邻应用名/说明文字，因此作为装饰图像处理，避免 VoiceOver
/// 把应用名重复读两遍。
class AppMark extends StatelessWidget {
  const AppMark({this.size = 40, super.key});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/icon/app-mark.png',
      width: size,
      height: size,
      filterQuality: FilterQuality.high,
      fit: BoxFit.contain,
      excludeFromSemantics: true,
    );
  }
}
