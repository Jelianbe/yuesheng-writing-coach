// ─────────────────────────────────────────────────────────────
// teacher_suggestion_repository_test — X-041d 追溯查询单元测试
//
// 覆盖 getLatestActiveBySyndrome：
//   1. 命中单条 active suggestion → 返回该行
//   2. 同症候多条 → 按 createdAt DESC 取首条
//   3. 跨症候过滤 → 不相干症候不会被查出
//   4. 跨 session 隔离 → 其他 session 的记录不返回
//   5. 空库 → null
//   6. status='resolved'（已采纳/已跳过）→ 仍被查出（追溯不漏）
//   7. markDismissed 后追溯
//   8. targetSyndromeId 为 null 的建议不会被查出
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/data/repositories/teacher_suggestion_repository.dart';

void main() {
  late AppDatabase db;
  late TeacherSuggestionRepository repo;
  late SessionRepository sessionRepo;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = TeacherSuggestionRepository(db);
    sessionRepo = SessionRepository(db);
  });

  tearDown(() async => db.close());

  /// 辅助：构造入参
  InsertTeacherSuggestionParams mkParams({
    required String sessionId,
    required String messageId,
    String source = 'diagnosis',
    String teachingDecision = 'train',
    String? targetSyndromeId = 'syn-emotion-tag',
    String? targetDimension,
    String taskType = 'rewrite',
    String taskDescription = '改写这段对话',
    String difficulty = 'medium',
    List<String> evaluationCriteria = const ['有冲突', '有动作'],
  }) {
    return InsertTeacherSuggestionParams(
      sessionId: sessionId,
      messageId: messageId,
      source: source,
      teachingDecision: teachingDecision,
      targetSyndromeId: targetSyndromeId,
      targetDimension: targetDimension,
      taskType: taskType,
      taskDescription: taskDescription,
      difficulty: difficulty,
      evaluationCriteria: evaluationCriteria,
    );
  }

  /// 辅助：先建 message 再插 suggestion（FK 约束需要 message 先存在）
  Future<String> insertSuggestionWithFreshMessage({
    required String sessionId,
    String? targetSyndromeId = 'syn-emotion-tag',
    String taskType = 'rewrite',
  }) async {
    final messageId = await sessionRepo.addMessage(
      sessionId,
      'assistant',
      'AI 反馈',
    );
    final id = await repo.insertTeacherSuggestion(
      mkParams(
        sessionId: sessionId,
        messageId: messageId,
        targetSyndromeId: targetSyndromeId,
        taskType: taskType,
      ),
    );
    return id;
  }

  test('#1 命中单条 active suggestion → 返回该行', () async {
    final sessionId = await sessionRepo.createBlankSession(title: '会话A');
    final id = await insertSuggestionWithFreshMessage(
      sessionId: sessionId,
      targetSyndromeId: 'syn-A',
      taskType: 'analyze',
    );

    final row = await repo.getLatestActiveBySyndrome(sessionId, 'syn-A');
    expect(row, isNotNull);
    expect(row!.id, id);
    expect(row.taskType, 'analyze');
    expect(row.status, 'active');
  });

  test('#2 同症候多条 → 按 createdAt DESC 取首条', () async {
    final sessionId = await sessionRepo.createBlankSession(title: '会话B');
    final id1 = await insertSuggestionWithFreshMessage(
      sessionId: sessionId,
      targetSyndromeId: 'syn-B',
    );
    await Future<void>.delayed(const Duration(seconds: 1));
    final id2 = await insertSuggestionWithFreshMessage(
      sessionId: sessionId,
      targetSyndromeId: 'syn-B',
      taskType: 'compare',
    );

    final row = await repo.getLatestActiveBySyndrome(sessionId, 'syn-B');
    expect(row, isNotNull);
    expect(row!.id, id2, reason: '最新在前');
    expect(row.taskType, 'compare');
    expect(row.id, isNot(id1));
  });

  test('#3 跨症候过滤 → 不相干症候不会被查出', () async {
    final sessionId = await sessionRepo.createBlankSession(title: '会话C');
    await insertSuggestionWithFreshMessage(
      sessionId: sessionId,
      targetSyndromeId: 'syn-X',
    );
    await insertSuggestionWithFreshMessage(
      sessionId: sessionId,
      targetSyndromeId: 'syn-Y',
    );

    final row = await repo.getLatestActiveBySyndrome(sessionId, 'syn-Z');
    expect(row, isNull, reason: '无匹配症候 → null');
  });

  test('#4 跨 session 隔离 → 其他 session 的记录不返回', () async {
    final s1 = await sessionRepo.createBlankSession(title: '会话D1');
    final s2 = await sessionRepo.createBlankSession(title: '会话D2');
    await insertSuggestionWithFreshMessage(
      sessionId: s1,
      targetSyndromeId: 'syn-cross',
    );
    await insertSuggestionWithFreshMessage(
      sessionId: s2,
      targetSyndromeId: 'syn-cross',
    );

    final rowS1 = await repo.getLatestActiveBySyndrome(s1, 'syn-cross');
    expect(rowS1, isNotNull);
    expect(rowS1!.sessionId, s1);

    final rowS2 = await repo.getLatestActiveBySyndrome(s2, 'syn-cross');
    expect(rowS2, isNotNull);
    expect(rowS2!.sessionId, s2);
    expect(rowS2.id, isNot(rowS1.id));
  });

  test('#5 空库 → null', () async {
    final sessionId = await sessionRepo.createBlankSession(title: '会话E');
    final row = await repo.getLatestActiveBySyndrome(sessionId, 'syn-empty');
    expect(row, isNull);
  });

  test('#6 status=resolved（已采纳）→ 仍被查出（追溯不漏）', () async {
    final sessionId = await sessionRepo.createBlankSession(title: '会话F');
    final id = await insertSuggestionWithFreshMessage(
      sessionId: sessionId,
      targetSyndromeId: 'syn-adopted',
      taskType: 'generate',
    );
    await repo.markAdopted(id);

    final row = await repo.getLatestActiveBySyndrome(sessionId, 'syn-adopted');
    expect(row, isNotNull, reason: '已采纳建议仍可追溯');
    expect(row!.id, id);
    expect(row.taskType, 'generate');
    expect(row.status, 'resolved');
    expect(row.adoptedAt, isNotNull);
  });

  test('#7 markDismissed 后 → 仍被查出（追溯包含已跳过建议）', () async {
    final sessionId = await sessionRepo.createBlankSession(title: '会话G');
    final id = await insertSuggestionWithFreshMessage(
      sessionId: sessionId,
      targetSyndromeId: 'syn-dismissed',
    );
    await repo.markDismissed(id);

    final row = await repo.getLatestActiveBySyndrome(
      sessionId,
      'syn-dismissed',
    );
    expect(row, isNotNull, reason: '已跳过建议也是历史触发源');
    expect(row!.id, id);
    expect(row.dismissedAt, isNotNull);
  });

  test('#8 targetSyndromeId 为 null 的建议不会被查出', () async {
    final sessionId = await sessionRepo.createBlankSession(title: '会话H');
    await insertSuggestionWithFreshMessage(
      sessionId: sessionId,
      targetSyndromeId: null,
    );

    final row = await repo.getLatestActiveBySyndrome(sessionId, 'syn-any');
    expect(row, isNull, reason: '维度型建议不参与症候级追溯');
  });
}
