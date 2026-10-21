import 'dart:async';

/// 取消当前任务的回调（通常是 `CoreRun.cancel`）。
typedef CancelCurrentJob = Future<void> Function();

/// 全局单飞命令队列。
///
/// 核心 CLI 几乎每个命令都会拿控制锁；GUI 必须保证同一时刻只有一个 sidecar。
/// 队列不会因为某个任务失败而卡住后续任务。
class CommandQueue {
  CommandQueue({this.onStateChanged});

  final void Function()? onStateChanged;

  Future<void> _tail = Future<void>.value();
  int _pending = 0;
  String? _currentLabel;
  CancelCurrentJob? _cancelCurrent;

  bool get isBusy => _pending > 0;
  bool get isRunning => _currentLabel != null;
  int get pending => _pending;
  String? get currentLabel => _currentLabel;

  Future<T> run<T>(
    String label,
    Future<T> Function() task, {
    CancelCurrentJob? cancel,
  }) {
    _pending++;
    _notify();
    final completer = Completer<T>();

    _tail = _tail.then((_) async {
      _currentLabel = label;
      _cancelCurrent = cancel;
      _notify();
      try {
        final value = await task();
        if (!completer.isCompleted) completer.complete(value);
      } catch (error, stackTrace) {
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      } finally {
        _currentLabel = null;
        _cancelCurrent = null;
        _pending--;
        _notify();
      }
    }).catchError((Object _) {
      // _tail 本身永远不应处于错误状态；任务错误已经交给 completer。
    });

    return completer.future;
  }

  Future<void> cancelCurrent() async {
    final cancel = _cancelCurrent;
    if (cancel == null) return;
    await cancel();
  }

  void _notify() {
    onStateChanged?.call();
  }
}
