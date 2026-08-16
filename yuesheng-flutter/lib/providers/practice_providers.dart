// ─────────────────────────────────────────────────────────────
// practice_providers — 练习任务状态管理
// 复刻 yuesheng-android/src/store/practice-store.ts
//
// 状态：
//   - activePracticeTask：当前练习任务（Teacher 建议「开始练习」触发）
//   - trainingResult：最近一次训练结果（passed/partial/failed/null）
//   - isSubmitting：是否提交中（防连点）
//
// 生命周期：
//   startPractice(task) → activePracticeTask = task
//   submitPractice() → 清空任务（结果由 onTrainingResult 回调单独设置）
//   skipPractice() → 清空任务
//   setTrainingResult(r) → 记录结果
//   resetPractice() → 全部清空
// ─────────────────────────────────────────────────────────────

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../types/teaching_types.dart';

/// 练习任务
class PracticeTask {
  final String? syndromeId;
  final String? syndromeName;
  final String taskDescription;
  final String taskGoal;

  const PracticeTask({
    this.syndromeId,
    this.syndromeName,
    required this.taskDescription,
    required this.taskGoal,
  });
}

/// 练习状态（不可变）
class PracticeState {
  final PracticeTask? activePracticeTask;
  final TrainingResult? trainingResult;
  final bool isSubmitting;

  const PracticeState({
    this.activePracticeTask,
    this.trainingResult,
    this.isSubmitting = false,
  });
}

/// 练习状态管理
class PracticeStore extends StateNotifier<PracticeState> {
  PracticeStore() : super(const PracticeState());

  /// 最近一次练习任务（供「再试一次」重新打开）
  PracticeTask? _lastTask;

  /// 开始练习：设置活动任务
  void startPractice(PracticeTask task) {
    _lastTask = task;
    state = PracticeState(activePracticeTask: task);
  }

  /// 提交练习：清空活动任务（结果由 onTrainingResult 单独设置）
  void submitPractice() {
    state = PracticeState(trainingResult: state.trainingResult);
  }

  /// 跳过练习：清空活动任务
  void skipPractice() {
    state = PracticeState(trainingResult: state.trainingResult);
  }

  /// 设置训练结果
  void setTrainingResult(TrainingResult? result) {
    state = PracticeState(
      activePracticeTask: state.activePracticeTask,
      trainingResult: result,
    );
  }

  /// 设置提交中状态
  void setSubmitting(bool submitting) {
    state = PracticeState(
      activePracticeTask: state.activePracticeTask,
      trainingResult: state.trainingResult,
      isSubmitting: submitting,
    );
  }

  /// 再试一次：重新打开上次练习任务，清空结果（对齐 RN onRetry 语义）
  void retryPractice() {
    final task = _lastTask;
    if (task == null) return;
    state = PracticeState(activePracticeTask: task);
  }

  /// 重置全部练习状态
  void resetPractice() {
    _lastTask = null;
    state = const PracticeState();
  }
}

/// 全局练习 store（单例）
final practiceStoreProvider =
    StateNotifierProvider<PracticeStore, PracticeState>((ref) {
      return PracticeStore();
    });
