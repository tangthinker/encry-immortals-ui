import 'dart:async';

import 'package:encry_immortals_ui/core/command_queue.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('严格串行执行，并正确维护 pending', () async {
    final events = <String>[];
    final queue = CommandQueue();

    final first = queue.run('first', (ticket) async {
      events.add('first-start');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      events.add('first-end');
      return 1;
    });
    final second = queue.run('second', (ticket) async {
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
    queue.dispose();
  });

  test('任务失败不会卡住后续任务', () async {
    final queue = CommandQueue();
    final failed = queue.run<void>('bad', (ticket) async {
      throw StateError('boom');
    });
    final ok = queue.run('good', (ticket) async => 'ok');

    await expectLater(failed, throwsStateError);
    expect(await ok, 'ok');
    expect(queue.pending, 0);
    queue.dispose();
  });

  test('cancelCurrent 只取消当前任务，不影响后续', () async {
    final queue = CommandQueue();
    var cancelled = false;
    final started = Completer<void>();
    final gate = Completer<void>();

    final first = queue.run('long', (ticket) async {
      ticket.attach(() async {
        cancelled = true;
        gate.complete();
      });
      started.complete();
      await gate.future;
      return 'done';
    });
    final second = queue.run('next', (ticket) async => 'next');

    await started.future;
    await queue.cancelCurrent();
    expect(cancelled, isTrue);
    expect(await first, 'done');
    expect(await second, 'next');
    queue.dispose();
  });

  test('排队任务的取消回调不会被误调用', () async {
    final queue = CommandQueue();
    var secondCancelled = false;
    final gate = Completer<void>();

    final first = queue.run('first', (ticket) async {
      await gate.future;
      return 'first-done';
    });
    final second = queue.run(
      'second',
      (ticket) async {
        ticket.attach(() async {
          secondCancelled = true;
        });
        return 2;
      },
    );

    await queue.cancelCurrent();
    expect(secondCancelled, isFalse);
    gate.complete();
    expect(await first, 'first-done');
    expect(await second, 2);
    queue.dispose();
  });

  test('取消发生在 attach 之前会在 attach 时补发', () async {
    final queue = CommandQueue();
    var cancelled = false;
    final ticketReady = Completer<QueueTicket>();
    final attachStarted = Completer<void>();

    final first = queue.run('first', (ticket) async {
      ticketReady.complete(ticket);
      await attachStarted.future;
      ticket.attach(() async {
        cancelled = true;
      });
      return 1;
    });

    final ticket = await ticketReady.future;
    await ticket.cancel();
    expect(ticket.isCancelled, isTrue);
    attachStarted.complete();
    expect(await first, 1);
    expect(cancelled, isTrue);
    queue.dispose();
  });
}
