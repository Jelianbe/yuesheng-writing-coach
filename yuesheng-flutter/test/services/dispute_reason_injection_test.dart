// ─────────────────────────────────────────────────────────────
// disputeReason 回注装配护栏（ADR-C113 G3-c）
//
// 背景：P0-3 链路 = UI 取理由 → disputeDiagnosis(reason:) 落 teaching_history →
//       message_injector 读回 → chat_context_builder 拼「（学员理由：…）」给 LLM。
//       G3-c 守最后一环：非 focus 症候摘要行尾必须带上 disputeReason（chat_context_builder.dart:306-307）。
//
// 构造：activeFocus 指向一个**不在列表里**的 focusId（如 F999），使列表里唯一的
//       被质疑症候 B001 走「非 focus 完整摘要」分支（_buildFullSyndromeSummary）——
//       该分支才会拼 disputeSuffix；focus 分支走 KB 词条、不带此后缀。
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/services/chat_context_builder.dart';
import 'package:writingcoach/types/teaching_types.dart';

void main() {
  test('G3-c：带 disputeReason 的非 focus 症候 → 装配结果含「（学员理由：…）」', () {
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
        reason: '焦点不在 B001，使其走非 focus 摘要行',
      ),
    );

    // 阳性对照：装配确实产出了该症候行（防空串上的负断言假绿）
    expect(assembled, contains('B001 对话抢话症'));
    // 核心断言：disputeReason 拼进 LLM 上下文（chat_context_builder.dart:306-307）
    expect(
      assembled,
      contains('（学员理由：第三句对话里两个人抢话）'),
      reason: '被质疑症候的理由必须随非 focus 摘要行回注给 LLM',
    );
  });

  test('G3-c：disputeReason 为空串 → 不出现「（学员理由：」后缀', () {
    final assembled = buildStructuredSyndromeContext(
      const [
        ActiveSyndromeView(
          syndromeId: 'B002',
          syndromeName: '视角漂移症',
          severity: Severity.l2,
          confirmationStatus: ConfirmationStatus.rejected,
          disputeReason: '',
        ),
      ],
      activeFocus: const ActiveFocusContext(
        focusId: 'F999',
        source: FocusSource.userOverride,
        reason: '对照：空理由不应拼后缀',
      ),
    );

    expect(assembled, contains('B002 视角漂移症'));
    expect(assembled, isNot(contains('（学员理由：')));
  });
}
