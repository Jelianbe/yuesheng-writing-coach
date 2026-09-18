// ─────────────────────────────────────────────────────────────
// version_retention_test — 章节版本快照保留策略纯函数单测（无需 DB）
//
// 覆盖：
//   1. 空列表 / 单条
//   2. 保底（**优先**，非无条件）：同秒 60 条 → 恰保留 10 条（字面量断言，最新在前）
//   3. 分桶：24h / 7d / 30d / >30d 各档桶内只留最新 1 条
//   4. versionBucketOf 四档**边界逐点**（含等号边界，11 个 age 取值）
//   5. 条数上限 40（字面量断言）
//   6. 体积上限：丢最旧直到达标，且至少保留 1 条
//   7. 单条即超预算 → 仍保留 1 条（最新永不淘汰）
//   8. 保底 × 体积硬顶：保留数可被压到保底以下（把「优先」变成可执行判据）
//   9. 乱序输入 → 输出恒为新→旧；同秒 70 条按下标定序（回归绊线）
//  10. chapterVersionBytes 按 UTF-8 真实字节数
//  11. 常量契约（漂移绊线）
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
    test('同秒 60 条 → 恰保留 10 条（字面量），且最新在前', () {
      // 元素为「下标」，下标 0 即最新（与仓库内「新→旧」存序一致）；
      // savedAtOf 恒等返回同一秒 ⇒ 60 条全落在同一小时桶。
      final sixty = List<int>.generate(60, (i) => i);
      final kept = retainVersions<int>(
        sixty,
        savedAtOf: (_) => t,
        bytesOf: (_) => 1,
        nowSec: t,
      );
      // 期望用**字面量**而非 kRecentKeepFloor 自指：常量被改成 41 也必须在这里变红。
      expect(kept.length, 10);
      expect(kept, <int>[0, 1, 2, 3, 4, 5, 6, 7, 8, 9]);
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

    test('versionBucketOf：四档边界逐点（边界含等号）', () {
      String at(int age) => versionBucketOf(t - age, t);
      expect(at(0), 'h0');
      expect(at(86399), 'h23');
      expect(at(86400), 'h24', reason: '24h 边界含等号 ⇒ 仍落 h 桶');
      expect(at(86401), 'd1');
      expect(at(604799), 'd6');
      expect(at(604800), 'd7', reason: '7d 边界含等号 ⇒ 仍落 d 桶');
      expect(at(604801), 'w1');
      expect(at(2591999), 'w4');
      expect(at(2592000), 'w4', reason: '30d 边界含等号 ⇒ 仍落 w 桶');
      // ⚠️ 规格草案此处写 'm0'，按实现实为 'm1'：首个 m 桶 = age ∈ (30d, 60d]，
      //    'm0' 不可达（w 桶在含等号边界处已吃掉 age = 2592000）。按实现落笔，未改实现。
      expect(at(2592001), 'm1');
      expect(versionBucketOf(t + 1, t), 'h0', reason: '负 age（时钟回拨）钳到 0');
    });
  });

  group('硬上限', () {
    test('条数上限 40（字面量）：超过则截取最新的 40 条', () {
      // 60 条各占一个不同月桶 ⇒ 分桶阶段全留，只能靠条数上限截断
      final items = <int>[for (var i = 0; i < 60; i++) t - month * (i + 2)];
      final kept = retainVersions<int>(
        items,
        savedAtOf: (v) => v,
        bytesOf: (_) => 1,
        nowSec: t,
        recentFloor: 1,
      );
      // 期望用**字面量**而非常量自指：上限被改成 39/41 必须在这里变红。
      expect(kept.length, 40);
      expect(kept.first, items.first);
      expect(kept.last, items[39]);
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

    test('保底 × 体积硬顶：12 条各 60KB（合计 720KB）⇒ 保留数 < 保底且 ≥ 1', () {
      const int kb60 = 60 * 1024;
      // 12 条全部落在同一小时桶 ⇒ 分桶阶段按保底给出 10 条，而 10×60KB=600KB 仍超顶
      final items = <int>[for (var i = 0; i < 12; i++) t - i * 10];
      final kept = retainVersions<int>(
        items,
        savedAtOf: (v) => v,
        bytesOf: (_) => kb60,
        nowSec: t,
      );
      // 这条把「保底是『优先』而非『无条件』」变成**可执行判据**，
      // 否则下一轮又会有人把文件头的措辞读回「无条件」。
      expect(kept.length, lessThan(kRecentKeepFloor));
      expect(kept.length, greaterThanOrEqualTo(1));
      expect(kept.first, items.first, reason: '最新那条永不淘汰');
      expect(
        kept.length,
        8,
        reason: '8×60KB=480KB ≤ 512KB；9×60KB=540KB > 512KB',
      );
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

    test('同秒多条按原下标升序（70 条 > 插入排序阈值 32；回归绊线）', () {
      // 70 个同秒元素，跨入 Dart 的 dual-pivot quicksort 区间（插入排序阈值 32）：
      // 实现若漏掉「同秒按下标定序」，相同键之间的相对顺序不再有保证 ⇒ 本用例变红。
      // 输入刻意取倒序，任何非输入序的输出都会被逐元素比对抓住。
      //
      // ⚠️ 鉴别力边界（如实写明）：这是**回归绊线**，不是「Dart sort 不稳定」的证明 ——
      //    若某 SDK 版本的排序实现对全同键恰好保持原序，本用例恒绿；
      //    真正保证正确性的是 `_sortNewestFirst` 里的显式 `a.compareTo(b)` 定序。
      final same = <int>[for (var i = 0; i < 70; i++) 69 - i];
      final kept = retainVersions<int>(
        same,
        savedAtOf: (_) => t,
        bytesOf: (_) => 1,
        nowSec: t,
        recentFloor: 100, // 放开保底，避免分桶/条数上限先把列表截短
        maxCount: 200,
      );
      expect(kept, same, reason: '同秒多条必须逐元素保持输入原序');
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

  group('常量契约（漂移绊线）', () {
    test('保留策略三常量与设计稿一致', () {
      // 漂移绊线：改值必须**显式**改这里 —— 逼改动人回看设计稿
      // （.ai/reports/2026-09-18-N3-版本时间机器-设计.md §6.1.4）
      // 与 UI 文案（lib/widgets/version_time_machine_sheet.dart 的措辞依赖这套参数）。
      // 另：`AppStateRepository.maxChapterVersions` 别名是否与叶子**脱钩**，由
      // `chapter_version_guard_test.dart#5` 守 —— 本文件刻意不 import 仓库，
      // 以保持「纯函数单测（无需 DB）」这一属性。
      expect(kMaxChapterVersions, 40);
      expect(kMaxChapterVersionBytes, 512 * 1024);
      expect(kRecentKeepFloor, 10);
    });
  });
}
