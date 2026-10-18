// ─────────────────────────────────────────────────────────────
// growth_narrative — 成长页「与上次相比」进步叙事装配（纯函数）
// （T-20261018-03 · B 议题 · 设计批 2026-10-18 舰长「批」）
//
// 职责：把 GrowthStore 已加载的既有数据（跨会话评估历史 + 症候复发）
// 装配成「时间轴上的事实陈述序列」——回答学员「我比上次强在哪」。
//
// R-009 / 四硬隔离符合性（设计批 §三，逐条）：
//   - 只陈述事实：条目句式全部为绝对值或时点对照，无结论词；
//   - 不设达标线：无「达标/目标/还差 N 次」字段；
//   - 学员侧只过程叙事：不出比率/排名（通过率/复发率等一律不进本卡）；
//   - 只记不判：方向由事实值自述（L3 → L2 的箭头即事实，不写成「改善」）。
//
// 原料边界（舰长「批」待裁②）：M3/M5 候选计数（北极星证据卡面）不进入
// 本卡——证据卡 = 舰长侧裁决工具（C133 四硬隔离②：学员不可见）。
//
// 偏差登记（实施中发现，舰长 2026-10-18 批时未见的数据口径事实）：
//   - 设计批文案④（写作行「这段时间写出 N 字 · 诊断 M 次」）**本批不实施**：
//     GrowthOverview 是全累计口径（总字数/总诊断数），与「对照上次评估」
//     锚点不同框；writingCurve 仅 14 天窗，与锚点时长亦不一致。要出诚实的
//     写作行须新增「锚点后字数/诊断增量」时间窗查询（超出本批零新查询
//     范围）⇒ 留后续批次，见任务卡 §五。
//   - 设计批文案⑤降级变体「对照 近 30 天」**本批未用**：无降级卡——
//     无主锚（少于两次带能力快照的评估）时整卡不渲染（⑥），不出只有
//     症候行的降级卡（其「较上次」是逐症候自有基线，与 30 天窗无关，
//     挂「近 30 天」标签反而是错帧）。
//
// 纯函数纪律：不 import Repository / DB / Provider；输入输出驱动，可单测。
// ─────────────────────────────────────────────────────────────

import 'package:writingcoach/services/growth_service.dart' show AbilityScore;
import 'package:writingcoach/services/syndrome_recurrence.dart';
import 'package:writingcoach/types/display_types.dart';

/// 叙事条目类型（事实分类，非质量档位）。
enum NarrativeItemType {
  /// 能力评分对照（上次评估 → 最近评估，六大能力均分，见 [_meanOverCommonDimensions]）。
  ability,

  /// 症候复诊对照（E-1 同型：第 N 次出现 · 较上次 L3 → L2）。
  severity,
}

/// 叙事条目（一条 = 一个事实陈述句；[text] 为逐字文案，UI 不改写）。
class NarrativeItem {
  final NarrativeItemType type;

  /// 逐字文案（R-027 已批句式；黑名单测试锚定无评价词）。
  final String text;

  const NarrativeItem({required this.type, required this.text});
}

/// 进步叙事（卡级装配结果）。
class GrowthNarrative {
  /// 锚点标签（本批恒为「对照 上次评估」；空叙事时为 ''）。
  final String anchorLabel;

  /// 条目序列（首条恒为能力行——主锚事实；其后为症候复诊行）。
  final List<NarrativeItem> items;

  const GrowthNarrative({required this.anchorLabel, required this.items});

  /// 空叙事 ⇒ 调用方不渲染卡片（设计批 §二 显隐规则）。
  bool get isEmpty => items.isEmpty;
}

/// R-027 文案锚串（设计批 §四 已批七条中本批使用的部分，逐字）。
///
/// 未使用：④ 写作行（偏差登记见文件头）、⑤ 的「近 30 天」降级变体（本批不出降级卡）。
class NarrativeText {
  /// ① 卡题
  static const title = '与上次相比';

  /// ⑤ 锚点标签（主锚；完整串 = '对照 ' + 锚点描述）
  static const anchorLabel = '对照 上次评估';

  /// ③ 能力行（{old}/{new} = 两次评估的六大能力均分，取共有维度）
  static const abilityItem = '能力评分 {old} → {new}';

