// ─────────────────────────────────────────────────────────────
// subplot_closure_detector_test — 批次67 B62j F11 情节闭环检测单元测试
//
// 覆盖：
//   1. 空输入 → 空数组
//   2. 未回收且超阈值（>=3章）→ 情节闭环观察项
//   3. 已回收 → 不误报
//   4. 未到阈值（<3章）→ 不误报（留回收空间）
//   5. 无引入章节 → 保守跳过
//   6. 多条 → 按引入章节升序输出
//   7. buildSubplotClosureContext：空 → null
//   8. buildSubplotClosureContext：非空 → 含观察、措辞与汇总
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/chat_context_builder.dart';
import 'package:writingcoach/services/subplot_closure_detector.dart';

void main() {
  test('#1 空输入 → 空数组', () {
    expect(detectUnclosedSubplots(const [], currentChapter: 12), isEmpty);
  });

  test('#2 未回收且超阈值（>=3章）→ 情节闭环观察项', () {
    final result = detectUnclosedSubplots([
      (
        name: '钥匙的秘密',
        introducedChapter: 3,
        resolvedChapter: null,
        introducedSortOrder: null,
      ),
    ], currentChapter: 12);

    expect(result.length, 1);
    final obs = result.first;
    expect(obs.name, '钥匙的秘密');
    expect(obs.introducedChapter, 3);
    expect(obs.currentChapter, 12);
    expect(obs.description, '第3章引入的支线「钥匙的秘密」至今（第12章）未回收');
  });

  test('#3 已回收 → 不误报', () {
    final result = detectUnclosedSubplots([
      (
        name: '钥匙的秘密',
        introducedChapter: 3,
        resolvedChapter: 8,
        introducedSortOrder: null,
      ),
    ], currentChapter: 12);

    expect(result, isEmpty);
  });

  test('#4 未到阈值（<3章）→ 不误报（留回收空间）', () {
    final result = detectUnclosedSubplots([
      (
        name: '新支线',
        introducedChapter: 11,
        resolvedChapter: null,
        introducedSortOrder: null,
      ),
    ], currentChapter: 12);

    expect(result, isEmpty, reason: '引入不足3章，不判定收束滞后');
  });

  test('#5 无引入章节 → 保守跳过', () {
    final result = detectUnclosedSubplots([
      (
        name: '无锚点支线',
        introducedChapter: null,
        resolvedChapter: null,
        introducedSortOrder: null,
      ),
    ], currentChapter: 12);

    expect(result, isEmpty, reason: '无时间锚点，无法判定收束滞后');
  });

  test('#6 多条 → 按引入章节升序输出', () {
    final result = detectUnclosedSubplots([
      (
        name: '后来的支线',
        introducedChapter: 10,
        resolvedChapter: null,
        introducedSortOrder: null,
      ),
      (
        name: '早先的支线',
        introducedChapter: 2,
        resolvedChapter: null,
        introducedSortOrder: null,
      ),
    ], currentChapter: 15);

    expect(result.length, 2);
    expect(result.first.name, '早先的支线');
    expect(result.first.description, '第2章引入的支线「早先的支线」至今（第15章）未回收');
    expect(result.last.name, '后来的支线');
  });

  test('#7 buildSubplotClosureContext 空 → null', () {
    expect(buildSubplotClosureContext(const []), isNull);
  });

  test('#8 buildSubplotClosureContext 非空 → 含观察、措辞与汇总', () {
    final observations = detectUnclosedSubplots([
      (
        name: '钥匙的秘密',
        introducedChapter: 3,
        resolvedChapter: null,
        introducedSortOrder: null,
      ),
      (
        name: '妹妹的身世',
        introducedChapter: 5,
        resolvedChapter: null,
        introducedSortOrder: null,
      ),
    ], currentChapter: 12);

    final ctx = buildSubplotClosureContext(observations);
    expect(ctx, isNotNull);
    expect(ctx, contains('情节闭环观察'));
    expect(ctx, contains('第3章引入的支线「钥匙的秘密」至今（第12章）未回收'));
    expect(ctx, contains('P012'));
    expect(ctx, contains('共 2 条支线收束滞后'));
  });

  // ─────────────────────────────────────────────────────────────
  // N12-F3b（`ADR-C96 §2` 消费侧冲突表第 4 行）：**减法判据吃身份**
  //
  // `currentChapter` 恒为身份键（`message_injector` 传 `chapter.sortOrder`），
  // 而 `introducedChapter` 是**一列多源**（AI 标称号 / 机器身份）⇒ 直接相减没有
  // 单一基线。身份落地后判据改指 `introducedSortOrder`；**描述文案仍用原值**
  // —— 它属 ADR 冻结的 9 处展示渲染，phase 1 一行不改。
  // ─────────────────────────────────────────────────────────────
  test('#9 判据吃**身份**（正例）：按原值会漏报，按身份命中阈值', () {
    final result = detectUnclosedSubplots([
      (
        name: '钥匙的秘密',
        introducedChapter: 12, // AI 原值（标称号）
        resolvedChapter: null,
        introducedSortOrder: 2, // 身份
      ),
    ], currentChapter: 5);

    expect(
      result.length,
      1,
      reason: '身份基线 5 − 2 = 3 达阈值；拿原值算则 5 − 12 = −7 ⇒ 漏报',
    );
  });

  test('#10 描述文案仍用**原值**（phase 1 展示零变更）', () {
    final result = detectUnclosedSubplots([
      (
        name: '钥匙的秘密',
        introducedChapter: 12,
        resolvedChapter: null,
        introducedSortOrder: 2,
      ),
    ], currentChapter: 5);

    expect(result.first.introducedChapter, 12, reason: '观察项透传原值（调用方与展示层仍在用）');
    expect(
      result.first.description,
      '第12章引入的支线「钥匙的秘密」至今（第5章）未回收',
      reason: '文案属冻结的 9 处渲染之一 ⇒ 本批不得改动它的数字来源',
    );
  });

  test('#11 判据吃**身份**（反例）：身份未到阈值 ⇒ 不得按原值误报', () {
    final result = detectUnclosedSubplots([
      (
        name: '刚埋下的支线',
        introducedChapter: 1, // AI 原值
        resolvedChapter: null,
        introducedSortOrder: 10, // 身份 = 第 11 章
      ),
    ], currentChapter: 12);

    expect(
      result,
      isEmpty,
      reason: '身份基线 12 − 10 = 2 < 3 ⇒ 未到阈值；按原值算得 11 ⇒ 误报',
    );
  });

  test('#12 存量行（身份为 null）⇒ 退回原值，行为逐字不变', () {
    final result = detectUnclosedSubplots([
      (
        name: '存量支线',
        introducedChapter: 3,
        resolvedChapter: null,
        introducedSortOrder: null,
      ),
    ], currentChapter: 12);

    expect(result.length, 1);
    expect(result.first.description, '第3章引入的支线「存量支线」至今（第12章）未回收');
  });

  // ── A8（ADR-C107）：删章后「引入章已不存在」的幽灵支线先过滤 ──────────────
  //
  // 支线行的 introduced* 是历史身份/标称号，删章不清空。于是用户删了引入章后，
  // 它仍被算成「引入后 N 章未回收」——可引入章本身都没了，无从回收。
  group('A8 幽灵支线过滤 dropGhostIntroducedSubplots', () {
    SubplotFactInput sub({
      required String name,
      int? introducedChapter,
      int? introducedSortOrder,
    }) => (
      name: name,
      introducedChapter: introducedChapter,
      resolvedChapter: null,
      introducedSortOrder: introducedSortOrder,
    );

    test('引入章身份已被删（不在现存集合）⇒ 丢弃', () {
      final out = dropGhostIntroducedSubplots(
        [sub(name: '幽灵', introducedChapter: 3, introducedSortOrder: 3)],
        {5, 7, 9}, // 现存章节身份里没有 3
      );
      expect(out, isEmpty, reason: '引入章 sortOrder=3 已不存在 ⇒ 不得参与闭环检测');
    });

    test('引入章身份仍在 ⇒ 保留', () {
      final out = dropGhostIntroducedSubplots(
        [sub(name: '正常', introducedChapter: 3, introducedSortOrder: 5)],
        {5, 7, 9},
      );
      expect(out.single.name, '正常');
    });

    test('存量行退回旧列：旧列不在集合 ⇒ 丢弃；在集合 ⇒ 保留', () {
      final dropped = dropGhostIntroducedSubplots(
        [sub(name: '旧列幽灵', introducedChapter: 2, introducedSortOrder: null)],
        {5, 7, 9},
      );
      expect(dropped, isEmpty);
      final kept = dropGhostIntroducedSubplots(
        [sub(name: '旧列正常', introducedChapter: 7, introducedSortOrder: null)],
        {5, 7, 9},
      );
      expect(kept.single.name, '旧列正常');
    });

    test('无引入章 ⇒ 保守保留（不误杀存量）', () {
      final out = dropGhostIntroducedSubplots(
        [sub(name: '无锚点', introducedChapter: null, introducedSortOrder: null)],
        {5, 7, 9},
      );
      expect(out.single.name, '无锚点');
    });
  });
}
