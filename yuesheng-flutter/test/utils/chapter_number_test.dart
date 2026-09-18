// ─────────────────────────────────────────────────────────────
// chapter_number_test — 章号口径纯函数（ADR-C95 · 批次 N12-F1 / N12-F3a）
//
// 本文件是 ADR-C95 §7 验收判据 1–3 的**直接**实现：
//   1. 正例：`sortOrder = 0` ⇒ 「第1章」（原缺陷：渲染成「第0章」）
//   2. 反例：**杀死 `sortOrder + 1` 兜底** —— 删过首章的稿里两者不相等
//   3. 反例：**杀死「非 null 即渲染」** —— 引用已删章 ⇒ 返回 null（调用方隐藏）
//
// `N12-F3a` 追加：`sortOrderAtPosition`（**写侧**归一 —— 用户能填的只有序位，库里存的是身份）。
//   反例 1：杀死「序位 == sortOrder」的朴素假设（删过首章的稿）；越界 ⇒ null，**禁**兜底成 0/+1。
//
// `N12-F3b` 追加：`chapterEncodings` / `resolveByEncoding` / `resolveChapterIdentity`
//   （`ADR-C96 §2` 的**身份解析**）与 `chapterAt`。本节是 `ADR-C96 §5` 判据 1–4 的直接实现，
//   两条反例分别杀死被否方案 **R4**（身份恒 = 当前章）与 **R5**（解析失败落 NULL）。
//
// `N12-F3c` 追加：`identityForUserPosition`（**用户手填序位** → 身份，写侧唯一入口）。
//   反例杀死「顺手复用 `resolveChapterIdentity`」—— 那会先按**标称号**试一遍而错锚。
//
// 口径与理由见 `docs/ADR-C95-chapter-number-convention.md` / `ADR-C96-fact-chapter-identity.md`；
// 实现 `lib/utils/chapter_number.dart`。
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/utils/chapter_number.dart';

/// 构造一个只关心 `sortOrder` 的章节（其余字段与解析无关）。
Chapter chapter(int sortOrder) => Chapter(
  id: 'ch-$sortOrder',
  manuscriptId: 'ms-c95',
  title: '第${sortOrder + 1}章',
  content: '',
  wordCount: 0,
  sortOrder: sortOrder,
  status: 'draft',
  createdAt: 0,
  updatedAt: 0,
);

/// 带**自定义标题**的章节 —— 标称号与序位刻意错位时用（`N12-F3b`）。
Chapter titled(int sortOrder, String title) => Chapter(
  id: 'ch-$sortOrder',
  manuscriptId: 'ms-c96',
  title: title,
  content: '',
  wordCount: 0,
  sortOrder: sortOrder,
  status: 'draft',
  createdAt: 0,
  updatedAt: 0,
);

