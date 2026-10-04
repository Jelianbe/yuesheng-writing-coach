// ─────────────────────────────────────────────────────────────
// block_projection — 分页编辑器块投影（ADR-0002 阶段0）
//
// 整章扁平字符串是唯一真源（drift/autosave/undo快照/一键排版等通路照旧），
// BlockProjection 只是它「按 '\n' 切块」的纯逻辑投影：
//   - blocks            split('\n') 的结果，空块=空行/段间空行
//   - join()            块间以 '\n' 拼回整串，与 split 互逆
//   - cumulativeOffsets  每块首字符在整串中的偏移（定位/选区换算用）
//   - locate()          光标整串绝对偏移 → 块号 + 块内偏移
//
// 纯逻辑类，不 import Flutter widget；可独立单测。
// ─────────────────────────────────────────────────────────────

/// 光标定位结果：落在第 [blockIndex] 块，块内偏移 [localOffset]。
class BlockLocation {
  const BlockLocation({required this.blockIndex, required this.localOffset});

  final int blockIndex;
  final int localOffset;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BlockLocation &&
          other.blockIndex == blockIndex &&
          other.localOffset == localOffset;

  @override
  int get hashCode => Object.hash(blockIndex, localOffset);

  @override
  String toString() => 'BlockLocation(block: $blockIndex, local: $localOffset)';
}

/// 整章文本的块投影。构造后不可变；文本变化 = 用新文本再构造一个投影。
class BlockProjection {
  factory BlockProjection.fromText(String text) {
    final blocks = List<String>.unmodifiable(text.split('\n'));
    final offsets = List<int>.filled(blocks.length, 0);
    for (var i = 1; i < blocks.length; i++) {
      offsets[i] = offsets[i - 1] + blocks[i - 1].length + 1; // +1 = '\n'
    }
    return BlockProjection._(blocks, List<int>.unmodifiable(offsets));
  }

  const BlockProjection._(this.blocks, this.cumulativeOffsets);

  /// 每块文本（空串 = 空行/段间空行）。只读。
  final List<String> blocks;

  /// 每块首字符在整串中的偏移；cumulativeOffsets[0] 恒为 0。
  final List<int> cumulativeOffsets;

  /// 拼回整串真源（join('\n')，与 split 互逆）。
  String join() => blocks.join('\n');

  /// 整串总长度（含块间 '\n'）。
  int get totalLength => join().length;

  /// 块首在整串中的偏移。
  int blockStartOffset(int blockIndex) => cumulativeOffsets[blockIndex];

  /// 把整串光标绝对偏移折成「块号 + 块内偏移」。
  ///
  /// 越界输入先钳制到 [0, totalLength]；偏移恰好落在块间 '\n' 上时
  /// 归到下一块的块首（程序化定位的边界态，点击落点不会产生该态）。
  BlockLocation locate(int absoluteOffset) {
    var offset = absoluteOffset;
    final total = totalLength;
    if (offset < 0) offset = 0;
    if (offset > total) offset = total;
    var lo = 0;
    var hi = cumulativeOffsets.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) ~/ 2;
      if (cumulativeOffsets[mid] <= offset) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return BlockLocation(
      blockIndex: lo,
      localOffset: offset - cumulativeOffsets[lo],
    );
  }

  /// 逆映射：某块内 [localOffset] 光标位置 → 整串绝对偏移。
  int caretAbsoluteOffset(int blockIndex, int localOffset) =>
      cumulativeOffsets[blockIndex] + localOffset;
}
