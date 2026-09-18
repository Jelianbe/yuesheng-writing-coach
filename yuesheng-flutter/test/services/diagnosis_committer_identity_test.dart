// ─────────────────────────────────────────────────────────────
// diagnosis_committer_identity_test — N12-F3b：三处写入点填「身份」(`ADR-C96` 裁定 1/2)
//
// 这是 `ADR-C96 §5` 判据 1–4 在**写入侧**的端到端取证：AI 抽取块经
// `applyFactExtractionFromContent` 落库后，三张表都应同时具备
//   · 旧载体（`chapter` / `introduced_chapter` / `resolved_chapter`）= **AI 原值**（`R1′`）
//   · 新载体（`chapterSortOrder` / `*_sort_order`）= 解析出的**身份键**
//
// 场景固定为「默认标题 3 章（身份 0/1/2 ↔ 标称号 1/2/3 ↔ 序位 1/2/3），诊断**第 3 章**」。
// 该场景下三种编码在**当前章**上同值 ⇒ 既能验证「当前章优先」生效，
// 又能验证真跨章引用（报 1）不会被吞成当前章（杀死 R4）。
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/chapter_repository.dart';
import 'package:writingcoach/data/repositories/character_fact_repository.dart';
import 'package:writingcoach/data/repositories/diagnosis_repository.dart';
import 'package:writingcoach/data/repositories/event_fact_repository.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/data/repositories/reference_repository.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/data/repositories/student_model_repository.dart';
import 'package:writingcoach/data/repositories/subplot_fact_repository.dart';
import 'package:writingcoach/data/repositories/teaching_state_repository.dart';
import 'package:writingcoach/services/diagnosis_committer.dart';

/// AI 抽取块：刻意把三种情形一次走完（本章号 / 跨章号 / 无号 / 不存在的号）。
String extractionBody() {
  return '[YS_FACT]{'
      '"characters":[{"name":"林晚","assertions":['
      '{"attribute":"性格","value":"外冷内热","chapter":3},'
      '{"attribute":"身世","value":"灵修世家","chapter":1},'
      '{"attribute":"习惯","value":"夜巡"}'
      ']}],'
      '"events":['
      '{"name":"跨章伏笔","event_type":"转折","chapter":99,"description":"边界值"},'
      '{"name":"本章事件","event_type":"日常","chapter":3,"description":"本章"}'
      '],'
      '"subplots":['
      '{"name":"钥匙的秘密","introduced_chapter":99,"description":"边界值"},'
      '{"name":"妹妹的身世","introduced_chapter":3,"resolved_chapter":1,'
      '"description":"跨章回收"}'
      ']}[/YS_FACT]';
}

void main() {
  late AppDatabase db;
  late String sessionId;
  late String manuscriptId;
  late String chapter3Id;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    sessionId = await SessionRepository(db).createBlankSession();

    manuscriptId = await ManuscriptRepository(
      db,
    ).createManuscript(title: '身份锚点稿', genre: '小说');
    final chRepo = ChapterRepository(db);
    // 默认标题 + 自动 sortOrder ⇒ 身份 0/1/2 ↔ 标称号 1/2/3 ↔ 序位 1/2/3
    await chRepo.createChapter(manuscriptId, title: '第1章', content: '开篇。');
    await chRepo.createChapter(manuscriptId, title: '第2章', content: '承接。');
    chapter3Id = await chRepo.createChapter(
      manuscriptId,
      title: '第3章',
      content: '林晚握紧了刀柄。',
    );
  });

  tearDown(() async => db.close());

  Future<void> commit() async {
    await ReferenceRepository(
      db,
    ).addReference(sessionId, 'chapter', chapter3Id, isPrimary: true);
    final result =
        await DiagnosisCommitter(
          sessionRepo: SessionRepository(db),
          stateRepo: TeachingStateRepository(db),
          diagnosisRepo: DiagnosisRepository(db),
          studentModelRepo: StudentModelRepository(db),
          referenceRepo: ReferenceRepository(db),
          chapterRepo: ChapterRepository(db),
          db: db,
          characterFactRepo: CharacterFactRepository(db),
          eventFactRepo: EventFactRepository(db),
          subplotFactRepo: SubplotFactRepository(db),
        ).applyFactExtractionFromContent(
          sessionId: sessionId,
          fullContent: extractionBody(),
        );
    expect(result.count, 3, reason: '三条 AI 断言都应落库');
  }

  test('#I1 人物断言：身份另存，AI 原值逐字保留（§5 判据 1/2/3）', () async {
    await commit();
    final row = await CharacterFactRepository(
      db,
    ).getCharacter(manuscriptId, '林晚');
    final assertions = CharacterFactRepository.parseAssertions(row!.assertions);

    // 判据 1：AI 报 3、当前章就是第 3 章 ⇒ 身份 2
    final current = assertions.singleWhere((a) => a.attribute == '性格');
    expect(current.chapter, 3, reason: 'R1′：AI 原值原样保留');
    expect(current.chapterSortOrder, 2);
    expect(current.chapterIdentity, 2);

    // 判据 2（杀死 R4）：AI 报 1 = 第 1 章 ⇒ 身份 0，**不是**当前章 2
    final cross = assertions.singleWhere((a) => a.attribute == '身世');
    expect(cross.chapter, 1);
    expect(cross.chapterSortOrder, 0, reason: 'R4（恒取当前章）会给 2');

    // 判据 3 的前置：AI 未给号 ⇒ 当前章身份（与同行 chapter_hash 的假设一致）
    final noChapter = assertions.singleWhere((a) => a.attribute == '习惯');
    expect(noChapter.chapter, isNull, reason: 'AI 没给 ⇒ 旧载体保持空，不代它填');
    expect(noChapter.chapterSortOrder, 2);

    // AI 落库仍走 pending（本条不改变既有裁决语义）
    expect(current.status, 'pending');
  });

  test('#I2 事件：chapter 保留原值 99，身份落 2（§5 判据 3）', () async {
    await commit();
    final repo = EventFactRepository(db);

    final cross = await repo.getEvent(manuscriptId, '跨章伏笔');
    expect(cross!.chapter, 99, reason: 'R1′：AI 原值原样保留');
    expect(
      cross.chapterSortOrder,
      2,
      reason: 'AI 报无此章 ⇒ 兜底当前章（**不得**落 NULL，否则事件丢锚点）',
    );

    final same = await repo.getEvent(manuscriptId, '本章事件');
    expect(same!.chapter, 3);
    expect(same.chapterSortOrder, 2);
  });

  test('#I3 支线：引入/回收两侧各自填身份，未回收侧仍为 NULL', () async {
    await commit();
    final repo = SubplotFactRepository(db);

    final oob = await repo.getSubplot(manuscriptId, '钥匙的秘密');
    expect(oob!.introducedChapter, 99, reason: 'R1′：AI 原值原样保留');
    expect(oob.introducedChapterSortOrder, 2, reason: '兜底当前章，detector 才不会跳过它');
    expect(oob.resolvedChapter, isNull);
    expect(
      oob.resolvedChapterSortOrder,
      isNull,
      reason: '未回收必须保持 NULL —— 若映射成当前章，detector 会以为「本章已回收」而跳过',
    );

    final resolved = await repo.getSubplot(manuscriptId, '妹妹的身世');
    expect(resolved!.introducedChapter, 3);
    expect(resolved.introducedChapterSortOrder, 2);
    expect(resolved.resolvedChapter, 1);
    expect(resolved.resolvedChapterSortOrder, 0, reason: '回收侧同样是身份（第 1 章 ⇒ 0）');
  });
}