void main() {
  group('buildChapterNoMap：sortOrder → 展示章号(1 基)', () {
    test('#C95-1 从 0 起的连续章 ⇒ 1,2,3（正例：首章是「第1章」不是「第0章」', () {
      final map = buildChapterNoMap([chapter(0), chapter(1), chapter(2)]);

      expect(map[0], 1, reason: '0 基首章的展示号必须是 1');
      expect(map[1], 2);
      expect(map[2], 3);
    });

    test('#C95-2 删过首章的稿（sortOrder 从 1 起）⇒ 1,2 —— 而非 2,3', () {
      // 这是 ADR-C95 §3 反例 1 的复现：删除不重编号。
      final map = buildChapterNoMap([chapter(1), chapter(2)]);

      expect(
        map[1],
        1,
        reason:
            '0 号章已删 ⇒ sortOrder=1 的章现在就是第 1 章；'
            '`sortOrder + 1` 会给出 2，是错的',
      );
      expect(map[2], 2, reason: '`sortOrder + 1` 会给出 3，是错的');
    });

    test('#C95-3 不连续的 sortOrder ⇒ 序位连续（身份值不参与展示号）', () {
      final map = buildChapterNoMap([chapter(0), chapter(5), chapter(9)]);

      expect(map[0], 1);
      expect(map[5], 2, reason: '展示号是序位，不是 sortOrder 的值');
      expect(map[9], 3);
    });

    test('#C95-4 空列表 ⇒ 空映射（不抛）', () {
      expect(buildChapterNoMap(const []), isEmpty);
    });
  });

  group('displayChapterNo / chapterLabel：解析失败必须返回 null', () {
    final map = buildChapterNoMap([chapter(0), chapter(1)]);

    test('#C95-5 命中 ⇒ 返回展示号与文案（正例）', () {
      expect(displayChapterNo(map, 1), 2);
      expect(chapterLabel(map, 1), '第2章');
    });

    test('#C95-6 引用已删章（sortOrder 不在列表中）⇒ null（负例：不编造数字）', () {
      // 这是 ADR-C95 §7 判据 3 的复现：原实现只判 `!= null` 就渲染。
      expect(displayChapterNo(map, 7), isNull);
      expect(chapterLabel(map, 7), isNull);
    });

    test('#C95-7 sortOrder 为 null ⇒ null（负例）', () {
      expect(displayChapterNo(map, null), isNull);
      expect(chapterLabel(map, null), isNull);
    });

    test('#C95-8 空映射 ⇒ 一律 null（负例）', () {
      expect(chapterLabel(const {}, 0), isNull);
    });
  });

  group('sortOrderAtPosition：序位(1 基) → sortOrder（写侧归一，N12-F3a）', () {
    test('#C95-9 正例：序位 → 该位置的 sortOrder，且与正向**互逆**', () {
      final map = buildChapterNoMap([chapter(0), chapter(5), chapter(9)]);

      expect(sortOrderAtPosition(map, 1), 0);
      expect(sortOrderAtPosition(map, 2), 5, reason: '序位 2 的章 sortOrder 是 5');
      expect(sortOrderAtPosition(map, 3), 9);
      // 互逆：正向(反向(p)) == p —— 正反两条路不可能分叉
      for (var p = 1; p <= 3; p++) {
        expect(displayChapterNo(map, sortOrderAtPosition(map, p)), p);
      }
    });

    test('#C95-10 负例：序位 <1 / 越界 / 空映射 ⇒ null（**禁**兜底成 0 或 `+1`）', () {
      final map = buildChapterNoMap([chapter(0), chapter(1)]);

      expect(sortOrderAtPosition(map, 0), isNull, reason: '序位从 1 起');
      expect(sortOrderAtPosition(map, -1), isNull);
      expect(sortOrderAtPosition(map, 3), isNull, reason: '只有 2 章');
      expect(sortOrderAtPosition(const {}, 1), isNull);
    });

    test('#C95-11 反例：删过首章的稿 —— 序位 1 是 sortOrder=1，**不是** 0', () {
      // 杀死「序位即 sortOrder」的朴素假设（ADR-C95 §3 反例 1：删除不重编号）。
      final map = buildChapterNoMap([chapter(1), chapter(2)]);

      expect(sortOrderAtPosition(map, 1), 1);
      expect(sortOrderAtPosition(map, 2), 2);
    });

    test('#C95-12 同序重复：与正向去重规则一致 —— 不可达序位返回 null', () {
      // 正向 putIfAbsent 取首次出现的序位 ⇒ 0→1、重复的 0 跳过、1→3
      final map = buildChapterNoMap([chapter(0), chapter(0), chapter(1)]);

      expect(map[0], 1);
      expect(map[1], 3);
      expect(
        sortOrderAtPosition(map, 2),
        isNull,
        reason: '序位 2 在去重后的映射里不存在 ⇒ 不得反查出某个章',
      );
      expect(sortOrderAtPosition(map, 1), 0);
      expect(sortOrderAtPosition(map, 3), 1);
    });
  });

  // ─────────────────────────────────────────────────────────────
  // `N12-F3c`：`identityForUserPosition` —— **用户手填序位** → 身份。
  //
  // 与 `sortOrderAtPosition` 的关系是「薄封装」（后者收 map、前者收列表），
  // 但**契约不同**，故单独成组：本函数是**写入侧的唯一入口**，
  // 其行为决定了 `world_fact.first_seen_chapter` / 断言 `chapterSortOrder`
  // 里到底存的是序位还是身份。
  //
  // ★ 夹具刻意取身份 5 / 7 / 9（序位 1 / 2 / 3）：在默认稿（身份 = 序位 − 1）上
  //   「归一」与「不归一」的结果**处处不同**，用例才有鉴别力（`DECISIONS §4-28`）。
  // ─────────────────────────────────────────────────────────────
  group('identityForUserPosition：用户手填序位 → 身份（写侧唯一入口，N12-F3c）', () {
    /// 删过首章、且中间有空洞的稿：身份 5 / 7 / 9 ⇔ 序位 1 / 2 / 3。
    List<Chapter> sparse() => [chapter(5), chapter(7), chapter(9)];

    test('#C95-13 正例：填「第2章」⇒ 落身份 7（**不是** 2）', () {
      expect(
        identityForUserPosition(sparse(), 2),
        7,
        reason: '不归一（直接存 2）在真稿上会被读成「sortOrder==2 的那章」= 不存在',
      );
      expect(identityForUserPosition(sparse(), 1), 5);
      expect(identityForUserPosition(sparse(), 3), 9);
    });

    test('#C95-14 写读闭环：归一后经 chapterLabel 必回到用户填的那个序位', () {
      final chapters = sparse();
      final map = buildChapterNoMap(chapters);
      for (var p = 1; p <= 3; p++) {
        expect(
          chapterLabel(map, identityForUserPosition(chapters, p)),
          '第$p章',
          reason: '用户填 p、界面显示 p —— 中间无论怎么编码都不该漂移',
        );
      }
    });

    test('#C95-15 负例：未填 / 越界 / 空稿 ⇒ null（**不猜**，ADR-C95 裁定 2）', () {
      expect(
        identityForUserPosition(sparse(), null),
        isNull,
        reason: '没填 ≠ 第1章',
      );
      expect(identityForUserPosition(sparse(), 0), isNull, reason: '序位从 1 起');
      expect(identityForUserPosition(sparse(), 99), isNull, reason: '该章不存在');
      expect(identityForUserPosition(const [], 1), isNull);
    });

    test('#C95-16 反例：**不得**走 resolveChapterIdentity 的编码阶梯', () {
      // 标称号与序位刻意错位：序位 2 的章，标题写的是「第7章」。
      final chapters = [titled(5, '第7章'), titled(7, '第1章'), titled(9, '第2章')];

      expect(
        identityForUserPosition(chapters, 2),
        7,
        reason: '用户填的是**序位** ⇒ 语义已定，直接归一',
      );
      expect(
        resolveByEncoding(2, chapters),
        9,
        reason:
            '同一输入若走阶梯会先试**标称号**「第2章」⇒ 错锚到身份 9；'
            '这正是 `ADR-C96 §2` 裁定 2 把两条路分工写死的理由',
      );
    });
  });

  // ─────────────────────────────────────────────────────────────
  // `N12-F3b` / `ADR-C96 §2`：**身份解析**（「当前章优先」四步 + 三编码阶梯）
  //
  // 本节是 `ADR-C96 §5` 验收判据 1–4 的**直接**实现。反例刻意杀死被否方案：
  //   · **R4**「身份恒 = 当前章」（不做解析）⇒ `current − introduced ≡ 0`
  //     ⇒ F11 情节闭环**永不触发**（功能回退）
  //   · **R5**「解析失败落 NULL」⇒ detector 跳过无锚点支线 ⇒ F11 **覆盖率回退**
  //   · 「不做当前章优先、直接上编码阶梯」⇒ 误锚到另一章
  // ─────────────────────────────────────────────────────────────
  group('chapterEncodings：一个章有三个「都叫章号」的数', () {
    test('#C96-1 默认标题：身份 / 标称号 / 序位 三者同时给出', () {
      final chapters = [chapter(0), chapter(1), chapter(2)];

      // 第 3 章：身份 = sortOrder 2、标称号 = 标题里的 3、序位 = 3。
      expect(chapterEncodings(chapters[2], chapters), [2, 3, 3]);
    });

    test('#C96-2 无编号标题（如「楔子」）⇒ 只给身份与序位', () {
      final chapters = [titled(0, '楔子'), titled(1, '第1章')];

      expect(
        chapterEncodings(chapters[0], chapters),
        [0, 1],
        reason: '标题里没有「第X章」⇒ 标称号这一项**不出现**（不是补 0、也不是补 null）',
      );
    });
  });

  group('resolveByEncoding：标称号 → 序位 → 身份（编码序不可换）', () {
    test('#C96-3 标称号优先于序位：两编码指向不同章时取标称号', () {
      // 标题序号与列表序位**刻意错位**（重排过的稿）。
      final chapters = [titled(0, '第2章'), titled(1, '第1章'), titled(2, '第7章')];

      expect(
        resolveByEncoding(1, chapters),
        1,
        reason: '标称号「第1章」落在 sortOrder=1 ⇒ 1；若序位优先会错得 0',
      );
    });

    test('#C96-4 序位优先于身份（身份排最后）', () {
      final chapters = [titled(0, '第9章'), titled(1, '第5章')];

      expect(
        resolveByEncoding(1, chapters),
        0,
        reason: '标题无「1」⇒ 序位 1 归 sortOrder=0；若身份优先会取 sortOrder==1',
      );
    });

    test('#C96-5 身份编码仅在标题与序位**都**落空时生效', () {
      // 两章的 sortOrder 都大于章节数 ⇒ 序位编码取不到它们。
      final chapters = [titled(0, '第9章'), titled(4, '第2章')];

      expect(
        resolveByEncoding(4, chapters),
        4,
        reason: '标题（9/2）与序位（1/2）都命中不了 4 ⇒ 落到身份编码',
      );
    });

    test('#C96-6 三编码全落空 ⇒ null（本函数不猜，兜底交给调用方）', () {
      final chapters = [chapter(0), chapter(1)];

      expect(resolveByEncoding(99, chapters), isNull);
      expect(resolveByEncoding(0, const []), isNull, reason: '空稿没有可归的章');
    });
  });

  group('resolveChapterIdentity：ADR-C96 §5 判据 1–4', () {
    // 默认标题 3 章：身份 0/1/2 ↔ 标称号 1/2/3 ↔ 序位 1/2/3。
    final three = [chapter(0), chapter(1), chapter(2)];

    test('#C96-7 判据1 正例（写读闭环）：诊断第 3 章、AI 报 3 ⇒ 身份 2', () {
      expect(resolveChapterIdentity(3, three, currentSortOrder: 2), 2);
    });

    test('#C96-8 判据2 反例：**杀死 R4「身份恒 = 当前章」**', () {
      // 诊断第 3 章（sortOrder=2）时 AI 报 1 —— 那是指第 1 章 ⇒ 身份必须是 0。
      expect(
        resolveChapterIdentity(1, three, currentSortOrder: 2),
        0,
        reason: 'R4（恒取当前章）会给 2；AI 报的是真跨章引用，必须解析出来',
      );
    });

    test('#C96-9 判据3 反例：**杀死 R5「解析失败落 NULL」**', () {
      final id = resolveChapterIdentity(99, three, currentSortOrder: 2);

      expect(id, isNotNull, reason: 'R5 会给 null ⇒ detector 跳过该支线 ⇒ F11 覆盖率回退');
      expect(
        id,
        2,
        reason: '兜底到当前章是**确定成立**的（本章正文正是本次抽取来源，chapter_hash 已如此断言）',
      );
    });

    test('#C96-10 判据4 反例：**杀死「身份编码优先」**（会错锚到第 3 章）', () {
      // 默认标题下 身份 = 序位 − 1：AI 报 2、当前章是第 2 章（sortOrder=1）。
      expect(
        resolveChapterIdentity(2, three, currentSortOrder: 1),
        1,
        reason: '当前章优先 ⇒ 1；若身份编码优先会取 sortOrder==2 的第 3 章',
      );
    });

    test('#C96-11 反例：杀死「不做当前章优先、直接上阶梯」的误锚', () {
      // 当前章是「楔子」（sortOrder=0，**无编号标题**），它的**序位**恰是 1；
      // 而另一章的标题写着「第1章」（sortOrder=1，实为第 2 章）。
      final chapters = [titled(0, '楔子'), titled(1, '第1章'), titled(2, '第2章')];

      expect(
        resolveChapterIdentity(1, chapters, currentSortOrder: 0),
        0,
        reason:
            'AI 报的 1 命中**当前章**的序位 ⇒ 按裁定 2 第 2 步归当前章；'
            '阶梯会把它锚到「第1章」那一章 —— 这正是要消灭的误锚',
      );
    });

    test('#C96-12 第 1 步：AI 未给号 ⇒ 当前章（保留现行为）', () {
      expect(resolveChapterIdentity(null, three, currentSortOrder: 1), 1);
      expect(
        resolveChapterIdentity(null, const [], currentSortOrder: 7),
        7,
        reason: '章节列表为空也必须给出确定值（同行 chapter_hash 的假设）',
      );
    });
  });

  group('chapterAt：从已升序列表取章（不猜不存在的章）', () {
    final chapters = [chapter(1), chapter(3)];

    test('#C96-13 命中 ⇒ 返回该章；不在列表 ⇒ null', () {
      expect(chapterAt(chapters, 3)?.id, 'ch-3');
      expect(
        chapterAt(chapters, 0),
        isNull,
        reason: '0 号章已删 ⇒ 不得凭 sortOrder 编造',
      );
      expect(chapterAt(const [], 1), isNull);
    });
  });
}
