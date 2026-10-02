// ─────────────────────────────────────────────────────────────
// feedback_variant_scheduler — 软风格层调度（ADR-C132 批2）
//
// 三层调度（变体池研讨报告 §4）：
//   硬门层（运行时强制：稿件锚定 / 状态资格 / 近轮去重）—— 资格由
//   调用方按学员状态裁决后传入 [FeedbackEligibility]；
//   persona 层（稳定声线）—— 在 skill_dispatcher 装配；
//   **软风格层（本文件）** —— 在 persona 内轮换表达面：按症候选变体、
//   填占位符、支持近轮去重（excludeIds）。
//
// 状态：纯函数库（无状态、无 IO），调度结果由调用方消费。
// 生产 LLM 接线（把选中的变体模板注入诊断反馈 prompt）属后续批，
// 本批交付调度能力 + 注入资产就绪（ADR §9 轮2 试点口径）。
//
// 约束（研讨报告 §4.3 / ADR §4）：
//  - 提问类变体（guidedQuestion）仅在中高水平 + 情绪平稳时可选——
//    由调用方传 [FeedbackEligibility.highStableOnly] 之外的值即被过滤；
//  - 主标签互斥、次标签可叠加由数据层保证（validateVariantPool）。
// ─────────────────────────────────────────────────────────────

import 'feedback_variant_pool.dart';

/// 按症候 + 状态资格选择一条变体。
///
/// [eligibility] 为当前学员状态对应的资格：
///   - 低水平 / 消沉 → [FeedbackEligibility.all]（提问类会被过滤）
///   - 中高水平 + 情绪平稳 → [FeedbackEligibility.highStableOnly]
///     （提问类可选；all 类也可用）
/// [excludeIds] 为近轮已用变体 id（近轮去重硬门层），默认空。
/// [preferFunction] 可指定偏好功能（如本轮要引导提问）；无可选时忽略。
/// 返回 null = 该症候无符合资格的变体（调用方回退默认话术路径）。
FeedbackVariant? selectVariant(
  String syndromeId, {
  required FeedbackEligibility eligibility,
  Set<String> excludeIds = const {},
  FeedbackFunction? preferFunction,
}) {
  var candidates = [
    for (final v in variantsForSyndrome(syndromeId))
      if (_eligible(v, eligibility) && !excludeIds.contains(v.id)) v,
  ];
  if (candidates.isEmpty) return null;
  if (preferFunction != null) {
    final preferred = [
      for (final v in candidates)
        if (v.function == preferFunction) v,
    ];
    if (preferred.isNotEmpty) candidates = preferred;
  }
  // 轮换：取候选集首条（调用方用 excludeIds 排除近轮已用即实现轮换）。
  return candidates.first;
}

/// 填充变体模板占位符（{anchor}/{word} → 具体文本）。
///
/// 缺失的占位符保持原样（调用方负责传全参数；缺参不抛错，
/// 让调度层在数据不完整时也能降级输出而非崩掉）。
String fillVariantTemplate(FeedbackVariant v, Map<String, String> params) {
  var text = v.template;
  for (final entry in params.entries) {
    text = text.replaceAll('{${entry.key}}', entry.value);
  }
  return text;
}

/// 资格裁决：变体是否可用于当前学员状态。
///
/// 规则（研讨报告 §4 资格门）：highStableOnly 变体仅在调用方声明
/// 高稳定资格时可用；all 变体任何状态可用。
bool _eligible(FeedbackVariant v, FeedbackEligibility eligibility) =>
    v.eligibility == FeedbackEligibility.all ||
    eligibility == FeedbackEligibility.highStableOnly;
