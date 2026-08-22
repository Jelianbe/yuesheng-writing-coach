// ignore_for_file: avoid_print
// 批次96-14+96-15：教学「老师」角色验收——全量语料（A 全量39单症候 / B 6冲突 / C 2负样本）
// 方法：子代理读真实提示词模拟 LLM 产出协议回复（落盘 test/fixtures/corpus_*.txt），
// 本测试用 app 真实解析器/校验器吃进，并断言结构化决策 + 合规约束。
//
// 重要边界：fixture 中的 natural_language 仅为驱动解析/一致性校验的样本输入，
// 话术由 AI 现场生成，绝不作为期望文案断言（本测试对其只查 P0xx 泄漏）。
//
// 覆盖验收维度：
//  1) 管道：诊断块/教学块均可被真实 parser 解析（schema 合法）
//  2) 教练底线：一致性通过（无判决词 / 无 P0xx 泄漏 / guide-train 必带 task）
//  3) 决策正确：L2 症候 → train；好文本 → encourage；过短 → defer
//  4) 诊断召回 + 误诊率：A/B 档命中 ground-truth 症候、主症排第一、无凭空症候
//  5) 负样本不误诊：C 档零 L2 误报
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/diagnosis_parser.dart';
import 'package:writingcoach/services/teacher_parser.dart';
import 'package:writingcoach/services/teacher_validator.dart';
import 'package:writingcoach/types/teaching_types.dart';

String _fix(String name) => File('test/fixtures/$name').readAsStringSync();

class CorpusItem {
  final String id;
  final String file;
  final List<String> expectSyndromes; // 期望命中的症候（L2）
  final String primarySyndrome; // 期望排在 syndromes[0] 的主症
  final String expectedDecision;
  final bool hasL2Expected; // true=A/B 档；false=C 档（不应有 L2）
  final String? expectedTaskSyndrome; // train/guide 时 target_syndrome_id 期望

  const CorpusItem({
    required this.id,
    required this.file,
    required this.expectSyndromes,
    required this.primarySyndrome,
    required this.expectedDecision,
    required this.hasL2Expected,
    this.expectedTaskSyndrome,
  });
}

