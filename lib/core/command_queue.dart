import 'dart:async';

import 'package:flutter/foundation.dart';

typedef CancelCurrentJob = Future<void> Function();

/// 交给任务的凭据：任务启动后把子进程的 cancel 回调挂上来。
class QueueTicket {
  CancelCurrentJob? _cancel;
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void attach(CancelCurrentJob cancel) {
    _cancel = cancel;
    if (_cancelled) unawaited(cancel());
  }

  Future<void> cancel() async {
    if (_cancelled) return;
    _cancelled = true;
    await _cancel?.call();
  }
}

/// 全局单飞命令队列。CLI 的控制锁要求同一时刻最多一个 sidecar。
class CommandQueue extends ChangeNotifier {
  Future<void> _tail = Future<void>.value();
  int _pending = 0;
  String? _currentLabel;
  QueueTicket? _currentTicket;
  bool _disposed = false;

  bool get isBusy => _pending > 0;
  bool get isRunning => _currentLabel != null;
  int get pending => _pending;
  String? get currentLabel => _currentLabel;

  Future<T> run<T>(String label, Future<T> Function(QueueTicket ticket) task) {
    _pending++;
    _notify();
    final completer = Completer<T>();
    final ticket = QueueTicket();

    _tail = _tail.then((_) async {
      if (_disposed) {
        if (!completer.isCompleted) {
          completer.completeError(StateError('命令队列已关闭'));
        }
        _pending--;
        return;
      }
      _currentLabel = label;
      _currentTicket = ticket;
      _notify();
      try {
        final value = await task(ticket);
        if (!completer.isCompleted) completer.complete(value);
      } catch (error, stackTrace) {
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      } finally {
        _currentLabel = null;
        _currentTicket = null;
        _pending--;
        _notify();
      }
    }).catchError((Object _) {
      // 任务错误已经交给 completer，队列本身保持可继续。
    });

    return completer.future;
  }

  Future<void> cancelCurrent() async {
    final ticket = _currentTicket;
    if (ticket == null) return;
    await ticket.cancel();
  }

  /// 取消/退出前等待子进程结束，避免孤儿 sidecar 继续持有锁。
  Future<bool> waitForIdle({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final stopwatch = Stopwatch()..start();
    while (isBusy && stopwatch.elapsed < timeout) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return !isBusy;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
