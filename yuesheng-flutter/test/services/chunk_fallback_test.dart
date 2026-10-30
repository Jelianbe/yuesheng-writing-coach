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

    test('P6 中英标点混合：中英句末同时成界，无缺口、覆盖完整、非末块收尾于句末', () {
      // 无换行整篇，中英句末标点交替（全角「。」「！」与半角 ". " "?" ";"）。
      const unit = '雨停了。The rain stopped. 她说：“走！”Go now? Fine; 好…';
      final src = List<String>.generate(120, (i) => '$i$unit').join();
      expect(src.contains('\n'), isFalse, reason: '语料必须是整篇无换行');
      expect(src.length, greaterThan(kDiagnosisChunkSize));

      final chunks = splitContent(src);
      expect(chunks.length, greaterThan(1), reason: '中英混合长稿同样不得整段成块');

      // ★ 注意：`splitContent` 的输出**不是** `join('')` 可还原的 —— 块间 overlap
      // 是设计语义（块头重复前块尾）。不变量是「无缺口 + 全部落在子串上 +
      // 首 0 / 末 源长」，不是「拼起来等于原文」（P2 的无损属于
      // `splitSentencesOrHardCut` 那一层，两者不可混用）。
      final cov = computeChunkCoverage(src, chunks);
      expect(cov.every((c) => c.located), isTrue, reason: '块必须是原文逐字子串');
      expect(cov.first.start, 0);
      expect(cov.last.end, src.length);
      var cursor = 0;
      for (var i = 0; i < chunks.length; i++) {
        expect(src.contains(chunks[i]), isTrue, reason: '块[$i] 不是原文子串');
        expect(
          cov[i].start,
          lessThanOrEqualTo(cursor),
          reason: '块[$i] 起点在上一块终点之后 ⇒ 出现缺口',
        );
        cursor = cov[i].end > cursor ? cov[i].end : cursor;
      }
      expect(cursor, src.length, reason: '末端未被覆盖 ⇒ 尾部丢失');

      for (var i = 0; i < chunks.length - 1; i++) {
        final tail = chunks[i].substring(chunks[i].length - 1);
        expect(
          _kEnders.contains(tail) || tail == '.',
          isTrue,
          reason: '非末块尾必须落在句末标点上（英文句点仅在后接空白时成界）',
        );
      }
      for (var i = 0; i < chunks.length; i++) {
        final lim = i == chunks.length - 1
            ? kDiagnosisChunkSize + kDiagnosisMinLastChunk
            : kDiagnosisChunkSize;
        expect(chunks[i].length, lessThanOrEqualTo(lim), reason: '块长越界');
      }
    });

    test('P7 英文句点只认「后接空白/行尾」：小数点不断句，". " 断句', () {
      // 反向：v1.2.3 / 3.14 不得成界
      const s = '版本 v1.2.3 已发布，共 3.14 万字节。下一段。';
      final parts = splitSentencesOrHardCut(s);
      expect(parts.length, 2, reason: '小数点/版本号被当句末 ⇒ 句中切成两段');
      expect(parts.first.endsWith('。'), isTrue);
      expect(parts.join(), s);
      // 正向：英文 ". " 与行尾 "." 成界
      expect(splitSentencesOrHardCut('One. Two.'), <String>['One.', ' Two.']);
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

      // 末块合并（空分隔符分支）：6200 = 3000 + 3000 + 200（< MINL）⇒ 并入前块。
      // 若该分支退化成 `last.split('')`（按码元切再 join）⇒ 尾部 200 字丢失。
      final merged = splitContent('风' * 6200);
      expect(merged.map((c) => c.length).toList(), <int>[3000, 3200]);
      expect(merged.join(), '风' * 6200, reason: '末块合并丢字');
    });
  });

  test('P4 回归：有换行稿路径不变（3×1199 ⇒ 2 块 × 2400）', () {
    final src = <String>['风' * 1199, '风' * 1199, '风' * 1199].join('\n\n');
    final chunks = splitContent(src);
    expect(chunks.length, 2);
    expect(chunks.every((c) => c.length == 2400), isTrue);
  });
}
