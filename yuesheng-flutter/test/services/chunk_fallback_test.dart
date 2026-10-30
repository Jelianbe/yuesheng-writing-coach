// ─────────────────────────────────────────────────────────────
// 分块链第三级降级（句末切分 + 单句硬切）不变量（T-20261031-02）
//
// 报批稿 `reports/2026-10-31-报批稿-T20261031-02-无换行长稿分块兜底.md` §6：
//   P2 无损  —— 块必须是原文逐字子串；句切后 join('') 必须还原原文
//   P3 覆盖  —— computeChunkCoverage 全部 located、首块 start=0、末块 end=源长
//   P5 兜底  —— 无任何标点时必须硬切成界，而不是整段成块
//   P4 回归  —— 有换行稿路径一字不动（3×1199 ⇒ 2×2400）
//
// 这些断言**不依赖快照**：快照被重冻后它们仍能变红（改回 return [content]
// ⇒ P2/P3/P5 全红；把句切套到有换行稿 ⇒ P4 红）。
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/progressive_diagnosis.dart';

const String _kSent = '他推开门，屋里没有人，只有桌上的茶还冒着热气。窗外的雨下得更急了，檐水连成一条线。';

/// 唯一化长稿：每句带 5 位序号前缀，**避免周期性重复**——否则
/// `computeChunkCoverage` 的 `indexOf` 会定位到更早的相同片段，覆盖断言失真
/// （合成语料自身的坑，与产品代码无关）。
String _prose(int n) {
  final b = StringBuffer();
  var i = 0;
  while (b.length < n) {
    b.write('${i.toString().padLeft(5, '0')}：$_kSent');
    i++;
  }
  return b.toString().substring(0, n);
}

const String _kEnders = '。！？…；!?';

void main() {
  group('splitSentencesOrHardCut（第三级降级本体）', () {
    test('P2 无损：切句后 join(\'\') 逐字还原原文', () {
      for (final s in <String>[
        _prose(4001),
        'Hello. World! How are you? Fine; thanks.',
        '他说：“走。”她点头！然后……雨停了；',
      ]) {
        expect(
          splitSentencesOrHardCut(s).join(),
          s,
          reason: '切句丢字 ⇒ 覆盖与证据锚定全错',
        );
      }
    });

    test('P5 兜底：单句超阈值 ⇒ 硬切成 ≤ 阈值，且仍无损', () {
      final s = '风' * 6000;
      final parts = splitSentencesOrHardCut(s);
      expect(parts.length, 2);
      expect(parts.every((p) => p.length <= kDiagnosisChunkSize), isTrue);
      expect(parts.join(), s);
    });
  });

  group('splitContent 第三级降级（整篇无换行）', () {
    test('中文长稿：块数 > 1、逐块子串、覆盖区间完整且不越界', () {
      for (final n in <int>[6000, 20000]) {
        final src = _prose(n);
        final chunks = splitContent(src);
        expect(chunks.length, greaterThan(1), reason: '无换行长稿不得再整段成块');

        final cov = computeChunkCoverage(src, chunks);
        expect(cov.length, chunks.length);
        expect(cov.every((c) => c.located), isTrue, reason: '块不是原文子串 ⇒ 覆盖定位失败');
        expect(cov.first.start, 0);
        expect(cov.last.end, src.length);

        for (var i = 0; i < chunks.length; i++) {
          expect(src.contains(chunks[i]), isTrue, reason: '块必须是原文逐字子串');
          // 末块可因「末块合并」带上一个前块尾 + 一段新内容。
          final lim = i == chunks.length - 1
              ? kDiagnosisChunkSize + kDiagnosisMinLastChunk
              : kDiagnosisChunkSize;
          expect(chunks[i].length, lessThanOrEqualTo(lim), reason: '块长越界');
        }
        // 非末块必须在句末标点处收尾（硬切只在单句自身超阈值时发生）。
        for (var i = 0; i < chunks.length - 1; i++) {
          final tail = chunks[i].substring(chunks[i].length - 1);
          expect(_kEnders.contains(tail), isTrue, reason: '块尾落在句中被切开');
        }
      }
    });

    test('P5 无任何标点 ⇒ 硬切兜底（6000→2×3000，20000→7 块上限 3000）', () {
      final six = '风' * 6000;
      expect(splitContent(six).map((c) => c.length).toList(), <int>[
        3000,
        3000,
      ]);
      final twenty = '风' * 20000;
      final chunks = splitContent(twenty);
      expect(chunks.length, 7);
      expect(chunks.every((c) => c.length <= kDiagnosisChunkSize), isTrue);
      expect(chunks.join(), twenty);
    });
  });

  test('P4 回归：有换行稿路径不变（3×1199 ⇒ 2 块 × 2400）', () {
    final src = <String>['风' * 1199, '风' * 1199, '风' * 1199].join('\n\n');
    final chunks = splitContent(src);
    expect(chunks.length, 2);
    expect(chunks.every((c) => c.length == 2400), isTrue);
  });
}
