// ─────────────────────────────────────────────────────────────
// ChatTrainingParser — 训练结果解析
// 复刻 yuesheng-android/src/services/chat-training-parser.ts
//
// 从 AI 回复中解析训练结果（passed/partial/failed）。
// 纯函数无 IO 依赖。
// ─────────────────────────────────────────────────────────────

import 'package:writingcoach/types/teaching_types.dart';

/// 训练结果解析的关键词模式
///
/// 真源：chat-training-parser.ts TRAINING_RESULT_PATTERNS
/// 批次2（2.4）：Map 遍历顺序 partial → failed → passed（保守偏置：
/// 宁可多练一轮不虚报达标）。混合表述（如"完成度不错，但还需要重新处理"）
/// 同时含 partial 与 passed 关键词时，partial 优先命中，避免虚报达标。
const Map<TrainingResult, List<String>> _kTrainingResultPatterns = {
  TrainingResult.partial: ['部分达标', '部分正确', '方向对了', '还需要'],
  TrainingResult.failed: ['未达标', '未通过', '需要重新', '不太对'],
  TrainingResult.passed: ['达标', '通过', '很好', '完成', '成功'],
};

/// 从 AI 回复中解析训练结果
///
/// 真源：chat-training-parser.ts parseTrainingResult
///
/// 匹配优先级：
///   1. 精确短语：部分达标 > 未达标 > 达标
///   2. 关键词：partial > failed > passed（保守偏置，防虚报达标）
///   3. 无匹配：返回 null
TrainingResult? parseTrainingResult(String content) {
  // 优先匹配精确短语（部分达标必须在达标之前判定，避免误判为 passed）
  if (content.contains('部分达标')) return TrainingResult.partial;
  if (content.contains('未达标')) return TrainingResult.failed;
  if (content.contains('达标')) return TrainingResult.passed;

  // 其次匹配关键词（partial 优先，混合表述不虚报达标）
  for (final entry in _kTrainingResultPatterns.entries) {
    for (final kw in entry.value) {
      if (content.contains(kw)) {
        return entry.key;
      }
    }
  }

  return null;
}
