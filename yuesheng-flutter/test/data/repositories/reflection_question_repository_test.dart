// ─────────────────────────────────────────────────────────────
// reflection_question_repository_test — C-3 批：对话思考题仓储
//
// 覆盖对象：lib/data/repositories/reflection_question_repository.dart（72 行，0 覆盖）
//   公开符号：ReflectionQuestionRepository.insertQuestions / listPending /
//              markReviewed / dismiss
//
// ★ 本文件只补 C-1 裁定（.ai/research/t13-c1-test-triage.md §②）点名的缺口：
//   · insertQuestions 的**去重**行为（messageId + question 相同只入一条）—— 零断言。
//   · markReviewed 的**间隔重复表**（1→1 天、2→3 天、3→7 天、4+→14 天）—— 零断言。
//   · listPending 的**status 过滤 + nextReviewAt 升序 + limit** —— 零断言。
//   · dismiss 的**状态改写** —— 零断言。
//
// ★ 可红判据（改哪一处必红）：
//   ① 删 lib/data/repositories/reflection_question_repository.dart:24 的
//      `if (exists == null)` 守卫（或删 :17-23 的存在性查询）
//      ⇒ 用例 #A 必红（m1+q1 变成 2 条、全表 3 条）。
//   ② 把 :47-52 的 switch 中 `2 => 3` 改成 `2 => 4`
//      ⇒ 用例 #B2 必红（第 2 档间隔差值不符）。
//   ③ 把 :47-52 的 `1 => 1` 改成 `1 => 2` ⇒ 用例 #B1 必红。
//   ④ 把 :47-52 的 `_ => 14` 改成 `_ => 10` ⇒ 用例 #B4 必红。
//   ⑤ 删 :33 的 `t.status.equals('pending')` 过滤 ⇒ 用例 #C1 必红。
//   ⑥ 删 :34 的 `OrderingTerm.asc(t.nextReviewAt)` ⇒ 用例 #C2 必红。
//   ⑦ 删 :35 的 `.limit(limit)` ⇒ 用例 #C3 必红。
//   ⑧ 把 :70 的 `Value('dismissed')` 改成 `Value('pending')` ⇒ 用例 #C4 必红。
//
// ★ 时间断言口径：markReviewed 用 DateTime.now()（:53）⇒ 绝对值不稳定。
//   本文件用**前后夹逼**（调用前取 before、调用后取 after）断言差值，
//   不用固定基准日，也不靠 sleep 猜时序。
// ─────────────────────────────────────────────────────────────

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/reflection_question_repository.dart';

/// 造一条思考题 companion（id 唯一，messageId 显式给值 —— 去重键含它）。
ReflectionQuestionsCompanion _q(
  String id, {
  required String messageId,
  required String question,
  int? nextReviewAt,
}) {
  return ReflectionQuestionsCompanion.insert(
    id: id,
    sessionId: 'sess_1',
    messageId: Value(messageId),
    question: question,
    nextReviewAt: nextReviewAt == null
        ? const Value.absent()
        : Value(nextReviewAt),
  );
}

/// 当前时刻（秒），用于时间夹逼。
int _nowSec() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

