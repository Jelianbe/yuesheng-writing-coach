// ─────────────────────────────────────────────────────────────
// focus_card_builder — 教学线 P1-4「当前焦点 + 下一步」卡数据组装
//
// 四份教学计算全部已存在且已单测（prioritizeSyndromes /
// detectStagnation / SkillLevel / interventionLevelForTrainingCount），
// 本文件只做「接线」：把既有计算合成一张卡的数据，不造新算法。
//
// R-009 红线：全部输出为「系统建议」，不强制、不替学员决定。
// ─────────────────────────────────────────────────────────────

import '../data/repositories/training_result_repository.dart';
import '../types/teaching_types.dart';
import 'student_profile_compute.dart';
import 'syndrome_registry.dart';
import 'syndrome_skill_levels.dart';

/// 焦点卡数据（P1-4）。全部派生自既有计算。
class FocusCardData {
  /// 焦点症候 ID
  final String focusId;

  /// 焦点症候名
  final String focusName;

  /// 优先级得分（prioritizeSyndromes 产物）
  final double focusScore;

  /// 「为什么」一句话（最新严重度 · 出现次数 · 趋势 · 教学状态）
  final String reason;

  /// 症候技能层级（注册表 L1-L5）
  final SkillLevel skillLevel;

  /// 介入级别（I do / We do / You do）
  final InterventionLevel intervention;

  /// 停滞信号（detectStagnation 产物）
  final bool stagnated;

  final String? stagnationReason;

  /// P2-10 三轴收束：教学阶段（P 系，来自成长总览）
  final TeachingPhase? phase;

  /// P2-10 三轴收束：零基础等级（N 系）
  final BeginnerLevel? beginnerLevel;

  /// P2-10 三轴收束：一句话坐标叙事「你在哪 → 下一步练什么」
  final String progressNarrative;

  const FocusCardData({
    required this.focusId,
    required this.focusName,
    required this.focusScore,
    required this.reason,
    required this.skillLevel,
    required this.intervention,
    required this.stagnated,
    this.stagnationReason,
    this.phase,
    this.beginnerLevel,
    required this.progressNarrative,
  });
}

/// 组装焦点卡数据。症候画像为空 → null（UI 隐藏整卡）。
///
/// 不传 performance / relapse：SyndromeTrainingStats 无连续通过/失败
/// 数据，不编造；介入级别只用次数档位 + L3 严重度回退（D3）。
FocusCardData? buildFocusCardData({
  required StudentProfile profile,
  required List<SyndromeTrainingStats> trainingStats,
  TeachingPhase? phase,
  BeginnerLevel? beginnerLevel,
}) {
  final prioritized = prioritizeSyndromes(profile.syndromeProfile);
  if (prioritized.isEmpty) return null;
  final top = prioritized.first;
  final agg = profile.syndromeProfile[top.id];
  if (agg == null) return null;

  final stagnation = detectStagnation(
    profile.syndromeProfile,
    profile.totalSessions,
  );
  final record = syndromeRecordOf(top.id);
  final stats = _statsFor(trainingStats, top.id);

  return FocusCardData(
    focusId: top.id,
    focusName: top.name,
    focusScore: top.score,
    reason: _buildReason(agg),
    skillLevel: record?.level ?? SkillLevel.l1,
    intervention: interventionLevelForTrainingCount(
      stats?.total ?? 0,
      currentSeverity: agg.latestSeverity,
    ),
    stagnated: stagnation.stagnated,
    stagnationReason: stagnation.reason,
    phase: phase,
    beginnerLevel: beginnerLevel,
    progressNarrative: buildProgressNarrative(
      phase: phase,
      beginnerLevel: beginnerLevel,
      focusName: top.name,
      skillLevel: record?.level ?? SkillLevel.l1,
      intervention: interventionLevelForTrainingCount(
        stats?.total ?? 0,
        currentSeverity: agg.latestSeverity,
      ),
    ),
  );
}

/// 从训练聚合中取指定症候的统计（无记录返回 null）。
SyndromeTrainingStats? _statsFor(
  List<SyndromeTrainingStats> trainingStats,
  String syndromeId,
) {
  for (final s in trainingStats) {
    if (s.syndromeId == syndromeId) return s;
  }
  return null;
}

/// 「为什么」文案：只陈述事实，不评判学员。
String _buildReason(SyndromeAggregation agg) {
  return '最新 ${agg.latestSeverity.value} · 出现 ${agg.occurrenceCount} 次 · '
      '${_trendLabel(agg.trend)} · ${_stateLabel(agg.teachingState)}';
}

/// 趋势中文（既有枚举，不新造语义）。
String _trendLabel(Trend trend) {
  switch (trend) {
    case Trend.improving:
      return '在好转';
    case Trend.worsening:
      return '在恶化';
    case Trend.stable:
      return '保持平稳';
    case Trend.unknown:
      return '趋势未明';
  }
}

/// 教学状态中文（既有枚举）。
String _stateLabel(TeachingState state) {
  switch (state) {
    case TeachingState.identified:
      return '已识别';
    case TeachingState.inProgress:
      return '教学中';
    case TeachingState.consolidating:
      return '巩固中';
    case TeachingState.mastered:
      return '已掌握';
  }
}

/// P2-10 三轴收束：把 P 系（阶段）/ N 系（零基础）/ 技能层级 / 介入级别
/// 四套坐标压成一句「你在哪 → 下一步练什么」。纯展示，不评判（R-009）。
///
/// 规则：N 系优先（教学起点坐标）；无 N 系回退 P 系；都无 → 只报焦点。
String buildProgressNarrative({
  required TeachingPhase? phase,
  required BeginnerLevel? beginnerLevel,
  required String focusName,
  required SkillLevel skillLevel,
  required InterventionLevel intervention,
}) {
  final String position;
  if (beginnerLevel != null) {
    position = _beginnerLevelLabel(beginnerLevel);
  } else if (phase != null) {
    position = _phaseLabel(phase);
  } else {
    position = '当前阶段未知';
  }
  return '坐标：$position · 当前焦点属「${skillLevel.value} ${skillLevel.label}」层 · '
      '介入 ${intervention.value}（${intervention.label}）——下一步：'
      '练「$focusName」对应的 ${skillLevel.label} 练习';
}

/// N 系 → 可读标签
String _beginnerLevelLabel(BeginnerLevel level) {
  switch (level) {
    case BeginnerLevel.n0Engage:
      return '起步期（N0 兴趣激活）';
    case BeginnerLevel.n1Elements:
      return '打基础（N1 要素感知）';
    case BeginnerLevel.n2Scene:
      return '搭场景（N2 场景构建）';
    case BeginnerLevel.n3Diagnose:
      return '会自诊（N3 独立诊断）';
    case BeginnerLevel.n4Independent:
      return '独立期（N4 自主写作）';
  }
}

/// P 系 → 可读标签
String _phaseLabel(TeachingPhase phase) {
  switch (phase) {
    case TeachingPhase.p0Engage:
      return 'P0 兴趣激活';
    case TeachingPhase.p1World:
      return 'P1 世界观与诊断';
    case TeachingPhase.p2PracticeLoop:
      return 'P2 练习循环';
    case TeachingPhase.p3Training:
      return 'P3 深度训练';
    case TeachingPhase.p4Review:
      return 'P4 毕业复核';
  }
}
