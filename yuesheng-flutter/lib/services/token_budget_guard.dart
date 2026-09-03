// ─────────────────────────────────────────────────────────────
// 运行时 token 预算闸门 — 2026-08-11 token/检索体检落地
//
// 问题背景：TokenBudgetTable 静态表是"所有阶段同时最坏"的审计上界
// （修订后 ~58100 > 50000），但 chat_service 组装 messages 时没有任何
// 运行时总量校验——历史消息全量追加、L3/画像/引用等可裁阶段超限也不降级。
//
// 本闸门在组装完成后一次性执行：
//   - 总估算 ≤ maxBudget        → 不动作（no-op）
//   - warning 线 < 总估算 ≤ 上限 → 仅报告 warning，不裁剪（避免误伤教学信息）
//   - 总估算 > maxBudget        → 按 TokenBudgetTable.planDegradation()
//     顺序（degradePriority 越小越先裁）整段裁掉已标记的可降级阶段，
//     直到总估算 ≤ maxBudget。
//
// 约定：
//   - chat_service 组装时用 BudgetStageNames 常量记录"阶段 → 消息索引"，
//     只记录可降级阶段（保底层与内嵌 L2 组不记录、不裁）。
//   - 闸门不重建 systemPrompt（L2 内嵌其中），因此 L2 组不参与运行时裁剪；
//     planDegradation() 返回它时会被"未标记"跳过。
//   - 裁剪粒度是"整段删除"（阶段级），不逐条截断文本——保持简单可验证。
// ─────────────────────────────────────────────────────────────

import '../config/shared_constants.dart';
import '../config/token_budget_table.dart';
import 'llm_client.dart'; // ChatMessage

/// 闸门执行报告
class BudgetGuardReport {
  /// 总估算是否超过 maxBudget（超限但可能无可裁阶段）
  final bool overBudget;

  /// 是否触发了裁剪（总估算超过 maxBudget 且至少裁掉一个阶段）
  final bool triggered;

  /// 是否越过警告线（warning 线 < 总估算，可能未触发裁剪）
  final bool overWarning;

  /// 裁剪前总估算（tokens）
  final int totalBefore;

  /// 裁剪后总估算（tokens）
  final int totalAfter;

  /// 被整段裁掉的阶段名（按裁剪顺序）
  final List<String> droppedStages;

  /// 被裁掉的消息条数
  final int droppedMessageCount;

  const BudgetGuardReport({
    required this.overBudget,
    required this.triggered,
    required this.overWarning,
    required this.totalBefore,
    required this.totalAfter,
    required this.droppedStages,
    required this.droppedMessageCount,
  });

  bool get dropped => droppedStages.isNotEmpty;
}

/// 运行时 token 预算闸门（无状态工具类）
abstract final class TokenBudgetGuard {
  /// 估算文本 token 数（与 skill_dispatcher / 预算表同口径）
  static int estimate(String text) =>
      (text.length * TokenEstimate.charToTokenRatio).round();

  static int _estimateAll(List<ChatMessage> messages) {
    var sum = 0;
    for (final m in messages) {
      sum += estimate(m.content);
    }
    return sum;
  }

  /// 排除 [exclude] 索引后的总估算
  static int _estimateExcluding(List<ChatMessage> messages, Set<int> exclude) {
    var sum = 0;
    for (var i = 0; i < messages.length; i++) {
      if (exclude.contains(i)) continue;
      sum += estimate(messages[i].content);
    }
    return sum;
  }

  /// 对已组装的 [messages] 执行预算校验与降级裁剪（原地修改列表）。
  ///
  /// [stageIndexes]：阶段名（[BudgetStageNames] 常量）→ 该阶段注入的
  /// 消息在 [messages] 中的索引列表。仅记录可降级阶段。
  static BudgetGuardReport apply(
    List<ChatMessage> messages, {
    required Map<String, List<int>> stageIndexes,
  }) {
    final maxBudget = TokenEstimate.maxBudget;
    final warning = (maxBudget * TokenEstimate.warningRatio).round();

    final total = _estimateAll(messages);
    final overBudget = total > maxBudget;
    final overWarning = total > warning;

    if (total <= maxBudget) {
      return _untrimmedReport(total, overWarning);
    }

    // 超上限：按降级顺序整段裁掉已标记阶段，边裁边估算
    final plan = _planRemovals(messages, stageIndexes, maxBudget, total);
    if (plan.toRemove.isNotEmpty) {
      _applyRemovals(messages, plan.toRemove);
    }

    return BudgetGuardReport(
      overBudget: overBudget,
      triggered: plan.droppedStages.isNotEmpty,
      overWarning: overWarning,
      totalBefore: total,
      totalAfter: _estimateAll(messages),
      droppedStages: plan.droppedStages,
      droppedMessageCount: plan.toRemove.length,
    );
  }

  /// 未超预算：原样报告（before == after、无裁剪）。
  ///
  /// R-019：由 [apply] 抽出（60 → 31 行）。
  static BudgetGuardReport _untrimmedReport(int total, bool overWarning) =>
      BudgetGuardReport(
        overBudget: false,
        triggered: false,
        overWarning: overWarning,
        totalBefore: total,
        totalAfter: total,
        droppedStages: const [],
        droppedMessageCount: 0,
      );

  /// 按 [TokenBudgetTable.planDegradation] 顺序整段裁掉已标记阶段，
  /// 边裁边估算，直到总估算回到 [maxBudget] 内。
  ///
  /// R-019：由 [apply] 抽出。只做规划，不修改 [messages]。
  static ({Set<int> toRemove, List<String> droppedStages}) _planRemovals(
    List<ChatMessage> messages,
    Map<String, List<int>> stageIndexes,
    int maxBudget,
    int total,
  ) {
    final toRemove = <int>{};
    final droppedStages = <String>[];
    var current = total;
    for (final stage in TokenBudgetTable.planDegradation()) {
      if (current <= maxBudget) break;
      final idxs = stageIndexes[stage.name] ?? const <int>[];
      final valid = idxs
          .where((i) => i < messages.length && !toRemove.contains(i))
          .toList();
      if (valid.isEmpty) continue; // 未标记 / 已被裁 → 跳过
      toRemove.addAll(valid);
      droppedStages.add(stage.name);
      current = _estimateExcluding(messages, toRemove);
    }
    return (toRemove: toRemove, droppedStages: droppedStages);
  }

  /// 原地剔除 [toRemove] 索引对应的消息。
  ///
  /// R-019：由 [apply] 抽出。
  static void _applyRemovals(List<ChatMessage> messages, Set<int> toRemove) {
    final kept = <ChatMessage>[];
    for (var i = 0; i < messages.length; i++) {
      if (toRemove.contains(i)) continue;
      kept.add(messages[i]);
    }
    messages
      ..clear()
      ..addAll(kept);
  }
}
