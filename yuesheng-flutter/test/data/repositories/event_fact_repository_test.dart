// ─────────────────────────────────────────────────────────────
// event_fact_repository_test — 批次67 B62j 事件知识仓储单元测试
//
// 覆盖：
//   1. upsert 新事件 → list/get 往返
//   2. 重复 upsert → 更新（UNIQUE(manuscript_id, name)）
//   3. 按章节排序（null 排最后）
//   4. parseParticipants 非法 JSON → 保守跳过
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/event_fact_repository.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';

void main() {
  late AppDatabase db;
  late EventFactRepository repo;
  late String manuscriptId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = EventFactRepository(db);
    manuscriptId = await ManuscriptRepository(
      db,
    ).createManuscript(title: '测试稿');
  });

  tearDown(() async => db.close());

  test('#1 upsert 新事件 → list/get 往返', () async {
    await repo.upsertEvent(
      manuscriptId: manuscriptId,
      name: '阿禾决定去金陵',
      eventType: '决定',
      chapter: 5,
      participants: ['阿禾', '阿青'],
      description: '收到密信后决定南下',
    );

    final list = await repo.listEvents(manuscriptId);
    expect(list.length, 1);
    expect(list.first.name, '阿禾决定去金陵');
    expect(list.first.chapter, 5);
    expect(list.first.eventType, '决定');
    expect(list.first.description, '收到密信后决定南下');

    final got = await repo.getEvent(manuscriptId, '阿禾决定去金陵');
    expect(got, isNotNull);
    expect(EventFactRepository.parseParticipants(got!.participants), [
      '阿禾',
      '阿青',
    ]);
  });

  test('#2 重复 upsert → 更新（不新增行）', () async {
    await repo.upsertEvent(
      manuscriptId: manuscriptId,
      name: '阿禾决定去金陵',
      eventType: '决定',
      chapter: 5,
    );
    await repo.upsertEvent(
      manuscriptId: manuscriptId,
      name: '阿禾决定去金陵',
      eventType: '决定',
      chapter: 6,
      causeEventId: 'event-1',
    );

    final list = await repo.listEvents(manuscriptId);
    expect(list.length, 1, reason: '同作品同名事件唯一');

    final got = await repo.getEvent(manuscriptId, '阿禾决定去金陵');
    expect(got!.chapter, 6);
    expect(got.causeEventId, 'event-1');
  });

  test('#3 按章节排序（null 排最后）', () async {
    await repo.upsertEvent(
      manuscriptId: manuscriptId,
      name: '后期事件',
      eventType: '冲突',
      chapter: 9,
    );
    await repo.upsertEvent(
      manuscriptId: manuscriptId,
      name: '无章节事件',
      eventType: '日常',
      chapter: null,
    );
    await repo.upsertEvent(
      manuscriptId: manuscriptId,
      name: '早期事件',
      eventType: '日常',
      chapter: 2,
    );

    final list = await repo.listEvents(manuscriptId);
    expect(list.map((e) => e.name).toList(), ['早期事件', '后期事件', '无章节事件']);
  });

  test('#4 parseParticipants 非法 JSON → 保守跳过', () {
    expect(EventFactRepository.parseParticipants(''), isEmpty);
    expect(EventFactRepository.parseParticipants('not-json'), isEmpty);
    expect(EventFactRepository.parseParticipants('{"a":1}'), isEmpty);

    final parsed = EventFactRepository.parseParticipants(
      '["阿禾", "", "阿青", null]',
    );
    expect(parsed, ['阿禾', '阿青']);
  });

  test('#5 updateCauseEventId 轻量更新因果边（批次3-D4）', () async {
    // 模拟 chat_service 两轮写入：先 upsert 两个事件（无因果边），再反查 id 填充
    await repo.upsertEvent(
      manuscriptId: manuscriptId,
      name: '父亲病重',
      eventType: '突发',
      chapter: 3,
    );
    await repo.upsertEvent(
      manuscriptId: manuscriptId,
      name: '阿禾决定去金陵',
      eventType: '决定',
      chapter: 5,
    );

    // 第一轮后两个事件都无 causeEventId
    var decision = await repo.getEvent(manuscriptId, '阿禾决定去金陵');
    expect(decision!.causeEventId, isNull);

    // 第二轮：反查触发事件 id，填入决定事件的因果边
    final trigger = await repo.getEvent(manuscriptId, '父亲病重');
    expect(trigger, isNotNull);
    await repo.updateCauseEventId(decision.id, trigger!.id);

    // 验证因果边已填入
    decision = await repo.getEvent(manuscriptId, '阿禾决定去金陵');
    expect(decision!.causeEventId, trigger.id);
  });
}