void main() {
  late AppDatabase db;
  late ReflectionQuestionRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = ReflectionQuestionRepository(db);
  });

  tearDown(() => db.close());

  group('insertQuestions — 去重', () {
    test('#A 同 messageId + 同 question 只入一条；不同 messageId 各入一条', () async {
      await repo.insertQuestions([
        _q('r1', messageId: 'm1', question: '为什么这样写？'),
        _q('r2', messageId: 'm1', question: '为什么这样写？'),
        _q('r3', messageId: 'm2', question: '为什么这样写？'),
      ]);

      final all = await db.select(db.reflectionQuestions).get();
      expect(all.length, 2, reason: '全表 2 条：m1 一条 + m2 一条');

      final dup =
          await (db.select(db.reflectionQuestions)..where(
                (t) => t.messageId.equals('m1') & t.question.equals('为什么这样写？'),
              ))
              .get();
      expect(dup.length, 1, reason: '同 messageId + 同 question 只能有 1 条');
      expect(dup.single.id, 'r1', reason: '先到者先入库，后到者被去重挡下');
    });

    test('#A2 重复插入同一批（两次调用）→ 第二次全被去重，表内条数不变', () async {
      final batch = [
        _q('r1', messageId: 'm1', question: '问题 A'),
        _q('r2', messageId: 'm2', question: '问题 B'),
      ];

      await repo.insertQuestions(batch);
      await repo.insertQuestions(batch);

      final all = await db.select(db.reflectionQuestions).get();
      expect(all.length, 2, reason: '去重是跨调用的，不只是批内去重');
    });
  });

  group('markReviewed — 间隔重复表', () {
    Future<int> markAndReadNext(String id, int expectedDays) async {
      final before = _nowSec();
      await repo.markReviewed(id);
      final after = _nowSec();
      final row = await (db.select(
        db.reflectionQuestions,
      )..where((t) => t.id.equals(id))).getSingle();
      expect(row.reviewCount, greaterThan(0), reason: '回顾次数必须累加');
      expect(row.status, 'reviewed', reason: '回顾后状态改为 reviewed');
      final target = expectedDays * 86400;
      expect(
        row.nextReviewAt,
        inInclusiveRange(before + target - 2, after + target + 2),
        reason: '下次回顾时间应落在 now + $expectedDays 天（容差 ±2s）',
      );
      return row.reviewCount;
    }

    test('#B1 第 1 次回顾 → reviewCount=1，间隔 1 天', () async {
      await repo.insertQuestions([_q('r1', messageId: 'm1', question: '问题 A')]);

      final count = await markAndReadNext('r1', 1);

      expect(count, 1, reason: '第 1 次回顾后 reviewCount 必须是 1');
    });

    test('#B2 第 2 次回顾 → 间隔 3 天（不是 1 天）', () async {
      await repo.insertQuestions([_q('r1', messageId: 'm1', question: '问题 A')]);
      await repo.markReviewed('r1');

      final count = await markAndReadNext('r1', 3);

      expect(count, 2, reason: '第 2 次回顾后 reviewCount 必须是 2');
    });

    test('#B3 第 3 次回顾 → 间隔 7 天', () async {
      await repo.insertQuestions([_q('r1', messageId: 'm1', question: '问题 A')]);
      await repo.markReviewed('r1');
      await repo.markReviewed('r1');

      final count = await markAndReadNext('r1', 7);

      expect(count, 3, reason: '第 3 次回顾后 reviewCount 必须是 3');
    });

    test('#B4 第 4 次回顾 → 间隔 14 天（4+ 走兜底档）', () async {
      await repo.insertQuestions([_q('r1', messageId: 'm1', question: '问题 A')]);
      await repo.markReviewed('r1');
      await repo.markReviewed('r1');
      await repo.markReviewed('r1');

      final count = await markAndReadNext('r1', 14);

      expect(count, 4, reason: '第 4 次回顾后 reviewCount 必须是 4');
    });

    test('#B5 回顾不存在的 id → 不抛异常（静默返回）', () async {
      await repo.markReviewed('no-such-id');

      final all = await db.select(db.reflectionQuestions).get();
      expect(all, isEmpty, reason: '不存在的 id 不应凭空造行');
    });
  });

  group('listPending / dismiss — 过滤、排序、限流、状态改写', () {
    test('#C1 只返回 status=pending 的行（reviewed / dismissed 都不在内）', () async {
      await repo.insertQuestions([
        _q('p1', messageId: 'm1', question: '待回顾 A', nextReviewAt: 2000),
        _q('p2', messageId: 'm2', question: '待回顾 B', nextReviewAt: 1000),
      ]);
      await repo.markReviewed('p2');
      await repo.dismiss('p1');

      final pending = await repo.listPending();
      expect(pending, isEmpty, reason: 'reviewed 与 dismissed 都不该出现在待回顾列表');
    });

    test('#C2 按 nextReviewAt 升序返回', () async {
      await repo.insertQuestions([
        _q('late', messageId: 'm1', question: '晚', nextReviewAt: 9000),
        _q('early', messageId: 'm2', question: '早', nextReviewAt: 1000),
        _q('mid', messageId: 'm3', question: '中', nextReviewAt: 5000),
      ]);

      final pending = await repo.listPending();

      expect(pending.map((t) => t.id).toList(), <String>[
        'early',
        'mid',
        'late',
      ], reason: '待回顾列表按 nextReviewAt 升序（早的先回顾）');
    });

    test('#C3 limit 生效', () async {
      await repo.insertQuestions([
        _q('a', messageId: 'm1', question: 'A', nextReviewAt: 1000),
        _q('b', messageId: 'm2', question: 'B', nextReviewAt: 2000),
        _q('c', messageId: 'm3', question: 'C', nextReviewAt: 3000),
      ]);

      final pending = await repo.listPending(limit: 2);

      expect(pending.length, 2, reason: 'limit 必须真的限制条数');
      expect(pending.map((t) => t.id).toList(), <String>[
        'a',
        'b',
      ], reason: 'limit 截断的是排序后的前 N 条');
    });

    test('#C4 dismiss 把行改成 dismissed 并从待回顾列表移除', () async {
      await repo.insertQuestions([
        _q('p1', messageId: 'm1', question: '待回顾 A', nextReviewAt: 1000),
        _q('p2', messageId: 'm2', question: '待回顾 B', nextReviewAt: 2000),
      ]);

      await repo.dismiss('p1');

      final row = await (db.select(
        db.reflectionQuestions,
      )..where((t) => t.id.equals('p1'))).getSingle();
      expect(row.status, 'dismissed', reason: 'dismiss 必须把状态改写为 dismissed');

      final pending = await repo.listPending();
      expect(pending.map((t) => t.id).toList(), <String>[
        'p2',
      ], reason: 'dismissed 的行不再出现在待回顾列表');
    });
  });
}
