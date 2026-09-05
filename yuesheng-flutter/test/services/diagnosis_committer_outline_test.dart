// diagnosis_committer_outline_test — applyOutlineEntitiesFromContent 直接测试
//
// R-019 批次八补测：覆盖 K-4 大纲实体落库 + 确认卡写入的关键路径。
//   #O1 章节主引用 + [YS_ENTITY] 块 → 实体落库 + outline_confirmation 卡片
//   #O2 非 chapter 主引用 → 静默跳过（不落库）
//   #O3 无大纲块 → 静默跳过
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/chapter_repository.dart';
import 'package:writingcoach/data/repositories/diagnosis_repository.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/data/repositories/outline_repository.dart';
import 'package:writingcoach/data/repositories/reference_repository.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/data/repositories/student_model_repository.dart';
import 'package:writingcoach/data/repositories/teaching_state_repository.dart';
import 'package:writingcoach/services/diagnosis_committer.dart';

void main() {
  late AppDatabase db;
  late SessionRepository sessionRepo;
  late OutlineRepository outlineRepo;
  late String sessionId;
  late String manuscriptId;
  late String chapterId;

  const kOutlineBody =
      '[YS_ENTITY]{"entities":[{"type":"character","key":"王建国",'
      '"aliases":["建国"],"impressions":[{"text":"攥紧拳头，是来复仇的"}]}]}[/YS_ENTITY]';

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    sessionRepo = SessionRepository(db);
    outlineRepo = OutlineRepository(db);
    sessionId = await sessionRepo.createBlankSession();

    final msRepo = ManuscriptRepository(db);
    final chRepo = ChapterRepository(db);
    manuscriptId = await msRepo.createManuscript(title: '大纲稿', genre: '小说');
    chapterId = await chRepo.createChapter(
      manuscriptId,
      title: '第一章',
      content: '王建国站在巷口，夜色沉沉。',
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
      outlineRepo: outlineRepo,
    );
  }

  test('#O1 章节主引用 + 大纲块 → 实体落库 + 确认卡', () async {
    final refRepo = ReferenceRepository(db);
    final chRepo = ChapterRepository(db);
    await refRepo.addReference(
      sessionId,
      'chapter',
      chapterId,
      isPrimary: true,
    );

    await buildCommitter().applyOutlineEntitiesFromContent(
      sessionId: sessionId,
      fullContent: kOutlineBody,
    );

    final entities = await outlineRepo.listEntities(manuscriptId);
    expect(entities, hasLength(1));
    expect(entities.single.entityKey, '王建国');

    final cards = await (db.select(
      db.messages,
    )..where((t) => t.messageType.equals('outline_confirmation'))).get();
    expect(cards, hasLength(1));
  });

  test('#O2 非 chapter 主引用 → 静默跳过（不落库）', () async {
    final refRepo = ReferenceRepository(db);
    await refRepo.addReference(
      sessionId,
      'manuscript',
      manuscriptId,
      isPrimary: true,
    );

    await buildCommitter().applyOutlineEntitiesFromContent(
      sessionId: sessionId,
      fullContent: kOutlineBody,
    );

    final entities = await outlineRepo.listEntities(manuscriptId);
    expect(entities, isEmpty, reason: '非章节主引用应静默跳过');
  });

  test('#O4 空 entities 数组 → 静默跳过（不落库不写卡）', () async {
    final refRepo = ReferenceRepository(db);
    await refRepo.addReference(
      sessionId,
      'chapter',
      chapterId,
      isPrimary: true,
    );

    await buildCommitter().applyOutlineEntitiesFromContent(
      sessionId: sessionId,
      fullContent: '[YS_ENTITY]{"entities":[]}[/YS_ENTITY]',
    );

    final entities = await outlineRepo.listEntities(manuscriptId);
    expect(entities, isEmpty);
    final cards = await (db.select(
      db.messages,
    )..where((t) => t.messageType.equals('outline_confirmation'))).get();
    expect(cards, isEmpty);
  });

  test('#O4 空 entities 数组 → 静默跳过（不落库不写卡）', () async {
    final refRepo = ReferenceRepository(db);
    await refRepo.addReference(
      sessionId,
      'chapter',
      chapterId,
      isPrimary: true,
    );

    await buildCommitter().applyOutlineEntitiesFromContent(
      sessionId: sessionId,
      fullContent: '[YS_ENTITY]{"entities":[]}[/YS_ENTITY]',
    );

    final entities = await outlineRepo.listEntities(manuscriptId);
    expect(entities, isEmpty);
    final cards = await (db.select(
      db.messages,
    )..where((t) => t.messageType.equals('outline_confirmation'))).get();
    expect(cards, isEmpty);
  });
  test('#O3 无大纲块 → 静默跳过', () async {
    final refRepo = ReferenceRepository(db);
    final chRepo = ChapterRepository(db);
    await refRepo.addReference(
      sessionId,
      'chapter',
      chapterId,
      isPrimary: true,
    );

    await buildCommitter().applyOutlineEntitiesFromContent(
      sessionId: sessionId,
      fullContent: '纯文本回复，没有协议块',
    );

    final entities = await outlineRepo.listEntities(manuscriptId);
    expect(entities, isEmpty);
  });
}
