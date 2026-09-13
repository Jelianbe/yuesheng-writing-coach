// ─────────────────────────────────────────────────────────────
// token 预算静态表 — 批次3（3.1）扩容前置；2026-08-11 体检修订
//
// 用途：为内容层扩容（P023+）与 25 步注入链路提供预算核算基准。
// 真源：docs/教学机制审查包.md §4.1（25 步注入表）+ §4.4（L1/L2/L3 体积）
//
// ⚠️ 【体积台账重建 · 2026-09-13（E 批）】下列 2026-08-11 数值为 0.4 口径旧值，
// 与当前实测不符，且其出处探针已删（见下行）。当前实测口径 = 锚点快照
// test/snapshots/skill_prompt_anchor.json 的 skillContent/prompt[*].len（UTF-16
// 码元，ratio=1.0，非 tokenizer），2026-09-13：
//   - L1（九件套 28,354 + attitude-yuesheng 1,189）= 29,543 字符
//     → 表内 l1Core worstCaseTokens=25000 系 2026-08-11 旧换算，已低估（见下）
//   - L2 最重 diagnosis 组 = 44,042 字符 → 表内 l2OnDemand=41250 亦低估
//     （五组：beginner 31,415 / diagnosis 44,042 / training 38,329 /
//      advanced 28,773 / outline 24,677）
//   - 各模式整 prompt：none 30,424 ～ diagnosis 74,571 字符
// 本表 worstCaseTokens 是运行时闸门输入，E 批只改注释、不改数值；如需按实测
// 重标定，应另行立项并评估 TokenBudgetGuard 行为变化。
//
// 2026-08-11 token/检索体检修订（0.4 口径旧值，静态合计仍为"所有阶段
// 同时最坏"的审计上界——超限提示需要降级机制，而非实际运行常态）：
//   - L1 核心 12000 → 10000（0.4 口径实测 9 命名项 + 3 态度档共 9323 字符，留 ~7% 余量；
//     「8 项」为过时口径——2026-09-06 ADR-C79 更正，真源 = skill_layers.dart l1SkillIds）
//   - L2 按需组 14000 → 16500（0.4 口径实测最重 diagnosis 组 16463 字符；原表低估）
//   - 训练教学知识 1800 → 400（0.4 口径实测 focus 单症候 ~330 字符）
//   - L3 结构化详情 2200 → 1100（0.4 口径实测 focus 症候+技法 ~722 字符）
// ⚠️ 原「实测来源」test/services/token_measure_temp_test.dart 已删除（审计用临时
//    文件），该出处不可复现；2026-09-13 起的可复现口径改用上述锚点快照。
//
// B26 中文口径再标定（2026-08-18）：charToTokenRatio 0.4→1.0，各阶段
// worstCaseTokens 按 1.0/0.4=2.5 精确换算（估算=chars×ratio，chars 不变），
// 旧"实测"注释数值为 0.4 口径。maxBudget 同步 50000→128000（见
// shared_constants.dart TokenEstimate 注释）。换算后合计 145250 > 128000，
// 闸门语义保持：常态（~70–90k）不触发、最坏情形真实触发。
//
// 核算口径：最坏情形逐项求和 vs 模型上下文 TokenEstimate.maxBudget(128000)。
// 溢出降级顺序（degradePriority 越小越先裁）：
//   L2 组数 → L3 非 focus 概览 → 规则检测器注入 → L3 训练知识 → 画像 →
//   引用上下文 → 附属文件 → 历史消息；临场输出约束与协议块说明为保底层（不裁）。
//
// 运行时闸门（TokenBudgetGuard，见 lib/services/token_budget_guard.dart）
// 在 chat_service 组装完成后按本表的 degradePriority 顺序裁除非保底层。
// ─────────────────────────────────────────────────────────────

import 'shared_constants.dart';

