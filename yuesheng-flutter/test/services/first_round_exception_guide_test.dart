// B1 包（T-20261113-02 · R-027 舰长 2026-11-15「都批」）：
// 分块链例外表按**同一真源**进短链首轮判据注入面，消除「能报不能撤」链差。
//
// 牙口五处（报批稿 §8）：
//   1) 整表首行与末行确实在块内（逐字）；
//   2) 整表是独立块 —— 首个例外行前恰一个空行接缝（接缝不吞换行）；
//   3) 零复制牙：块后缀 == `\n\n` + buildChunkExceptionGuide()（手抄副本即红）；
//   4) R-009 牙：禁 P007 ⇒ 无 P007例外，但仍有 P008例外；
//   5) 早退保持：四个首轮 ID 全禁 ⇒ 空串（原 `ids.isEmpty` 语义不被破坏）。

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/chunk_exception_guide_data.dart';
import 'package:writingcoach/services/syndrome_knowledge_base.dart';

void main() {
  const guideTitle = '例外情况指引（以下场景通常不应判定为症候）：';

  group('B1 · 例外表进短链首轮面', () {
    test('① 整表首行与末行逐字在块内', () {
      final block = buildFirstRoundCriteriaBlock();
      final lines = kChunkExceptionGuideLines;
      expect(block, contains(guideTitle), reason: '缺例外表首行标题');
      expect(block, contains(lines.last), reason: '缺例外表末行（兜底句）');
      // 末行确实是块的结尾（后面不得再挂别的东西）。
      expect(block.endsWith(lines.last), isTrue, reason: '末行不在块尾');
    });

    test('② 独立块：首个例外行前恰一个空行接缝', () {
      final block = buildFirstRoundCriteriaBlock();
      final idx = block.indexOf(guideTitle);
      expect(idx, greaterThan(0), reason: '例外块没出现或出现在块首');
      expect(
        block.substring(idx - 2, idx),
        '\n\n',
        reason: '接缝不是恰好两个换行（§4-161 同型：raw string 吃起首换行）',
      );
      expect(
        block.substring(idx - 3, idx),
        isNot('\n\n\n'),
        reason: '接缝是多于一个空行（拼接多吃了一个换行）',
      );
    });

    test('③ 零复制牙：块后缀 == 空行 + 真源装配结果', () {
      final block = buildFirstRoundCriteriaBlock();
      final guide = buildChunkExceptionGuide();
      expect(
        block.endsWith('\n\n$guide'),
        isTrue,
        reason: '块内例外表与真源装配结果不等 ⇒ 出现副本（改真源不会自动跟上）',
      );
      // 真源本身非空，避免「两边都空」的恒真退化。
      expect(guide.length, greaterThan(2000), reason: '真源疑似被清空');
    });

    test('④ R-009 牙：关闭 P007 ⇒ 剔除其例外行，其余保留', () {
      final block = buildFirstRoundCriteriaBlock(
        disabledSyndromeIds: const {'P007'},
      );
      expect(block, isNot(contains('- P007例外')), reason: 'R-009：关闭的症候不该被提示');
      expect(block, contains('- P008例外'), reason: '未关闭症候的例外不该被连带剔除');
      expect(block, contains(guideTitle), reason: '剔除后其余行仍在 ⇒ 标题保留');
    });

    test('⑤ 早退保持：四个首轮 ID 全禁 ⇒ 空串', () {
      final block = buildFirstRoundCriteriaBlock(
        disabledSyndromeIds: const {'P001', 'P002', 'P003', 'P018'},
      );
      expect(block, isEmpty, reason: 'ids.isEmpty 早退语义被破坏');
    });
  });
}
