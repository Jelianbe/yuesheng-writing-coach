// ───────────────────────────────────────────────
// W-15-B B2 · 诊断卡「暂时无法判断」徽标护栏
//
// 任务书 §三 B2.3：pending_context=true 条目展示层带「暂时无法判断」徽标；
// 缺省（null/false）不渲染（数据诚实：不编造状态）。
// harness 对齐 diagnosis_card_test.dart（ProviderScope + 基础字段构造）。
// ───────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/message_card_service.dart';
import 'package:writingcoach/widgets/diagnosis_card.dart';

Widget _wrap(Widget child) => ProviderScope(
  child: MaterialApp(home: Scaffold(body: child)),
);

const _kBadgeText = '暂时无法判断';

void main() {
  testWidgets('pending_context=true ⇒ 渲染「暂时无法判断」徽标', (tester) async {
    await tester.pumpWidget(
      _wrap(
        DiagnosisCard(
          syndromeCount: 1,
          syndromes: const [
            DiagnosisSyndromeCard(
              syndromeId: 'P001',
              name: '情绪标签化',
              severity: 'L2',
              evidenceCount: 1,
              pendingContext: true,
            ),
          ],
          suggestedActions: const [],
          confidence: 0.9,
        ),
      ),
    );
    expect(find.text(_kBadgeText).hitTestable(), findsOneWidget);
  });

  testWidgets('pending_context 缺省（null）⇒ 不渲染徽标', (tester) async {
    await tester.pumpWidget(
      _wrap(
        DiagnosisCard(
          syndromeCount: 1,
          syndromes: const [
            DiagnosisSyndromeCard(
              syndromeId: 'P001',
              name: '情绪标签化',
              severity: 'L2',
              evidenceCount: 1,
            ),
          ],
          suggestedActions: const [],
          confidence: 0.9,
        ),
      ),
    );
    expect(find.text(_kBadgeText), findsNothing);
  });

  testWidgets('pending_context=false ⇒ 不渲染徽标（与 null 同口径）', (tester) async {
    await tester.pumpWidget(
      _wrap(
        DiagnosisCard(
          syndromeCount: 1,
          syndromes: const [
            DiagnosisSyndromeCard(
              syndromeId: 'P001',
              name: '情绪标签化',
              severity: 'L2',
              evidenceCount: 1,
              pendingContext: false,
            ),
          ],
          suggestedActions: const [],
          confidence: 0.9,
        ),
      ),
    );
    expect(find.text(_kBadgeText), findsNothing);
  });
}
