// ─────────────────────────────────────────────────────────────
// StageDropNotice — 预算闸门知情截断提示（S1 · R2 / Q0 裁定）
//
// 病灶：观察段（ruleDetectors）此前不在闸门可裁名单（死配置）；S1 接线后
// 超限时观察段会被整段裁掉——若上下文不明示，AI 会把「无线索」误读为
// 「无矛盾」，比静默消失更糟（架构 §1.2）。本类在闸门触发后按被裁阶段
// 生成独立 system 提示消息：
//   · 用户素材阶段（references / attachedFiles / fact）→ X-040 素材缺失提示
//     （文案自 chat_service._logBudgetOutcome 逐字迁入，回归测试冻结；
//     ADR-C74 三步法：新逻辑进独立类，chat_service 零净增）
//   · ruleDetectors → 观察线索缺失提示（新增，明示已让路的检测线索条数）
// 两者同时被裁时素材提示优先（沿用 X-040 既有行为面，架构 §4.1 alt 分支）。
// ─────────────────────────────────────────────────────────────

import 'package:writingcoach/config/token_budget_table.dart';

/// 预算闸门知情截断提示生成器（无状态，纯函数）
abstract final class StageDropNotice {
  /// 按被裁阶段生成提示文本；返回 null = 无需提示（被裁阶段既不含用户
  /// 素材也不含观察段）。
  ///
  /// [droppedStages]：闸门报告的被裁阶段名（按裁剪顺序，即
  /// [BudgetGuardReport.droppedStages]）。
  /// [countByStage]：各被裁阶段的消息条数（即
  /// [BudgetGuardReport.droppedCountByStage]），仅用于 ruleDetectors
  /// 提示中的条数明示（知情截断「明示已裁 N 条」）。
  static String? build(
    List<String> droppedStages, {
    Map<String, int> countByStage = const {},
  }) {
    final materialStages = droppedStages
        .where(
          (s) =>
              s == BudgetStageNames.references ||
              s == BudgetStageNames.attachedFiles ||
              s == BudgetStageNames.fact,
        )
        .toList();
    if (materialStages.isNotEmpty) {
      return '# 素材缺失提示（X-040 PHI）\n\n'
          '由于本轮 token 预算超限，已裁掉以下用户素材：${materialStages.join('、')}。\n'
          '回复时：\n'
          '1. 不得假定素材内容直接给出诊断结论；\n'
          '2. 若回复需这些内容支撑，明确告知用户需重新提供或简化提供；\n'
          '3. 可基于现有上下文（活跃症候 + 历史对话）做方向性引导。';
    }
    if (droppedStages.contains(BudgetStageNames.ruleDetectors)) {
      final count = countByStage[BudgetStageNames.ruleDetectors] ?? 0;
      return '# 观察线索缺失提示（预算让路）\n\n'
          '由于本轮 token 预算超限，规则观察段（$count 条检测线索）已整体让路给'
          '教学主链路。本轮请勿假设存在矛盾/设定不一致/因果断裂/支线未收束/文法问题'
          '等观察线索；如学员请求检查，请说明本轮预算受限，引导其稍后重试或缩小诊断范围。';
    }
    return null;
  }
}
