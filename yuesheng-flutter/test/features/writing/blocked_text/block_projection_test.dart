// ─────────────────────────────────────────────────────────────
// block_projection 测试 — ADR-0002 阶段0 块投影纯逻辑
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/features/writing/blocked_text/block_projection.dart';

void main() {
  group('split ↔ join 可逆', () {
    test('普通多段切块', () {
      final p = BlockProjection.fromText('第一段。\n第二段。\n第三段。');
      expect(p.blocks, ['第一段。', '第二段。', '第三段。']);
      expect(p.join(), '第一段。\n第二段。\n第三段。');
    });

    test('空文本 → 一个空块，join 回空串', () {
      final p = BlockProjection.fromText('');
      expect(p.blocks, ['']);
      expect(p.join(), '');
      expect(p.totalLength, 0);
    });

    test('尾部换行 → 末尾空块，join 原样还原', () {
      final p = BlockProjection.fromText('第一段。\n');
      expect(p.blocks, ['第一段。', '']);
      expect(p.join(), '第一段。\n');
    });

    test('开头换行 → 首块为空', () {
      final p = BlockProjection.fromText('\n第二段。');
      expect(p.blocks, ['', '第二段。']);
      expect(p.join(), '\n第二段。');
    });

    test('段间空行（连续 \\n）→ 中间空块', () {
      final p = BlockProjection.fromText('第一段。\n\n第二段。');
      expect(p.blocks, ['第一段。', '', '第二段。']);
      expect(p.join(), '第一段。\n\n第二段。');
    });

    test('全角首行缩进前缀原样保留在块内', () {
      final p = BlockProjection.fromText('\u3000\u3000第一段。\n\u3000\u3000第二段。');
      expect(p.blocks[0], '\u3000\u3000第一段。');
      expect(p.blocks[1], '\u3000\u3000第二段。');
      expect(p.join(), '\u3000\u3000第一段。\n\u3000\u3000第二段。');
    });
  });

  group('cumulativeOffsets 偏移表', () {
    test('普通段落偏移正确', () {
      final p = BlockProjection.fromText('一\n二二');
      expect(p.cumulativeOffsets, [0, 2]);
      expect(p.blocks[1], p.join().substring(2, 4));
    });

    test('含空块时段间空行偏移正确', () {
      final p = BlockProjection.fromText('a\n\nb');
      expect(p.cumulativeOffsets, [0, 2, 3]);
      expect(p.blocks[1], '');
      expect(p.blocks[2], 'b');
    });

    test('空文本偏移表只有 0', () {
      final p = BlockProjection.fromText('');
      expect(p.cumulativeOffsets, [0]);
    });
  });

  group('locate 光标绝对偏移 → 块定位', () {
    final p = BlockProjection.fromText('一\n二二'); // 长度4，块: ['一','二二']

    test('块首 / 块内 / 整串末尾', () {
      expect(p.locate(0), const BlockLocation(blockIndex: 0, localOffset: 0));
      expect(p.locate(1), const BlockLocation(blockIndex: 0, localOffset: 1));
      expect(p.locate(4), const BlockLocation(blockIndex: 1, localOffset: 2));
    });

    test('落在块间 \\n 上归到下一块块首', () {
      expect(p.locate(2), const BlockLocation(blockIndex: 1, localOffset: 0));
    });

    test('含空块时定位到空块', () {
      final p2 = BlockProjection.fromText('a\n\nb'); // ['a','','b']
      expect(p2.locate(2), const BlockLocation(blockIndex: 1, localOffset: 0));
      expect(p2.locate(3), const BlockLocation(blockIndex: 2, localOffset: 0));
    });

    test('越界偏移钳制到两端', () {
      expect(p.locate(-5), const BlockLocation(blockIndex: 0, localOffset: 0));
      expect(p.locate(999), const BlockLocation(blockIndex: 1, localOffset: 2));
    });

    test('逆映射 round-trip：locate(caretAbsoluteOffset(i,local)) 自洽', () {
      final probes = [(0, 0), (0, 1), (1, 0), (1, 2)];
      for (final (i, local) in probes) {
        final abs = p.caretAbsoluteOffset(i, local);
        expect(
          p.locate(abs),
          BlockLocation(blockIndex: i, localOffset: local),
          reason: 'abs=$abs (block $i local $local)',
        );
      }
    });
  });
}
