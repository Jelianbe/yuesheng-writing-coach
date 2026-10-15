// ─────────────────────────────────────────────────────────────
// W-15-A 回归测试：机械收敛层 + 分块覆盖区间
//
// 覆盖（设计稿 §3.2 / §3.4）：
//   1. evidenceJaccard：完全重叠 / 部分重叠 / 空集
//   2. mergeOutputConvergence：
//      a. 同 id + 证据重叠 ≥ 0.5 → 合并（severity 取高、证据并集）
//      b. 同 id + 证据不相交 → 保留为独立条目
//      c. 不同 id 永不合并
//      d. cap 5：溢出条目进 report.overflow（不丢弃）
//      e. 排序：severity 主序 + 同档内干预价值次序（复用 W-19-A）
//      f. 纯函数：输入不被修改
//   3. computeChunkCoverage：精确偏移 / overlap 交集 / 定位失败防御位
//   4. buildMergePrompt：分片块头带「覆盖原文 [s, e)」
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/merge_convergence.dart';
import 'package:writingcoach/services/progressive_diagnosis.dart';
import 'package:writingcoach/types/teaching_types.dart';

Syndrome _s(
  String id,
  Severity severity,
  List<String> evidence, {
  String? value,
  String? explanation,
}) => Syndrome(
  syndromeId: id,
  name: 'n-$id',
  severity: severity,
  evidence: evidence,
  explanation: explanation ?? 'x-$id',
  interventionValue: value,
);

