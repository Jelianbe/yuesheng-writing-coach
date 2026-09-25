// ─────────────────────────────────────────────────────────────
// training_contract_test — B29 训练结果解析契约测试（纯函数）
//
// 锁定 parseTrainingResult 的关键行为，防止保守偏置（partial > failed > passed）
// 被误改导致虚报达标：
//   1. 精确短语优先级：部分达标 > 未达标 > 达标
//   2. 混合表述（含 partial 与 passed 关键词）→ 判 partial，不虚报达标
//   3. 无关键词 → 返回 null（交给上游兜底）
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/chat_training_parser.dart';
import 'package:writingcoach/types/teaching_types.dart';

void main() {
  group('parseTrainingResult 精确短语优先级', () {
    test('部分达标 → partial', () {
      expect(parseTrainingResult('本次练习部分达标'), TrainingResult.partial);
    });
    test('未达标 → failed', () {
      expect(parseTrainingResult('本次练习未达标'), TrainingResult.failed);
    });
    test('达标 → passed', () {
      expect(parseTrainingResult('本次练习达标'), TrainingResult.passed);
    });
  });

  group('parseTrainingResult 混合表述保守偏置', () {
    test('「完成度不错，但还需要重新处理」→ partial（不虚报达标）', () {
      // 同时含「完成」(passed 关键词) 与「还需要」(partial 关键词)，
      // partial 必须优先命中，避免对未完成练习虚报达标。
      expect(parseTrainingResult('完成度不错，但还需要重新处理'), TrainingResult.partial);
    });
    test('「方向对了，但还需要打磨」→ partial', () {
      expect(parseTrainingResult('方向对了，但还需要打磨'), TrainingResult.partial);
    });
    test('「达标，但部分达标」→ partial（精确短语优先于关键词）', () {
      expect(parseTrainingResult('整体达标，但部分达标'), TrainingResult.partial);
    });
    test('「不太对，需要重新来」→ failed', () {
      // 「不太对」(failed 关键词) 命中，优先于任何 passed 关键词。
      expect(parseTrainingResult('这个不太对，需要重新来'), TrainingResult.failed);
    });
    test('「很好，写得不错」→ passed', () {
      expect(parseTrainingResult('很好，写得不错'), TrainingResult.passed);
    });
  });

  group('parseTrainingResult 无匹配兜底', () {
    test('无关文本 → null', () {
      expect(parseTrainingResult('今天天气真好，我们聊聊别的'), isNull);
    });
    test('空串 → null', () {
      expect(parseTrainingResult(''), isNull);
    });
  });

  group('parseTrainingResult 否定式归一（ADR-C100 回归护栏）', () {
    // 这些「单句纯否定」用例同时是 ADR-C100 的负向验证：若序3（否定式归一）
    // 被摘掉，下列输入会落到序5 passed 关键词（含「通过」「达标」「完成」）
    // 而误判 passed —— 届时本组整体变红，门禁拦下回归。
    test('「这次没有通过，请重试」→ failed（否定式归一）', () {
      expect(parseTrainingResult('这次没有通过，请重试'), TrainingResult.failed);
    });
    test('「目标是达标，本次未通过」→ failed', () {
      expect(parseTrainingResult('目标是达标，本次未通过'), TrainingResult.failed);
    });
    test('「本次还不达标」→ failed', () {
      expect(parseTrainingResult('本次还不达标'), TrainingResult.failed);
    });
    test('「本次练习不达标」→ failed', () {
      expect(parseTrainingResult('本次练习不达标'), TrainingResult.failed);
    });
    test('「没有完成」→ failed', () {
      expect(parseTrainingResult('没有完成'), TrainingResult.failed);
    });
    test('「不通过」→ failed（不互为「未通过」子串）', () {
      expect(parseTrainingResult('不通过'), TrainingResult.failed);
    });
    test('「还没达标，但方向对了」→ partial（partial 先于否定式）', () {
      // 混合句：方向对了（partial 关键词）优先于否定式，归 partial（保守偏置）。
      expect(parseTrainingResult('还没达标，但方向对了'), TrainingResult.partial);
    });
  });
}
