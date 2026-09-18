// ─────────────────────────────────────────────────────────────
// version_retention_test — 章节版本快照保留策略纯函数单测（无需 DB）
//
// 覆盖：
//   1. 空列表 / 单条
//   2. 保底下限：同秒 60 条 → 恰保留 kRecentKeepFloor 条（最新在前）
//   3. 分桶：24h / 7d / 30d / >30d 各档桶内只留最新 1 条
//   4. 条数上限（kMaxChapterVersions）
//   5. 体积上限：丢最旧直到达标，且至少保留 1 条
//   6. 单条即超预算 → 仍保留 1 条（最新永不淘汰）
//   7. 乱序输入 → 输出恒为新→旧
//   8. chapterVersionBytes 按 UTF-8 真实字节数
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/data/repositories/version_retention.dart';

void main() {
  const int t = 1700000000;
  const int hour = 3600;
  const int day = 86400;
  const int week = 7 * day;
  const int month = 30 * day;

  group('retainVersions 基本形态', () {
    test('空列表 → 空', () {
      final kept = retainVersions<int>(
        <int>[],
        savedAtOf: (v) => v,
        bytesOf: (_) => 1,
        nowSec: t,
      );
      expect(kept, isEmpty);
    });

    test('单条 → 保留', () {
      final kept = retainVersions<int>(
        <int>[t - day * 90],
        savedAtOf: (v) => v,
        bytesOf: (_) => 1,
        nowSec: t,
      );
      expect(kept, <int>[t - day * 90]);
    });
  });

  group('保底下限（★有意收窄①）', () {
    test('同秒 60 条 → 恰保留 kRecentKeepFloor 条，且最新在前', () {
      // 元素为「下标」，下标 0 即最新（与仓库内「新→旧」存序一致）；
      // savedAtOf 恒等返回同一秒 ⇒ 60 条全落在同一小时桶。
      final sixty = List<int>.generate(60, (i) => i);
      final kept = retainVersions<int>(
        sixty,
        savedAtOf: (_) => t,
        bytesOf: (_) => 1,
        nowSec: t,
      );
      expect(kept.length, kRecentKeepFloor);
      expect(kept, <int>[for (var i = 0; i < kRecentKeepFloor; i++) i]);
    });

    test('单次写作（≤kRecentKeepFloor 条，同一小时桶）零退化', () {
      final eight = List<int>.generate(8, (i) => t - i);
      final kept = retainVersions<int>(
        eight,
        savedAtOf: (v) => v,
        bytesOf: (_) => 1,
        nowSec: t,
      );
      expect(kept.length, 8);
    });
  });

  group('时间分桶', () {
    test('24h / 7d / 30d / >30d 各档桶内只留最新 1 条', () {
      final items = <int>[
        t, // h0
        t - hour * 5, // h5
        t - hour * 5 - 60, // 仍 h5 ⇒ 应被丢
        t - day * 3, // d3
        t - day * 3 - 60, // 仍 d3 ⇒ 应被丢
        t - week * 2, // w2
        t - week * 2 - 60, // 仍 w2 ⇒ 应被丢
        t - month * 3, // m3
        t - month * 3 - 60, // 仍 m3 ⇒ 应被丢
      ];
      final kept = retainVersions<int>(
        items,
        savedAtOf: (v) => v,
        bytesOf: (_) => 1,
        nowSec: t,
        recentFloor: 1,
        maxCount: 100,
      );
      expect(kept, <int>[
        t,
        t - hour * 5,
        t - day * 3,
        t - week * 2,
        t - month * 3,
      ]);
    });

    test('versionBucketOf：四档边界与负 age 钳零', () {
      expect(versionBucketOf(t, t), 'h0');
      expect(versionBucketOf(t - hour * 5, t), 'h5');
      expect(versionBucketOf(t - day * 3, t), 'd3');
      expect(versionBucketOf(t - week * 2, t), 'w2');
      expect(versionBucketOf(t - month * 3, t), 'm3');
      expect(versionBucketOf(t + 60, t), 'h0', reason: 'age<0（时钟回拨）钳到 0');
    });
  });

  group('硬上限', () {
    test('条数上限：超过 kMaxChapterVersions 时截取最新的 N 条', () {
      // 60 条各占一个不同月桶 ⇒ 分桶阶段全留，只能靠条数上限截断
      final items = <int>[for (var i = 0; i < 60; i++) t - month * (i + 2)];
      final kept = retainVersions<int>(
        items,
        savedAtOf: (v) => v,
        bytesOf: (_) => 1,
        nowSec: t,
        recentFloor: 1,
      );
      expect(kept.length, kMaxChapterVersions);
      expect(kept.first, items.first);
      expect(kept.last, items[kMaxChapterVersions - 1]);
    });

    test('体积上限：从最旧开始丢直到达标，且至少保留 1 条', () {
      final items = <int>[for (var i = 0; i < 5; i++) t - day * i];
      final kept = retainVersions<int>(
        items,
        savedAtOf: (v) => v,
        bytesOf: (_) => 10, // 每条 10 字节
        nowSec: t,
        maxBytes: 25, // 只容得下 2 条
        recentFloor: 1,
        maxCount: 100,
      );
      expect(kept, <int>[t, t - day]);
    });

    test('单条即超预算 → 仍保留 1 条（最新永不淘汰）', () {
      final kept = retainVersions<int>(
        <int>[t, t - 100],
        savedAtOf: (v) => v,
        bytesOf: (_) => 1000,
        nowSec: t,
        maxBytes: 5,
        recentFloor: 1,
        maxCount: 100,
      );
      expect(kept, <int>[t]);
    });
  });

  group('确定性排序（★有意收窄②）', () {
    test('乱序输入 → 输出恒为新→旧', () {
      final shuffled = <int>[
        t - day * 3,
        t,
        t - day,
        t - day * 20,
        t - day * 2,
      ];
      final kept = retainVersions<int>(
        shuffled,
        savedAtOf: (v) => v,
        bytesOf: (_) => 1,
        nowSec: t,
        recentFloor: 1,
        maxCount: 100,
      );
      expect(kept, <int>[t, t - day, t - day * 2, t - day * 3, t - day * 20]);
    });

    test('同秒多条按原下标升序（不依赖 List.sort 稳定性）', () {
      // 元素即下标，savedAt 全同 ⇒ 只能靠原下标定序
      final same = <int>[7, 3, 9, 0, 5];
      final kept = retainVersions<int>(
        same,
        savedAtOf: (_) => t,
        bytesOf: (_) => 1,
        nowSec: t,
      );
      expect(kept, <int>[7, 3, 9, 0, 5], reason: '同秒时必须保持输入原序');
    });
  });

  group('chapterVersionBytes', () {
    test('按 UTF-8 真实字节数（汉字 3 字节）', () {
      expect(chapterVersionBytes('字'), 3);
      expect(chapterVersionBytes('abc'), 3);
      expect(chapterVersionBytes('字a'), 4);
      expect(chapterVersionBytes(''), 0);
    });
  });
}
