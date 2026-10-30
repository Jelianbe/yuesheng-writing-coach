// ─────────────────────────────────────────────────────────────
// diagnosis_excluded_persist_test — ADR-0012 轮次级 excluded 落库（写/读回往返）
//
// 覆盖（判据见 `.ai/adr/0012-持久化批-excluded落DiagnosisRow.md §5`）：
//   ① 写/读回往返：commitDiagnosis 含 2 条 excluded → excludedOf 读回逐字一致
//      （reason 保留）——删 excludedJson 写入 ⇒ 本用例红
//   ② 缺省列：不带 excluded 构造 → 读回空列表不崩
//   ②b 畸形 JSON 行 → 解码退化为空列表不崩（R-028 留痕）
//   ④ B4 守卫：excluded ID 绝不进 active_problems / rejected 名册
//      ——把 excluded 误写进 activeProblems ⇒ 本用例红
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/diagnosis_repository.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/types/teaching_types.dart';

void main() {
  late AppDatabase db;
  late DiagnosisRepository repo;
  late SessionRepository sessionRepo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = DiagnosisRepository(db);
    sessionRepo = SessionRepository(db);
  });

  tearDown(() => db.close());

  group('ADR-0012 轮次级 excluded 落库', () {
    test('① 写/读回往返：2 条 excluded（含 reason）读回逐字一致', () async {
      final sid = await sessionRepo.createBlankSession();
      await repo.commitDiagnosis(
        DiagnosisInput(
          sessionId: sid,
          messageId: 'msg-1',
          syndromes: const [
            {'syndrome_id': 'P002', 'name': '信息倾泻', 'severity': 'L2'},
          ],
          suggestedActions: const [],
          confidence: 0.8,
          excluded: const [
            ParsedExclusion(syndromeId: 'P001', reason: '本轮证据下不成立'),
            ParsedExclusion(syndromeId: 'P017'),
          ],
        ),
      );

      final rows = await repo.listDiagnosisHistory(sid);
      expect(rows, hasLength(1));
      final got = repo.excludedOf(rows.single);

      expect(got, hasLength(2), reason: '去 excludedJson 写入 ⇒ 红');
      expect(got[0].syndromeId, 'P001');
      expect(got[0].reason, '本轮证据下不成立', reason: 'reason 逐字保留不得截断');
      expect(got[1].syndromeId, 'P017');
      expect(
        got[1].reason,
        '',
        reason: '无理由条 ⇒ 空串（批 2 toJson 省略 key，fromJson 兜底）',
      );
    });

    test('② 缺省列：不带 excluded 构造 → 读回空列表不崩', () async {
      final sid = await sessionRepo.createBlankSession();
      await repo.commitDiagnosis(
        DiagnosisInput(
          sessionId: sid,
          messageId: 'msg-1',
          syndromes: const [
            {'syndrome_id': 'P003', 'name': '视角漂移', 'severity': 'L2'},
          ],
          suggestedActions: const [],
          confidence: 0.8,
        ),
      );

      final rows = await repo.listDiagnosisHistory(sid);
      expect(rows, hasLength(1));
      expect(repo.excludedOf(rows.single), isEmpty);
    });

    test('②b 畸形 JSON 行 → 解码退化为空列表不崩（R-028 留痕）', () async {
      final sid = await sessionRepo.createBlankSession();
      await repo.commitDiagnosis(
        DiagnosisInput(
          sessionId: sid,
          messageId: 'msg-1',
          syndromes: const [
            {'syndrome_id': 'P003', 'name': '视角漂移', 'severity': 'L2'},
          ],
          suggestedActions: const [],
          confidence: 0.8,
        ),
      );
      // 模拟手工 SQL 灌入畸形值（存量行/外部写坏）
      await db.customUpdate(
        "UPDATE diagnosis_results SET excluded_json = 'not-json{{' "
        "WHERE message_id = 'msg-1'",
      );

      final rows = await repo.listDiagnosisHistory(sid);
      expect(repo.excludedOf(rows.single), isEmpty, reason: '畸形 JSON 必须退空不抛');
    });

    test('④ B4 守卫：excluded ID 绝不进 active_problems / rejected 名册', () async {
      final sid = await sessionRepo.createBlankSession();
      await repo.commitDiagnosis(
        DiagnosisInput(
          sessionId: sid,
          messageId: 'msg-1',
          syndromes: const [
            {'syndrome_id': 'P002', 'name': '信息倾泻', 'severity': 'L2'},
          ],
          suggestedActions: const [],
          confidence: 0.8,
          excluded: const [
            ParsedExclusion(syndromeId: 'P999', reason: '查过但未报出'),
          ],
        ),
      );

      // active_problems 表内零 P999 行（UPSERT 循环只遍历 syndromes）
      final apRows = await db.select(db.activeProblems).get();
      expect(
        apRows.any((r) => r.syndromeId == 'P999'),
        isFalse,
        reason:
            'excluded 是独立 List ⇒ P999 不得入 active_problems；'
            '若把 excluded 误写进 UPSERT ⇒ 红',
      );
      // 活跃问题视图不含 P999
      expect(
        (await repo.listActiveProblems(sid)).any((v) => v.syndromeId == 'P999'),
        isFalse,
      );
      // rejected 名册恒空（更不可能含 P999）
      expect(await repo.listRejectedProblems(sid), isEmpty);
    });
  });
}
