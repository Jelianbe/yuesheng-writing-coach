// ─────────────────────────────────────────────────────────────
// PracticeStore 单元测试 — 练习任务状态管理
//
// 覆盖路径：
//   1. startPractice → activePracticeTask 设置
//   2. submitPractice → 清空活动任务（保留结果）
//   3. skipPractice → 清空活动任务（保留结果）
//   4. setTrainingResult → 结果记录
//   5. retryPractice → 重新打开上次任务 + 清空结果（failed 再试）
//   6. resetPractice → 全部清空
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/providers/practice_providers.dart';
import 'package:writingcoach/types/teaching_types.dart';

PracticeTask _task({String name = '叙事含糊'}) {
  return PracticeTask(
    syndromeId: 's1',
    syndromeName: name,
    taskDescription: '针对「叙事含糊」完成一段针对性写作练习。',
    taskGoal: '用具体细节替代抽象概括。',
  );
}

void main() {
  group('PracticeStore', () {
    test('startPractice → activePracticeTask 设置', () {
      final store = PracticeStore();
      final task = _task();

      store.startPractice(task);

      expect(store.state.activePracticeTask, same(task));
      expect(store.state.trainingResult, isNull);
    });

    test('submitPractice → 清空活动任务（保留结果）', () {
      final store = PracticeStore();
      store.startPractice(_task());
      store.setTrainingResult(TrainingResult.passed);

      store.submitPractice();

      expect(store.state.activePracticeTask, isNull);
      expect(store.state.trainingResult, TrainingResult.passed);
    });

    test('skipPractice → 清空活动任务', () {
      final store = PracticeStore();
      store.startPractice(_task());

      store.skipPractice();

      expect(store.state.activePracticeTask, isNull);
    });

    test('setTrainingResult → 结果记录', () {
      final store = PracticeStore();
      store.startPractice(_task());

      store.setTrainingResult(TrainingResult.failed);

      expect(store.state.trainingResult, TrainingResult.failed);
    });

    test('retryPractice → 重新打开上次任务 + 清空结果', () {
      final store = PracticeStore();
      final task = _task();
      store.startPractice(task);
      store.submitPractice();
      store.setTrainingResult(TrainingResult.failed);
      expect(store.state.activePracticeTask, isNull);

      store.retryPractice();

      expect(store.state.activePracticeTask, same(task));
      expect(store.state.trainingResult, isNull);
      expect(store.state.isSubmitting, isFalse);
    });

    test('retryPractice（无上次任务）→ 状态不变', () {
      final store = PracticeStore();

      store.retryPractice();

      expect(store.state.activePracticeTask, isNull);
      expect(store.state.trainingResult, isNull);
    });

    test('resetPractice → 全部清空，且不可再 retry', () {
      final store = PracticeStore();
      store.startPractice(_task());
      store.setTrainingResult(TrainingResult.partial);

      store.resetPractice();

      expect(store.state.activePracticeTask, isNull);
      expect(store.state.trainingResult, isNull);

      store.retryPractice();
      expect(store.state.activePracticeTask, isNull);
    });
  });
}
