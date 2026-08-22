// ─────────────────────────────────────────────────────────────
// 症候技能层级 + 介入级别（批次60：教学决策层）
// 依据：AI写作教学系统前置研究 V2.0 §2.1 Progressive Mastery 技能层级
//   L1 基础表达 → L2 叙事节奏 → L3 角色塑造 → L4 情节结构 → L5 风格声线
// 设计约束（用户红线）：
//   - 层级是「软引导」，不是硬拦截——AI 建议不受限，仅 fallback 排序优先
//     「当前层级+1」以内的症候（AI 自主判断优先）
//   - 介入级别遵循「逐步撤除脚手架」：I do 示范 → We do 引导 → You do 独立
// ─────────────────────────────────────────────────────────────

import '../types/teaching_types.dart';
import 'syndrome_registry.dart'; // kSyndromeRegistry / kSyndromeSkillLevelsDerived（b9 真源）
import 'training_input_builder.dart'; // TrainingPerformance（7.2 performance_gate）

/// 技能层级（V2.0 §2.1：基础表达 → 叙事节奏 → 角色塑造 → 情节结构 → 风格声线）
enum SkillLevel {
  l1('L1', '基础表达'),
  l2('L2', '叙事节奏'),
  l3('L3', '角色塑造'),
  l4('L4', '情节结构'),
  l5('L5', '风格声线');

  final String value;
  final String label;

  const SkillLevel(this.value, this.label);
}

/// 症候 → 技能层级映射（b9 真源化：由 syndrome_registry 派生，不再手写）
///
/// 分配逻辑（对齐报告五层）：
///   L1 基础表达：情绪/句式/修辞/对话/文法——字句层的表达基本功
///   L2 叙事节奏：信息/节奏/过渡/跳跃——段落到章节的推进感
///   L3 角色塑造：动机/辨识度/一致性/情感——人物是否立得住
///   L4 情节结构：冲突/开篇/结尾/高潮/巧合/伏笔/视角——故事骨架
///   L5 风格声线：暂无症候（F10 声线漂移归入时扩展）
///
/// 保留历史注释（批次70/15/23-26 分批接入记录）：
///   L1 基础表达：P003/P007/P008/P011/P022；L2 叙事节奏：P004/P006/P020/P021/P028/P029
///   L3 角色塑造：P009/P010/P018/P019；L4 情节结构：P005/P012-P017/P023-P027/P030/P031
///   （P023-P027 批次15 D9 网文商业；P028-P031 批次23-26 叙事基础空缺）
Map<String, SkillLevel> get kSyndromeSkillLevels => kSyndromeSkillLevelsDerived;

/// 症候的技能层级（未知症候 → null）
SkillLevel? skillLevelOf(String? syndromeId) {
  if (syndromeId == null || syndromeId.isEmpty) return null;
  return kSyndromeSkillLevels[syndromeId];
}

/// 学员当前技能层级（由 beginner_level 映射）。
///
/// N0/N1（元素）→ L1 基础表达；N2（场景）→ L2 叙事节奏；
/// N3（诊断）→ L3 角色塑造；N4（独立）→ L4 情节结构。
/// 未定级 → null（不限制）。
SkillLevel? skillLevelForBeginner(BeginnerLevel? level) {
  switch (level) {
    case BeginnerLevel.n0Engage:
    case BeginnerLevel.n1Elements:
      return SkillLevel.l1;
    case BeginnerLevel.n2Scene:
      return SkillLevel.l2;
    case BeginnerLevel.n3Diagnose:
      return SkillLevel.l3;
    case BeginnerLevel.n4Independent:
      return SkillLevel.l4;
    case null:
      return null;
  }
}

/// 介入级别（V2.0 §2.2 Gradual Release of Responsibility）
enum InterventionLevel {
  iDo('I do', '示范+引导'),
  weDo('We do', '标注+引导'),
  youDo('You do', '独立练习');

  final String value;
  final String label;

  const InterventionLevel(this.value, this.label);
}

/// 介入级别 = f(该症候已训练次数, 当前严重度, 复发信号, 历史表现)：「逐步撤除脚手架」
///
///   0-1 次 → I do（给示范参考，学员先看懂）
///   2-3 次 → We do（示范改为引导方向，学员动手为主）
///   ≥4 次 → You do（撤掉示范，只留自查锚点，独立练习 + 点评）
///
/// D3（批次8）：综合 severity + 复发信号 —— 复发（relapse）或严重（L3）时
/// 回退脚手架到 I do，防「已训练 4 次后复发仍 You do」过早撤脚手架。
/// 注：L2 是默认诊断严重度，不触发回退（否则次数分级整体失效）。
///
/// 7.2（批次16）performance_gate：综合历史训练表现双向修正——
///   - 延迟撤脚手架（保守，主）：连续 3 次未达标 → 强制 I do（G1）；
///     passRate<0.5 → 降一档（G2）；连续 2 次未达标且基础档位 You do → 不升档（G3）
///   - 提前撤脚手架（正向，辅）：首次训练即通过 → 升 We do（G4）；
///     2-3 次全部通过 → 升 You do（G5）
///   规则顺序：D3 > G1 > G2 > G3 > 基础次数档位 > G4 > G5（延迟永远优先于提前）
///   performance 为 null（无训练记录）→ 维持纯次数分级。
InterventionLevel interventionLevelForTrainingCount(
  int trainingCount, {
  Severity? currentSeverity,
  bool? relapse,
  TrainingPerformance? performance,
}) {
  // D3（批次8）：复发或严重 L3 → 无条件回退 I do（最高优先级）
  if (relapse ?? false) return InterventionLevel.iDo;
  if (currentSeverity == Severity.l3) return InterventionLevel.iDo;

  // 基础次数档位（逐步撤除脚手架）
  final base = trainingCount >= 4
      ? InterventionLevel.youDo
      : trainingCount >= 2
      ? InterventionLevel.weDo
      : InterventionLevel.iDo;

  // 7.2（批次16）：无表现数据 → 维持次数分级
  if (performance == null) return base;

  // G1 强制 I do：连续 3 次未达标（学员明显卡住，重新给示范）
  if (performance.consecutiveFails >= 3) return InterventionLevel.iDo;

  // G2 降一档：passRate < 0.5 且基础档位为 We do/You do
  if (performance.passRate < 0.5 && base != InterventionLevel.iDo) {
    return base == InterventionLevel.youDo
        ? InterventionLevel.weDo
        : InterventionLevel.iDo;
  }

  // G3 不升档：连续 2 次未达标且基础档位为 You do → 保持 We do
  if (performance.consecutiveFails >= 2 && base == InterventionLevel.youDo) {
    return InterventionLevel.weDo;
  }

  // G4 提前升 We do：基础档位 I do 且首次训练即通过（全部记录通过）
  if (base == InterventionLevel.iDo &&
      performance.totalCount >= 1 &&
      performance.consecutivePasses == performance.totalCount) {
    return InterventionLevel.weDo;
  }

  // G5 提前升 You do：基础档位 We do 且 2-3 次全部通过
  if (base == InterventionLevel.weDo &&
      performance.totalCount >= 2 &&
      performance.consecutivePasses == performance.totalCount) {
    return InterventionLevel.youDo;
  }

  return base;
}