  /// ② 症候行（{name}/{n}/{prev}/{cur} 逐字代入；E-1 同型）
  static const severityItem = '{name} · 第 {n} 次出现 · 较上次 {prev} → {cur}';

  /// R-009 评价词黑名单（测试断言条目文案不含这些词）。
  static const bannedWords = <String>[
    '进步',
    '掌握',
    '好转',
    '提升',
    '下降',
    '达标',
    '优秀',
    '成功',
  ];
}

/// 装配进步叙事（纯函数）。
///
/// 显隐规则（设计批 §二）：
///   - **主锚 = 上次评估时点**：[evaluationHistory] 需 ≥2 个带能力快照的
///     评估（旧报告无快照 ⇒ 跳过不编造，AbilityProgressChart 同款纪律）；
///   - 无主锚 ⇒ 返回空叙事（items 空）⇒ 整卡不渲染；
///   - 症候行逐条自判：occurrences ≥2 且 previousSeverity/currentSeverity
///     均非空才出（E-1「首次出现不渲染」同款先例）。
GrowthNarrative buildGrowthNarrative({
  required List<EvaluationData> evaluationHistory,
  required List<SyndromeRecurrence> recurrences,
}) {
  final ability = _buildAbilityItem(evaluationHistory);
  if (ability == null) {
    return const GrowthNarrative(anchorLabel: '', items: []);
  }
  return GrowthNarrative(
    anchorLabel: NarrativeText.anchorLabel,
    items: <NarrativeItem>[ability, ..._buildSeverityItems(recurrences)],
  );
}

/// 能力行：最近一次评估 vs 上一次评估的六大能力均分（取共有维度）。
NarrativeItem? _buildAbilityItem(List<EvaluationData> history) {
  final points = history.where((h) => h.abilityScores.isNotEmpty).toList()
    ..sort((a, b) => a.generatedAt.compareTo(b.generatedAt));
  if (points.length < 2) return null;
  final prev = points[points.length - 2];
  final last = points[points.length - 1];
  // 共有维度均值（缺维度的快照不编造对齐；无共有维度 ⇒ 不出能力行）。
  final prevMean = _meanOverCommonDimensions(
    prev.abilityScores,
    last.abilityScores,
  );
  final lastMean = _meanOverCommonDimensions(
    last.abilityScores,
    prev.abilityScores,
  );
  if (prevMean == null || lastMean == null) return null;
  return NarrativeItem(
    type: NarrativeItemType.ability,
    text: NarrativeText.abilityItem
        .replaceAll('{old}', '$prevMean')
        .replaceAll('{new}', '$lastMean'),
  );
}

/// 六大能力均分：仅取 [a] 与 [b] **共有**维度的分数求均值（四舍五入）；
/// 无共有维度返回 null（不出能力行，不编造对比）。
int? _meanOverCommonDimensions(List<AbilityScore> a, List<AbilityScore> b) {
  final bByDim = <String, int>{for (final s in b) s.dimension: s.score};
  final common = a.where((s) => bByDim.containsKey(s.dimension)).toList();
  if (common.isEmpty) return null;
  final sum = common.fold<int>(0, (acc, s) => acc + s.score);
  return (sum / common.length).round();
}

/// 症候复诊行（E-1 同型）：occurrences ≥2 且两次严重度均已知才出；
/// 排序 = occurrences 降序 + 症候名升序（确定性，防快照抖动）。
List<NarrativeItem> _buildSeverityItems(List<SyndromeRecurrence> recurrences) {
  final eligible =
      recurrences
          .where(
            (r) =>
                r.occurrences >= 2 &&
                r.previousSeverity != null &&
                r.currentSeverity != null,
          )
          .toList()
        ..sort((a, b) {
          final byOcc = b.occurrences.compareTo(a.occurrences);
          if (byOcc != 0) return byOcc;
          return a.syndromeName.compareTo(b.syndromeName);
        });
  return eligible
      .map(
        (r) => NarrativeItem(
          type: NarrativeItemType.severity,
          text: NarrativeText.severityItem
              .replaceAll('{name}', r.syndromeName)
              .replaceAll('{n}', '${r.occurrences}')
              .replaceAll('{prev}', r.previousSeverity!)
              .replaceAll('{cur}', r.currentSeverity!),
        ),
      )
      .toList();
}