/// 注入阶段名（预算表真源）。
///
/// 运行时标记（chat_service 组装时记录"阶段 → 消息索引"）与
/// 预算闸门（TokenBudgetGuard）均引用这些常量，避免字符串散落漂移。
abstract final class BudgetStageNames {
  static const String l1Core = 'L1 核心 skill（9 命名项 + 3 态度档）';
  static const String l1Attitude = 'L1 态度档位 skill';
  static const String l2OnDemand = 'L2 按需组（仅当前 mode 一组）';
  static const String positionGuidance = '位置判断引导语';
  static const String studentProfile = '学员画像（五维聚合）';
  static const String planContinuation = '上轮教学计划延续';
  static const String intentAndGranularity = '意图分类 + 颗粒度';
  static const String references = '引用上下文（主/次）';
  static const String reviewer = 'Reviewer 门控提示';
  static const String voiceDrift = '声线漂移提示';
  // R9（2026-09-13）：旧值「5 个全命中」为过期计数——实测观察注入器 7 个
  // （message_injector.dart :811/:846/:892/:919/:972/:1025/:1048）。
  static const String ruleDetectors = '规则观察检测器（7 个观察注入器）';
  static const String entity = '[YS_ENTITY] 协议 + 实体索引';
  static const String fact = '[YS_FACT] 协议 + 内容';
  static const String attachedFiles = '附属文件上下文';
  static const String focusSwitch = 'Focus 切换提示';
  static const String intervention = '介入级别（I/We/You do）';
  static const String trainingEvaluation = '训练评估注入（T2）';
  static const String trainingKnowledge = '训练教学知识（L3，3 症候）';
  static const String l3Structure = 'L3 结构化症候详情（focus 全量+非 focus 概览）';
  static const String skillLevel = '学员技能层级软引导';
  static const String outputConstraints = '临场输出约束（最高优先级）';
  static const String history = '历史消息（最坏 20 条）';
}

/// 单个注入阶段的预算条目
class TokenBudgetStage {
  final String name;

  /// 最坏情形 token 估算
  final int worstCaseTokens;

  /// 溢出降级优先级：1=最先裁；[TokenBudgetTable.kBottomLinePriority]=保底不裁
  final int degradePriority;

  const TokenBudgetStage({
    required this.name,
    required this.worstCaseTokens,
    required this.degradePriority,
  });
}

/// 25 步注入 token 预算静态表
abstract final class TokenBudgetTable {
  const TokenBudgetTable._();

  /// 保底优先级：该优先级的阶段不进入降级裁减清单
  static const int kBottomLinePriority = 100;

