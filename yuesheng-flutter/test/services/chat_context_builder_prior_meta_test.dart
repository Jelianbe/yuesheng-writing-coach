// ─────────────────────────────────────────────────────────────
// prior_diagnosis 元信息标注测试（H6 动作1，2026-10-14 舰长批准）
//
// 语义：活跃症候上下文中，凡「待确认」（suspected / null = 上一轮模型
// 报出、未经用户确认）条目在场 ⇒ 注入头部追加来源标注，防既有结论无
// 溯源、被当「成立」依据复用（批1 H6 三路证实；run4/6 实拍 24 样本
// suspected 全部落库待注入）。
//
// 用户主权边界（R-009）：
//   - confirmed 条目**不得**被标注（用户认同的诊断不能贬为「模型输出」）
//   - rejected 条目维持 P0-3 既有独立标注链路（学员已质疑 + disputeReason）
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/chat_context_builder.dart';
import 'package:writingcoach/types/teaching_types.dart';

void main() {
  const focusCtx = ActiveFocusContext(
    focusId: 'P001',
    source: FocusSource.aiSuggested,
    reason: '测试焦点',
  );

  test('① suspected 在场 ⇒ 注入头部含 prior_diagnosis 元信息标注', () {
    final assembled = buildStructuredSyndromeContext(const [
      ActiveSyndromeView(
        syndromeId: 'P001',
        syndromeName: '情绪标签化',
        severity: Severity.l2,
        // confirmationStatus 缺省 = null = 待确认（模型报出未经确认）
      ),
    ], activeFocus: focusCtx);
    expect(
      assembled.contains('### 来源标注（prior_diagnosis 元信息）'),
      isTrue,
      reason: 'suspected 条目在场但未追加来源标注（H6 动作1 缺失）',
    );
    expect(assembled.contains('上一轮模型自身输出'), isTrue);
    expect(assembled.contains('未经用户确认'), isTrue);
    expect(assembled.contains('不得单独作为「成立」依据'), isTrue);
  });

  test('② ConfirmationStatus.suspected 显式值同样触发标注', () {
    final assembled = buildStructuredSyndromeContext(const [
      ActiveSyndromeView(
        syndromeId: 'P001',
        syndromeName: '情绪标签化',
        severity: Severity.l2,
        confirmationStatus: ConfirmationStatus.suspected,
      ),
    ], activeFocus: focusCtx);
    expect(assembled.contains('### 来源标注（prior_diagnosis 元信息）'), isTrue);
  });

  test('③ 全 confirmed ⇒ 不含标注（用户主权：已认同的诊断不贬为模型输出）', () {
    final assembled = buildStructuredSyndromeContext(const [
      ActiveSyndromeView(
        syndromeId: 'P001',
        syndromeName: '情绪标签化',
        severity: Severity.l2,
        confirmationStatus: ConfirmationStatus.confirmed,
      ),
    ], activeFocus: focusCtx);
    expect(
      assembled.contains('### 来源标注（prior_diagnosis 元信息）'),
      isFalse,
      reason: 'confirmed 条目不得被 prior_diagnosis 标注（R-009）',
    );
    expect(assembled.contains('[已确认]'), isTrue);
  });

  test('④ 仅 rejected ⇒ 不含标注（P0-3 独立链路维持现状，不扩大改动面）', () {
    final assembled = buildStructuredSyndromeContext(
      const [
        ActiveSyndromeView(
          syndromeId: 'B001',
          syndromeName: '对话抢话症',
          severity: Severity.l2,
          confirmationStatus: ConfirmationStatus.rejected,
          disputeReason: '第三句对话里两个人抢话',
        ),
      ],
      activeFocus: const ActiveFocusContext(
        focusId: 'F999',
        source: FocusSource.userOverride,
        reason: '焦点不在 B001',
      ),
    );
    expect(
      assembled.contains('### 来源标注（prior_diagnosis 元信息）'),
      isFalse,
      reason: 'rejected 非 suspected，不触发 prior_diagnosis 标注',
    );
    // P0-3 既有链路原样：质疑标注 + 学员理由
    expect(assembled.contains('学员已质疑·勿再主动展开'), isTrue);
    expect(assembled.contains('（学员理由：第三句对话里两个人抢话）'), isTrue);
  });

  test('⑤ 混合 confirmed + suspected ⇒ 标注在场且 [已确认] 行不受约束语义保留', () {
    final assembled = buildStructuredSyndromeContext(const [
      ActiveSyndromeView(
        syndromeId: 'P001',
        syndromeName: '情绪标签化',
        severity: Severity.l2,
        confirmationStatus: ConfirmationStatus.confirmed,
      ),
      ActiveSyndromeView(
        syndromeId: 'P006',
        syndromeName: '语言堆砌',
        severity: Severity.l1,
        confirmationStatus: ConfirmationStatus.suspected,
      ),
    ], activeFocus: focusCtx);
    expect(assembled.contains('### 来源标注（prior_diagnosis 元信息）'), isTrue);
    expect(assembled.contains('不受此标注约束'), isTrue);
    expect(assembled.contains('[已确认]'), isTrue);
    expect(assembled.contains('[待确认]'), isTrue);
  });
}
