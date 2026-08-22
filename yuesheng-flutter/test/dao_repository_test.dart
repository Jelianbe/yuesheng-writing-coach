// ─────────────────────────────────────────────────────────────
// DAO Repository 单元测试
// 使用内存数据库，验证 7 个 repository 的增查改删
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/database/utils.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/data/repositories/chapter_repository.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/data/repositories/diagnosis_repository.dart';
import 'package:writingcoach/data/repositories/teaching_state_repository.dart';
import 'package:writingcoach/data/repositories/student_model_repository.dart';
import 'package:writingcoach/data/repositories/app_state_repository.dart';
import 'package:writingcoach/data/repositories/error_log_repository.dart';
import 'package:writingcoach/data/repositories/reference_repository.dart';
import 'package:writingcoach/data/repositories/outline_repository.dart';
import 'package:writingcoach/services/outline_service.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  // ════════════════════════════════════════════════════════════
  // 1. ManuscriptRepository
  // ════════════════════════════════════════════════════════════
  group('ManuscriptRepository', () {
    test('创建 + 查询单条', () async {
      final repo = ManuscriptRepository(db);
      final id = await repo.createManuscript(title: '测试稿件', genre: '小说');
      expect(id, isNotEmpty);

      final ms = await repo.getManuscript(id);
      expect(ms, isNotNull);
      expect(ms!.title, '测试稿件');
      expect(ms.genre, '小说');
      expect(ms.status, 'active');
      expect(ms.language, '中文');
    });

    test('列出 active 稿件（软删除的不返回）', () async {
      final repo = ManuscriptRepository(db);
      final id1 = await repo.createManuscript(title: '稿件A');
      await repo.createManuscript(title: '稿件B');
      await repo.deleteManuscript(id1); // 软删除

      final list = await repo.listManuscripts();
      expect(list.length, 1);
      expect(list.first.title, '稿件B');
    });

    test('更新稿件', () async {
      final repo = ManuscriptRepository(db);
      final id = await repo.createManuscript(title: '原标题');
      await repo.updateManuscript(id, title: '新标题', genre: '散文');

      final ms = await repo.getManuscript(id);
      expect(ms!.title, '新标题');
      expect(ms.genre, '散文');
    });

    test('按 sort_order 查询', () async {
      final repo = ManuscriptRepository(db);
      await repo.createManuscript(title: 'A');
      await repo.createManuscript(title: 'B');
      // sortOrder 默认都是 0，getManuscriptByOrder(0) 应返回其中一个
      final ms = await repo.getManuscriptByOrder(0);
      expect(ms, isNotNull);
    });
  });

  // ════════════════════════════════════════════════════════════
  // 2. ChapterRepository
  // ════════════════════════════════════════════════════════════
  group('ChapterRepository', () {
    test('创建 + 列出章节（sort_order 自动递增）', () async {
      final msRepo = ManuscriptRepository(db);
      final chRepo = ChapterRepository(db);
      final msId = await msRepo.createManuscript(title: '作品');

      await chRepo.createChapter(msId, title: '第一章');
      await chRepo.createChapter(msId, title: '第二章');

      final chapters = await chRepo.listChapters(msId);
      expect(chapters.length, 2);
      expect(chapters[0].title, '第一章');
      expect(chapters[0].sortOrder, 0);
      expect(chapters[1].title, '第二章');
      expect(chapters[1].sortOrder, 1);
    });

    test('保存章节内容（同步更新 word_count）', () async {
      final msRepo = ManuscriptRepository(db);
      final chRepo = ChapterRepository(db);
      final msId = await msRepo.createManuscript(title: '作品');
      final chId = await chRepo.createChapter(msId, title: '章节');

      await chRepo.saveChapterContent(chId, '这是章节内容');
      final ch = await chRepo.getChapter(chId);
      expect(ch!.content, '这是章节内容');
      expect(ch.wordCount, 6);
    });

    test('adoptContentToChapter（旧内容备份到 previous_content）', () async {
      final msRepo = ManuscriptRepository(db);
      final chRepo = ChapterRepository(db);
      final msId = await msRepo.createManuscript(title: '作品');
      final chId = await chRepo.createChapter(
        msId,
        title: '章节',
        content: '旧内容',
      );

      await chRepo.adoptContentToChapter(chId, '新内容');
      final ch = await chRepo.getChapter(chId);
      expect(ch!.content, '新内容');
      expect(ch.previousContent, '旧内容');
    });

    // P0 漏洞 3：二次采纳时 previousContent 更新为上一次的 content（契约验证）
    // 设计意图：previousContent 是"上一次采纳前的内容"，撤销时恢复到上一次。
    // 连续两次采纳后，最初的原始内容不再可恢复（由产品决策决定）。
    test('adoptContentToChapter 二次采纳（previousContent 更新为上次 content）', () async {
      final msRepo = ManuscriptRepository(db);
      final chRepo = ChapterRepository(db);
      final msId = await msRepo.createManuscript(title: '作品');
      final chId = await chRepo.createChapter(
        msId,
        title: '章节',
        content: '原始内容',
      );

      // 第一次采纳：previousContent = '原始内容', content = '第一版'
      await chRepo.adoptContentToChapter(chId, '第一版');
      var ch = await chRepo.getChapter(chId);
      expect(ch!.content, '第一版');
      expect(ch.previousContent, '原始内容');

      // 第二次采纳：previousContent = '第一版', content = '第二版'
      await chRepo.adoptContentToChapter(chId, '第二版');
      ch = await chRepo.getChapter(chId);
      expect(ch!.content, '第二版');
      expect(ch.previousContent, '第一版'); // 不再是'原始内容'
    });

    test('批量创建章节', () async {
      final msRepo = ManuscriptRepository(db);
      final chRepo = ChapterRepository(db);
      final msId = await msRepo.createManuscript(title: '作品');

      final count = await chRepo.createChaptersBatch(msId, [
        (title: '第一章', content: '内容1'),
        (title: '第二章', content: '内容2'),
        (title: '第三章', content: '内容3'),
      ]);
      expect(count, 3);

      final chapters = await chRepo.listChapters(msId);
      expect(chapters.length, 3);
      expect(chapters[2].sortOrder, 2);
    });
  });

  // ════════════════════════════════════════════════════════════
  // 3. SessionRepository
  // ════════════════════════════════════════════════════════════
  group('SessionRepository', () {
    test('创建空白会话（同步创建 teaching_state）', () async {
      final repo = SessionRepository(db);
      final sessionId = await repo.createBlankSession(title: '测试会话');

      final sessions = await repo.listSessions();
      expect(sessions.length, 1);
      expect(sessions.first.title, '测试会话');

      // teaching_state 应同步创建
      final tsRepo = TeachingStateRepository(db);
      final state = await tsRepo.getTeachingState(sessionId);
      expect(state, isNotNull);
      expect(state!.currentPhase, 'P0_ENGAGE');
    });

    test('getOrCreateSessionForManuscript（复用现有会话）', () async {
      final msRepo = ManuscriptRepository(db);
      final sesRepo = SessionRepository(db);
      final msId = await msRepo.createManuscript(title: '作品');

      final s1 = await sesRepo.getOrCreateSessionForManuscript(msId);
      final s2 = await sesRepo.getOrCreateSessionForManuscript(msId);
      expect(s1, s2); // 应复用同一会话
    });

    test('addMessage + listMessages（chat 类型更新 preview）', () async {
      final sesRepo = SessionRepository(db);
      final sessionId = await sesRepo.createBlankSession();

      await sesRepo.addMessage(sessionId, 'user', '你好，这是测试消息');
      await sesRepo.addMessage(
        sessionId,
        'assistant',
        '收到',
        messageType: 'diagnosis_result',
      );

      final messages = await sesRepo.listMessages(sessionId);
      expect(messages.length, 2);
      expect(messages[0].role, 'user');
      expect(messages[1].role, 'assistant');

      // preview 应只有第一条 chat 消息的内容
      final sessions = await sesRepo.listSessions();
      expect(sessions.first.preview, '你好，这是测试消息');
    });

    test('批次71：addMessage 携带 referencesJson → 读回一致', () async {
      final sesRepo = SessionRepository(db);
      final sessionId = await sesRepo.createBlankSession();

      const refsJson =
          '[{"refType":"chapter","refId":"c1","manuscriptId":"m1","title":"我的小说 · 第三章"}]';
      await sesRepo.addMessage(
        sessionId,
        'user',
        '帮我看看这一章',
        referencesJson: refsJson,
      );

      final messages = await sesRepo.listMessages(sessionId);
      expect(messages.length, 1);
      expect(messages.first.referencesJson, refsJson);
    });

    test('批次71：不传 referencesJson → 读回为 null', () async {
      final sesRepo = SessionRepository(db);
      final sessionId = await sesRepo.createBlankSession();

      await sesRepo.addMessage(sessionId, 'user', '普通消息');
      final messages = await sesRepo.listMessages(sessionId);
      expect(messages.first.referencesJson, isNull);
    });

    test('deleteMessage', () async {
      final sesRepo = SessionRepository(db);
      final sessionId = await sesRepo.createBlankSession();
      final msgId = await sesRepo.addMessage(sessionId, 'user', '测试');

      await sesRepo.deleteMessage(sessionId, msgId);
      final messages = await sesRepo.listMessages(sessionId);
      expect(messages, isEmpty);
    });

    test('批次73：deleteSession 级联清理会话相关数据', () async {
      final sesRepo = SessionRepository(db);
      final msRepo = ManuscriptRepository(db);
      final chRepo = ChapterRepository(db);
      final refRepo = ReferenceRepository(db);
      final appStateRepo = AppStateRepository(db);
      final tsRepo = TeachingStateRepository(db);
      final smRepo = StudentModelRepository(db);

      final msId = await msRepo.createManuscript(title: '作品');
      final chId = await chRepo.createChapter(
        msId,
        title: '第一章',
        content: '正文',
        sortOrder: 0,
      );
      final sId = await sesRepo.createBlankSession(title: '待删会话');
      await sesRepo.addMessage(sId, 'user', '消息A');
      await sesRepo.addMessage(sId, 'assistant', '消息B');
      await refRepo.addReference(sId, 'chapter', chId, isPrimary: true);
      await tsRepo.updatePhase(sId, 'P1_WORLD'); // teaching_state 已随建会话创建
      await appStateRepo.setValue('eval_round:$sId', '3');
      await appStateRepo.setValue('eval_report:$sId:any', '{}');
      await smRepo.appendTeachingHistory(sId, {'type': 'diagnosis'});

      // 删除前数据齐全
      expect(await sesRepo.listMessages(sId), hasLength(2));

      await sesRepo.deleteSession(sId);

      // 会话本体 + 级联（messages/diagnosis_results/teaching_state/
      // active_problem/session_reference 走 FK CASCADE）
      expect(await sesRepo.listSessions(), isEmpty);
      expect(await sesRepo.listMessages(sId), isEmpty);
      expect(await refRepo.listReferencesOfSession(sId), isEmpty);
      expect(await tsRepo.getTeachingState(sId), isNull);
      // app_state 孤儿 KV 手动清理（无外键）
      expect(await appStateRepo.getValue('eval_round:$sId'), isNull);
      expect(await appStateRepo.getValue('eval_report:$sId:any'), isNull);
      // student_model 按会话存储、无级联且 session_id NOT NULL（SET NULL 会违反
      // 约束）——deleteSession 显式删除该会话的画像行
      expect(await db.select(db.studentModels).get(), isEmpty);
    });

    test('listRelatedSessions（章节/作品会话 + 本书引用命中，无关会话排除，活跃度排序）', () async {
      final msRepo = ManuscriptRepository(db);
      final chRepo = ChapterRepository(db);
      final sesRepo = SessionRepository(db);
      final refRepo = ReferenceRepository(db);

      final bookA = await msRepo.createManuscript(title: '作品A');
      final bookB = await msRepo.createManuscript(title: '作品B');
      final ch1 = await chRepo.createChapter(bookA, title: '章节1');

      // 1. 章节级会话（getOrCreateSessionForChapter → chapter 引用 + manuscript 缓存）
      final sChapter = await sesRepo.getOrCreateSessionForChapter(bookA, ch1);
      // 2. ChatPage @ 引用本书章节的会话（session_reference 手动添加）
      final sRef = await sesRepo.createBlankSession(title: '对话');
      await refRepo.addReference(sRef, 'chapter', ch1);
      // 3. ChatPage @ 引用本书的会话（session_reference 手动添加）
      final sManuRef = await sesRepo.createBlankSession(title: '本书对话');
      await refRepo.addReference(sManuRef, 'manuscript', bookA);
      // 4. 无关会话（bookB 的会话 + 孤立会话）
      final sBookB = await sesRepo.getOrCreateSessionForManuscript(bookB);
      final sOrphan = await sesRepo.createBlankSession(title: '孤立');

      // 拉开活跃度差距：sChapter/sRef 置旧，sManuRef 保持最新 → 排序可断言
      await (db.update(db.sessions)..where((t) => t.id.isIn({sChapter, sRef})))
          .write(SessionsCompanion(updatedAt: const Value(100)));

      final related = await sesRepo.listRelatedSessions(bookA);
      final ids = related.map((e) => e.session.id).toSet();
      expect(ids, contains(sChapter));
      expect(ids, contains(sRef));
      expect(ids, contains(sManuRef));
      expect(ids, isNot(contains(sBookB)));
      expect(ids, isNot(contains(sOrphan)));
      // 活跃度排序：sManuRef 最新 → 第一位
      expect(related.first.session.id, sManuRef);
    });

    test('listRelatedSessions（手动引用章节命中）', () async {
      final msRepo = ManuscriptRepository(db);
      final chRepo = ChapterRepository(db);
      final sesRepo = SessionRepository(db);
      final refRepo = ReferenceRepository(db);

      final bookA = await msRepo.createManuscript(title: '作品A');
      final ch1 = await chRepo.createChapter(bookA, title: '章节1');
      final s1 = await sesRepo.createBlankSession(title: '章节对话');
      await refRepo.addReference(s1, 'chapter', ch1);

      final related = await sesRepo.listRelatedSessions(bookA);
      expect(related.map((e) => e.session.id), contains(s1));
    });

    test('listRelatedSessions（无关联 → 空列表）', () async {
      final msRepo = ManuscriptRepository(db);
      final sesRepo = SessionRepository(db);
      final bookA = await msRepo.createManuscript(title: '作品A');
      await sesRepo.createBlankSession(title: '无关对话');

      final related = await sesRepo.listRelatedSessions(bookA);
      expect(related, isEmpty);
    });
  });

  // ════════════════════════════════════════════════════════════
  // 4. DiagnosisRepository
  // ════════════════════════════════════════════════════════════
  group('DiagnosisRepository', () {
    test('commitDiagnosis + getLatestDiagnosis', () async {
      final sesRepo = SessionRepository(db);
      final diagRepo = DiagnosisRepository(db);
      final sessionId = await sesRepo.createBlankSession();
      final msgId = await sesRepo.addMessage(sessionId, 'assistant', '诊断结果');

      final diagId = await diagRepo.commitDiagnosis(
        DiagnosisInput(
          sessionId: sessionId,
          messageId: msgId,
          syndromes: [
            {
              'syndrome_id': 's1',
              'name': '症候A',
              'severity': 'L2',
              'evidence': [],
              'explanation': '',
            },
          ],
          suggestedActions: ['建议1', '建议2'],
          confidence: 0.85,
        ),
      );
      expect(diagId, isNotEmpty);

      final latest = await diagRepo.getLatestDiagnosis(sessionId);
      expect(latest, isNotNull);
      expect(latest!.confidence, 0.85);
    });

    test('commitDiagnosis 自动创建 active_problem', () async {
      final sesRepo = SessionRepository(db);
      final diagRepo = DiagnosisRepository(db);
      final sessionId = await sesRepo.createBlankSession();
      final msgId = await sesRepo.addMessage(sessionId, 'assistant', '诊断');

      await diagRepo.commitDiagnosis(
        DiagnosisInput(
          sessionId: sessionId,
          messageId: msgId,
          syndromes: [
            {'syndrome_id': 's1', 'name': '症候A', 'severity': 'L3'},
            {'syndrome_id': 's2', 'name': '症候B', 'severity': 'L1'},
          ],
          suggestedActions: [],
          confidence: 0.5,
        ),
      );

      final problems = await diagRepo.listActiveProblems(sessionId);
      expect(problems.length, 2);
    });

    test('resolveSyndromesBatch（解决症候 + 重算 summary）', () async {
      final sesRepo = SessionRepository(db);
      final diagRepo = DiagnosisRepository(db);
      final sessionId = await sesRepo.createBlankSession();
      final msgId = await sesRepo.addMessage(sessionId, 'assistant', '诊断');

      await diagRepo.commitDiagnosis(
        DiagnosisInput(
          sessionId: sessionId,
          messageId: msgId,
          syndromes: [
            {'syndrome_id': 's1', 'name': '症候A', 'severity': 'L2'},
          ],
          suggestedActions: [],
          confidence: 0.5,
        ),
      );

      final count = await diagRepo.resolveSyndromesBatch(sessionId, ['s1']);
      expect(count, 1);

      final problems = await diagRepo.listActiveProblems(sessionId);
      expect(problems, isEmpty); // 解决后不再出现在 active 列表
    });

    test('confirmDiagnosis + disputeDiagnosis', () async {
      final sesRepo = SessionRepository(db);
      final diagRepo = DiagnosisRepository(db);
      final sessionId = await sesRepo.createBlankSession();
      final msgId = await sesRepo.addMessage(sessionId, 'assistant', '诊断');

      await diagRepo.commitDiagnosis(
        DiagnosisInput(
          sessionId: sessionId,
          messageId: msgId,
          syndromes: [
            {'syndrome_id': 's1', 'name': '症候A', 'severity': 'L1'},
          ],
          suggestedActions: [],
          confidence: 0.5,
        ),
      );

      // 确认诊断（severity 升级 L1→L3）
      await diagRepo.confirmDiagnosis(sessionId, 's1', '症候A', 'L3');
      // 验证 severity 已升级（需要直接查 DB，因为 listActiveProblems 不返回 severity 之外的字段）

      // 驳回另一个症候
      await diagRepo.disputeDiagnosis(sessionId, 's1', '症候A');
    });

    // P0 漏洞 4：confirmDiagnosis severity 升级/降级保护
    // SQL: CASE WHEN severity < ? THEN ? ELSE severity END（字符串比较 L1<L2<L3）
    // 原测试注释说"需要直接查 DB"但没断言，此测试通过 listActiveProblems.severity 验证
    test('confirmDiagnosis severity 升级（L1→L3）', () async {
      final sesRepo = SessionRepository(db);
      final diagRepo = DiagnosisRepository(db);
      final sessionId = await sesRepo.createBlankSession();
      final msgId = await sesRepo.addMessage(sessionId, 'assistant', '诊断');

      await diagRepo.commitDiagnosis(
        DiagnosisInput(
          sessionId: sessionId,
          messageId: msgId,
          syndromes: [
            {'syndrome_id': 's1', 'name': '症候A', 'severity': 'L1'},
          ],
          suggestedActions: [],
          confidence: 0.5,
        ),
      );

      await diagRepo.confirmDiagnosis(sessionId, 's1', '症候A', 'L3');

      final problems = await diagRepo.listActiveProblems(sessionId);
      expect(problems.length, 1);
      expect(problems.first.severity, 'L3'); // 从 L1 升级到 L3
      expect(problems.first.confirmationStatus, 'confirmed');
    });

    test('confirmDiagnosis severity 降级保护（L3→L1 不降级）', () async {
      final sesRepo = SessionRepository(db);
      final diagRepo = DiagnosisRepository(db);
      final sessionId = await sesRepo.createBlankSession();
      final msgId = await sesRepo.addMessage(sessionId, 'assistant', '诊断');

      await diagRepo.commitDiagnosis(
        DiagnosisInput(
          sessionId: sessionId,
          messageId: msgId,
          syndromes: [
            {'syndrome_id': 's1', 'name': '症候A', 'severity': 'L3'},
          ],
          suggestedActions: [],
          confidence: 0.5,
        ),
      );

      // 尝试用 L1 确认（应保持 L3，不降级）
      await diagRepo.confirmDiagnosis(sessionId, 's1', '症候A', 'L1');

      final problems = await diagRepo.listActiveProblems(sessionId);
      expect(problems.first.severity, 'L3'); // 保持 L3，不降级
    });

    test('confirmDiagnosis severity 相等（L2→L2 保持）', () async {
      final sesRepo = SessionRepository(db);
      final diagRepo = DiagnosisRepository(db);
      final sessionId = await sesRepo.createBlankSession();
      final msgId = await sesRepo.addMessage(sessionId, 'assistant', '诊断');

      await diagRepo.commitDiagnosis(
        DiagnosisInput(
          sessionId: sessionId,
          messageId: msgId,
          syndromes: [
            {'syndrome_id': 's1', 'name': '症候A', 'severity': 'L2'},
          ],
          suggestedActions: [],
          confidence: 0.5,
        ),
      );

      await diagRepo.confirmDiagnosis(sessionId, 's1', '症候A', 'L2');

      final problems = await diagRepo.listActiveProblems(sessionId);
      expect(problems.first.severity, 'L2'); // 保持不变
    });

    test('不复活已 resolved 的症候', () async {
      final sesRepo = SessionRepository(db);
      final diagRepo = DiagnosisRepository(db);
      final sessionId = await sesRepo.createBlankSession();
      final msgId = await sesRepo.addMessage(sessionId, 'assistant', '诊断');

      // 第一次诊断
      await diagRepo.commitDiagnosis(
        DiagnosisInput(
          sessionId: sessionId,
          messageId: msgId,
          syndromes: [
            {'syndrome_id': 's1', 'name': '症候A', 'severity': 'L2'},
          ],
          suggestedActions: [],
          confidence: 0.5,
        ),
      );

      // 解决症候
      await diagRepo.resolveSyndromesBatch(sessionId, ['s1']);

      // 再次诊断同症候 — 不应复活
      final msgId2 = await sesRepo.addMessage(sessionId, 'assistant', '诊断2');
      await diagRepo.commitDiagnosis(
        DiagnosisInput(
          sessionId: sessionId,
          messageId: msgId2,
          syndromes: [
            {'syndrome_id': 's1', 'name': '症候A', 'severity': 'L2'},
          ],
          suggestedActions: [],
          confidence: 0.6,
        ),
      );

      final problems = await diagRepo.listActiveProblems(sessionId);
      expect(problems, isEmpty); // 已 resolved 的不被复活
    });

    // B1 记忆合并（Mem0 风格）：同症候同严重度 → 跳过 INSERT，active_problem 仍更新
    // 复刻 RN diagnosis-dao.test.ts 'NO_OP 症候：同症候同严重度时跳过 INSERT'
    test('记忆合并 NO_OP：同症候同严重度跳过 INSERT，active_problem 仍更新', () async {
      final sesRepo = SessionRepository(db);
      final diagRepo = DiagnosisRepository(db);
      final sessionId = await sesRepo.createBlankSession();
      final msgId = await sesRepo.addMessage(sessionId, 'assistant', '诊断1');

      // 第一轮：P001 L2
      await diagRepo.commitDiagnosis(
        DiagnosisInput(
          sessionId: sessionId,
          messageId: msgId,
          syndromes: [
            {'syndrome_id': 'P001', 'name': '逻辑跳跃', 'severity': 'L2'},
          ],
          suggestedActions: [],
          confidence: 0.7,
        ),
      );

      // 第二轮：P001 也是 L2 → NO_OP（跳过 INSERT）
      final msgId2 = await sesRepo.addMessage(sessionId, 'assistant', '诊断2');
      await diagRepo.commitDiagnosis(
        DiagnosisInput(
          sessionId: sessionId,
          messageId: msgId2,
          syndromes: [
            {'syndrome_id': 'P001', 'name': '逻辑跳跃', 'severity': 'L2'},
          ],
          suggestedActions: [],
          confidence: 0.7,
        ),
      );

      final history = await diagRepo.listDiagnosisHistory(sessionId);
      expect(history.length, 2);
      // 最新一条 syndromes 被过滤为空（NO_OP）
      final latest = history.first;
      final latestSyndromes = jsonDecode(latest.syndromes) as List;
      expect(latestSyndromes, isEmpty);
      // active_problem 仍更新（含 NO_OP）
      final problems = await diagRepo.listActiveProblems(sessionId);
      expect(problems.length, 1);
      expect(problems.first.syndromeId, 'P001');
    });

    test('记忆合并：严重度变化 → 非 NO_OP，正常 INSERT', () async {
      final sesRepo = SessionRepository(db);
      final diagRepo = DiagnosisRepository(db);
      final sessionId = await sesRepo.createBlankSession();
      final msgId = await sesRepo.addMessage(sessionId, 'assistant', '诊断1');

      // 第一轮：P001 L2
      await diagRepo.commitDiagnosis(
        DiagnosisInput(
          sessionId: sessionId,
          messageId: msgId,
          syndromes: [
            {'syndrome_id': 'P001', 'name': '逻辑跳跃', 'severity': 'L2'},
          ],
          suggestedActions: [],
          confidence: 0.7,
        ),
      );

      // 第二轮：P001 升级为 L3 → 非 NO_OP
      final msgId2 = await sesRepo.addMessage(sessionId, 'assistant', '诊断2');
      await diagRepo.commitDiagnosis(
        DiagnosisInput(
          sessionId: sessionId,
          messageId: msgId2,
          syndromes: [
            {'syndrome_id': 'P001', 'name': '逻辑跳跃', 'severity': 'L3'},
          ],
          suggestedActions: [],
          confidence: 0.8,
        ),
      );

      final history = await diagRepo.listDiagnosisHistory(sessionId);
      final latest = history.first;
      final latestSyndromes = jsonDecode(latest.syndromes) as List;
      expect(latestSyndromes.length, 1);
      expect((latestSyndromes.first as Map)['severity'], 'L3');
      // active_problem 严重度同步更新为 L3
      final problems = await diagRepo.listActiveProblems(sessionId);
      expect(problems.first.severity, 'L3');
    });

    test('记忆合并：混合场景——NO_OP 与 ADD 并行', () async {
      final sesRepo = SessionRepository(db);
      final diagRepo = DiagnosisRepository(db);
      final sessionId = await sesRepo.createBlankSession();
      final msgId = await sesRepo.addMessage(sessionId, 'assistant', '诊断1');

      // 第一轮：P001 L2
      await diagRepo.commitDiagnosis(
        DiagnosisInput(
          sessionId: sessionId,
          messageId: msgId,
          syndromes: [
            {'syndrome_id': 'P001', 'name': '逻辑跳跃', 'severity': 'L2'},
          ],
          suggestedActions: [],
          confidence: 0.7,
        ),
      );

      // 第二轮：P001 同 L2（NO_OP）+ P002 全新症候（ADD）
      final msgId2 = await sesRepo.addMessage(sessionId, 'assistant', '诊断2');
      await diagRepo.commitDiagnosis(
        DiagnosisInput(
          sessionId: sessionId,
          messageId: msgId2,
          syndromes: [
            {'syndrome_id': 'P001', 'name': '逻辑跳跃', 'severity': 'L2'},
            {'syndrome_id': 'P002', 'name': '视角跳跃', 'severity': 'L1'},
          ],
          suggestedActions: [],
          confidence: 0.7,
        ),
      );

      final history = await diagRepo.listDiagnosisHistory(sessionId);
      final latest = history.first;
      final latestSyndromes = jsonDecode(latest.syndromes) as List;
      // 仅保留 ADD 的 P002
      expect(latestSyndromes.length, 1);
      expect((latestSyndromes.first as Map)['syndrome_id'], 'P002');
      // active_problem 含全部两个症候
      final problems = await diagRepo.listActiveProblems(sessionId);
      expect(problems.length, 2);
    });

    test('B5-4 批次5（5.3）：active_problem 写入时维护 updated_at', () async {
      final sesRepo2 = SessionRepository(db);
      final diagRepo = DiagnosisRepository(db);
      final sessionId = await sesRepo2.createBlankSession();
      final msgId = await sesRepo2.addMessage(sessionId, 'assistant', '诊断1');

      // 首次写入：INSERT 携带 updated_at
      await diagRepo.commitDiagnosis(
        DiagnosisInput(
          sessionId: sessionId,
          messageId: msgId,
          syndromes: [
            {'syndrome_id': 'P001', 'name': '逻辑跳跃', 'severity': 'L2'},
          ],
          suggestedActions: [],
          confidence: 0.7,
        ),
      );
      final row1 = await (db.select(db.activeProblems)).getSingle();
      expect(row1.updatedAt, isNotNull, reason: 'INSERT 时应写 updated_at');

      // 二次写入同症候（UPDATE 路径）：updated_at 应刷新
      final msgId2 = await sesRepo2.addMessage(sessionId, 'assistant', '诊断2');
      await diagRepo.commitDiagnosis(
        DiagnosisInput(
          sessionId: sessionId,
          messageId: msgId2,
          syndromes: [
            {'syndrome_id': 'P001', 'name': '逻辑跳跃', 'severity': 'L3'},
          ],
          suggestedActions: [],
          confidence: 0.8,
        ),
      );
      final row2 = await (db.select(db.activeProblems)).getSingle();
      expect(row2.updatedAt, isNotNull);
      expect(
        row2.updatedAt,
        greaterThanOrEqualTo(row1.updatedAt!),
        reason: 'UPDATE 时应刷新 updated_at',
      );

      // 解决后 updated_at 同步（resolveSyndromesBatch）
      await diagRepo.resolveSyndromesBatch(sessionId, ['P001']);
      final row3 = await (db.select(db.activeProblems)).getSingle();
      expect(row3.status, 'resolved');
      expect(row3.updatedAt, isNotNull);
    });
  });

  // ════════════════════════════════════════════════════════════
  // 4.5 OutlineRepository（批次73 A5 确认卡流转集成测）
  // ════════════════════════════════════════════════════════════
  group('OutlineRepository A5 确认卡流转', () {
    late OutlineRepository outlineRepo;
    late String manuscriptId;

    setUp(() async {
      outlineRepo = OutlineRepository(db);
      manuscriptId = await ManuscriptRepository(
        db,
      ).createManuscript(title: '大纲流转稿');
    });

    Future<String> seedPending({
      required String entityKey,
      required String impression,
      String? conflictWith,
    }) async {
      await outlineRepo.insertEntity(
        manuscriptId: manuscriptId,
        entityType: 'character',
        entityKey: entityKey,
      );
      final ents = await outlineRepo.listEntities(manuscriptId);
      final ent = ents.lastWhere((e) => e.entityKey == entityKey);
      expect(ent.status, 'pending', reason: '新建实体默认 pending');
      return outlineRepo.insertImpression(
        entityId: ent.id,
        impression: impression,
        conflictWith: conflictWith,
      );
    }

    test(
      'A5-1 approveImpression（新实体）→ 印象 active + 实体 pending→active',
      () async {
        final impId = await seedPending(
          entityKey: '王建国',
          impression: '攥紧拳头，是来复仇的',
        );

        await outlineRepo.approveImpression(impId);

        final imp = await outlineRepo.getImpressionById(impId);
        expect(imp!.status, 'active');
        final ent = (await outlineRepo.listEntities(manuscriptId)).single;
        expect(ent.status, 'active', reason: '接受首条印象时实体也应转正');
      },
    );

    test('A5-2 rejectImpression → 印象 rejected，实体仍 pending', () async {
      final impId = await seedPending(entityKey: '王叔', impression: '左眼有一道刀疤');

      await outlineRepo.rejectImpression(impId);

      final imp = await outlineRepo.getImpressionById(impId);
      expect(imp!.status, 'rejected');
      final ent = (await outlineRepo.listEntities(manuscriptId)).single;
      expect(ent.status, 'pending', reason: '没有被接受的印象，实体不应转正');
    });

    test(
      'A5-3 approveImpression 带 conflict_with → 旧印象置 superseded（二选一）',
      () async {
        // 先建旧 active 印象（模拟第一轮 accept 过）
        await outlineRepo.insertEntity(
          manuscriptId: manuscriptId,
          entityType: 'character',
          entityKey: '林小芸',
        );
        final ent = (await outlineRepo.listEntities(manuscriptId)).single;
        // 手动 approve 旧印象（实体也 active）
        final oldImpId = await outlineRepo.insertImpression(
          entityId: ent.id,
          impression: '在二楼远远观望巷口',
        );
        await outlineRepo.approveImpression(oldImpId);
        expect(
          (await outlineRepo.getImpressionById(oldImpId))!.status,
          'active',
        );
        expect((await outlineRepo.getEntityById(ent.id))!.status, 'active');

        // 第二轮产出新印象，冲突旧印象
        final newImpId = await outlineRepo.insertImpression(
          entityId: ent.id,
          impression: '冲下二楼与王建国并肩对峙',
          conflictWith: oldImpId,
        );

        await outlineRepo.approveImpression(newImpId);

        final oldImp = await outlineRepo.getImpressionById(oldImpId);
        final newImp = await outlineRepo.getImpressionById(newImpId);
        expect(newImp!.status, 'active', reason: '新印象被接受');
        expect(
          oldImp!.status,
          'superseded',
          reason: '冲突的旧印象应置 superseded（二选一）',
        );
        expect((await outlineRepo.getEntityById(ent.id))!.status, 'active');
      },
    );

    test('A5-4 reject 冲突印象 → 旧印象保留（不做二选一清退）', () async {
      await outlineRepo.insertEntity(
        manuscriptId: manuscriptId,
        entityType: 'character',
        entityKey: '林小芸',
      );
      final ent = (await outlineRepo.listEntities(manuscriptId)).single;
      final oldImpId = await outlineRepo.insertImpression(
        entityId: ent.id,
        impression: '在二楼观望',
      );
      await outlineRepo.approveImpression(oldImpId);

      final newImpId = await outlineRepo.insertImpression(
        entityId: ent.id,
        impression: '冲下二楼',
        conflictWith: oldImpId,
      );

      await outlineRepo.rejectImpression(newImpId);

      final oldImp = await outlineRepo.getImpressionById(oldImpId);
      final newImp = await outlineRepo.getImpressionById(newImpId);
      expect(newImp!.status, 'rejected');
      expect(oldImp!.status, 'active', reason: '拒绝新认知 → 旧认知保留');
    });

    test(
      'A5-5 buildEntityIndexContext 只回显 active 印象（过滤 pending/rejected/superseded）',
      () async {
        // 建稿 + 章节（outlineService 组装索引时按章查稿）
        final chapterRepo = ChapterRepository(db);
        await chapterRepo.createChapter(
          manuscriptId,
          title: '第一章',
          content: '...',
        );
        final outlineService = OutlineService(outlineRepo);

        // 林小芸：active / pending / rejected / superseded 各一条
        await outlineRepo.insertEntity(
          manuscriptId: manuscriptId,
          entityType: 'character',
          entityKey: '林小芸',
        );
        final ent = (await outlineRepo.listEntities(manuscriptId)).single;
        final activeId = await outlineRepo.insertImpression(
          entityId: ent.id,
          impression: '握银色小手枪',
        );
        await outlineRepo.insertImpression(
          entityId: ent.id,
          impression: '先松后紧',
        );
        final rejectedId = await outlineRepo.insertImpression(
          entityId: ent.id,
          impression: '冷眼旁观',
        );
        // 先 approve 一条再标 superseded，模拟被新认知替代
        final supersededId = await outlineRepo.insertImpression(
          entityId: ent.id,
          impression: '在二楼观望',
        );
        await outlineRepo.approveImpression(activeId);
        await outlineRepo.approveImpression(supersededId);
        // 用冲突 approve 方式把 supersededId 推成 superseded（再建新印象冲突它）
        final newerId = await outlineRepo.insertImpression(
          entityId: ent.id,
          impression: '站在王建国身边',
          conflictWith: supersededId,
        );
        await outlineRepo.approveImpression(newerId);
        // 手动拒绝一条
        await outlineRepo.rejectImpression(rejectedId);

        // 调用 buildEntityIndexContext，验证回显过滤
        final ctx = await outlineService.buildEntityIndexContext(manuscriptId);
        expect(ctx, isNotNull, reason: '应有 active 印象产出索引行');
        expect(ctx, contains('林小芸'));
        expect(ctx, contains('握银色小手枪'), reason: 'active 印象必须回显');
        expect(ctx, contains('站在王建国身边'), reason: '新 active 印象必须回显');
        expect(ctx!.contains('先松后紧'), false, reason: 'pending 印象不应泄漏给索引上下文');
        expect(ctx.contains('冷眼旁观'), false, reason: 'rejected 印象不应泄漏给索引上下文');
        expect(ctx.contains('在二楼观望'), false, reason: 'superseded 印象不应再回显');
      },
    );

    test('B5-1 批次5（5.2）：approveImpression 非 pending 印象不覆盖（防陈旧确认卡）', () async {
      final impId = await seedPending(entityKey: '老张', impression: '年轻时是个镖师');
      // 先清理为 expired（负窗口 → 立即全部过期，模拟超时清理后陈旧确认卡仍存在）
      await outlineRepo.cleanupPendingImpressions(maxAgeDays: -1);
      expect((await outlineRepo.getImpressionById(impId))!.status, 'expired');

      // 陈旧卡上点「接受」→ 不得覆盖（保持 expired，不激活）
      await outlineRepo.approveImpression(impId);
      expect((await outlineRepo.getImpressionById(impId))!.status, 'expired');
    });

    test('B5-2 批次5（5.2）：cleanupPendingImpressions 清理超时 + 归档作品来源', () async {
      final impId = await seedPending(entityKey: '赵四', impression: '爱抽旱烟');
      // 超时清理（负窗口 → 全部 pending 过期）
      final cleaned = await outlineRepo.cleanupPendingImpressions(
        maxAgeDays: -1,
      );
      expect(cleaned, greaterThanOrEqualTo(1));
      expect((await outlineRepo.getImpressionById(impId))!.status, 'expired');

      // 归档作品下的 pending 印象也清理
      final msRepo = ManuscriptRepository(db);
      final newMsId = await msRepo.createManuscript(title: '待归档稿');
      await outlineRepo.insertEntity(
        manuscriptId: newMsId,
        entityType: 'character',
        entityKey: '李四',
      );
      final newMsEnts = await outlineRepo.listEntities(newMsId);
      await outlineRepo.insertImpression(
        entityId: newMsEnts.single.id,
        impression: '擅长说书',
      );
      // 正常 7 天窗口内不清理
      final cleaned2 = await outlineRepo.cleanupPendingImpressions();
      expect(cleaned2, 0, reason: '新 pending 未超时不应清理');
      // 软删稿件 → 其 pending 印象随归档清理
      await msRepo.deleteManuscript(newMsId);
      final cleaned3 = await outlineRepo.cleanupPendingImpressions();
      expect(cleaned3, 1, reason: '归档作品下的 pending 印象应被清理');
    });

    test('B5-3 批次5（5.8）：rejectImpression 批量清理同冲突 pending', () async {
      // 旧印象 B 已 active，两个新印象 A1/A2 都 conflict_with=B
      await outlineRepo.insertEntity(
        manuscriptId: manuscriptId,
        entityType: 'character',
        entityKey: '钱五',
      );
      final ent = (await outlineRepo.listEntities(
        manuscriptId,
      )).lastWhere((e) => e.entityKey == '钱五');
      final oldId = await outlineRepo.insertImpression(
        entityId: ent.id,
        impression: '沉默寡言',
      );
      await outlineRepo.approveImpression(oldId);
      final a1 = await outlineRepo.insertImpression(
        entityId: ent.id,
        impression: '话痨',
        conflictWith: oldId,
      );
      final a2 = await outlineRepo.insertImpression(
        entityId: ent.id,
        impression: '健谈',
        conflictWith: oldId,
      );

      // 拒绝 A1 → A1 与 A2（同冲突指向）一并 rejected，旧印象 B 保持 active
      await outlineRepo.rejectImpression(a1);
      expect((await outlineRepo.getImpressionById(a1))!.status, 'rejected');
      expect(
        (await outlineRepo.getImpressionById(a2))!.status,
        'rejected',
        reason: '同冲突指向的其它 pending 应批量拒绝',
      );
      expect(
        (await outlineRepo.getImpressionById(oldId))!.status,
        'active',
        reason: '拒绝即保留旧认知',
      );
    });
  });

  // ════════════════════════════════════════════════════════════
  // 5. TeachingStateRepository
  // ════════════════════════════════════════════════════════════
  group('TeachingStateRepository', () {
    test('更新阶段 + 子阶段 + 新手等级', () async {
      final sesRepo = SessionRepository(db);
      final tsRepo = TeachingStateRepository(db);
      final sessionId = await sesRepo.createBlankSession();

      await tsRepo.updatePhase(sessionId, 'P1_WORLD');
      await tsRepo.updateSubphase(sessionId, 'world_building');
      await tsRepo.updateBeginnerLevel(sessionId, 'N1_ELEMENTS');

      final state = await tsRepo.getTeachingState(sessionId);
      expect(state!.currentPhase, 'P1_WORLD');
      expect(state.currentSubphase, 'world_building');
      expect(state.beginnerLevel, 'N1_ELEMENTS');
    });

    test('persistAttitude（双写 teaching_state + student_model）', () async {
      final sesRepo = SessionRepository(db);
      final tsRepo = TeachingStateRepository(db);
      final sessionId = await sesRepo.createBlankSession();

      await tsRepo.persistAttitude(sessionId, 'yuesheng');

      // 验证 teaching_state.attitude_level
      final state = await tsRepo.getTeachingState(sessionId);
      expect(state!.attitudeLevel, 'yuesheng');

      // 验证 student_model.attitude_preference
      final model = await (db.select(
        db.studentModels,
      )..where((t) => t.sessionId.equals(sessionId))).getSingleOrNull();
      expect(model, isNotNull);
      expect(model!.attitudePreference, 'yuesheng');
    });

    test('persistAttitude（student_model 已存在 → 更新而非重建）', () async {
      final sesRepo = SessionRepository(db);
      final tsRepo = TeachingStateRepository(db);
      final sessionId = await sesRepo.createBlankSession();

      // 首次写入：自动建行
      await tsRepo.persistAttitude(sessionId, 'doubao');
      final firstModel = await (db.select(
        db.studentModels,
      )..where((t) => t.sessionId.equals(sessionId))).getSingle();

      // 再次切换态度：应更新同一行，而非新增
      await tsRepo.persistAttitude(sessionId, 'sensei');

      final models = await (db.select(
        db.studentModels,
      )..where((t) => t.sessionId.equals(sessionId))).get();
      expect(models.length, 1, reason: '重复 persist 不应重建 student_model 行');
      expect(models.first.id, firstModel.id, reason: '应复用原行 id');
      expect(models.first.attitudePreference, 'sensei');

      // teaching_state 同步更新
      final state = await tsRepo.getTeachingState(sessionId);
      expect(state!.attitudeLevel, 'sensei');
    });

    test('A2 persistAttitude（无 teaching_state 行 → Upsert 自动建行+双写一致）', () async {
      // 不走 createBlankSession，直接插入 session 行，不建 teaching_state
      final dbObj = db;
      final sessionId = generateUuid();
      final now = nowSec();
      await dbObj
          .into(dbObj.sessions)
          .insert(
            SessionsCompanion.insert(
              id: sessionId,
              title: const Value('孤行 session'),
              preview: const Value(''),
              diagnosisSummary: const Value('{}'),
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
          );
      final preState = await (dbObj.select(
        dbObj.teachingState,
      )..where((t) => t.sessionId.equals(sessionId))).getSingleOrNull();
      expect(preState, isNull, reason: '前置：该 session 未建 teaching_state 行');

      final tsRepo = TeachingStateRepository(dbObj);
      await tsRepo.persistAttitude(sessionId, 'doubao');

      final state = await tsRepo.getTeachingState(sessionId);
      expect(state, isNotNull, reason: 'A2 修复：Upsert 应自动创建 teaching_state 行');
      expect(state!.attitudeLevel, 'doubao');
      expect(state.currentPhase, 'P0_ENGAGE', reason: '默认值回退为 P0_ENGAGE');

      final model = await (dbObj.select(
        dbObj.studentModels,
      )..where((t) => t.sessionId.equals(sessionId))).getSingleOrNull();
      expect(model, isNotNull);
      expect(
        model!.attitudePreference,
        'doubao',
        reason: '双写：student_model 一致',
      );
    });

    test(
      'A2 updatePhase/updateBeginnerLevel/updateSubphase（无行时自动建行）',
      () async {
        final dbObj = db;
        final sessionId = generateUuid();
        await dbObj
            .into(dbObj.sessions)
            .insert(
              SessionsCompanion.insert(
                id: sessionId,
                title: const Value('孤行 session2'),
                preview: const Value(''),
                diagnosisSummary: const Value('{}'),
                createdAt: Value(nowSec()),
                updatedAt: Value(nowSec()),
              ),
            );

        final tsRepo = TeachingStateRepository(dbObj);
        await tsRepo.updatePhase(sessionId, 'P1_WORLD');
        await tsRepo.updateBeginnerLevel(sessionId, 'N2_SCENE');
        await tsRepo.updateSubphase(sessionId, 'showing_syndrome');

        final state = await tsRepo.getTeachingState(sessionId);
        expect(state, isNotNull);
        expect(state!.currentPhase, 'P1_WORLD');
        expect(state.beginnerLevel, 'N2_SCENE');
        expect(state.currentSubphase, 'showing_syndrome');
      },
    );
  });

  // ════════════════════════════════════════════════════════════
  // 6. StudentModelRepository
  // ════════════════════════════════════════════════════════════
  group('StudentModelRepository', () {
    test('appendTeachingHistory + getTeachingHistory', () async {
      final sesRepo = SessionRepository(db);
      final smRepo = StudentModelRepository(db);
      final sessionId = await sesRepo.createBlankSession();

      await smRepo.appendTeachingHistory(sessionId, {
        'type': 'diagnosis',
        'syndromes': ['s1'],
        'timestamp': 1700000000,
        'sessionId': sessionId,
      });
      await smRepo.appendTeachingHistory(sessionId, {
        'type': 'confirmation',
        'syndromes': ['s1'],
        'action': 'confirmed',
        'timestamp': 1700000001,
        'sessionId': sessionId,
      });

      final history = await smRepo.getTeachingHistory(sessionId);
      expect(history.length, 2);
      expect(history[0]['type'], 'diagnosis');
      expect(history[1]['type'], 'confirmation');
    });

    test('updateOnboardingData + getOnboardingData', () async {
      final sesRepo = SessionRepository(db);
      final smRepo = StudentModelRepository(db);
      final sessionId = await sesRepo.createBlankSession();

      await smRepo.updateOnboardingData(sessionId, {
        'experience': 'beginner',
        'genre_preference': '小说',
      });

      final data = await smRepo.getOnboardingData(sessionId);
      expect(data, isNotNull);
      expect(data!['experience'], 'beginner');
      expect(data['genre_preference'], '小说');
    });

    // P0 漏洞 1：hasAnyOnboardingData 全套（波6 边界 A 修复核心依赖）
    // SQL: WHERE onboarding_data IS NOT NULL AND onboarding_data NOT IN ('', 'null') LIMIT 1
    test('hasAnyOnboardingData 空表返回 false', () async {
      final smRepo = StudentModelRepository(db);
      expect(await smRepo.hasAnyOnboardingData(), false);
    });

    test('hasAnyOnboardingData onboarding_data=NULL 返回 false', () async {
      final sesRepo = SessionRepository(db);
      final smRepo = StudentModelRepository(db);
      final sessionId = await sesRepo.createBlankSession();
      // createBlankSession 不创建 student_model，appendTeachingHistory 会创建
      // 这里手动用 _ensureStudentModel 等价物：appendTeachingHistory 触发创建
      await smRepo.appendTeachingHistory(sessionId, {'type': 'test'});
      // 此时 onboarding_data = NULL
      expect(await smRepo.hasAnyOnboardingData(), false);
    });

    test('hasAnyOnboardingData onboarding_data="" 返回 false', () async {
      final sesRepo = SessionRepository(db);
      final smRepo = StudentModelRepository(db);
      final sessionId = await sesRepo.createBlankSession();
      await smRepo.appendTeachingHistory(sessionId, {'type': 'test'});
      // 用 customStatement 写入空串（绕过 updateOnboardingData 的 jsonEncode）
      await db.customStatement(
        "UPDATE student_model SET onboarding_data = '' WHERE session_id = ?",
        [sessionId],
      );
      expect(await smRepo.hasAnyOnboardingData(), false);
    });

    test('hasAnyOnboardingData onboarding_data="null" 返回 false', () async {
      final sesRepo = SessionRepository(db);
      final smRepo = StudentModelRepository(db);
      final sessionId = await sesRepo.createBlankSession();
      await smRepo.appendTeachingHistory(sessionId, {'type': 'test'});
      await db.customStatement(
        "UPDATE student_model SET onboarding_data = 'null' WHERE session_id = ?",
        [sessionId],
      );
      expect(await smRepo.hasAnyOnboardingData(), false);
    });

    test('hasAnyOnboardingData 有效 JSON 返回 true', () async {
      final sesRepo = SessionRepository(db);
      final smRepo = StudentModelRepository(db);
      final sessionId = await sesRepo.createBlankSession();
      await smRepo.updateOnboardingData(sessionId, {'level': 'beginner'});
      expect(await smRepo.hasAnyOnboardingData(), true);
    });

    test('hasAnyOnboardingData 跨 session 全表扫描（核心场景）', () async {
      // 模拟边界 A：用户在 session A 填过问卷，本次启动用 session B
      final sesRepo = SessionRepository(db);
      final smRepo = StudentModelRepository(db);
      final sessionA = await sesRepo.createBlankSession();
      await sesRepo.createBlankSession(); // session B（无 student_model 行）

      // session A 有 onboarding_data
      await smRepo.updateOnboardingData(sessionA, {'level': 'beginner'});
      // 全表扫描应命中 session A 的数据
      expect(await smRepo.hasAnyOnboardingData(), true);
    });
  });

  // ════════════════════════════════════════════════════════════
  // 7. AppStateRepository
  // ════════════════════════════════════════════════════════════
  group('AppStateRepository', () {
    test('onboarding 完成状态', () async {
      final repo = AppStateRepository(db);
      expect(await repo.getOnboardingCompleted(), false);

      await repo.setOnboardingCompleted(true);
      expect(await repo.getOnboardingCompleted(), true);
    });

    test('通用 key-value', () async {
      final repo = AppStateRepository(db);
      await repo.setValue('test_key', 'test_value');
      expect(await repo.getValue('test_key'), 'test_value');
    });

    test('章节草稿 CRUD', () async {
      final repo = AppStateRepository(db);
      final chId = 'chapter-123';

      expect(await repo.hasChapterDraft(chId), false);

      await repo.saveChapterDraft(chId, '草稿标题', '草稿内容');
      expect(await repo.hasChapterDraft(chId), true);

      final draft = await repo.getChapterDraft(chId);
      expect(draft, isNotNull);
      expect(draft!.title, '草稿标题');
      expect(draft.content, '草稿内容');

      await repo.clearChapterDraft(chId);
      expect(await repo.hasChapterDraft(chId), false);
    });

    // P0 漏洞 2：questionnaire_completed 用户级标记（波6 新增，bootstrap 依赖）
    // key='questionnaire_completed'，与 onboarding_completed 区分
    test('questionnaire_completed 用户级标记（默认/设置/覆盖）', () async {
      final repo = AppStateRepository(db);

      // 默认 false
      expect(await repo.getQuestionnaireCompleted(), false);

      // 设为 true
      await repo.setQuestionnaireCompleted(true);
      expect(await repo.getQuestionnaireCompleted(), true);

      // 覆盖回 false
      await repo.setQuestionnaireCompleted(false);
      expect(await repo.getQuestionnaireCompleted(), false);
    });

    test('questionnaire_completed 与 onboarding_completed 互不干扰', () async {
      final repo = AppStateRepository(db);

      await repo.setOnboardingCompleted(true);
      expect(await repo.getQuestionnaireCompleted(), false);

      await repo.setQuestionnaireCompleted(true);
      expect(await repo.getOnboardingCompleted(), true);
      expect(await repo.getQuestionnaireCompleted(), true);
    });

    test('B5-5 批次5（5.4）：删除孤儿会话时清理 app_state 的 eval_* 孤儿键', () async {
      final sesRepo = SessionRepository(db);
      final appRepo = AppStateRepository(db);

      // 孤儿会话（无消息）→ 删会话时应清理其 eval_round:/eval_report: 键
      final orphanId = await sesRepo.createBlankSession();
      await appRepo.setValue('eval_round:$orphanId', '1');
      await appRepo.setValue('eval_report:$orphanId:m1', '{"round":1}');
      await appRepo.setValue('eval_report:$orphanId:m2', '{"round":1}');

      // 非孤儿会话（有消息）→ 不删，键保留
      final aliveId = await sesRepo.createBlankSession();
      await sesRepo.addMessage(aliveId, 'assistant', '测试消息');
      await appRepo.setValue('eval_round:$aliveId', '2');

      final deleted = await sesRepo.deleteOrphanSessions();
      expect(deleted, 1);
      expect(
        await appRepo.getValue('eval_round:$orphanId'),
        isNull,
        reason: '孤儿会话的 eval_round 键应随会话删除',
      );
      expect(
        await appRepo.listEvaluationReports(orphanId),
        isEmpty,
        reason: '孤儿会话的 eval_report 键应随会话删除',
      );
      expect(
        await appRepo.getValue('eval_round:$aliveId'),
        '2',
        reason: '非孤儿会话的键不受影响',
      );
    });
  });

  // ════════════════════════════════════════════════════════════
  // 8. ErrorLogRepository
  // ════════════════════════════════════════════════════════════
  group('ErrorLogRepository', () {
    test('插入 + 查询日志', () async {
      final repo = ErrorLogRepository(db);
      final id = await repo.insertErrorLog(
        level: 'error',
        category: 'api',
        message: 'API 调用失败',
        context: {'url': '/api/test', 'status': 500},
      );
      expect(id, startsWith('err_'));

      final logs = await repo.queryErrorLogs();
      expect(logs.length, 1);
      expect(logs[0].level, 'error');
      expect(logs[0].category, 'api');
      expect(logs[0].message, 'API 调用失败');
      expect(logs[0].context?['url'], '/api/test');
    });

    test('分页查询', () async {
      final repo = ErrorLogRepository(db);
      for (var i = 0; i < 5; i++) {
        await repo.insertErrorLog(
          level: 'error',
          category: 'general',
          message: '错误$i',
        );
      }

      final page1 = await repo.queryErrorLogs(
        query: ErrorLogQuery(limit: 2, offset: 0),
      );
      final page2 = await repo.queryErrorLogs(
        query: ErrorLogQuery(limit: 2, offset: 2),
      );

      expect(page1.length, 2);
      expect(page2.length, 2);
    });

    test('条件过滤', () async {
      final repo = ErrorLogRepository(db);
      await repo.insertErrorLog(level: 'error', category: 'api', message: 'A');
      await repo.insertErrorLog(
        level: 'warn',
        category: 'general',
        message: 'B',
      );
      await repo.insertErrorLog(
        level: 'error',
        category: 'database',
        message: 'C',
      );

      final errors = await repo.queryErrorLogs(
        query: ErrorLogQuery(level: 'error'),
      );
      expect(errors.length, 2);

      final apiErrors = await repo.queryErrorLogs(
        query: ErrorLogQuery(level: 'error', category: 'api'),
      );
      expect(apiErrors.length, 1);
      expect(apiErrors[0].message, 'A');
    });

    test('统计 + 清理', () async {
      final repo = ErrorLogRepository(db);
      await repo.insertErrorLog(
        level: 'error',
        category: 'general',
        message: 'A',
      );
      await repo.insertErrorLog(
        level: 'warn',
        category: 'general',
        message: 'B',
      );
      await repo.insertErrorLog(
        level: 'error',
        category: 'general',
        message: 'C',
      );

      final stats = await repo.getErrorLogStats();
      expect(stats.length, 2); // error + warn
      final errorCount = stats.firstWhere((s) => s.level == 'error').count;
      expect(errorCount, 2);

      final deleted = await repo.clearAllErrorLogs();
      expect(deleted, 3);
    });
  });
}
