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
// 的介入层级块。ADR-C139（D1 修复）：无复发（全部 c<1，纯首次诊断）时不再返回
// null——改输出三档介入契约块，使 c=0「指认根因 + 受限示范单句」指令在任何诊断
// 请求下都可达（此前 c=0 返回 null → C136 真实回放 D1：LLM 指认根因却转引导式
// 追问、无示范句）。复发明细仅在 prior≥1 时追加。
//
// R-009：所有层级不替写学员句子、不打分、不探测；N≥3 为引导自主指认的提问，
// 不提示答案。提问类仅在学员 highStable 资格时启用，否则安全降级为根因+方向
// （低水平/消沉学员不得用引导提问）。
// ─────────────────────────────────────────────────────────────

/// 学员状态资格（fading 引导提问的资格门）。
///
/// 规则：引导提问（N≥3 guidedRecall）仅对中高水平 + 情绪平稳开放；低水平 /
/// 消沉一律安全降级为「根因 + 方向」（rootCauseOnly）。资格裁决由
/// chat_service._resolveFadingEligibility 按教学阶段完成后传入。
///
/// C146：本枚举原属 feedback_variant_pool.dart，话术变体池成句模板摘除后，
/// 资格门是教学策略决策（非话术），随 fading 层级一并迁入本文件保留。
enum FeedbackEligibility {
  /// 所有状态可用（直给 / 根因 + 方向的默认资格）。
  all('all'),

  /// 仅中高水平 + 情绪平稳可用（引导提问的强制资格）。
  highStableOnly('high_stable_only');

  final String value;
  const FeedbackEligibility(this.value);
}

/// 反馈介入层级（fading 支架渐退三档）。
enum FeedbackTier {
  /// N=1 首次指认 + 受限示范单句（介入契约始终输出此档指令）。
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

/// 由会话内 prior confirmed 计数 + 学员资格构造 fading 介入层级块。
///
/// 始终返回块（不再因无复发返回 null）：先输出三档介入契约（c=0 指认根因+受限
/// 示范单句 / c=1 只指根因与方向 / c≥2 引导自主指认），再追加 prior≥1 的复发明细。
/// guidedRecall 在学员非 highStable 时安全降级为 rootCauseOnly（资格门：低水平/
/// 消沉不得用引导提问）。
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
    lines.add(_lineFor(sid, c, tier));
  });
  // ADR-C139（D1 修复）：三档介入契约始终输出。
  // R-009：契约只给「为说明改法的一句示范」，不改全段、不替写成品段落；不评级。
  // 刻意不出现「分」字（feedback_tier_test R-009 形态审计断言块内无评分词）。
  const contract =
      '\n\n[反馈介入层级（fading）]\n'
      '按同一症候在本会话内的出现次数递减介入（少示范、多放手）：\n'
      '· 首次出现（第 1 次）：指认根因，并给一句受限示范单句——为说明改法，'
      '只示范一句、指向根因；不改全段、不替写成品段落；\n'
      '· 复发（第 2 次）：只指根因与方向，不给示范句；\n'
      '· 多次复发（第 3 次起）：不先给答案，先问「你发现这一处的问题了吗」，'
      '等学员自己说出根因。';

  if (lines.isEmpty) return contract;
  return '$contract\n'
      '\n本会话此前已诊断过下列症候，再次遇到时按上述层级递减介入：\n'
      '${lines.join('\n')}';
}

/// 单条复发症候的 override 行：层级指令（fading 渐退）。
///
/// C146：话术变体池成句模板及其生产注入已按 96-17 反硬编码护栏摘除——本块只
/// 输出教学层级指令（指根因与方向 / 引导自主指认），具体措辞由 AI 现场生成，
/// 不再注入任何写死成句骨架。
String _lineFor(String syndromeId, int priorCount, FeedbackTier tier) {
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
  return '- [$syndromeId] $directive';
}
