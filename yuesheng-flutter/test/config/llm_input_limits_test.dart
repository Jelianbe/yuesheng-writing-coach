// ─────────────────────────────────────────────────────────────
// llm_input_limits_test — 历史窗口「按批对齐」裁剪（A-1b 前缀稳定化）
//
// 契约：historyStartIndex 单调不减、恒为 historyTrimBatch 的倍数，
// 保留条数落在 [maxHistoryMessages, maxHistoryMessages + batch − 1]。
//
// 为什么需要这层护栏：旧实现 `sublist(total − 20)` 是**逐条滑窗**，
// 历史首条每轮前移 2 条 —— 而它是 prompt 里历史块的首字节，上下文缓存
// 是**严格前缀匹配**，于是追加式历史每轮全价 miss（实测 miss 2,195
// token/轮）。改动只是「把裁剪对齐到批边界」，没有任何可见行为断言能
// 拦住回归，故在此直接锁死纯函数契约。
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/config/shared_constants.dart';

void main() {
  const cap = LlmInputLimits.maxHistoryMessages; // 20
  const batch = LlmInputLimits.historyTrimBatch; // 10

  group('历史窗口按批对齐裁剪（A-1b）', () {
    test('未超下限 ⇒ 不裁（起点 0）', () {
      for (var n = 0; n <= cap; n++) {
        expect(LlmInputLimits.historyStartIndex(n), 0, reason: 'n=$n');
      }
    });

    test('超下限但未到批边界 ⇒ 暂不裁（窗口允许长到 cap+batch−1）', () {
      for (var n = cap + 1; n < cap + batch; n++) {
        expect(LlmInputLimits.historyStartIndex(n), 0, reason: 'n=$n');
      }
      // 恰跨批边界 ⇒ 一次前移 batch
      expect(LlmInputLimits.historyStartIndex(cap + batch), batch);
    });

    test('起点恒为 batch 倍数；保留条数有界（≤ cap+batch−1）', () {
      for (var n = 0; n <= 500; n++) {
        final from = LlmInputLimits.historyStartIndex(n);
        expect(from % batch, 0, reason: 'n=$n from=$from 未对齐批边界');
        expect(from, lessThanOrEqualTo(n), reason: 'n=$n 起点越界');
        final kept = n - from;
        // 不足下限时全量上送；越过下限后至少保留 cap 条
        expect(
          kept,
          greaterThanOrEqualTo(n < cap ? n : cap),
          reason: 'n=$n kept=$kept',
        );
        expect(kept, lessThan(cap + batch), reason: 'n=$n kept=$kept');
      }
    });

    test('单调不减（头部只前移、永不回退 ⇒ 前缀关系可传递）', () {
      var prev = 0;
      for (var n = 0; n <= 500; n++) {
        final from = LlmInputLimits.historyStartIndex(n);
        expect(from, greaterThanOrEqualTo(prev), reason: 'n=$n');
        prev = from;
      }
    });

    test('★ 核心：每轮 +2 条时，头部仅少数轮次移动', () {
      var moves = 0;
      var rounds = 0;
      var prevFrom = LlmInputLimits.historyStartIndex(0);
      for (var n = 2; n <= 400; n += 2) {
        final from = LlmInputLimits.historyStartIndex(n);
        rounds++;
        if (from != prevFrom) moves++;
        prevFrom = from;
      }
      // batch/2 = 每 5 轮才动一次 ⇒ 移动轮次占比应 ≈ 0.2
      expect(
        moves / rounds,
        lessThan(0.25),
        reason: '头部移动 $moves / $rounds 轮 —— 已退化成逐条滑窗',
      );
    });

    test('回归护栏：超下限后不再逐条前移（旧实现必挂）', () {
      // 旧实现 from = n − cap ⇒ 60→40、62→42、64→44（逐轮 +2，首条每轮前移）
      // 新实现：60/62/64 落在同一批区间 ⇒ 恒为 40（头部不动 ⇒ 前缀可复用）
      expect(LlmInputLimits.historyStartIndex(60), 40);
      expect(LlmInputLimits.historyStartIndex(62), 40);
      expect(LlmInputLimits.historyStartIndex(64), 40);
      expect(
        LlmInputLimits.historyStartIndex(62),
        isNot(62 - LlmInputLimits.maxHistoryMessages),
        reason: '仍是逐条滑窗口径（旧实现此处给出 42）',
      );
    });

    test('窗口末条恒为最新消息（当前 user 消息必被保留）', () {
      for (final n in [1, 21, 30, 37, 60, 137, 299]) {
        final from = LlmInputLimits.historyStartIndex(n);
        expect(n - 1, greaterThanOrEqualTo(from), reason: 'n=$n 的末条落在窗口外');
      }
    });
  });
}
