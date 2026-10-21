import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/vertical_slice.dart';
import 'bootstrap.dart';

class SelfCheckState {
  const SelfCheckState({
    this.running = false,
    this.steps = const <SliceStep>[],
    this.logs = const <String>[],
    this.report,
    this.error,
    this.currentStep,
  });

  final bool running;
  final List<SliceStep> steps;
  final List<String> logs;
  final VerticalSliceReport? report;
  final String? error;
  final String? currentStep;

  bool get hasRun => report != null || steps.isNotEmpty || error != null;

  bool get passed => report?.success ?? false;

  bool get cancelled => report?.cancelled ?? false;

  SelfCheckState copyWith({
    bool? running,
    List<SliceStep>? steps,
    List<String>? logs,
    VerticalSliceReport? report,
    String? error,
    String? currentStep,
  }) {
    return SelfCheckState(
      running: running ?? this.running,
      steps: steps ?? this.steps,
      logs: logs ?? this.logs,
      report: report ?? this.report,
      error: error ?? this.error,
      currentStep: currentStep ?? this.currentStep,
    );
  }
}

final selfCheckProvider =
    NotifierProvider<SelfCheckController, SelfCheckState>(
      SelfCheckController.new,
    );

class SelfCheckController extends Notifier<SelfCheckState> {
  VerticalSliceRunner? _runner;

  @override
  SelfCheckState build() => const SelfCheckState();

  Future<void> run() async {
    if (state.running) return;
    final bootstrap = await ref.read(bootstrapProvider.future);
    final gateway = bootstrap.gateway;
    if (gateway == null) {
      state = SelfCheckState(
        error: bootstrap.error ?? '核心 sidecar 不可用。',
      );
      return;
    }

    final logs = <String>[];
    state = const SelfCheckState(running: true);

    void append(String line) {
      logs.add('[${_clock()}] $line');
      state = state.copyWith(logs: List<String>.unmodifiable(logs));
    }

    append('开始 M0 垂直切片 · core ${bootstrap.version ?? '未知'}');
    final runner = VerticalSliceRunner(
      gateway: gateway,
      logger: append,
      onStepStarted: (title) {
        state = state.copyWith(currentStep: title);
      },
      onStepFinished: (step) {
        state = SelfCheckState(
          running: state.running,
          steps: List<SliceStep>.unmodifiable([...state.steps, step]),
          logs: state.logs,
          report: state.report,
          error: state.error,
        );
      },
    );
    _runner = runner;
    try {
      final report = await runner.run();
      state = SelfCheckState(
        running: false,
        steps: report.steps,
        logs: List<String>.unmodifiable(logs),
        report: report,
        error: report.error,
      );
    } catch (error) {
      append('异常终止：$error');
      state = SelfCheckState(
        running: false,
        logs: List<String>.unmodifiable(logs),
        error: '$error',
      );
    } finally {
      _runner = null;
    }
  }

  Future<void> cancel() async {
    await _runner?.cancel();
  }

  void reset() {
    if (state.running) return;
    state = const SelfCheckState();
  }

  String _clock() {
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(now.hour)}:${two(now.minute)}:${two(now.second)}';
  }
}
