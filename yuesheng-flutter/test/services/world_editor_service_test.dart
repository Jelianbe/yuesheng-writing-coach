// ─────────────────────────────────────────────────────────────
// world_editor_service_test — 批次 W1 世界观人工写入服务单测
//
// 覆盖（对应 W1-T01 验收标准）：
//   1. appendAssertion 追加 → 断言数 +1，历史断言逐字节不变（不覆盖）
//   2. appendAssertion 断言固定 source='user' / status='confirmed'
//   3. appendAssertion evidence 空串 / 空白 → 存 null（不进判据）
//   4. appendAssertion 属性 / 取值为空 → false（不写；防 parseAssertions 静默丢）
//   5. appendAssertion 主题不存在 → false
//   6. archiveWorld / restoreWorld 委派仓储（软归档往返）
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/data/repositories/world_fact_repository.dart';
import 'package:writingcoach/services/world_editor_service.dart';
import 'package:writingcoach/types/character_types.dart';

void main() {
  late AppDatabase db;
  late WorldFactRepository repo;
  late WorldEditorService editor;
  late String manuscriptId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = WorldFactRepository(db);
    editor = WorldEditorService(db);
    manuscriptId = await ManuscriptRepository(
      db,
    ).createManuscript(title: '测试稿');
  });

  tearDown(() async => db.close());

  test('#1 appendAssertion → 断言数 +1，历史断言逐字节不变', () async {
    await repo.upsertWorld(
      manuscriptId: manuscriptId,
      name: '灵气体系',
      assertions: [
        CharacterAssertion(
          attribute: '灵气浓度',
          value: '稀薄',
          chapter: 3,
          timestamp: 100,
          evidence: '这方天地灵气稀薄',
        ),
      ],
    );
    final row = await repo.getWorld(manuscriptId, '灵气体系');
    final before = WorldFactRepository.parseAssertions(row!.assertions);

    final ok = await editor.appendAssertion(
      worldId: row.id,
      attribute: '灵气浓度',
      value: '充沛',
      chapter: 20,
      evidence: '此地灵脉充沛',
    );
    expect(ok, isTrue);

    final after = WorldFactRepository.parseAssertions(
      (await repo.getWorld(manuscriptId, '灵气体系'))!.assertions,
    );
    expect(after.length, 2, reason: '追加应 +1，历史断言不被覆盖');
    expect(
      after.first.toJson().toString(),
      before.single.toJson().toString(),
      reason: '历史断言逐字节不变',
    );
    expect(after.last.value, '充沛');
  });

  test('#2 appendAssertion 断言固定 source=user / status=confirmed', () async {
    await repo.upsertWorld(manuscriptId: manuscriptId, name: '王朝');
    final row = await repo.getWorld(manuscriptId, '王朝');
    await editor.appendAssertion(
      worldId: row!.id,
      attribute: '国号',
      value: '大靖',
      chapter: 1,
      evidence: '大靖立国三百载',
    );
    final a = WorldFactRepository.parseAssertions(
      (await repo.getWorld(manuscriptId, '王朝'))!.assertions,
    ).single;
    expect(a.attribute, '国号');
    expect(a.value, '大靖');
    expect(a.chapter, 1);
    expect(a.status, 'confirmed');
    expect(a.source, 'user', reason: '手动录入固定 user，不被 AI 覆写');
  });

  test('#3 evidence 空串 / 空白 → 存 null（不进判据）', () async {
    await repo.upsertWorld(manuscriptId: manuscriptId, name: '地理');
    final row = await repo.getWorld(manuscriptId, '地理');
    await editor.appendAssertion(
      worldId: row!.id,
      attribute: '地貌',
      value: '荒原',
      evidence: '   ',
    );
    final a = WorldFactRepository.parseAssertions(
      (await repo.getWorld(manuscriptId, '地理'))!.assertions,
    ).single;
    expect(a.evidence, isNull, reason: '空串 / 空白须归一为 null（存储统一）');
  });

  test('#4 属性 / 取值为空 → false（不写）', () async {
    await repo.upsertWorld(manuscriptId: manuscriptId, name: '禁剑令');
    final row = await repo.getWorld(manuscriptId, '禁剑令');
    expect(
      await editor.appendAssertion(
        worldId: row!.id,
        attribute: '  ',
        value: 'x',
      ),
      isFalse,
    );
    expect(
      await editor.appendAssertion(worldId: row.id, attribute: 'x', value: ''),
      isFalse,
    );
    expect(
      WorldFactRepository.parseAssertions(
        (await repo.getWorld(manuscriptId, '禁剑令'))!.assertions,
      ),
      isEmpty,
      reason: '非法输入不得落库',
    );
  });

  test('#5 主题不存在 → false', () async {
    expect(
      await editor.appendAssertion(
        worldId: 'no-such-id',
        attribute: 'a',
        value: 'b',
      ),
      isFalse,
    );
  });

  test('#6 archiveWorld / restoreWorld 委派仓储', () async {
    await repo.upsertWorld(manuscriptId: manuscriptId, name: '灵气体系');
    final id = (await repo.getWorld(manuscriptId, '灵气体系'))!.id;
    expect(await editor.archiveWorld(id), isTrue);
    expect(await repo.listWorlds(manuscriptId), isEmpty);
    expect(await editor.restoreWorld(id), isTrue);
    expect((await repo.listWorlds(manuscriptId)).single.name, '灵气体系');
  });
}
