// ─────────────────────────────────────────────────────────────
// ChatTrainingParser 单元测试 — 批次2（2.4）回退顺序
//
// 修复前：关键词 Map 遍历 passed→partial→failed，"完成"先命中 →
// 混合表述"完成度不错，但还需要重新处理"被虚报为达标（passed）。
// 修复后：partial → failed → passed（保守偏置：宁可多练一轮不虚报达标）。
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/services/chat_training_parser.dart';
import 'package:writingcoach/types/teaching_types.dart';

void main() {
  group('parseTrainingResult（批次2 2.4 回退顺序）', () {
    test('#1 混合表述：完成度不错 + 还需要重新处理 → partial（不虚报达标）', () {
      expect(
        parseTrainingResult('完成度不错，但因果链还需要重新处理'),
        TrainingResult.partial,
        reason: '同时含 partial「还需要」与 passed「完成」，partial 优先（保守偏置）',
      );
    });

    test('#2 精确短语「部分达标」→ partial', () {
      expect(parseTrainingResult('这部分算部分达标'), TrainingResult.partial);
    });

    test('#3 精确短语「未达标」→ failed', () {
      expect(parseTrainingResult('本次练习未达标'), TrainingResult.failed);
    });

    test('#4 「达标」→ passed', () {
      expect(parseTrainingResult('这次已经达标了'), TrainingResult.passed);
    });

    test('#5 「未通过」→ failed', () {
      expect(parseTrainingResult('本次练习未通过'), TrainingResult.failed);
    });

    test('#6 「方向对了」→ partial', () {
      expect(parseTrainingResult('方向对了，但细节还要打磨'), TrainingResult.partial);
    });

    test('#7 无关键词 → null', () {
      expect(parseTrainingResult('继续练习吧'), isNull);
    });
  });
}
