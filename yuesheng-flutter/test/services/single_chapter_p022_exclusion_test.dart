// B 包（T-20261028-06 · R-027 舰长批）：
// P022 退出单章/短链诊断面，merge 侧保留。
//
// 牙口四处：
//   1) 短链诊断 prompt 的索引不再有 P022 行（真走 buildSystemPromptV2）；
//   2) 库常量 kSyndromeIndexContent 仍含该行（四库一致性反查牙，防「顺手删库」）；
//   3) 排除函数按集合剥症候；空集不剥（merge 侧语义）；
//   4) 单章排除集只挂短链调用点，merge 的 commitDiagnosisFromContent 保持单参。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/contracts/diagnosis_capability.dart';
import 'package:writingcoach/contracts/teaching_capability.dart';
import 'package:writingcoach/services/diagnosis_flow_handler.dart'
    show filterExcludedSyndromes;
import 'package:writingcoach/services/skill_dispatcher.dart'
    show buildSystemPromptV2;
import 'package:writingcoach/services/syndrome_knowledge_base.dart';
import 'package:writingcoach/services/syndrome_registry.dart';
import 'package:writingcoach/types/teaching_types.dart';

ParseResult _result(List<String> ids) => ParseResult(
  displayContent: '诊断正文',
  diagnosis: ParsedDiagnosis(
    syndromes: [
      for (final id in ids)
        Syndrome(
          syndromeId: id,
          name: id,
          severity: Severity.l2,
          evidence: const ['原句'],
          explanation: '说明',
        ),
    ],
    suggestedActions: const [],
    confidence: 0.8,
  ),
);

void main() {
  group('B 包 · P022 退出单章短链面', () {
    test('① 短链诊断 prompt 索引无 P022 行（真走装配链）', () {
      final r = buildSystemPromptV2(
        const SkillLoadContext(
          phase: TeachingPhase.p2PracticeLoop,
          attitude: AttitudeLevel.yuesheng,
          subphase: TeachingSubphase.diagnosis,
        ),
        modeOverride: L2Mode.diagnosis,
      );
      expect(r.systemPrompt, contains('| P021 |'), reason: '邻行应在');
      expect(r.systemPrompt, contains('| P023 |'), reason: '邻行应在');
      expect(
        r.systemPrompt,
        isNot(contains('| P022 |')),
        reason: 'P022 索引行不应进入单章短链注入面',
      );
    });

    test('② 库常量仍保留 P022 行（四库一致性反查牙）', () {
      expect(
        kSyndromeIndexContent,
        contains('| P022 |'),
        reason: '不得从库常量删行——排除只发生在注入点',
      );
    });

    test('③ 排除集剥 P022、留同轮其他症候；空集不剥（merge 语义）', () {
      final filtered = filterExcludedSyndromes(
        _result(const ['P022', 'P001']),
        const {'P022'},
      );
      expect(filtered.diagnosis!.syndromes.map((s) => s.syndromeId), ['P001']);
      expect(filtered.displayContent, '诊断正文', reason: '正文不动（只剥 syndrome）');

      final untouched = filterExcludedSyndromes(
        _result(const ['P022']),
        const {},
      );
      expect(
        untouched.diagnosis!.syndromes.single.syndromeId,
        'P022',
        reason: 'merge/跨章路径不传排除集 ⇒ P022 保留',
      );
    });

    test('④ 单章排除集只挂短链调用点（merge 保持单参）', () {
      final src = File(
        'lib/services/diagnosis_flow_handler.dart',
      ).readAsStringSync();
      expect(
        RegExp(
          r'extraExcluded:\s*kSingleChapterExcludedSyndromeIds',
        ).allMatches(src).length,
        1,
        reason: '单章排除集只允许出现在短链专用入口 `_filterShortChain`',
      );
      expect(
        RegExp(r'_filterShortChain\(').allMatches(src).length,
        2,
        reason: '短链专用入口应只有「定义 + 唯一调用」两处（多一处即挂错链）',
      );
      expect(
        RegExp(
          r'_filterDisabled\(\s*_diagnosis\.parseDiagnosis\(fullContent\)\s*\)',
        ).hasMatch(src),
        isTrue,
        reason: 'commitDiagnosisFromContent（merge）必须保持单参调用',
      );
    });

    test('⑤ 索引行数 = 注册表条数 − 1（只少 P022 一条）', () {
      final idx = buildSyndromeIndexContent(kSingleChapterExcludedSyndromeIds);
      final rows = RegExp(
        r'^\| P\d{3} \|',
        multiLine: true,
      ).allMatches(idx).length;
      expect(rows, kSyndromeIds.length - 1);
    });
  });
}
