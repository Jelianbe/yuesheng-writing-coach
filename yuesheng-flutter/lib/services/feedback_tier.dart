// ─────────────────────────────────────────────────────────────
// feedback_tier — M2→M3 fading 支架渐退（ADR-C134 批2）
//
// 同一症候在会话内的复发次数 → 反馈介入层级（ADR §5.2 写死层级表）。
//
// N 口径：countConfirmedDiagnosesBySyndrome(sessionId) 返回的是「本轮诊断
// 落库之前」已 confirmed 的行数（本轮尚未 commit，**不含本轮**）。设 prior=c：
//   c=0 → N=1 首次：指认 + 受限示范单句（默认教学路径，不注入 override）
//   c=1 → N=2：只指根因 + 方向（无示范句）
//   c≥2 → N≥3：只问「你发现了吗」（引导学员自主指认，不给答案）
//
// 纯函数库（无状态、无 IO）。buildFadingBlock 返回可直接追加进诊断反馈 prompt
// 的 override 块；无复发（全部 c<1）时返回 null → 调用方不注入，const/无会话
// 数据用例零漂移。
//
// R-009：所有层级不替写学员句子、不打分、不探测；N≥3 为引导自主指认的提问，
// 不提示答案。提问类仅在学员 highStable 资格时启用，否则安全降级为根因+方向
// （低水平/消沉学员不得用引导提问）。
// ─────────────────────────────────────────────────────────────

import 'feedback_variant_pool.dart';
import 'feedback_variant_scheduler.dart';

/// 反馈介入层级（fading 支架渐退三档）。
enum FeedbackTier {
  /// N=1 首次指认 + 受限示范（默认教学路径，不注入 override）。
  firstTouch,

  /// N=2 只指根因与方向，不给示范句。
  rootCauseOnly,

  /// N≥3 引导自主指认（「你发现了吗」，不直接给答案）。
  guidedRecall,
}

/// prior 已 confirmed 次数 → 本轮反馈层级（口径见文件头 N 口径说明）。
FeedbackTier tierForPriorCount(int priorConfirmed) {
  if (priorConfirmed >= 2) return FeedbackTier.guidedRecall;
  if (priorConfirmed == 1) return FeedbackTier.rootCauseOnly;
  return FeedbackTier.firstTouch;
}

/// 由会话内 prior confirmed 计数 + 学员资格构造 fading override 块。
///
/// 返回 null = 无任何复发症候（全部 prior<1），走默认教学路径、不注入。
/// 仅枚举 prior≥1（N≥2）的症候；guidedRecall 在学员非 highStable 时安全降级
/// 为 rootCauseOnly（资格门：低水平/消沉不得用引导提问）。
String? buildFadingBlock(
  Map<String, int> priorBySyndrome,
  FeedbackEligibility eligibility,
) {
  final lines = <String>[];
  priorBySyndrome.forEach((sid, c) {
    if (c < 1) return; // N=1 首次：默认路径，不进 override 块
    var tier = tierForPriorCount(c);
    if (tier == FeedbackTier.guidedRecall &&
        eligibility != FeedbackEligibility.highStableOnly) {
      tier = FeedbackTier.rootCauseOnly; // 资格门安全降级
    }
    lines.add(_lineFor(sid, c, tier, eligibility));
  });
  if (lines.isEmpty) return null;
  return '\n\n【复发症候·渐退反馈（fading）】\n'
      '本会话此前已诊断过下列症候，再次遇到时按「少示范、多放手」递减介入；'
      '首次出现的症候仍走默认教学路径（指认 + 受限示范单句）：\n'
      '${lines.join('\n')}';
}

/// 单条复发症候的 override 行：层级指令 + 池内表达骨架（若有）。
///
/// 软风格层生产接线：按层级经 scheduler 选一条池内变体作表达骨架；试点外
/// 症候无池内变体时仅保留层级指令（调用方已在边界层容错，这里不抛错）。
String _lineFor(
  String syndromeId,
  int priorCount,
  FeedbackTier tier,
  FeedbackEligibility eligibility,
) {
  final occurrenceNo = priorCount + 1; // 本轮是第几次见到它
  final directive = switch (tier) {
    FeedbackTier.rootCauseOnly =>
      '第 $occurrenceNo 次复发：只指根因与方向，'
          '不要给示范句。',
    FeedbackTier.guidedRecall =>
      '第 $occurrenceNo 次复发：不直接指认，先问'
          '「你发现这一处的问题了吗」，等学员自己说出根因，不要提示答案。',
    FeedbackTier.firstTouch => '',
  };
  final variant = selectVariantForRecurrence(
    syndromeId,
    priorCount,
    eligibility,
  );
  final skeleton = variant == null
      ? ''
      : '\n    表达骨架（{anchor}=你标出的原句片段，{word}=具体词，替换后使用）：'
            '${variant.template}';
  return '- [$syndromeId] $directive$skeleton';
}
