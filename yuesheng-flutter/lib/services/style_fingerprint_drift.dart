// ─────────────────────────────────────────────────────────────
// style_fingerprint 拆分：style_fingerprint_drift.dart（R-019 ≤300 行）
// 声线漂移检测 detectVoiceDrift。迁移自 style_fingerprint.dart，行为零变更。
// ─────────────────────────────────────────────────────────────
part of 'style_fingerprint.dart';
/// 声线漂移检测：当前指纹 vs 基线指纹。
///
/// 返回例证式提示列表（最多 3 条，按显著性排序）；无偏差返回空列表。
/// 文案对齐报告 L3→L1 触发示例（"你的句子长度通常 15-20 词，但这章平均 8 词——
/// 是刻意加速还是无意识变化？"）——提问式、软引导、带具体数字。
List<String> detectVoiceDrift(
  StyleFingerprint baseline,
  StyleFingerprint current,
) {
  final hints = <String>[];

  // 1. 句长均值偏离
  if (baseline.avgSentenceLength > 0) {
    final ratio =
        (current.avgSentenceLength - baseline.avgSentenceLength).abs() /
        baseline.avgSentenceLength;
    if (ratio >= kDriftSentenceLengthRatio) {
      hints.add(
        '你的句子长度通常约 ${baseline.avgSentenceLength.round()} 字，'
        '但这段平均只有 ${current.avgSentenceLength.round()} 字——'
        '是刻意加速，还是无意识的变化？',
      );
    }
  }

  // 2. 对话/叙述配比偏离
  if ((current.dialogueRatio - baseline.dialogueRatio).abs() >=
      kDriftDialogueRatioAbs) {
    final bPct = (baseline.dialogueRatio * 100).round();
    final cPct = (current.dialogueRatio * 100).round();
    hints.add(
      '你通常对话约占 $bPct%，但这段到了 $cPct%——'
      '对话和叙述的配比变化，是有意为之吗？',
    );
  }

  // 3. 句式结构偏离（简单句占比）
  if ((current.simpleSentenceRatio - baseline.simpleSentenceRatio).abs() >=
      kDriftSimpleRatioAbs) {
    final bPct = (baseline.simpleSentenceRatio * 100).round();
    final cPct = (current.simpleSentenceRatio * 100).round();
    hints.add(
      '你惯用的句式偏${baseline.simpleSentenceRatio >= 0.5 ? '简短' : '绵长'}'
      '（简单句约 $bPct%），这段到了 $cPct%——'
      '是情绪需要，还是节奏不自觉地变了？',
    );
  }

  // 4. 标点特征偏离（感叹号/省略号激增）
  if (current.exclamationDensity >= kDriftExclamationMin &&
      baseline.exclamationDensity < kDriftExclamationBaselineMax) {
    hints.add(
      '这段感叹号比平时多不少（每千字 ${current.exclamationDensity.round()} 个）——'
      '是情绪强烈，还是语气不自觉地变急了？',
    );
  }
  if (current.ellipsisDensity >= kDriftEllipsisMin &&
      baseline.ellipsisDensity < kDriftEllipsisBaselineMax) {
    hints.add(
      '这段省略号用得比平时密（每千字 ${current.ellipsisDensity.round()} 次）——'
      '是留白的刻意安排吗？',
    );
  }

  return hints.take(3).toList();
}
