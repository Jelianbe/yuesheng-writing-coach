// ─────────────────────────────────────────────────────────────
// fact_triple_key_contract_test — `FactStaleService.tripleKey` 的**键口径契约**
//
// 背景（`X1`，2026-09-18 侦察后裁定，见 `.ai/DECISIONS §2`）：
//   `tripleKey` 是 `mergeAssertions` / `mergeForTransfer` /
//   `CharacterEditorService._sameAssertion` 共用的**断言同一性键**
//   （attribute + value + **chapter**）。同文件另外两处章号判据
//   （`belongsToChapter` / `mergeAssertions` 的 stale 支）已在 `N12-F3b` phase 1
//   改比 `chapterIdentity`，**唯此处仍取旧列 `a.chapter`**。
//   于是登记了一个疑问：这是不是同一类「漏改」？
//
// 裁定：**不是，且刻意不改**。两类判据的**比较方向相反**：
//   - `belongsToChapter` 是**跨源比较**：拿「存的值」比「外部传入的章号」
//     ⇒ 两侧基号不同 ⇒ 干净稿上**恒假**（真缺陷，已修）。
//   - `tripleKey` 是**自洽比较**：拿「两条已存断言的同一字段」互比
//     ⇒ 两侧同基 ⇒ 本来就能对上。改成 `chapterIdentity` 反而**新增**分歧：
//     存量行无载体 ⇒ 回退值 = AI 标称号（3），新行载体 = 身份（2）⇒ 不等
//     ⇒ **每章重诊都会把旧断言重复一条**（本文件 #1 即此承重面）。
//   ⇒ 判据：**跨源比较必须归一；自洽比较保持原列。**（`.ai/DECISIONS §4-40`）
//
// 覆盖：
//   1. 正例（承重）：存量行 ↔ 新行 同章同事实 ⇒ 归并（改成 chapterIdentity 即红）
//   2. 反例：跨章同属性同值 ⇒ 不归并（挡「并集取交」型过度合并）
//   3. 已知残余：提炼条（旧列 null）↔ 诊断行（旧列标称号）⇒ 不归并（记录代价）
//   4. 边界：`chapterIdentity` 对存量行回退旧列 ⇒ 它 **≠** 身份（"兼容，不是治愈"）
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/fact_stale_service.dart';
import 'package:writingcoach/types/character_types.dart';

CharacterAssertion a(
  String attribute,
  String value, {
  int? chapter,
  int? chapterSortOrder,
  String? chapterHash,
  bool stale = false,
  String status = 'confirmed',
  String source = 'ai',
  int timestamp = 1000,
}) {
  return CharacterAssertion(
    attribute: attribute,
    value: value,
    chapter: chapter,
    chapterSortOrder: chapterSortOrder,
    timestamp: timestamp,
    status: status,
    source: source,
    chapterHash: chapterHash,
    stale: stale,
  );
}

