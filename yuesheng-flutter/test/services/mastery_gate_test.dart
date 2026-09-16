// ─────────────────────────────────────────────────────────────
// mastery_gate_test — 教学线 P0-1 软门控判定测试
//
// 覆盖 masteryEvidenceSatisfiedFromRow（顶层纯函数）+ countExplanationItems：
//   1. 无自评（三列皆空）→ 放行
//   2. 自评完整（信心 5 + 解释 2 条 + 迁移）→ 放行
//   3. 信心不足（rating 2）→ 拦截
//   4. 解释不足（1 条）→ 拦截
//   5. 迁移缺失 → 拦截
//   6. countExplanationItems 计数（句号族/换行/分号）
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/services/evaluation_service.dart';

TrainingResultRow mkRow({
  int? confidenceRating,
  String? explanationText,
  String? transferText,
}) {
  return TrainingResultRow(
    id: 'tr-test',
    sessionId: 's-test',
    suggestionId: null,
    syndromeId: 'P003',
    taskType: 'rewrite',
    userContent: '作答',
    result: 'passed',
    feedbackJson: null,
    score: null,
    confidenceRating: confidenceRating,
    explanationText: explanationText,
    transferText: transferText,
    createdAt: 0,
  );
}

void main() {
  group('masteryEvidenceSatisfiedFromRow', () {
    test('#1 无自评（三列皆空）→ 放行', () {
      expect(
        masteryEvidenceSatisfiedFromRow(mkRow()),
        isTrue,
        reason: '旧数据/学员跳过自评不阻塞（渐进 + R-009）',
      );
    });

    test('#2 自评完整（信心 5 + 解释 2 条 + 迁移）→ 放行', () {
      final row = mkRow(
        confidenceRating: 5,
        explanationText: '因为主语要明确。我删掉了情绪词。',
        transferText: '换成对话我会先写动作。',
      );
      expect(masteryEvidenceSatisfiedFromRow(row), isTrue);
    });

    test('#3 信心不足（rating 2）→ 拦截', () {
      final row = mkRow(
        confidenceRating: 2,
        explanationText: '因为主语要明确。我删掉了情绪词。',
        transferText: '换成对话我会先写动作。',
      );
      expect(masteryEvidenceSatisfiedFromRow(row), isFalse);
    });

    test('#4 解释不足（1 条）→ 拦截', () {
      final row = mkRow(
        confidenceRating: 5,
        explanationText: '因为主语要明确。',
        transferText: '换成对话我会先写动作。',
      );
      expect(masteryEvidenceSatisfiedFromRow(row), isFalse);
    });

    test('#5 迁移缺失 → 拦截', () {
      final row = mkRow(
        confidenceRating: 5,
        explanationText: '因为主语要明确。我删掉了情绪词。',
      );
      expect(masteryEvidenceSatisfiedFromRow(row), isFalse);
    });

    test('#6 信心缺失但有解释+迁移 → 按 rating 0 拦截', () {
      final row = mkRow(
        explanationText: '因为主语要明确。我删掉了情绪词。',
        transferText: '换成对话我会先写动作。',
      );
      expect(masteryEvidenceSatisfiedFromRow(row), isFalse);
    });
  });

  group('countExplanationItems', () {
    test('#7 句号族计数（2 条）', () {
      expect(countExplanationItems('因为主语要明确。我删掉了情绪词。'), 2);
    });

    test('#8 换行/分号计数（3 条）', () {
      expect(countExplanationItems('主语要明确；\n我删掉了情绪词！\n还有节奏。'), 3);
    });

    test('#9 空/空白 → 0', () {
      expect(countExplanationItems(null), 0);
      expect(countExplanationItems('   '), 0);
      expect(countExplanationItems(''), 0);
    });
  });
}
