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
///
/// ADR-C100（2026-09-25）：新增「否定式归一 + 判定顺序前移」，消除
/// "没通过 / 不达标 / 没有完成" 被裸 `达标`/`通过` 截胡误判为 passed 的类。
/// 详见 `.ai/reports/2026-09-25-D01-D02-侦察与裁决.md` §2 与
/// `.ai/reports/2026-09-25-外部审查立项与侦察队列.md`。
const Map<TrainingResult, List<String>> _kTrainingResultPatterns = {
  TrainingResult.partial: ['部分正确', '方向对了', '还需要'],
  TrainingResult.failed: ['需要重新', '不太对'],
  TrainingResult.passed: ['达标', '通过', '很好', '完成', '成功'],
};

/// 否定式前缀（ADR-C100）：与正向社会词组合即判 failed。
/// 注意 `没有` 必须排在 `没` 之前匹配，否则 "没有完成" 会被拆成
/// 没 + 有完成 而漏判。
const List<String> _kNegationPrefixes = ['未', '不', '没', '没有'];

/// 正向社会词（ADR-C100）：与否定前缀组合即判 failed。
const List<String> _kPositiveStems = ['达标', '通过', '完成', '成功'];

/// 从 AI 回复中解析训练结果
///
/// 真源：chat-training-parser.ts parseTrainingResult
///
/// ADR-C100 判定顺序（先判否定、再判肯定，杜绝虚报达标）：
///   1. 含 `部分达标` → partial（精确短语优先）
///   2. 含 partial 关键词 → partial（保守偏置，防虚报达标）
///   3. 含否定式（未/不/没/没有 + 达标|通过|完成|成功）→ failed
///   4. 含 failed 关键词 → failed
///   5. 含 passed 关键词 → passed
///   6. 无匹配 → null（= 不计通过、不写 history、不触发 FSM 重评估）
///
/// 与代码自述意图一致（本文件顶部批次2注释「宁可多练一轮不虚报达标」）。
/// 否定式未被归一前：裸 `达标`/`通过` 在否定检测之前生效，导致
/// "这次没有通过，请重试" 被判 passed（违背自述意图，且污染教学状态机）。
TrainingResult? parseTrainingResult(String content) {
  // 1. 精确短语：部分达标 必须在一切之前判定
  if (content.contains('部分达标')) return TrainingResult.partial;

  // 2. partial 关键词（保守偏置，混合表述不虚报达标）
  for (final kw in _kTrainingResultPatterns[TrainingResult.partial]!) {
    if (content.contains(kw)) return TrainingResult.partial;
  }

  // 3. 否定式归一（ADR-C100 关键修复）：未/不/没/没有 + 正向社会词 → failed。
  //    必须在序5 passed 关键词之前生效，否则裸 `达标`/`通过` 会截胡否定句。
  for (final prefix in _kNegationPrefixes) {
    for (final stem in _kPositiveStems) {
      if (content.contains('$prefix$stem')) return TrainingResult.failed;
    }
  }

  // 4. failed 关键词
  for (final kw in _kTrainingResultPatterns[TrainingResult.failed]!) {
    if (content.contains(kw)) return TrainingResult.failed;
  }

  // 5. passed 关键词
  for (final kw in _kTrainingResultPatterns[TrainingResult.passed]!) {
    if (content.contains(kw)) return TrainingResult.passed;
  }

  // 6. 无匹配：null 语义即「不计通过」—— 报告要求的「解析失败不计通过」
  //    现状已满足，无需新增 unknown 态（该语义在 ADR-C100 中明确为有意设计）。
  return null;
}
