// progression_builder_test — Progressions 章节演进纯逻辑测试（第三批）
//
//   1. 断言按章节聚合（含多属性同章合并）
//   2. 章节升序排序（乱序输入）
//   3. 无章节断言/事件被过滤
//   4. firstSeenChapter 插入「首次出现」+ 同章已有断言时不重复插
//   5. 空输入 → 空列表
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/services/progression_builder.dart';
import 'package:writingcoach/types/character_types.dart';

void main() {
  CharacterAssertion a({
    required String attribute,
    required String value,
    int? chapter,
  }) => CharacterAssertion(
    attribute: attribute,
    value: value,
    chapter: chapter,
    timestamp: 0,
  );

  test('#1 断言按章节聚合，多属性同章合并', () {
    final points = buildProgressions(
      assertions: [
        a(attribute: '出身', value: '临安', chapter: 3),
        a(attribute: '职业', value: '医师', chapter: 3),
        a(attribute: '宿敌', value: '沈某', chapter: 12),
      ],
    );
    expect(points.length, 2);
    expect(points[0].chapter, 3);
    expect(points[0].items, containsAll(['出身: 临安', '职业: 医师']));
    expect(points[1].chapter, 12);
    expect(points[1].items, ['宿敌: 沈某']);
  });

  test('#2 章节升序排序（乱序输入）', () {
    final points = buildProgressions(
      assertions: [
        a(attribute: 'B', value: 'b', chapter: 20),
        a(attribute: 'A', value: 'a', chapter: 5),
        a(attribute: 'C', value: 'c', chapter: 1),
      ],
    );
    expect([for (final p in points) p.chapter], [1, 5, 20]);
  });

  test('#3 无章节断言/事件被过滤', () {
    final points = buildProgressions(
      assertions: [
        a(attribute: '有章', value: 'v', chapter: 7),
        a(attribute: '无章', value: 'x'),
      ],
      events: [
        EventFact(
          id: 'e1',
          manuscriptId: 'm1',
          name: '有章事件',
          chapter: 8,
          eventType: '日常',
          participants: '[]',
          description: '',
          stale: 0,
          createdAt: 0,
          updatedAt: 0,
        ),
        EventFact(
          id: 'e2',
          manuscriptId: 'm1',
          name: '无章事件',
          eventType: '日常',
          participants: '[]',
          description: '',
          stale: 0,
          createdAt: 0,
          updatedAt: 0,
        ),
      ],
    );
    expect(points.length, 2);
    expect(points[0].items, ['有章: v']);
    expect(points[1].items, ['有章事件']);
  });

  test('#4 firstSeenChapter 插「首次出现」；同章有断言时不重复插', () {
    final points = buildProgressions(
      assertions: [a(attribute: '出身', value: '临安', chapter: 3)],
      firstSeenChapter: 3,
    );
    expect(points.single.chapter, 3);
    expect(points.single.items, ['首次出现', '出身: 临安']);

    final points2 = buildProgressions(
      assertions: [a(attribute: '出身', value: '临安', chapter: 5)],
      firstSeenChapter: 2,
    );
    expect(points2.length, 2);
    expect(points2[0].chapter, 2);
    expect(points2[0].items, ['首次出现']);
    expect(points2[1].chapter, 5);
  });

  test('#5 空输入 → 空列表', () {
    expect(buildProgressions(assertions: []), isEmpty);
  });
}
