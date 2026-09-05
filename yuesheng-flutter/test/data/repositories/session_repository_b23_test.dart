// ─────────────────────────────────────────────────────────────
// session_repository_b23_test — B23 回归测试
//
// 场景：多步写（建会话 + 建 teaching_state + 建 session_reference）
// 必须整体原子——任何一步失败都不应留下孤儿会话 / 缺失教学态 / 悬空引用。
// 修复：createBlankSession 与两个 getOrCreate* 均已包 _db.transaction。
// 本测试锁定不变量：每次创建后，会话、teaching_state、引用三者齐备；
// 复用路径不重复建 teaching_state / 引用。
//
// 注意：sessions.manuscript_id / chapter_id 是 FK（references manuscripts/chapters，
// onDelete: setNull）。故在 setUp 中先用 ManuscriptRepository / ChapterRepository
// 建立真实稿件/章节行，使 getOrCreate* 写入的外键引用成立（符合真实运行路径：
// 会话总是挂在已存在的稿件/章节上）。
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/data/repositories/chapter_repository.dart';

void main() {
  late AppDatabase db;
  late SessionRepository sessionRepo;
  late String ms1;
  late String ms2;
  late String ms3;
  late String ch2; // 挂在 ms2 下的章节

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    sessionRepo = SessionRepository(db);
    final mRepo = ManuscriptRepository(db);
    final cRepo = ChapterRepository(db);
    ms1 = await mRepo.createManuscript(title: 'ms-1');
    ms2 = await mRepo.createManuscript(title: 'ms-2');
    ms3 = await mRepo.createManuscript(title: 'ms-3');
    ch2 = await cRepo.createChapter(ms2, title: 'ch-2', content: 'x');
  });

  tearDown(() async => db.close());

  Future<int> _teachingStateCount(String sessionId) async => (await (db.select(
    db.teachingState,
  )..where((t) => t.sessionId.equals(sessionId))).get()).length;

  Future<List<String>> _refTypes(String sessionId) async =>
      (await (db.select(
            db.sessionReferences,
          )..where((t) => t.sessionId.equals(sessionId))).get())
          .map((r) => r.refType)
          .toList();

  Future<int> _sessionCount(String sessionId) async => (await (db.select(
    db.sessions,
  )..where((t) => t.id.equals(sessionId))).get()).length;
  Future<String> _sessionTitle(String sessionId) async => (await (db.select(
    db.sessions,
  )..where((t) => t.id.equals(sessionId))).getSingle()).title;

  test('B23 createBlankSession 原子建会话 + teaching_state', () async {
    final id = await sessionRepo.createBlankSession(title: 't');
    expect(await _sessionCount(id), 1, reason: '会话行应存在');
    expect(await _teachingStateCount(id), 1, reason: '教学态行应随会话建立（B23 根因修复）');
  });

  test(
    'B23 getOrCreateSessionForManuscript 原子建会话 + teaching_state + 主引用',
    () async {
      final id = await sessionRepo.getOrCreateSessionForManuscript(ms1);
      expect(await _sessionCount(id), 1);
      expect(await _teachingStateCount(id), 1);
      final refs = await _refTypes(id);
      expect(refs, contains('manuscript'), reason: '主引用（manuscript）应齐备');
    },
  );

  test(
    'B23 getOrCreateSessionForChapter 原子建会话 + teaching_state + 双引用',
    () async {
      final id = await sessionRepo.getOrCreateSessionForChapter(ms2, ch2);
      expect(await _sessionCount(id), 1);
      expect(await _teachingStateCount(id), 1);
      final refs = await _refTypes(id);
      expect(refs, contains('chapter'), reason: '主引用（chapter）应齐备');
      expect(refs, contains('manuscript'), reason: '次要引用（manuscript）应齐备');
      expect(await _sessionTitle(id), '诊断·ch-2', reason: '章节标题命名（批次61：诊断·标题）');
    },
  );

  test('B23 复用现有会话不重复建 teaching_state / 引用', () async {
    final first = await sessionRepo.getOrCreateSessionForManuscript(ms3);
    final second = await sessionRepo.getOrCreateSessionForManuscript(ms3);
    expect(first, second, reason: '应复用现有会话');
    expect(await _teachingStateCount(first), 1, reason: 'teaching_state 不应重复建');
    expect(
      (await _refTypes(first)).where((r) => r == 'manuscript').length,
      1,
      reason: 'manuscript 引用不应重复建',
    );
  });
}
