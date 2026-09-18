// progression_builder_test — Progressions 章节演进纯逻辑测试（第三批）
//
// ★ `N12-F3b` phase 3（2026-09-18）：分组键由**旧列** `chapter` 改为**身份**
//   `chapterSortOrder`。本文件因此重写为**判别性夹具** —— 每个用例都构造
//   「旧列值与身份不一致」的输入，使**两种实现的结果不同**；否则测试对这类回归
//   **零鉴别力**（既有教训：旧夹具两种读法渲染完全相同，改错了也全绿，
//   见 `DECISIONS §4-28`）。
//
//   1. 断言按**身份**聚合（旧列不同、身份相同 ⇒ 并为一个节点）
//   2. 按**身份**升序 —— 与按旧列升序结果**不同**
//   3. **无身份**的断言/事件被过滤（**即使旧列有值**）
//   4. firstSeenChapter（身份）插「首次出现」+ 同章已有断言时不重复插
//   5. 空输入 → 空列表
//   6. 全无身份 → 空列表（区块据此隐藏）
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/services/progression_builder.dart';
import 'package:writingcoach/types/character_types.dart';

void main() {
  CharacterAssertion a({
    required String attribute,
    required String value,
    int? chapter,
    int? chapterSortOrder,
  }) => CharacterAssertion(
    attribute: attribute,
    value: value,
    chapter: chapter,
    chapterSortOrder: chapterSortOrder,
    timestamp: 0,
  );

  EventFact e({required String name, int? chapter, int? chapterSortOrder}) =>
      EventFact(
        id: name,
        manuscriptId: 'm1',
        name: name,
        chapter: chapter,
        chapterSortOrder: chapterSortOrder,
        eventType: '日常',
        participants: '[]',
        description: '',
        stale: 0,
        createdAt: 0,
        updatedAt: 0,
      );

  test('#1 按身份聚合：旧列不同、身份相同 ⇒ 合并为一个节点', () {
    final points = buildProgressions(
      assertions: [
        a(attribute: '出身', value: '临安', chapter: 3, chapterSortOrder: 0),
        // 同身份、旧列不同（真实形态：AI 标称号 vs 机器身份）⇒ 必须并入**同**节点
        a(attribute: '职业', value: '医师', chapter: 4, chapterSortOrder: 0),
        a(attribute: '宿敌', value: '沈某', chapter: 9, chapterSortOrder: 7),
      ],
    );
    expect(points.length, 2);
    expect(points[0].chapterIdentity, 0, reason: '分组键 = 身份，不是旧列 3');
    expect(points[0].items, containsAll(['出身: 临安', '职业: 医师']));
    expect(points[1].chapterIdentity, 7);
    expect(points[1].items, ['宿敌: 沈某']);
  });

  test('#2 按身份升序 —— 与按旧列升序**不同**（判别性）', () {
    // 旧列 1/3/2 ⇒ 升序 [1,2,3]；身份 5/0/2 ⇒ 升序 [0,2,5]。两者顺序不同。
    final points = buildProgressions(
      assertions: [
        a(attribute: 'B', value: 'b', chapter: 1, chapterSortOrder: 5),
        a(attribute: 'A', value: 'a', chapter: 3, chapterSortOrder: 0),
        a(attribute: 'C', value: 'c', chapter: 2, chapterSortOrder: 2),
      ],
    );
    expect(
      [for (final p in points) p.chapterIdentity],
      [0, 2, 5],
      reason: '按旧列会得到 [1,2,3] —— 两种实现在本夹具上结果必然不同',
    );
  });

  test('#3 无身份被过滤 —— **即使旧列有值**（判别性）', () {
    final points = buildProgressions(
      assertions: [
        a(attribute: '有身份', value: 'v', chapter: 7, chapterSortOrder: 0),
        a(attribute: '只有旧列', value: 'x', chapter: 7),
      ],
      events: [
        e(name: '有身份事件', chapter: 8, chapterSortOrder: 1),
        e(name: '无身份事件', chapter: 8),
      ],
    );
    expect(points.length, 2);
    expect(points[0].chapterIdentity, 0);
    expect(points[0].items, ['有身份: v']);
    expect(points[1].chapterIdentity, 1);
    expect(points[1].items, ['有身份事件']);
    // 反向取证：被丢掉的**必须是「因为无身份」**，而不是「因为旧列为空」——
    // 上面两条的旧列都**有值**（7 / 8），所以这条断言才真正判定了筛选依据。
    final allItems = [for (final p in points) ...p.items];
    expect(allItems, isNot(contains('只有旧列: x')));
    expect(allItems, isNot(contains('无身份事件')));
  });

  test('#4 firstSeenChapter 插「首次出现」；同章有断言时不重复插', () {
    final points = buildProgressions(
      assertions: [
        a(attribute: '出身', value: '临安', chapter: 3, chapterSortOrder: 3),
      ],
      firstSeenChapter: 3,
    );
    expect(points.single.chapterIdentity, 3);
    expect(points.single.items, ['首次出现', '出身: 临安']);

    final points2 = buildProgressions(
      assertions: [
        a(attribute: '出身', value: '临安', chapter: 5, chapterSortOrder: 5),
      ],
      firstSeenChapter: 2,
    );
    expect(points2.length, 2);
    expect(points2[0].chapterIdentity, 2);
    expect(points2[0].items, ['首次出现']);
    expect(points2[1].chapterIdentity, 5);
  });

  test('#5 空输入 → 空列表', () {
    expect(buildProgressions(assertions: []), isEmpty);
  });

  test('#6 全无身份 → 空列表（区块据此隐藏，不建「未知」桶）', () {
    final points = buildProgressions(
      assertions: [a(attribute: 'x', value: 'y', chapter: 3)],
      events: [e(name: '无身份事件', chapter: 3)],
    );
    expect(points, isEmpty, reason: '位置有序视图里「无位序」≡「无章节」；塞进「未知」桶会伪造「同章」语义');
  });
}
