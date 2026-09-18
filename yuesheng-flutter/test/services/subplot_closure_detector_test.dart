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
    expect(ctx, contains('P014'));
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
}
