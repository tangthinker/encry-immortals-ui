import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// 仅用于开发期 UI 截图：
/// `open ... --env EIMMORTAL_SCREENSHOT=/tmp/eimui.png` 后自动保存窗口内容。
class ScreenshotHarness extends StatefulWidget {
  const ScreenshotHarness({required this.child, super.key});

  final Widget child;

  @override
  State<ScreenshotHarness> createState() => _ScreenshotHarnessState();
}

class _ScreenshotHarnessState extends State<ScreenshotHarness> {
  final GlobalKey _boundaryKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    if (kDebugMode) {
      final path = Platform.environment['EIMMORTAL_SCREENSHOT'];
      if (path != null && path.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _capture(path));
      }
    }
  }

  Future<void> _capture(String path) async {
    final seconds =
        int.tryParse(Platform.environment['EIMMORTAL_SCREENSHOT_DELAY'] ?? '') ??
        3;
    await Future<void>.delayed(Duration(seconds: seconds));
    if (!mounted) return;
    final boundary =
        _boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return;
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) return;
    await File(path).writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(key: _boundaryKey, child: widget.child);
  }
}