const List<CorpusItem> corpus = [
  // ── A 档：全量单症候（P003–P041 各 1 代表，单一清晰症候，L2 → train）──
  CorpusItem(
    id: 'A1',
    file: 'corpus_A1_p003.txt',
    expectSyndromes: ['P003'],
    primarySyndrome: 'P003',
    expectedDecision: 'train',
    hasL2Expected: true,
    expectedTaskSyndrome: 'P003',
  ),
  CorpusItem(
    id: 'A2',
    file: 'corpus_A2_p007.txt',
    expectSyndromes: ['P007'],
    primarySyndrome: 'P007',
    expectedDecision: 'train',
    hasL2Expected: true,
    expectedTaskSyndrome: 'P007',
  ),
  CorpusItem(
    id: 'A3',
    file: 'corpus_A3_p009.txt',
    expectSyndromes: ['P009'],
    primarySyndrome: 'P009',
    expectedDecision: 'train',
    hasL2Expected: true,
    expectedTaskSyndrome: 'P009',
  ),
  CorpusItem(
    id: 'A4',
    file: 'corpus_A4_p011.txt',
    expectSyndromes: ['P011'],
    primarySyndrome: 'P011',
    expectedDecision: 'train',
    hasL2Expected: true,
    expectedTaskSyndrome: 'P011',
  ),
  CorpusItem(
    id: 'A5',
    file: 'corpus_A5_p012.txt',
    expectSyndromes: ['P012'],
    primarySyndrome: 'P012',
    expectedDecision: 'train',
    hasL2Expected: true,
    expectedTaskSyndrome: 'P012',
  ),
  CorpusItem(
    id: 'A6',
    file: 'corpus_A6_p013.txt',
    expectSyndromes: ['P013'],
    primarySyndrome: 'P013',
    expectedDecision: 'train',
    hasL2Expected: true,
    expectedTaskSyndrome: 'P013',
  ),
  CorpusItem(
    id: 'A7',
    file: 'corpus_A7_p021.txt',
    expectSyndromes: ['P021'],
    primarySyndrome: 'P021',
    expectedDecision: 'train',
    hasL2Expected: true,
    expectedTaskSyndrome: 'P021',
  ),
  CorpusItem(
    id: 'A8',
    file: 'corpus_A8_p028.txt',
    expectSyndromes: ['P028'],
    primarySyndrome: 'P028',
    expectedDecision: 'train',
    hasL2Expected: true,
    expectedTaskSyndrome: 'P028',
  ),
  CorpusItem(
    id: 'A9',
    file: 'corpus_A9_p022.txt',
    expectSyndromes: ['P022'],
    primarySyndrome: 'P022',
    expectedDecision: 'train',
    hasL2Expected: true,
    expectedTaskSyndrome: 'P022',
  ),
  CorpusItem(
    id: 'A10',
    file: 'corpus_A10_p004.txt',
    expectSyndromes: ['P004'],
    primarySyndrome: 'P004',
    expectedDecision: 'train',
    hasL2Expected: true,
    expectedTaskSyndrome: 'P004',
  ),
  CorpusItem(
    id: 'A11',
    file: 'corpus_A11_p005.txt',
    expectSyndromes: ['P005'],
    primarySyndrome: 'P005',
    expectedDecision: 'train',
    hasL2Expected: true,
    expectedTaskSyndrome: 'P005',
  ),
  CorpusItem(
    id: 'A_p006',
    file: 'corpus_A_p006.txt',
    expectSyndromes: ['P006'],
    primarySyndrome: 'P006',
    expectedDecision: 'train',
    hasL2Expected: true,
    expectedTaskSyndrome: 'P006',
  ),
  CorpusItem(
    id: 'A12',
    file: 'corpus_A12_p008.txt',
    expectSyndromes: ['P008'],
    primarySyndrome: 'P008',
    expectedDecision: 'train',
    hasL2Expected: true,
    expectedTaskSyndrome: 'P008',
  ),
  CorpusItem(
    id: 'A13',
    file: 'corpus_A13_p010.txt',
    expectSyndromes: ['P010'],
    primarySyndrome: 'P010',
    expectedDecision: 'train',
    hasL2Expected: true,
    expectedTaskSyndrome: 'P010',
  ),
  CorpusItem(
    id: 'A14',
    file: 'corpus_A14_p014.txt',
    expectSyndromes: ['P014'],
    primarySyndrome: 'P014',
    expectedDecision: 'train',
    hasL2Expected: true,
    expectedTaskSyndrome: 'P014',
  ),
  CorpusItem(
    id: 'A15',
    file: 'corpus_A15_p015.txt',
    expectSyndromes: ['P015'],
    primarySyndrome: 'P015',
    expectedDecision: 'train',
    hasL2Expected: true,
    expectedTaskSyndrome: 'P015',
  ),
  CorpusItem(
    id: 'A16',
    file: 'corpus_A16_p016.txt',
    expectSyndromes: ['P016'],
    primarySyndrome: 'P016',
    expectedDecision: 'train',
    hasL2Expected: true,
    expectedTaskSyndrome: 'P016',
  ),
  CorpusItem(
    id: 'A17',
    file: 'corpus_A17_p017.txt',
    expectSyndromes: ['P017'],
    primarySyndrome: 'P017',
    expectedDecision: 'train',
    hasL2Expected: true,
    expectedTaskSyndrome: 'P017',
  ),
  CorpusItem(
    id: 'A18',
    file: 'corpus_A18_p018.txt',
    expectSyndromes: ['P018'],
    primarySyndrome: 'P018',
    expectedDecision: 'train',
    hasL2Expected: true,
    expectedTaskSyndrome: 'P018',
  ),
  CorpusItem(
    id: 'A19',
    file: 'corpus_A19_p019.txt',
    expectSyndromes: ['P019'],
    primarySyndrome: 'P019',
    expectedDecision: 'train',
    hasL2Expected: true,
    expectedTaskSyndrome: 'P019',
  ),
  CorpusItem(
    id: 'A20',
    file: 'corpus_A20_p020.txt',
    expectSyndromes: ['P020'],
    primarySyndrome: 'P020',
    expectedDecision: 'train',
    hasL2Expected: true,
    expectedTaskSyndrome: 'P020',
  ),
  CorpusItem(
    id: 'A21',
    file: 'corpus_A21_p023.txt',
    expectSyndromes: ['P023'],
    primarySyndrome: 'P023',
    expectedDecision: 'train',
    hasL2Expected: true,
    expectedTaskSyndrome: 'P023',
  ),
  CorpusItem(
    id: 'A22',
    file: 'corpus_A22_p024.txt',
    expectSyndromes: ['P024'],
    primarySyndrome: 'P024',
    expectedDecision: 'train',
    hasL2Expected: true,
    expectedTaskSyndrome: 'P024',
  ),
  CorpusItem(
    id: 'A23',
    file: 'corpus_A23_p025.txt',
    expectSyndromes: ['P025'],
    primarySyndrome: 'P025',
    expectedDecision: 'train',
    hasL2Expected: true,
    expectedTaskSyndrome: 'P025',
  ),
  CorpusItem(
    id: 'A24',
    file: 'corpus_A24_p026.txt',
    expectSyndromes: ['P026'],
    primarySyndrome: 'P026',
    expectedDecision: 'train',
    hasL2Expected: true,
    expectedTaskSyndrome: 'P026',
  ),
  CorpusItem(
    id: 'A25',
    file: 'corpus_A25_p027.txt',
    expectSyndromes: ['P027'],
    primarySyndrome: 'P027',
    expectedDecision: 'train',
    hasL2Expected: true,
    expectedTaskSyndrome: 'P027',
  ),
  CorpusItem(
    id: 'A26',
    file: 'corpus_A26_p029.txt',
    expectSyndromes: ['P029'],
    primarySyndrome: 'P029',
    expectedDecision: 'train',
    hasL2Expected: true,
    expectedTaskSyndrome: 'P029',
  ),
  CorpusItem(
    id: 'A27',
    file: 'corpus_A27_p030.txt',
    expectSyndromes: ['P030'],
    primarySyndrome: 'P030',
    expectedDecision: 'train',
    hasL2Expected: true,
    expectedTaskSyndrome: 'P030',
  ),
  CorpusItem(
    id: 'A28',
    file: 'corpus_A28_p031.txt',
    expectSyndromes: ['P031'],
    primarySyndrome: 'P031',
    expectedDecision: 'train',
    hasL2Expected: true,
    expectedTaskSyndrome: 'P031',
  ),
  CorpusItem(
    id: 'A29',
    file: 'corpus_A29_p032.txt',
    expectSyndromes: ['P032'],
    primarySyndrome: 'P032',
    expectedDecision: 'train',
    hasL2Expected: true,
    expectedTaskSyndrome: 'P032',
  ),
  CorpusItem(
    id: 'A30',
    file: 'corpus_A30_p033.txt',
    expectSyndromes: ['P033'],
    primarySyndrome: 'P033',
    expectedDecision: 'train',
    hasL2Expected: true,
    expectedTaskSyndrome: 'P033',
  ),
  CorpusItem(
    id: 'A31',
    file: 'corpus_A31_p034.txt',
    expectSyndromes: ['P034'],
    primarySyndrome: 'P034',
    expectedDecision: 'train',
    hasL2Expected: true,
    expectedTaskSyndrome: 'P034',
  ),
  CorpusItem(
    id: 'A32',
    file: 'corpus_A32_p035.txt',
    expectSyndromes: ['P035'],
    primarySyndrome: 'P035',
    expectedDecision: 'train',
    hasL2Expected: true,
    expectedTaskSyndrome: 'P035',
  ),
  CorpusItem(
    id: 'A33',
    file: 'corpus_A33_p036.txt',
    expectSyndromes: ['P036'],
    primarySyndrome: 'P036',
    expectedDecision: 'train',
    hasL2Expected: true,
    expectedTaskSyndrome: 'P036',
  ),
  CorpusItem(
    id: 'A34',
    file: 'corpus_A34_p037.txt',
    expectSyndromes: ['P037'],
    primarySyndrome: 'P037',
    expectedDecision: 'train',
    hasL2Expected: true,
    expectedTaskSyndrome: 'P037',
  ),
  CorpusItem(
    id: 'A35',
    file: 'corpus_A35_p038.txt',
    expectSyndromes: ['P038'],
    primarySyndrome: 'P038',
    expectedDecision: 'train',
    hasL2Expected: true,
    expectedTaskSyndrome: 'P038',
  ),
  CorpusItem(
    id: 'A36',
    file: 'corpus_A36_p039.txt',
    expectSyndromes: ['P039'],
    primarySyndrome: 'P039',
    expectedDecision: 'train',
    hasL2Expected: true,
    expectedTaskSyndrome: 'P039',
  ),
  CorpusItem(
    id: 'A37',
    file: 'corpus_A37_p040.txt',
    expectSyndromes: ['P040'],
    primarySyndrome: 'P040',
    expectedDecision: 'train',
    hasL2Expected: true,
    expectedTaskSyndrome: 'P040',
  ),
  CorpusItem(
    id: 'A38',
    file: 'corpus_A38_p041.txt',
    expectSyndromes: ['P041'],
    primarySyndrome: 'P041',
    expectedDecision: 'train',
    hasL2Expected: true,
    expectedTaskSyndrome: 'P041',
  ),
  // ── B 档：6 组冲突（优先级裁决，主症排第一，train 锁主症）──
  CorpusItem(
    id: 'B1',
    file: 'corpus_B1_p012_p006.txt',
    expectSyndromes: ['P012', 'P006'],
    primarySyndrome: 'P012',
    expectedDecision: 'train',
    hasL2Expected: true,
    expectedTaskSyndrome: 'P012',
  ),
  CorpusItem(
    id: 'B2',
    file: 'corpus_B2_p028_p003.txt',
    expectSyndromes: ['P028', 'P003'],
    primarySyndrome: 'P028',
    expectedDecision: 'train',
    hasL2Expected: true,
    expectedTaskSyndrome: 'P028',
  ),
  CorpusItem(
    id: 'B3',
    file: 'corpus_B3_p005_p003.txt',
    expectSyndromes: ['P005'],
    primarySyndrome: 'P005',
    expectedDecision: 'train',
    hasL2Expected: true,
    expectedTaskSyndrome: 'P005',
  ),
  CorpusItem(
    id: 'B4',
    file: 'corpus_B4_p012_p015.txt',
    expectSyndromes: ['P012', 'P015'],
    primarySyndrome: 'P012',
    expectedDecision: 'train',
    hasL2Expected: true,
    expectedTaskSyndrome: 'P012',
  ),
  CorpusItem(
    id: 'B5',
    file: 'corpus_B5_p030_p006.txt',
    expectSyndromes: ['P030', 'P006'],
    primarySyndrome: 'P030',
    expectedDecision: 'train',
    hasL2Expected: true,
    expectedTaskSyndrome: 'P030',
  ),
  CorpusItem(
    id: 'B6',
    file: 'corpus_B6_p041_p012.txt',
    expectSyndromes: ['P041', 'P012'],
    primarySyndrome: 'P041',
    expectedDecision: 'train',
    hasL2Expected: true,
    expectedTaskSyndrome: 'P041',
  ),
  // ── C 档：2 段负样本（不误诊）──
  CorpusItem(
    id: 'C1',
    file: 'corpus_C1_good.txt',
    expectSyndromes: [],
    primarySyndrome: '',
    expectedDecision: 'encourage',
    hasL2Expected: false,
  ),
  CorpusItem(
    id: 'C2',
    file: 'corpus_C2_short.txt',
    expectSyndromes: [],
    primarySyndrome: '',
    expectedDecision: 'defer',
    hasL2Expected: false,
  ),
];