  /// 各阶段最坏情形 token 估算
  /// （来源：机制审查包 §4.4；2026-08-11 体检修订 L1/L2/L3 数值见文件头；
  ///   引用/附件 = ContextBudget.totalBudget(15000 chars)，按 charToTokenRatio(1.0) 折算）
  static const List<TokenBudgetStage> stages = [
    TokenBudgetStage(
      name: BudgetStageNames.l1Core,
      worstCaseTokens: 25000, // 旧口径实测 9323×2.5≈23308
      degradePriority: kBottomLinePriority,
    ),
    TokenBudgetStage(
      name: BudgetStageNames.l1Attitude,
      worstCaseTokens: 2500, // 旧口径实测 attitude skill ~1100×2.5≈2750
      degradePriority: kBottomLinePriority,
    ),
    TokenBudgetStage(
      name: BudgetStageNames.l2OnDemand,
      worstCaseTokens: 41250, // 旧口径实测最重 diagnosis 组 16463×2.5≈41158
      degradePriority: 1,
    ),
    TokenBudgetStage(
      name: BudgetStageNames.positionGuidance,
      worstCaseTokens: 2000,
      degradePriority: kBottomLinePriority,
    ),
    TokenBudgetStage(
      name: BudgetStageNames.studentProfile,
      worstCaseTokens: 3750,
      degradePriority: 5,
    ),
    TokenBudgetStage(
      name: BudgetStageNames.planContinuation,
      worstCaseTokens: 750,
      degradePriority: kBottomLinePriority,
    ),
    TokenBudgetStage(
      name: BudgetStageNames.intentAndGranularity,
      worstCaseTokens: 1000,
      degradePriority: kBottomLinePriority,
    ),
    TokenBudgetStage(
      name: BudgetStageNames.references,
      worstCaseTokens: 15000, // = ContextBudget.totalBudget(15000 chars)×1.0
      degradePriority: 6,
    ),
    TokenBudgetStage(
      name: BudgetStageNames.reviewer,
      worstCaseTokens: 750,
      degradePriority: kBottomLinePriority,
    ),
    TokenBudgetStage(
      name: BudgetStageNames.voiceDrift,
      worstCaseTokens: 500,
      degradePriority: kBottomLinePriority,
    ),
    TokenBudgetStage(
      name: BudgetStageNames.ruleDetectors,
      worstCaseTokens: 3750,
      degradePriority: 3,
    ),
    TokenBudgetStage(
      name: BudgetStageNames.entity,
      worstCaseTokens: 2000,
      degradePriority: kBottomLinePriority,
    ),
    TokenBudgetStage(
      name: BudgetStageNames.fact,
      worstCaseTokens: 2250,
      degradePriority: kBottomLinePriority,
    ),
    TokenBudgetStage(
      name: BudgetStageNames.attachedFiles,
      worstCaseTokens: 15000, // = ContextBudget.totalBudget(15000 chars)×1.0
      degradePriority: 7,
    ),
    TokenBudgetStage(
      name: BudgetStageNames.focusSwitch,
      worstCaseTokens: 750,
      degradePriority: kBottomLinePriority,
    ),
    TokenBudgetStage(
      name: BudgetStageNames.intervention,
      worstCaseTokens: 500,
      degradePriority: kBottomLinePriority,
    ),
    TokenBudgetStage(
      name: BudgetStageNames.trainingEvaluation,
      worstCaseTokens: 3000,
      degradePriority: kBottomLinePriority,
    ),
    TokenBudgetStage(
      name: BudgetStageNames.trainingKnowledge,
      worstCaseTokens: 1000, // 旧口径实测 focus 单症候 ~330×2.5≈825
      degradePriority: 4,
    ),
    TokenBudgetStage(
      name: BudgetStageNames.l3Structure,
      worstCaseTokens: 2750, // 旧口径实测 focus 症候+技法 ~722×2.5≈1805
      degradePriority: 2,
    ),
    TokenBudgetStage(
      name: BudgetStageNames.skillLevel,
      worstCaseTokens: 500,
      degradePriority: kBottomLinePriority,
    ),
    TokenBudgetStage(
      name: BudgetStageNames.outputConstraints,
      worstCaseTokens: 1250,
      degradePriority: kBottomLinePriority,
    ),
    TokenBudgetStage(
      name: BudgetStageNames.history,
      // 批次 B-2：派生自 LlmInputLimits.maxHistoryMessages（单一真源），
      // 20 条 × 1000 chars ≈ 20000 tokens（最坏）；改封顶数自动跟随。
      worstCaseTokens: LlmInputLimits.maxHistoryMessages * 1000,
      degradePriority: 8,
    ),
  ];

  /// 最坏情形合计（tokens）
  static int get worstCaseTotal =>
      stages.fold(0, (sum, s) => sum + s.worstCaseTokens);

  /// 保底层（永不裁减）阶段名
  static List<String> get bottomLineStages => stages
      .where((s) => s.degradePriority == kBottomLinePriority)
      .map((s) => s.name)
      .toList();

  /// 溢出降级清单（按 degradePriority 升序，不含保底层）
  static List<TokenBudgetStage> planDegradation() {
    final sorted = [...stages]
      ..sort((a, b) => a.degradePriority.compareTo(b.degradePriority));
    return sorted
        .where((s) => s.degradePriority < kBottomLinePriority)
        .toList();
  }

  /// 调试报告：逐项 + 合计 + 与模型上下文对比
  static String debugReport() {
    final buf = StringBuffer('token 预算静态表（最坏情形）\n');
    for (final s in stages) {
      buf.writeln(
        '  ${s.name.padRight(30)} ${s.worstCaseTokens.toString().padLeft(6)} tokens',
      );
    }
    final warning = (TokenEstimate.maxBudget * TokenEstimate.warningRatio)
        .round();
    buf.writeln(
      '  合计 $worstCaseTotal / ${TokenEstimate.maxBudget}（warning=$warning）',
    );
    return buf.toString();
  }
}
