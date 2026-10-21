import 'dart:io';

import 'package:flutter/material.dart';

import '../theme.dart';

class LogPanel extends StatefulWidget {
  const LogPanel({
    required this.lines,
    this.height = 300,
    this.emptyText = '暂无日志',
    super.key,
  });

  final List<String> lines;
  final double height;
  final String emptyText;

  @override
  State<LogPanel> createState() => _LogPanelState();
}

class _LogPanelState extends State<LogPanel> {
  final ScrollController _controller = ScrollController();
  bool _stickToBottom = true;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(covariant LogPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.lines.length != oldWidget.lines.length && _stickToBottom) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToBottom());
    }
  }

  void _onScroll() {
    if (!_controller.hasClients) return;
    final position = _controller.position;
    _stickToBottom = position.pixels >= position.maxScrollExtent - 48;
  }

  void _jumpToBottom() {
    if (!_controller.hasClients) return;
    _controller.jumpTo(_controller.position.maxScrollExtent);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fontFamily = Platform.isMacOS ? 'Menlo' : 'Consolas';
    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: AppColors.logBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderSoft),
      ),
      child: widget.lines.isEmpty
          ? Center(
              child: Text(
                widget.emptyText,
                style:  TextStyle(fontSize: 12, color: AppColors.faint),
              ),
            )
          : Scrollbar(
              controller: _controller,
              child: ListView.builder(
                controller: _controller,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                itemCount: widget.lines.length,
                itemBuilder: (context, index) {
                  final line = widget.lines[index];
                  final color = line.contains('✗')
                      ? AppColors.danger
                      : line.contains('✓')
                      ? AppColors.success
                      : line.contains('▶')
                      ? AppColors.blue
                      : AppColors.muted;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text(
                      line,
                      style: TextStyle(
                        fontFamily: fontFamily,
                        fontFamilyFallback: const [
                          'Consolas',
                          'Courier New',
                          'PingFang SC',
                        ],
                        fontSize: 11.5,
                        height: 1.55,
                        color: color,
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}
