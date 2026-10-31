// B 包（T-20261028-06 · R-027 舰长批）：
// P022 退出单章/短链诊断面，merge 侧保留。
//
// 牙口六处：
//   1) 短链诊断 prompt 的索引不再有 P022 行（真走 buildSystemPromptV2）；
//   2) 库常量 kSyndromeIndexContent 仍含该行（四库一致性反查牙，防「顺手删库」）；
//   3) 排除函数按集合剥症候；空集不剥（merge 侧语义）；
//   4) 短链并集（P022 + P031）只挂短链调用点；merge 出口排 P031 但**不并 P022**；
//   5) 单章排除集行数判据（索引面只少 P022 一条）；
//   6) 续批 T-20261031-11 件①：P031 退出两链注入面（N1 检出力 + N2 防错删，成对）。

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

    test('④ 短链并集只挂短链调用点；merge 出口排 P031 但不并 P022', () {
      final src = File(
        'lib/services/diagnosis_flow_handler.dart',
      ).readAsStringSync();
      // ① 并集真源只允许出现在短链专用入口一处
      expect(
        RegExp(
          r'extraExcluded:\s*kShortChainExcludedSyndromeIds',
        ).allMatches(src).length,
        1,
        reason: '短链并集（P022 + P031）只允许出现在短链专用入口 `_filterShortChain`',
      );
      // ② merge 出口：切片内两要素同现（排 P031 · 不并短链并集）——
      //    只匹配一个名字不算牙：并了 P022 就等于把「跨章侧仍判」改掉（越界）。
      final mergeStart = src.indexOf('final rawParse = _filterDisabled(');
      expect(mergeStart, isNot(-1), reason: '找不到 merge 出口 rawParse');
      final mergeTail = src.indexOf(');', mergeStart);
      expect(mergeTail, greaterThan(mergeStart), reason: 'merge 出口切片右边界异常');
      final mergeSlice = src.substring(mergeStart, mergeTail + 2);
      expect(
        mergeSlice,
        contains('extraExcluded: kNonDiagnosableSyndromeIds'),
        reason: 'commitDiagnosisFromContent（merge）须显式排除前提层不可诊（P031）',
      );
      expect(
        mergeSlice,
        isNot(contains('kShortChainExcludedSyndromeIds')),
        reason: 'merge 出口不得并短链并集——并了就连带排除 P022（跨章侧仍判）',
      );
      expect(
        mergeSlice,
        isNot(contains('kSingleChapterExcludedSyndromeIds')),
        reason: '同上：merge 出口出现单章排除集 = P022 被跨章侧误删',
      );
      // ③ 短链专用入口仍只有「定义 + 唯一调用」两处（多一处即挂错链）
      expect(
        RegExp(r'_filterShortChain\(').allMatches(src).length,
        2,
        reason: '短链专用入口应只有「定义 + 唯一调用」两处（多一处即挂错链）',
      );
    });

    test('⑥ P031 退出短链注入面 + 库常量仍保留该行（N1/N2 成对牙）', () {
      // N1 检出力：装配点用并集过滤后，注入面不得再出现 P031 行。
      final filtered = buildSyndromeIndexContent(
        kShortChainExcludedSyndromeIds,
      );
      expect(
        filtered,
        isNot(contains('| P031 ')),
        reason: 'P031 已退出诊断注入面（判据对象在创作前提层），短链索引不应再含该行',
      );
      // 邻行在场：防「整块被删空」时 N1 反向断言恒绿（坑 1：自述强于鉴别力）。
      expect(filtered, contains('| P030 |'), reason: '邻行 P030 应在');
      expect(filtered, contains('| P032 |'), reason: '邻行 P032 应在');
      // N2 防错删：库常量本体**不删行**，排除只发生在注入点。
      expect(
        kSyndromeIndexContent,
        contains('| P031 '),
        reason: '不得从库常量删 P031 行——四库一致性 #1/行数 护栏依赖它',
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
