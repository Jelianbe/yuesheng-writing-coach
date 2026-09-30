// ─────────────────────────────────────────────────────────────
// setting_library_service_test — 设定资料库用户裁决服务单元测试
//
// 批次：2026-09-16 设定资料库第一批（承重墙）
// 覆盖：confirm / reject / supersede / resolveConflict 三选一
//       + replaceAssertions 原样写回（merge 不干扰用户裁决）
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/character_fact_repository.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/data/repositories/world_fact_repository.dart';
import 'package:writingcoach/services/setting_library_service.dart';
import 'package:writingcoach/types/character_types.dart';

void main() {
  late AppDatabase db;
  late CharacterFactRepository charRepo;
  late WorldFactRepository worldRepo;
  late SettingLibraryService service;
  late String manuscriptId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    charRepo = CharacterFactRepository(db);
    worldRepo = WorldFactRepository(db);
    service = SettingLibraryService(
      characterRepo: charRepo,
      worldRepo: worldRepo,
    );
    manuscriptId = await ManuscriptRepository(
      db,
    ).createManuscript(title: '测试稿');
  });

  tearDown(() async => db.close());

  CharacterAssertion pendingAssertion({
    required String attribute,
    required String value,
  }) => CharacterAssertion(
    attribute: attribute,
    value: value,
    chapter: 3,
    timestamp: 1000,
    status: 'pending',
  );

  Future<List<CharacterAssertion>> loadCharacter(String name) async {
    final row = await charRepo.getCharacter(manuscriptId, name);
    return CharacterFactRepository.parseAssertions(row!.assertions);
  }

  test('#1 confirm：pending → confirmed（原样落库，不被 merge 干扰）', () async {
    await charRepo.upsertCharacter(
      manuscriptId: manuscriptId,
      name: '阿禾',
      assertions: [pendingAssertion(attribute: '职业', value: '捕快')],
    );

    await service.confirmCharacter(
      manuscriptId: manuscriptId,
      name: '阿禾',
      attribute: '职业',
      value: '捕快',
    );

    final assertions = await loadCharacter('阿禾');
    expect(assertions.length, 1);
    expect(assertions.first.status, 'confirmed');
    expect(assertions.first.evidence, isNull);
  });

  test('#2 reject：pending → rejected + 拒绝理由', () async {
    await charRepo.upsertCharacter(
      manuscriptId: manuscriptId,
      name: '阿禾',
      assertions: [pendingAssertion(attribute: '职业', value: '捕快')],
    );

    await service.rejectCharacter(
      manuscriptId: manuscriptId,
      name: '阿禾',
      attribute: '职业',
      value: '捕快',
      reason: '抽取错误',
    );

    final assertions = await loadCharacter('阿禾');
    expect(assertions.first.status, 'rejected');
    expect(assertions.first.rejectReason, '抽取错误');
  });

  test('#3 supersede：标记被取代（留库不进列表）', () async {
    await charRepo.upsertCharacter(
      manuscriptId: manuscriptId,
      name: '阿禾',
      assertions: [pendingAssertion(attribute: '职业', value: '捕快')],
    );

    await service.supersedeCharacter(
      manuscriptId: manuscriptId,
      name: '阿禾',
      attribute: '职业',
      value: '捕快',
    );

    final assertions = await loadCharacter('阿禾');
    expect(assertions.first.status, 'superseded');
  });

  test('#4 只改被裁决的那条：同属性异值另一条不受影响', () async {
    await charRepo.upsertCharacter(
      manuscriptId: manuscriptId,
      name: '阿禾',
      assertions: [
        pendingAssertion(attribute: '职业', value: '捕快'),
        pendingAssertion(attribute: '性格', value: '冷静'),
      ],
    );

    await service.confirmCharacter(
      manuscriptId: manuscriptId,
      name: '阿禾',
      attribute: '职业',
      value: '捕快',
    );

    final assertions = await loadCharacter('阿禾');
    final job = assertions.singleWhere((a) => a.attribute == '职业');
    final trait = assertions.singleWhere((a) => a.attribute == '性格');
    expect(job.status, 'confirmed');
    expect(trait.status, 'pending', reason: '未被裁决的断言必须原样保留');
  });

  test('#5 resolveConflict keepA：A confirmed、B superseded', () async {
    await charRepo.upsertCharacter(
      manuscriptId: manuscriptId,
      name: '阿禾',
      assertions: [
        pendingAssertion(attribute: '职业', value: '捕快'),
        pendingAssertion(attribute: '职业', value: '郎中'),
      ],
    );

    final before = await loadCharacter('阿禾');
    final a = before.firstWhere((x) => x.value == '捕快');
    final b = before.firstWhere((x) => x.value == '郎中');

    await service.resolveCharacterConflict(
      manuscriptId: manuscriptId,
      name: '阿禾',
      attribute: '职业',
      a: a,
      b: b,
      verdict: MergeVerdict.keepA,
    );

    final after = await loadCharacter('阿禾');
    expect(after.length, 2);
    expect(after.firstWhere((x) => x.value == '捕快').status, 'confirmed');
    expect(after.firstWhere((x) => x.value == '郎中').status, 'superseded');
  });

  test('#6 resolveConflict keepB：A superseded、B confirmed', () async {
    await charRepo.upsertCharacter(
      manuscriptId: manuscriptId,
      name: '阿禾',
      assertions: [
        pendingAssertion(attribute: '职业', value: '捕快'),
        pendingAssertion(attribute: '职业', value: '郎中'),
      ],
    );

    final before = await loadCharacter('阿禾');
    final a = before.firstWhere((x) => x.value == '捕快');
    final b = before.firstWhere((x) => x.value == '郎中');

    await service.resolveCharacterConflict(
      manuscriptId: manuscriptId,
      name: '阿禾',
      attribute: '职业',
      a: a,
      b: b,
      verdict: MergeVerdict.keepB,
    );

    final after = await loadCharacter('阿禾');
    expect(after.firstWhere((x) => x.value == '捕快').status, 'superseded');
    expect(after.firstWhere((x) => x.value == '郎中').status, 'confirmed');
  });

  test('#7 resolveConflict keepBoth：两值都 confirmed', () async {
    await charRepo.upsertCharacter(
      manuscriptId: manuscriptId,
      name: '阿禾',
      assertions: [
        pendingAssertion(attribute: '职业', value: '捕快'),
        pendingAssertion(attribute: '职业', value: '郎中'),
      ],
    );

    final before = await loadCharacter('阿禾');
    final a = before.firstWhere((x) => x.value == '捕快');
    final b = before.firstWhere((x) => x.value == '郎中');

    await service.resolveCharacterConflict(
      manuscriptId: manuscriptId,
      name: '阿禾',
      attribute: '职业',
      a: a,
      b: b,
      verdict: MergeVerdict.keepBoth,
    );

    final after = await loadCharacter('阿禾');
    expect(after.length, 2);
    expect(
      after.every((x) => x.status == 'confirmed'),
      isTrue,
      reason: 'keepBoth：两值都保留为已确认',
    );
  });

  test('#8 人物不存在 → 静默跳过不抛', () async {
    await service.confirmCharacter(
      manuscriptId: manuscriptId,
      name: '不存在的人',
      attribute: '职业',
      value: '捕快',
    );
    // 不应抛；无行可改，静默成功
  });

  test('#9 世界观侧 confirm/reject 同构生效', () async {
    await worldRepo.upsertWorld(
      manuscriptId: manuscriptId,
      name: '大梁王朝',
      assertions: [pendingAssertion(attribute: '政体', value: '郡县制')],
    );

    await service.rejectWorld(
      manuscriptId: manuscriptId,
      name: '大梁王朝',
      attribute: '政体',
      value: '郡县制',
      reason: '设定冲突',
    );

    final row = await worldRepo.getWorld(manuscriptId, '大梁王朝');
    final assertions = WorldFactRepository.parseAssertions(row!.assertions);
    expect(assertions.first.status, 'rejected');
    expect(assertions.first.rejectReason, '设定冲突');
  });

  // ── A5（ADR-C107）：裁决精确化 —— 拒绝 AI 的 pending 不得连带改写同 (属性,值)
  // 其他章节/不同时间戳的已确认断言（R-009 越权，单向不可撤）。
  test('#10 A5：拒绝 pending 不连带同 (属性,值) 异章/异戳的 user 已确认断言', () async {
    // 用户手写已确认（source=user，chapter 与 AI 抽取不同，timestamp 更晚）
    final userWritten = CharacterAssertion(
      attribute: '职业',
      value: '捕快',
      chapter: null,
      chapterSortOrder: 1,
      timestamp: 5000,
      status: 'confirmed',
      source: 'user',
    );
    // AI 在第 3 章抽到的同值 pending
    final aiPending = CharacterAssertion(
      attribute: '职业',
      value: '捕快',
      chapter: 3,
      chapterSortOrder: 3,
      timestamp: 1000,
      status: 'pending',
      source: 'ai',
    );
    await charRepo.upsertCharacter(
      manuscriptId: manuscriptId,
      name: '阿禾',
      assertions: [userWritten, aiPending],
    );

    // 用户只在确认卡里拒绝 AI 那条（传入 target = AI pending 本身）
    await service.rejectCharacter(
      manuscriptId: manuscriptId,
      name: '阿禾',
      attribute: '职业',
      value: '捕快',
      reason: '抽取错误',
      target: aiPending,
    );

    final after = await loadCharacter('阿禾');
    final rejected = after.singleWhere((a) => a.timestamp == 1000);
    final kept = after.singleWhere((a) => a.timestamp == 5000);
    expect(rejected.status, 'rejected', reason: 'AI pending 被用户拒绝');
    expect(
      kept.status,
      'confirmed',
      reason: '用户手写的同值已确认断言**不得**被连带改成 rejected',
    );
    expect(kept.source, 'user');
  });

  test('#11 A5：confirm 同样按 target 精确定位（不连带另一条同值断言）', () async {
    final a1 = CharacterAssertion(
      attribute: '出身',
      value: '临安',
      chapter: 3,
      chapterSortOrder: 3,
      timestamp: 1000,
      status: 'pending',
    );
    final a2 = CharacterAssertion(
      attribute: '出身',
      value: '临安',
      chapter: 7,
      chapterSortOrder: 7,
      timestamp: 2000,
      status: 'pending',
    );
    await charRepo.upsertCharacter(
      manuscriptId: manuscriptId,
      name: '阿禾',
      assertions: [a1, a2],
    );

    await service.confirmCharacter(
      manuscriptId: manuscriptId,
      name: '阿禾',
      attribute: '出身',
      value: '临安',
      target: a1,
    );

    final after = await loadCharacter('阿禾');
    expect(after.singleWhere((a) => a.timestamp == 1000).status, 'confirmed');
    expect(
      after.singleWhere((a) => a.timestamp == 2000).status,
      'pending',
      reason: '只确认 target 那条，另一条同值不同章仍待裁决',
    );
  });
}