void main() {
  for (final item in corpus) {
    test('[${item.id}] ${item.file} → 真实解析+一致性+ground truth', () {
      final raw = _fix(item.file);

      // ── 诊断层 ──
      final diag = parseDiagnosis(raw);
      expect(diag.diagnosis, isNotNull, reason: '${item.id}: 诊断块应被解析');
      final d = diag.diagnosis!;
      final hitIds = d.syndromes.map((s) => s.syndromeId).toList();
      final l2Hits = d.syndromes
          .where((s) => s.severity == Severity.l2)
          .toList();
      print(
        '[$item] 诊断命中: ${d.syndromes.map((s) => "${s.syndromeId}/${s.severity}").join(", ")}  '
        'confidence=${d.confidence}',
      );

      if (item.hasL2Expected) {
        // 召回：期望症候全部命中
        for (final exp in item.expectSyndromes) {
          expect(
            hitIds.contains(exp),
            isTrue,
            reason: '$item: 应召回 $exp（诊断召回率）',
          );
        }
        // 主症排第一
        expect(
          hitIds.first,
          equals(item.primarySyndrome),
          reason: '$item: 主症 ${item.primarySyndrome} 应排 syndromes[0]',
        );
        // 误诊率：所有 L2 命中都应在期望集合内（不得凭空造症候）
        final spurious = l2Hits
            .where((s) => !item.expectSyndromes.contains(s.syndromeId))
            .map((s) => s.syndromeId)
            .toList();
        expect(
          spurious,
          isEmpty,
          reason: '$item: 出现非期望 L2 症候（误诊/误报）=$spurious',
        );
      } else {
        // 负样本：不应有 L2 误报
        expect(l2Hits, isEmpty, reason: '$item: 负样本不应命中任何 L2 症候（误诊）');
      }

      // ── 教学层 ──
      final tParse = parseTeacherDecision(raw);
      expect(tParse.teacher, isNotNull, reason: '$item: 教学块应被解析(schema 合法)');
      final t = tParse.teacher!;
      print(
        '[$item] 决策=${t.teachingDecision}  task=${t.trainingTask?.taskType}  '
        'target=${t.trainingTask?.targetSyndromeId}',
      );
      print('[$item] 自然语言=${t.naturalLanguage}');

      final cons = checkTeacherConsistency(t);
      print(
        '[$item] 一致性.passed=${cons.passed}  '
        '违规=${cons.violations.map((v) => "${v.severity}:${v.rule}").join(", ")}',
      );
      expect(
        cons.passed,
        isTrue,
        reason: '$item: 一致性应通过（无判决词/无P0xx泄漏/decision↔task）',
      );

      // 决策符合预期
      expect(
        t.teachingDecision,
        equals(item.expectedDecision),
        reason: '$item: 决策应为 ${item.expectedDecision}',
      );

      // task 与决策一致
      if (item.expectedDecision == 'train' ||
          item.expectedDecision == 'guide') {
        expect(
          t.trainingTask,
          isNotNull,
          reason: '$item: ${item.expectedDecision} 必带 training_task',
        );
        if (item.expectedTaskSyndrome != null) {
          expect(
            t.trainingTask!.targetSyndromeId,
            equals(item.expectedTaskSyndrome),
            reason: '$item: training_task 应锁定主症 ${item.expectedTaskSyndrome}',
          );
        }
      } else {
        expect(
          t.trainingTask,
          isNull,
          reason: '$item: ${item.expectedDecision} 不应有 training_task',
        );
      }

      // 自然语言不得泄漏症候 ID
      expect(
        RegExp(r'P0\d{2}').hasMatch(t.naturalLanguage),
        isFalse,
        reason: '$item: natural_language 不得泄漏症候ID',
      );
    });
  }
}
