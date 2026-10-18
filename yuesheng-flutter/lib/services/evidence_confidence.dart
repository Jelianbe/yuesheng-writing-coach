// ─────────────────────────────────────────────────────────────
// evidence_confidence — 证据把握度（本地计算，替代模型自报置信度）
//
// 背景（信心系统重构 · Part B）：原诊断协议让模型输出一个 0-1 的
// `confidence`，但模型自报的单次置信度不校准、纯展示无作用、还消耗
// 输出 token。改为**本地计算**的证据把握度：
//   把握 = 证据强度（该症候 evidence 条数 + 引用原文具体度）
//        + 跨轮复现加成（同症候跨会话出现次数）
// 数据诚实约束：数值只来自真实落库/解析数据，不来自模型猜测。
//
// 用途：
//   - 弱把握（< [kWeakEvidenceConfidence]）症候 → 标「待确认（证据
//     不足）」，不进活跃症候注入、不当教学焦点，用户确认后才进入。
//   - 替代诊断卡上原模型 confidence 的展示。
// ─────────────────────────────────────────────────────────────

/// 弱证据把握度阈值：低于此值视为「证据不足」，需用户确认后才进入教学。
///
/// ★ 2026-10-18 活性审查（T-20261018-01 / DECISIONS §4-214 裁3）：
/// **数学死路登记**——本阈值在正常诊断产出上结构性不可达：
/// `computeEvidenceConfidence` 的输出下界 = 0 条证据 0.0（会被解析拒绝）/
/// 1 条 <6 字短证据 0.35（诊断协议要求 5-20 字 evidence，近乎不存在）/
/// 1 条具体证据 0.55（> 0.4）；语料实测 240 格 + t02 复跑共 1136 条
/// 把握度**零触发**（最低 0.55）。`isWeakEvidence` / `isWeakUnconfirmed`
/// 为活代码 + 不可达分支。降阈值属无数据支撑的行为变更（§4-214 裁3 否决）；
/// 若未来放宽协议允许超短证据，此处须先复测可达性再议。
const double kWeakEvidenceConfidence = 0.4;

/// 单条 evidence 视为「具体」的最小长度（引用了具体原文，而非泛泛描述）。
const int kEvidenceSpecificMinChars = 6;

/// 计算单个症候的证据把握度（0-1）。
///
/// [evidence]：该症候引用的原文片段列表（解析自诊断块）。
/// [recurrenceOccurrences]：同症候跨会话出现次数（>=2 视为复现，上调把握）。
///
/// 分量设计（刻意简单、可解释，避免给"信心"加玄学）：
///   - 证据强度分量（0.0–0.8）：
///       * 0 条 → 0.0
///       * 1 条且短（< [kEvidenceSpecificMinChars]）→ 0.35（弱）
///       * 1 条且具体 → 0.55
///       * >=2 条 → 0.65 + 0.05*(n-2)，封顶 0.8
///   - 复现加成（0.0–0.2）：出现 >=2 次 → +0.15；>=4 次 → +0.2
/// 综合 clamp 到 [0, 1]。
double computeEvidenceConfidence({
  required List<String> evidence,
  required int recurrenceOccurrences,
}) {
  final n = evidence.length;

  // 1. 证据强度分量（0.0–0.8）
  double strength;
  if (n == 0) {
    strength = 0.0;
  } else if (n == 1) {
    final specific = evidence.first.trim().length >= kEvidenceSpecificMinChars;
    strength = specific ? 0.55 : 0.35;
  } else {
    strength = 0.65 + 0.05 * (n - 2);
  }
  strength = strength.clamp(0.0, 0.8).toDouble();

  // 2. 复现加成（0.0–0.2）
  final occ = recurrenceOccurrences;
  double recurrence = 0.0;
  if (occ >= 4) {
    recurrence = 0.2;
  } else if (occ >= 2) {
    recurrence = 0.15;
  }

  return ((strength + recurrence).clamp(0.0, 1.0) * 100).round() / 100;
}

/// 是否视为「证据不足」（弱把握）。
bool isWeakEvidence(double confidence) => confidence < kWeakEvidenceConfidence;

/// Whether a syndrome is 'weak-confidence AND unconfirmed' (Part B gate).
/// NULL evidenceConfidence (legacy data / growth view) is NOT weak -> not gated.
bool isWeakUnconfirmed({
  required double? evidenceConfidence,
  required bool confirmed,
}) =>
    evidenceConfidence != null &&
    evidenceConfidence < kWeakEvidenceConfidence &&
    !confirmed;
