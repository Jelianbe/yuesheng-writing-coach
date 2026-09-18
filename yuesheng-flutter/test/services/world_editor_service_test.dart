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
//
// `N12-F3c` 追加（章号写侧归一，与 `N12-F3a` / 角色侧同口径）：
//   7. 用户手填章号 = **序位** ⇒ 写库前归一到身份，落**新载体** `chapterSortOrder`
//   8. 序位不存在 / 未填 ⇒ 新载体 null（**不猜**），旧列仍保留用户原写的数（R1′）
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/chapter_repository.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/data/repositories/world_fact_repository.dart';
import 'package:writingcoach/services/world_editor_service.dart';
import 'package:writingcoach/types/character_types.dart';

void main() {
  late AppDatabase db;
  late WorldFactRepository repo;
  late WorldEditorService editor;
  late ChapterRepository chapterRepo;
  late String manuscriptId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = WorldFactRepository(db);
    editor = WorldEditorService(db);
    chapterRepo = ChapterRepository(db);
    manuscriptId = await ManuscriptRepository(
      db,
    ).createManuscript(title: '测试稿');
  });

  tearDown(() async => db.close());

  /// 待解析断言列表（`N12-F3c` 追加用例共用）。
  Future<List<CharacterAssertion>> assertionsOf(String name) async {
    final row = await repo.getWorld(manuscriptId, name);
    return WorldFactRepository.parseAssertions(row!.assertions);
  }

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

  // ══ `N12-F3c`：章号写侧归一 ══════════════════════════════════════════
  // ★ 判据的关键在**夹具让序位与身份分叉**：只造「第 1 章身份就是 0」的默认稿，
  //   「归一」与「不归一」两种实现渲染/存储结果**逐字相同** ⇒ 用例没有鉴别力
  //   （`DECISIONS §4-28`）。故唯一一章刻意取 `sortOrder: 7`（序位 1，身份 7）。
  group('章号写侧归一（N12-F3c）', () {
    test('#7 序位 → 身份：旧列存用户原写的数，新载体存身份', () async {
      await chapterRepo.createChapter(
        manuscriptId,
        title: '第三章',
        content: '这方天地灵气稀薄。',
        sortOrder: 7,
      );
      await repo.upsertWorld(manuscriptId: manuscriptId, name: '灵气体系');
      final row = await repo.getWorld(manuscriptId, '灵气体系');

      expect(
        await editor.appendAssertion(
          worldId: row!.id,
          attribute: '灵气浓度',
          value: '稀薄',
          chapter: 1, // 用户填的是他看得见的**序位**
        ),
        isTrue,
      );

      final a = (await assertionsOf('灵气体系')).single;
      expect(a.chapter, 1, reason: 'R1′：用户原写的数原样保留，不覆盖不篡改');
      expect(a.chapterSortOrder, 7, reason: '序位 1 ⇒ 身份 7（不归一则会存成 1）');
    });

    test('#8 序位不存在 / 未填 ⇒ 新载体 null（不猜），旧列仍保留原值', () async {
      await chapterRepo.createChapter(
        manuscriptId,
        title: '第三章',
        content: 'x',
        sortOrder: 7,
      );
      await repo.upsertWorld(manuscriptId: manuscriptId, name: '王朝');
      final row = await repo.getWorld(manuscriptId, '王朝');

      await editor.appendAssertion(
        worldId: row!.id,
        attribute: '国号',
        value: '大靖',
        chapter: 99, // 越界
      );
      await editor.appendAssertion(
        worldId: row.id,
        attribute: '都城',
        value: '金陵',
      );

      final list = await assertionsOf('王朝');
      final outOfRange = list.firstWhere((a) => a.value == '大靖');
      expect(outOfRange.chapter, 99, reason: 'R1′：越界也保留用户原值');
      expect(
        outOfRange.chapterSortOrder,
        isNull,
        reason: '序位 99 不存在 ⇒ 不猜（ADR-C95 裁定 2）',
      );
      expect(
        list.firstWhere((a) => a.value == '金陵').chapterSortOrder,
        isNull,
        reason: '未填章号 ⇒ 无身份',
      );
    });

    test('#9 判别性：身份不等于序位时，读的是**身份**（不是用户填的数）', () async {
      // 两章、身份 5/9（序位 1/2）—— 任何一个用户可能填的数（1、2）都**不是**身份。
      await chapterRepo.createChapter(
        manuscriptId,
        title: '第一章',
        content: 'a',
        sortOrder: 5,
      );
      await chapterRepo.createChapter(
        manuscriptId,
        title: '第二章',
        content: 'b',
        sortOrder: 9,
      );
      await repo.upsertWorld(manuscriptId: manuscriptId, name: '地理');
      final row = await repo.getWorld(manuscriptId, '地理');

      await editor.appendAssertion(
        worldId: row!.id,
        attribute: '地貌',
        value: '荒原',
        chapter: 2,
      );

      final a = (await assertionsOf('地理')).single;
      expect(a.chapterSortOrder, 9, reason: '序位 2 ⇒ 身份 9；存成 2 就是没归一');
      expect(
        a.chapterSortOrder,
        isNot(a.chapter),
        reason: '本夹具下两者必须不同，否则本用例无鉴别力',
      );
    });
  });
}
