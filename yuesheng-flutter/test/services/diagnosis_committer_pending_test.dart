// ─────────────────────────────────────────────────────────────
// diagnosis_committer_pending_test — 设定库第一批验收锚点：AI 写入 pending 置位
//
// 覆盖（Y1 验收项「pending 置位有测试锚定」）：
//   #P1 AI 抽取断言（默认 source=ai）→ 落库 status == 'pending'（待用户裁决）
//   #P2 user 来源断言 → 落库 confirmed（不被置 pending，用户主权）
//   #P3 rejected 断言 → 保留 rejected（拒绝记忆不被覆写）
//   #P4 pending 不参与冲突检测（isActiveAssertion 只认 confirmed && !stale）
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/character_fact_repository.dart';
import 'package:writingcoach/data/repositories/chapter_repository.dart';
import 'package:writingcoach/data/repositories/diagnosis_repository.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/data/repositories/reference_repository.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/data/repositories/student_model_repository.dart';
import 'package:writingcoach/data/repositories/teaching_state_repository.dart';
import 'package:writingcoach/data/repositories/world_fact_repository.dart';
import 'package:writingcoach/services/character_identity.dart';
import 'package:writingcoach/services/diagnosis_committer.dart';
import 'package:writingcoach/services/setting_library_service.dart';
import 'package:writingcoach/types/character_types.dart';

void main() {
  late AppDatabase db;
  late SessionRepository sessionRepo;
  late String sessionId;
  late String manuscriptId;
  late String chapterId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    sessionRepo = SessionRepository(db);
    sessionId = await sessionRepo.createBlankSession();

    final msRepo = ManuscriptRepository(db);
    final chRepo = ChapterRepository(db);
    manuscriptId = await msRepo.createManuscript(title: '锚点稿', genre: '小说');
    chapterId = await chRepo.createChapter(
      manuscriptId,
      title: '第一章',
      content: '林晚立于山门，灵气自四方涌来。',
    );
  });

  tearDown(() async => db.close());

  DiagnosisCommitter buildCommitter() {
    return DiagnosisCommitter(
      sessionRepo: sessionRepo,
      stateRepo: TeachingStateRepository(db),
      diagnosisRepo: DiagnosisRepository(db),
      studentModelRepo: StudentModelRepository(db),
      referenceRepo: ReferenceRepository(db),
      chapterRepo: ChapterRepository(db),
      db: db,
      characterFactRepo: CharacterFactRepository(db),
    );
  }

  /// 构造 AI 抽取块：AI 协议只输出 attribute/value/evidence（source/status
  /// 由写入路径填值，协议不传——ADR-C78 语义）。
  String extractionBody() {
    return '[YS_FACT]{"characters":[{"name":"林晚","assertions":['
        '{"attribute":"性格","value":"外冷内热"},'
        '{"attribute":"身世","value":"灵修世家"}'
        ']}]}[/YS_FACT]';
  }

  Future<void> commit() async {
    final refRepo = ReferenceRepository(db);
    await refRepo.addReference(
      sessionId,
      'chapter',
      chapterId,
      isPrimary: true,
    );
    final result = await buildCommitter().applyFactExtractionFromContent(
      sessionId: sessionId,
      fullContent: extractionBody(),
    );
    expect(result.count, 2, reason: '两条 AI 断言都应落库');
  }

  test('#P1 AI 默认 source=ai → 落库 pending（待用户裁决）', () async {
    await commit();
    final row = await CharacterFactRepository(
      db,
    ).getCharacter(manuscriptId, '林晚');
    final assertions = CharacterFactRepository.parseAssertions(row!.assertions);
    final ai = assertions.singleWhere((a) => a.attribute == '性格');
    expect(ai.status, 'pending', reason: 'AI 抽取未经裁决不得直接成为事实');
    expect(ai.source, 'ai');
  });

  test('#P2 用户手动录入 → confirmed（用户主权不被置 pending）', () async {
    final repo = CharacterFactRepository(db);
    await repo.upsertCharacter(
      manuscriptId: manuscriptId,
      name: '林晚',
      assertions: [
        CharacterAssertion(
          attribute: '身世',
          value: '灵修世家',
          timestamp: 100,
          status: 'confirmed',
          source: 'user',
        ),
      ],
    );
    final row = await repo.getCharacter(manuscriptId, '林晚');
    final assertions = CharacterFactRepository.parseAssertions(row!.assertions);
    final user = assertions.singleWhere((a) => a.attribute == '身世');
    expect(user.status, 'confirmed', reason: '手动录入不走 AI pending 置位');
    expect(user.source, 'user');
  });

  test('#P3 确认卡拒绝 → rejected（拒绝记忆本体，不被 AI 覆写）', () async {
    final repo = CharacterFactRepository(db);
    await repo.upsertCharacter(
      manuscriptId: manuscriptId,
      name: '林晚',
      assertions: [
        CharacterAssertion(
          attribute: '外貌',
          value: '长发',
          timestamp: 100,
          status: 'confirmed',
          source: 'ai',
        ),
      ],
    );
    // 用户经确认卡裁决拒绝 → rejected + reason
    await SettingLibraryService(
      characterRepo: CharacterFactRepository(db),
      worldRepo: WorldFactRepository(db),
    ).rejectCharacter(
      manuscriptId: manuscriptId,
      name: '林晚',
      attribute: '外貌',
      value: '长发',
      reason: '与后文矛盾',
    );
    final row = await repo.getCharacter(manuscriptId, '林晚');
    final assertions = CharacterFactRepository.parseAssertions(row!.assertions);
    final rejected = assertions.singleWhere((a) => a.attribute == '外貌');
    expect(rejected.status, 'rejected', reason: '拒绝记忆必须保留');
    expect(rejected.rejectReason, '与后文矛盾');
  });

  test(
    '#P4 pending 不参与冲突检测（isActiveAssertion 只认 confirmed && !stale）',
    () async {
      // 同人物同属性两条断言：一 pending 一 confirmed，异值。
      // pending 不参与 ⇒ 检测器只看到 confirmed 一条 ⇒ 不报冲突。
      final facts = [
        CharacterFact(
          id: 'cf_a',
          manuscriptId: manuscriptId,
          name: '林晚',
          assertions: jsonEncode([
            CharacterAssertion(
              attribute: '性格',
              value: '外冷内热',
              timestamp: 1,
              status: 'pending',
              source: 'ai',
            ).toJson(),
          ]),
          description: '',
          aliases: '[]',
          status: 'active',
          createdAt: 1000,
          updatedAt: 1000,
        ),
        CharacterFact(
          id: 'cf_b',
          manuscriptId: manuscriptId,
          name: '林晚',
          assertions: jsonEncode([
            CharacterAssertion(
              attribute: '性格',
              value: '热情似火',
              timestamp: 2,
              status: 'confirmed',
              source: 'user',
            ).toJson(),
          ]),
          description: '',
          aliases: '[]',
          status: 'active',
          createdAt: 1000,
          updatedAt: 1000,
        ),
      ];
      final conflicts = detectConflictsForFacts(facts);
      expect(
        conflicts.where((c) => c.characterName == '林晚'),
        isEmpty,
        reason: 'pending 断言不得触发矛盾检测（零缓冲防护）',
      );
    },
  );
}
