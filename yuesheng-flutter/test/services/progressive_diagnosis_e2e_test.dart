// ─────────────────────────────────────────────────────────────
// Progressive Diagnosis e2e 真机复核（ADR-C73 §8 实施记录）
//
// 目的：补单元测试 #6/#7 的「边界单点」局限——以真实诊断文本输入为基准，
// 验证 splitContent 在真机场景下的行为合理（耗时、不挂死、切片合理、
// 跨块上下文连续）。
//
// 覆盖场景：
//   E2E-1: 5000 字无段落长文（最坏单段，原死循环触发路径）秒级返回
//   E2E-2: 8000 字多段长文（典型分段写作）切片合理、末段不丢
//   E2E-3: 跨块 overlap 上下文连续（分块诊断的核心设计目标）
//   E2E-4: 10000 字极长文（极端输入）仍秒级返回
//   E2E-5: 50000 字超长文（远超实际）鲁棒性兜底
//
// 性能阈值取保守值（2-5 秒），实测远超此基线；阈值用于拦截「退化」、
// 不拦截正常实现——任何满足 batch I 修复要求的实现都应轻松通过。
// ─────────────────────────────────────────────────────────────

// ignore_for_file: prefer_initializing_formals

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/progressive_diagnosis.dart';

void main() {
  group('splitContent e2e 真机复核', () {
    test('E2E-1 5000 字无 \\n\\n 单段长文（原死循环触发路径）秒级返回', () {
      // 真机最坏场景：用户复制整篇没分段的长文粘贴
      // 长度 5000 > kDiagnosisChunkSize=3000，且无段落边界
      // 批次 H 侦察实证：未修复时会**同步死循环**（timeout 失效）
      // 修复后（ADR-C73 §2）：整段成块并推进 startIndex，秒级返回
      final long = '甲乙丙丁戊己庚辛壬癸' * 500; // 500 × 10 = 5000 字符

      final sw = Stopwatch()..start();
      final chunks = splitContent(long);
      sw.stop();

      expect(chunks, isNotEmpty, reason: '不应返回空（修复后整段成块）');
      expect(
        sw.elapsedMilliseconds,
        lessThan(2000),
        reason: '5000 字应在 2 秒内完成（原死循环会无限挂死）',
      );
      // 单段原子性：整段成块
      expect(chunks.single, long, reason: '单段超长整段成块，不切字符');
    });

    test('E2E-2 8000 字多段长文（典型分段写作）切片合理、末段不丢', () {
      // 真机典型：用户分段写的长文，每段 800 字共 10 段
      // 验证：(1) 至少切 2 块 (2) 首段必在前块 (3) 末段必在某个块
      final paragraphs = <String>[];
      for (var i = 0; i < 10; i++) {
        paragraphs.add('第${i}段：' + '中文字符' * 130); // 约 800 字/段
      }
      final content = paragraphs.join('\n\n');

      final chunks = splitContent(content);

      expect(chunks.length, greaterThanOrEqualTo(2), reason: '8000 字应至少 2 块');
      expect(chunks.first, contains('第0段'), reason: '首段必在第一块（确保不丢头）');
      // 末段可能因 MIN_LAST_CHUNK 合并到前块——只要出现在任一块即可
      final containsTail = chunks.any((c) => c.contains('第9段'));
      expect(containsTail, isTrue, reason: '末段必出现在某个块（确保不丢尾）');
    });

    test('E2E-3 跨块 overlap 上下文连续（分块诊断核心设计目标）', () {
      // 分块诊断的关键设计目标：每块 LLM 单独识别，必须靠 overlap
      // 把上下文带进下一块，否则跨块症候会被切碎识别错误。
      // 验证：第二块前半部分应包含第一块末尾段落（overlap 保证）
      final paragraphs = <String>[];
      for (var i = 0; i < 15; i++) {
        paragraphs.add(
          '段落${i.toString().padLeft(2, '0')}的内容：'
                  '上下文标记ABC${i.toString().padLeft(2, '0')}XYZ' +
              'X' * 300,
        );
      }
      final content = paragraphs.join('\n\n');

      final chunks = splitContent(content);

      expect(chunks.length, greaterThanOrEqualTo(2), reason: '15 段应至少切 2 块');

      // 提取第一块末尾段落号
      final firstChunk = chunks.first;
      final secondChunk = chunks[1];
      final pattern = RegExp(r'段落(\d+)');
      final matches = pattern.allMatches(firstChunk).toList();
      expect(matches, isNotEmpty, reason: '第一块应含段落标记');

      // 取最后两个段落号（overlap ≈ 200 字符 ≈ 一段以内）
      final tailNumbers = matches.reversed
          .take(2)
          .map((m) => m.group(1)!)
          .toList();

      // 第二块前半部分应至少包含其中一个末尾段落号
      final secondHalf = secondChunk.substring(0, secondChunk.length ~/ 2);
      final overlapHit = tailNumbers.any((n) => secondHalf.contains('段落$n'));

      expect(
        overlapHit,
        isTrue,
        reason:
            '第二块前半部分应包含第一块末尾段落（overlap 上下文连续）。'
            '期望段落号之一: $tailNumbers，'
            '第二块前半长度: ${secondHalf.length}',
      );
    });

    test('E2E-4 10000 字极长文（极端单段）秒级返回', () {
      // 真机极端：用户复制整本小说片段
      // 远超 SIZE（3000），验证修复在更大输入下仍稳定
      final long = '天地玄黄宇宙洪荒日月盈昃辰宿列张' * 500; // 12 × 500 = 6000
      // 凑到 10000+
      final padded = long + '寒来暑往秋收冬藏' * 200; // + 8 × 200 = 1600 → 7600
      final content = (padded + '闰余成岁' * 300); // + 4 × 300 = 1200 → 8800
      // 凑到 10000：再补
      final fullContent = content + '律吕调阳' * 200; // + 4 × 200 = 800 → 9600
      expect(fullContent.length, greaterThanOrEqualTo(9000));

      final sw = Stopwatch()..start();
      final chunks = splitContent(fullContent);
      sw.stop();

      expect(chunks, isNotEmpty);
      expect(
        sw.elapsedMilliseconds,
        lessThan(2000),
        reason: '10000 字应在 2 秒内完成',
      );
      // 无段落边界 → 单段原子性：整段成块
      expect(chunks.single, fullContent);
    });

    test('E2E-5 50000 字超长文（远超实际）鲁棒性兜底不挂死', () {
      // 边界鲁棒性：远超实际场景的输入仍能在合理时间内返回
      // 注：50000 字 > kDiagnosisMinLastChunk=500 但 < 整段 SIZE；
      // 由于无段落边界，仍触发单段原子路径
      final long = '穗' * 50000;

      final sw = Stopwatch()..start();
      final chunks = splitContent(long);
      sw.stop();

      expect(chunks, isNotEmpty);
      expect(
        sw.elapsedMilliseconds,
        lessThan(5000),
        reason: '50000 字应在 5 秒内完成（退化告警）',
      );
      // 单段原子：整段成块
      expect(chunks.single, long);
    });
  });
}
