import 'dart:async';

import 'package:encry_immortals_ui/core/command_queue.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('严格串行执行，并正确维护 pending', () async {
    final events = <String>[];
    final queue = CommandQueue(onStateChanged: () {});

    final first = queue.run('first', () async {
      events.add('first-start');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      events.add('first-end');
      return 1;
    });
    final second = queue.run('second', () async {
      events.add('second-start');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      events.add('second-end');
      return 2;
    });

    expect(queue.isBusy, isTrue);
    expect(queue.pending, 2);
    expect(await first, 1);
    expect(await second, 2);
    expect(events, [
      'first-start',
      'first-end',
      'second-start',
      'second-end',
    ]);
    expect(queue.isBusy, isFalse);
    expect(queue.pending, 0);
  });

  test('任务失败不会卡住后续任务', () async {
    final queue = CommandQueue();
    final failed = queue.run<void>('bad', () async {
      throw StateError('boom');
    });
    final ok = queue.run('good', () async => 'ok');

    await expectLater(failed, throwsStateError);
    expect(await ok, 'ok');
    expect(queue.pending, 0);
  });

  test('cancelCurrent 调用当前任务的取消回调', () async {
    final queue = CommandQueue();
    var cancelled = false;
    final started = Completer<void>();
    final future = queue.run(
      'long',
      () async {
        started.complete();
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return 'done';
      },
      cancel: () async {
        cancelled = true;
      },
    );

    await started.future;
    await queue.cancelCurrent();
    expect(cancelled, isTrue);
    expect(await future, 'done');
  });

  test('排队任务的取消回调不会被误调用', () async {
    final queue = CommandQueue();
    var secondCancelled = false;
    final gate = Completer<void>();

    final first = queue.run('first', () async {
      await gate.future;
      return 'first-done';
    });
    final second = queue.run(
      'second',
      () async => 2,
      cancel: () async {
        secondCancelled = true;
      },
    );

    await queue.cancelCurrent();
    expect(secondCancelled, isFalse);
    gate.complete();
    expect(await first, 'first-done');
    expect(await second, 2);
  });
}