void main() {
  group('tripleKey 键口径契约（第三项**刻意**取旧列 `chapter`）', () {
    test('#1 正例（承重）：AI 链路「存量行 ↔ 新行」同章同事实 ⇒ 归并成 1 条', () {
      // 存量行（`N12-F3b` 之前落库）：只有旧列，装的是 **AI 标称号 3**，无载体。
      final legacy = a(
        '性格',
        '冷静',
        chapter: 3,
        chapterHash: 'old',
        status: 'pending',
      );
      // 新行：同一章、同一事实。AI 仍报标称号 3；载体另记**身份 2**。
      final fresh = a(
        '性格',
        '冷静',
        chapter: 3,
        chapterSortOrder: 2,
        chapterHash: 'new',
        status: 'pending',
      );

      final merged = FactStaleService.mergeAssertions(
        [legacy],
        [fresh],
        'new',
        chapterNo: 2,
      );

      expect(
        merged,
        hasLength(1),
        reason:
            '键取旧列 ⇒ 两侧都是「3」⇒ 命中规则 (a)、旧行被顶替。'
            '若把 tripleKey 第三项改成 chapterIdentity：存量行回退值 3 ≠ 新载体 2 '
            '⇒ 键不等 ⇒ **变成 2 条**（同章同值重复展示）——本用例即该改法的红灯。',
      );
      expect(
        merged.single.chapterSortOrder,
        2,
        reason: '存活的是新行（带载体）⇒ 展示侧才出得来章标；存活的若是存量行则永远显示「早期」',
      );
    });

    test('#2 反例：**跨章**同属性同值 ⇒ 绝不归并（挡「按并集取交」的过度合并）', () {
      // 存量行属**第 2 章**（旧列 = 标称号 2，无载体）。
      // 第 3 章的**身份**恰好也是 2 —— 这正是「把 chapter 与 chapterIdentity
      // 两维并集取交」会误判为同一章的那一格：{2} ∩ {3, 2} = {2}。
      final ch2Legacy = a('性格', '冷静', chapter: 2, chapterHash: 'h2');
      final ch3Fresh = a(
        '性格',
        '冷静',
        chapter: 3,
        chapterSortOrder: 2,
        chapterHash: 'h3',
      );

      final merged = FactStaleService.mergeAssertions(
        [ch2Legacy],
        [ch3Fresh],
        'h3',
        chapterNo: 2,
      );

      expect(
        merged,
        hasLength(2),
        reason:
            '第 2 章的断言属别章 ⇒ 必须原样留下。过度合并 = 重诊第 3 章时静默吞掉第 2 章的'
            '已存事实（R1′ / R-009 不可接受），比「重复展示」严重一个量级。',
      );
      expect(
        merged.first.stale,
        isTrue,
        reason:
            '兼容层的**已知不精确**（不是本批新增）：存量行无载体 ⇒ 回退值 2 与第 3 章的身份 2 '
            '撞车 ⇒ 该行被标灰。它**不删数据**、只多一个灰标；治愈手段是给存量行补载体，'
            '不是放宽本键。',
      );
    });

    test('#3 已知残余（记录代价，勿以 `chapterIdentity` 修）：提炼条 ↔ 诊断行 同章 ⇒ 不归并', () {
      // 提炼条（`N12-F3c` 起）：提炼协议里**不含章号** ⇒ 旧列留空，只落载体。
      final extracted = a('性格', '冷静', chapterSortOrder: 2, status: 'pending');
      // 诊断行：旧列 = AI 标称号 3、载体 = 身份 2。
      final diagnosed = a(
        '性格',
        '冷静',
        chapter: 3,
        chapterSortOrder: 2,
        chapterHash: 'h3',
        status: 'pending',
      );

      final merged = FactStaleService.mergeAssertions(
        [diagnosed],
        [extracted],
        'h3',
        chapterNo: 2,
      );

      expect(
        merged,
        hasLength(2),
        reason:
            '键里一个是「null」、一个是「3」⇒ 不归并 —— 待确认列表会出现两条**同章同值**的断言。'
            '这是**现状的代价**：改成 chapterIdentity 能同时修掉本条与 #1，但 #1 是**每章重诊都会踩**'
            '的主链路、本条只在用户显式点「从正文提炼断言」时出现 ⇒ 两害相权取轻，保留现状。'
            '裁定留痕：`.ai/DECISIONS §2` 的 X1 行。',
      );
    });

    test('#4 边界：`chapterIdentity` 对存量行**回退旧列** ⇒ 它 ≠ 身份（"兼容，不是治愈"）', () {
      final legacy = a('性格', '冷静', chapter: 3);
      expect(
        legacy.chapterIdentity,
        3,
        reason:
            '无载体 ⇒ 回退旧列。而 `character_fact` 存量行（`N12-F3b` 之前）的旧列装的是 '
            '**AI 标称号**（`_asAiPending` 原样透传，**没有** `?? chapterNo` —— 那条兜底只存在于'
            'event / subplot 侧）⇒ 这个回退值**不是身份**，不能拿它当去重键（#1）。',
      );
      final fresh = a('性格', '冷静', chapter: 3, chapterSortOrder: 2);
      expect(
        fresh.chapterIdentity,
        2,
        reason: '有载体 ⇒ 取载体。与上一行相差 1，正是「干净稿上标称号 = 身份 + 1」',
      );
    });

    test('#5 反例：AI **未报**章号（旧列 null）的断言 ≠ 旧列标称号相同的**别章**存量行', () {
      // 存量行属**第 2 章**（旧列 = 标称号 2，无载体）。
      final ch2Legacy = a('身份', '守夜人', chapter: 2, chapterHash: 'h2');
      // AI 这一条**没报章号** ⇒ 旧列 null、载体 = 当前章（第 3 章）的身份 2。
      final noAiNo = a('身份', '守夜人', chapterSortOrder: 2, chapterHash: 'h3');

      final merged = FactStaleService.mergeAssertions(
        [ch2Legacy],
        [noAiNo],
        'h3',
        chapterNo: 2,
      );

      expect(
        merged,
        hasLength(2),
        reason:
            '两章不同 ⇒ 不得归并。本用例专挡「旧列优先、回退载体」（`chapter ?? chapterSortOrder`）'
            '那种写法：它会把 null 兜成 2，与第 2 章的标称号 2 撞车 ⇒ 误合并成 1 条'
            '（重诊第 3 章时静默吞掉第 2 章的已存事实）。',
      );
    });
  });
}
