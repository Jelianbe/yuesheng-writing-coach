// ─────────────────────────────────────────────────────────────
// ADR-0006 D 组：payload overall 透传 + 往返稳定 + 呈现区判据
//
// 覆盖：
//   payload fromJson/toJson 往返稳定（含空串/null 归一）
//   H-3 payload 侧防御性二次校验（缺 coverage ⇒ null）
//   诊断卡 overall 呈现（widget 级：verdict/覆盖度/无分数）
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:writingcoach/services/message_card_service.dart';
import 'package:writingcoach/types/teaching_types.dart';
import 'package:writingcoach/widgets/diagnosis_card.dart';

OverallDiagnosis _overall({
  String verdict = '基本完整',
  String coverage = '基于已诊断 3/20 章',
}) => OverallDiagnosis(
  verdict: verdict,
  reasons: ['节奏尚可', '因果链完整'],
  keep: '开篇钩子',
  priority: ['先改转场', '再改密度'],
  coverage: coverage,
);

Map<String, dynamic> _payloadJson({OverallDiagnosis? overall}) => {
  'syndromeCount': 1,
  'syndromes': [
    {
      'syndromeId': 'P001',
      'name': '情绪标签化',
      'severity': 'L2',
      'evidenceCount': 1,
      'evidence': ['她很难过'],
      'explanation': '直接贴标签',
    },
  ],
  'suggestedActions': ['A009'],
  'confidence': 0.8,
  'diagnosisId': 'm1',
  if (overall != null) 'overall': overall.toJson(),
};

void main() {
  group('payload overall 透传与往返', () {
    test('#1 有 overall ⇒ fromJson 读出全部字段', () {
      final p = DiagnosisResultCardPayload.fromJson(
        _payloadJson(overall: _overall()),
      );
      expect(p.overall, isNotNull);
      expect(p.overall!.verdict, '基本完整');
      expect(p.overall!.reasons, ['节奏尚可', '因果链完整']);
      expect(p.overall!.keep, '开篇钩子');
      expect(p.overall!.priority, ['先改转场', '再改密度']);
      expect(p.overall!.coverage, '基于已诊断 3/20 章');
    });

    test('#2 toJson→fromJson 往返稳定（overall 不丢）', () {
      final p = DiagnosisResultCardPayload.fromJson(
        _payloadJson(overall: _overall()),
      );
      final p2 = DiagnosisResultCardPayload.fromJson(p.toJson());
      expect(p2.overall, isNotNull);
      expect(p2.overall!.verdict, p.overall!.verdict);
      expect(p2.overall!.reasons, p.overall!.reasons);
      expect(p2.overall!.coverage, p.overall!.coverage);
    });

    test('#3 无 overall 键（旧数据）⇒ null、不抛', () {
      final p = DiagnosisResultCardPayload.fromJson(
        _payloadJson(overall: null),
      );
      expect(p.overall, isNull);
      expect(p.toJson().containsKey('overall'), isFalse);
    });

    test('#4 H-3 payload 侧防御：overall 缺 coverage ⇒ null', () {
      final json = _payloadJson()
        ..['overall'] = {
          'verdict': '结构完整',
          'reasons': ['x'],
          'priority': <String>[],
        };
      final p = DiagnosisResultCardPayload.fromJson(json);
      expect(p.overall, isNull);
    });

    test('#5 H-3 payload 侧防御：verdict 非三档 ⇒ null', () {
      final json = _payloadJson()
        ..['overall'] = {
          'verdict': '神作',
          'reasons': ['x'],
          'coverage': '基于已诊断 3/20 章',
        };
      final p = DiagnosisResultCardPayload.fromJson(json);
      expect(p.overall, isNull);
    });
  });

  group('诊断卡 overall 呈现（widget 级）', () {
    testWidgets('#6 overall 非空 ⇒ 渲染 verdict + 覆盖度 + keep + priority', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: DiagnosisCard(
                  syndromeCount: 1,
                  syndromes: const [
                    DiagnosisSyndromeCard(
                      syndromeId: 'P001',
                      name: '情绪标签化',
                      severity: 'L2',
                      evidenceCount: 1,
                      evidence: ['她很难过'],
                      explanation: '直接贴标签',
                    ),
                  ],
                  suggestedActions: const ['A009'],
                  confidence: 0.8,
                  overall: _overall(),
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('整体判定'), findsOne);
      expect(find.text('基本完整'), findsOne);
      expect(find.text('基于已诊断 3/20 章'), findsOne);
      expect(find.textContaining('最值得保持：开篇钩子'), findsOne);
      expect(find.textContaining('建议先改：先改转场 → 再改密度'), findsOne);
      // 诚实边界句（R-009）
      expect(find.textContaining('文笔质感、情绪感染力、主题立意'), findsOne);
    });

    testWidgets('#7 R-009：不呈现任何数字分数', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: DiagnosisCard(
                  syndromeCount: 1,
                  syndromes: const [
                    DiagnosisSyndromeCard(
                      syndromeId: 'P001',
                      name: '情绪标签化',
                      severity: 'L2',
                      evidenceCount: 1,
                      evidence: ['她很难过'],
                      explanation: '直接贴标签',
                    ),
                  ],
                  suggestedActions: const ['A009'],
                  confidence: 0.8,
                  overall: _overall(),
                ),
              ),
            ),
          ),
        ),
      );
      // 呈现区不得出现「分」或百分制数字（confidence 是既有字段且不在
      // overall 区内；此处只扫 overall 专属文本）。
      final overallTexts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .where((s) => s.contains('整体判定') || s.contains('基本完整'));
      for (final t in overallTexts) {
        expect(t, isNot(contains('分')));
        expect(RegExp(r'\d{1,3}\s*/\s*100').hasMatch(t), isFalse);
      }
    });

    testWidgets('#8 overall 为 null ⇒ 整体判定区不渲染', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: DiagnosisCard(
                  syndromeCount: 1,
                  syndromes: const [
                    DiagnosisSyndromeCard(
                      syndromeId: 'P001',
                      name: '情绪标签化',
                      severity: 'L2',
                      evidenceCount: 1,
                      evidence: ['她很难过'],
                      explanation: '直接贴标签',
                    ),
                  ],
                  suggestedActions: const ['A009'],
                  confidence: 0.8,
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('整体判定'), findsNothing);
    });
  });
}
