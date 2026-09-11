// ─────────────────────────────────────────────────────────────
// createOrReuseBlankSession（真机反馈三批#4：反复点「+」不堆空会话）
//
// 根因：旧 createNew() 立即 createBlankSession 落库，点一次堆一个空会话。
// 修复：新建前先复用「无消息 + 无 manuscript 关联」的自由空会话。
// ─────────────────────────────────────────────────────────────
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';

void main() {
  late AppDatabase db;
  late SessionRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = SessionRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> insertMessage(String sessionId, String role, String text) async {
    await db
        .into(db.messages)
        .insert(
          MessagesCompanion.insert(
            id: 'msg-${DateTime.now().microsecondsSinceEpoch}',
            sessionId: sessionId,
            role: role,
            content: text,
          ),
        );
  }

  group('createOrReuseBlankSession（真机#4 不堆空会话）', () {
    test('连续新建 3 次 → 复用同一会话，库里只 1 条', () async {
      final a = await repo.createOrReuseBlankSession();
      final b = await repo.createOrReuseBlankSession();
      final c = await repo.createOrReuseBlankSession();
      expect(a, b, reason: '第 1、2 次新建应复用同一空会话');
      expect(b, c, reason: '第 3 次仍应复用');
      final all = await db.select(db.sessions).get();
      expect(all.length, 1, reason: '不应堆积多个空会话');
    });

    test('空会话发过消息后 → 再新建开新会话', () async {
      final a = await repo.createOrReuseBlankSession();
      await insertMessage(a, 'user', '你好');

      final b = await repo.createOrReuseBlankSession();
      expect(b, isNot(a), reason: '有消息的会话不应被复用，应开新会话');
      final all = await db.select(db.sessions).get();
      expect(all.length, 2);
    });

    test('新建/复用的自由会话 manuscriptId 为 null（不串作品会话）', () async {
      final a = await repo.createOrReuseBlankSession();
      final row = await (db.select(
        db.sessions,
      )..where((t) => t.id.equals(a))).getSingle();
      expect(row.manuscriptId, isNull, reason: '自由对话会话不应挂在某作品下，避免与章节会话混用');
    });
  });
}
