// TokenBudgetGuard 运行时预算闸门单元测试（2026-08-11 体检落地）
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/config/shared_constants.dart';
import 'package:writingcoach/config/token_budget_table.dart';
import 'package:writingcoach/services/llm_client.dart';
import 'package:writingcoach/services/token_budget_guard.dart';

/// 构造一条 token 数≈[tokens] 的 system 消息（length × 0.4 取整）
ChatMessage m(int tokens) =>
    ChatMessage(role: 'system', content: 'x' * (tokens * 5 ~/ 2));

void main() {
  final maxBudget = TokenEstimate.maxBudget;
  final warning = (maxBudget * TokenEstimate.warningRatio).round();

  test('不超限：no-op 不裁剪', () {
    final messages = [
      m(20000), // systemPrompt（保底，不标记）
      m(8000), // 历史
    ];
    final report = TokenBudgetGuard.apply(messages, stageIndexes: {
      BudgetStageNames.history: [1],
    });

    expect(report.triggered, false);
    expect(report.overWarning, false);
    expect(report.droppedStages, isEmpty);
    expect(report.droppedMessageCount, 0);
    expect(messages.length, 2);
  });

  test('超 warning 线但未超上限：仅提示不裁剪', () {
    final messages = [
      m(40000), // 保底
      m(1500), // 画像
    ];
    final report = TokenBudgetGuard.apply(messages, stageIndexes: {
      BudgetStageNames.studentProfile: [1],
    });

    expect(report.totalBefore > warning, true);
    expect(report.totalBefore <= maxBudget, true);
    expect(report.overWarning, true);
    expect(report.triggered, false);
    expect(messages.length, 2); // 未裁
  });

  test('超上限：按 degradePriority 顺序整段裁剪，保底与后序阶段保留', () {
    final messages = [
      m(40000), // idx0 systemPrompt（保底，不标记）
      m(1500), // idx1 画像
      m(6000), // idx2 引用
      m(1100), // idx3 L3 结构
      m(4000), // idx4 历史1
      m(4000), // idx5 历史2
    ];
    // 合计 56600 > 50000
    final report = TokenBudgetGuard.apply(messages, stageIndexes: {
      BudgetStageNames.studentProfile: [1],
      BudgetStageNames.references: [2],
      BudgetStageNames.l3Structure: [3],
      BudgetStageNames.history: [4, 5],
    });

    expect(report.triggered, true);
    // 降级顺序：L3(2) → 画像(5) → 引用(6)；历史(8) 最后裁，此处裁完引用已达标
    expect(
      report.droppedStages,
      [
        BudgetStageNames.l3Structure,
        BudgetStageNames.studentProfile,
        BudgetStageNames.references,
      ],
    );
    expect(report.droppedMessageCount, 3);
    expect(report.totalAfter <= maxBudget, true);
    // 保底 systemPrompt 与历史保留
    expect(messages.length, 3);
    expect(messages[0].content, startsWith('x'));
    expect(messages[1].content, startsWith('x'));
    expect(messages[2].content, startsWith('x'));
  });

  test('超上限但未标记阶段跳过（L2 内嵌保底语义）', () {
    final messages = [
      m(40000), // 保底
      m(8000), // 历史
      m(10000), // 附属文件
    ];
    // 合计 58000；标记了 引用(未实际注入，索引无效 99)
    final report = TokenBudgetGuard.apply(messages, stageIndexes: {
      BudgetStageNames.references: [99], // 无效索引 → 跳过
    });

    expect(report.overBudget, true); // 超限
    expect(report.triggered, false); // 但无可裁阶段 → 未实际裁剪
    expect(report.droppedStages, isEmpty);
    expect(report.droppedMessageCount, 0);
    expect(messages.length, 3); // 一条未删（全部保底/无效标记）
  });
}
