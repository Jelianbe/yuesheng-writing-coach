// ─────────────────────────────────────────────────────────────
// writing_coach_panel 相关：纯 prompt 构造 / 展示纯函数
//
// R-019 真分解：把「不依赖任何实例状态」的字符串逻辑抽为 top-level 函数，
// 供 WritingCoachSessionActions / WritingCoachTeachingController 复用。
// 无副作用、无 Flutter 依赖，便于单测与复用。
// ─────────────────────────────────────────────────────────────

import 'partial_agreement_card.dart' show quickOptionLabel;

/// 批次81 H3：部分认同「部分认同」反馈 → 组装发送文案（含快速选项展开）。
///
/// [feedback] 用户手写反馈；[quickOption] 快速选项 value（非空时优先）。
/// 调用方需先保证 detail 非空。
String buildPartialAgreementMessage(String feedback, String? quickOption) {
  final detail = quickOption != null ? quickOptionLabel(quickOption) : feedback;
  return '我对刚才的诊断结果有不同看法：$detail。请根据我的反馈调整诊断。';
}

/// 批次81 H3：部分认同「跳过此症候」→ 组装重新诊断文案。
String buildPartialAgreementSkipMessage() => '请跳过这个症候，重新给出诊断结果。';

/// 批次61：Teacher 建议卡「教我原理」→ 组装教原理请求文案。
String buildTeachPrincipleMessage(String syndromeName) {
  return '我想了解「$syndromeName」的原理。请用简单的话给我讲清楚：'
      '它是什么、怎么判断、怎么避免。一次只讲一个点。';
}

/// 诊断用户消息展示文案（批次98：对话历史只展示简洁消息，全文运行时注入）。
String buildDiagnosisUserMessageContent(bool isSelection) =>
    isSelection ? '请诊断以下选中文本' : '请诊断本章内容';

/// 单次诊断 prompt（对齐 RN chat.tsx#L212：显式要求 [YS_DIAGNOSIS] 格式，
/// 全文由 SendMessageOptions.chapterFullText 运行时注入，不落库）。
String buildDiagnosisPrompt(String title, bool isSelection) =>
    isSelection ? '请诊断选中文本' : '请诊断本章：《$title》';