void main() {
  group('evidenceJaccard', () {
    test('完全重叠 = 1；部分重叠介于 0/1；空集 = 0', () {
      expect(evidenceJaccard([' abc ', 'def'], ['abc', 'DEF']), 1.0);
      final partial = evidenceJaccard(['a', 'b'], ['b', 'c']);
      expect(partial, greaterThan(0));
      expect(partial, lessThan(1));
      expect(evidenceJaccard([], ['a']), 0);
      expect(evidenceJaccard(['a'], []), 0);
    });
  });

  group('mergeOutputConvergence · 去重', () {
    test('同 id + 证据重叠 ≥ 0.5 → 合并：severity 取高、证据并集', () {
      // {aaa,bbb} vs {aaa,bbb,ccc}：交 2 / 并 3 = 0.67 ≥ 0.5
      final (:displayed, :report) = mergeOutputConvergence([
        _s('P001', Severity.l1, ['aaa', 'bbb']),
        _s('P001', Severity.l3, ['aaa', 'bbb', 'ccc']),
      ]);
      expect(report.dedupedCount, 1);
      final merged = displayed.single;
      expect(merged.severity, Severity.l3);
      expect(merged.evidence.toSet(), {'aaa', 'bbb', 'ccc'});
    });

    test('同 id + 证据不相交（Jaccard=0）→ 保留两条独立条目', () {
      final (:displayed, :report) = mergeOutputConvergence([
        _s('P001', Severity.l1, ['aaa']),
        _s('P001', Severity.l2, ['bbb']),
      ]);
      expect(report.dedupedCount, 2);
      expect(displayed.length, 2);
    });

    test('不同 id 证据再像也不合并', () {
      final result = mergeOutputConvergence([
        _s('P001', Severity.l1, ['aaa']),
        _s('P002', Severity.l1, ['aaa']),
      ]);
      expect(result.report.dedupedCount, 2);
    });

    test('证据重叠恰 = 0.5 达阈值 → 合并（边界含等号）', () {
      // {a,b,c,d} vs {a,b}：交 2 / 并 4 = 0.5（恰达阈值）
      final result = mergeOutputConvergence([
        _s('P001', Severity.l1, ['a', 'b', 'c', 'd']),
        _s('P001', Severity.l1, ['a', 'b']),
      ]);
      expect(result.report.dedupedCount, 1);
    });
  });

  group('mergeOutputConvergence · cap 与排序', () {
    test('超 5 条：展示截前 5，溢出进 report.overflow 不丢弃', () {
      final input = List.generate(
        8,
        (i) => _s('P0${i + 10}', Severity.values[i % 3], ['e-$i']),
      );
      final (:displayed, :report) = mergeOutputConvergence(input);
      expect(report.rawCount, 8);
      expect(report.dedupedCount, 8);
      expect(displayed.length, kMergeDisplayCap);
      expect(report.overflow.length, 3);
      // 溢出者 = 排序垫底者（severity 最低）
      expect(report.overflow.every((s) => s.severity == Severity.l1), isTrue);
    });

    test('溢出条目仍在返回结构中可还原全量（displayed + overflow）', () {
      final input = List.generate(
        7,
        (i) => _s('P0${i + 10}', Severity.l2, ['e-$i']),
      );
      final (:displayed, :report) = mergeOutputConvergence(input);
      final all = [...displayed, ...report.overflow];
      expect(all.map((s) => s.syndromeId).toSet().length, 7);
    });

    test('排序：severity 主序 + 同档内干预价值降序（复用 W-19-A）', () {
      final result = mergeOutputConvergence([
        _s('P001', Severity.l2, ['e1'], value: 'low'),
        _s('P002', Severity.l2, ['e2'], value: 'high'),
      ]);
      expect(result.displayed.map((s) => s.syndromeId).toList(), [
        'P002',
        'P001',
      ]);
    });

    test('纯函数：输入列表不被修改', () {
      final input = [
        _s('P001', Severity.l1, ['aaa']),
        _s('P001', Severity.l2, ['aaa']),
      ];
      mergeOutputConvergence(input);
      expect(input.length, 2);
      expect(input[0].severity, Severity.l1);
    });
  });

  group('computeChunkCoverage', () {
    test('精确偏移：单块覆盖全文', () {
      const content = '零一二三\n\n四五';
      final cov = computeChunkCoverage(content, [content]);
      expect(cov.single.start, 0);
      expect(cov.single.end, content.length);
      expect(cov.single.located, isTrue);
    });

    test('overlap：下一块起点落在上一块区间内（区间有交集）', () {
      // splitContent 用 SIZE=3000 才分块；直接喂多块文本走 compute 层
      const content = 'AAAA\n\nBBBB\n\nCCCC\n\nDDDD';
      final chunks = ['AAAA\n\nBBBB', 'BBBB\n\nCCCC', 'CCCC\n\nDDDD'];
      final cov = computeChunkCoverage(content, chunks);
      expect(cov.length, 3);
      expect(cov[0].start, 0);
      expect(cov[1].start, greaterThan(cov[0].start));
      expect(cov[1].start, lessThan(cov[0].end)); // overlap ⇒ 区间相交
      expect(cov[2].start, lessThan(cov[1].end));
      expect(cov.last.end, content.length);
    });

    test('定位失败 → located=false 防御位（不抛错）', () {
      final cov = computeChunkCoverage('abc', ['xyz']);
      expect(cov.single.located, isFalse);
      expect(cov.single.isValid, isFalse);
    });
  });

  group('buildMergePrompt 覆盖标注', () {
    test('传 chunkCoverage 时分片块头带「覆盖原文 [s, e)」', () {
      final prompt = buildMergePrompt(
        [
          ChunkAnalysisResult(
            chunkIndex: 0,
            notes: [
              const ChunkNote(
                syndromeId: 'P001',
                description: 'd',
                evidence: ['e'],
                severity: 'L1',
              ),
            ],
            success: true,
          ),
        ],
        chunkCoverage: const [ChunkCoverage(index: 0, start: 10, end: 99)],
      );
      expect(prompt, contains('## 分片 1（覆盖原文 [10, 99)）'));
    });

    test('不传时保持旧格式（向后兼容）', () {
      final prompt = buildMergePrompt(const [
        ChunkAnalysisResult(
          chunkIndex: 0,
          notes: [
            ChunkNote(
              syndromeId: 'P001',
              description: 'd',
              evidence: ['e'],
              severity: 'L1',
            ),
          ],
          success: true,
        ),
      ]);
      expect(prompt, contains('## 分片 1\n'));
      expect(prompt, isNot(contains('覆盖原文')));
    });
  });
}
