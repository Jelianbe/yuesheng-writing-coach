import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/diagnosis_repository.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';

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

  group('listAllActiveProblems', () {
    test('#1 空 DB → 返回空列表', () async {
      final result = await repo.listAllActiveProblems();
      expect(result, isEmpty);
    });

    test('#2 跨 session 聚合相同 syndrome_id → 合并为一条，取最新严重度', () async {
      // session A
      final sidA = await sessionRepo.createBlankSession();
      await repo.commitDiagnosis(
        DiagnosisInput(
          sessionId: sidA,
          messageId: 'msg-a',
          syndromes: [
            {'syndrome_id': 'S001', 'name': '视角跳跃', 'severity': 'L2'},
          ],
          suggestedActions: [],
          confidence: 0.8,
        ),
      );

      // 确保 created_at 有秒级时间差（nowSec 精度到秒）
      await Future.delayed(const Duration(seconds: 1));

      // session B — 同一 syndrome 但更严重
      final sidB = await sessionRepo.createBlankSession();
      await repo.commitDiagnosis(
        DiagnosisInput(
          sessionId: sidB,
          messageId: 'msg-b',
          syndromes: [
            {'syndrome_id': 'S001', 'name': '视角跳跃', 'severity': 'L3'},
          ],
          suggestedActions: [],
          confidence: 0.9,
        ),
      );

      final result = await repo.listAllActiveProblems();

      expect(result.length, 1); // 合并为一条
      expect(result.first.syndromeId, 'S001');
      expect(result.first.severity, 'L3'); // 取最新
      expect(result.first.syndromeName, '视角跳跃');
    });

    test('#3 排除 resolved 状态的症候', () async {
      final sid = await sessionRepo.createBlankSession();
      await repo.commitDiagnosis(
        DiagnosisInput(
          sessionId: sid,
          messageId: 'msg-1',
          syndromes: [
            {'syndrome_id': 'S001', 'name': '症候A', 'severity': 'L2'},
          ],
          suggestedActions: [],
          confidence: 0.8,
        ),
      );
      // 解决该症候
      await repo.resolveProblem(sid, 'S001');

      final result = await repo.listAllActiveProblems();
      expect(result, isEmpty); // resolved 被排除
    });

    test('#4 按 severity DESC 排序（L3 在前）', () async {
      final sid = await sessionRepo.createBlankSession();
      await repo.commitDiagnosis(
        DiagnosisInput(
          sessionId: sid,
          messageId: 'msg-1',
          syndromes: [
            {'syndrome_id': 'S001', 'name': 'L2症候', 'severity': 'L2'},
            {'syndrome_id': 'S002', 'name': 'L3症候', 'severity': 'L3'},
            {'syndrome_id': 'S003', 'name': 'L1症候', 'severity': 'L1'},
          ],
          suggestedActions: [],
          confidence: 0.8,
        ),
      );

      final result = await repo.listAllActiveProblems();
      expect(result.length, 3);
      expect(result[0].severity, 'L3');
      expect(result[1].severity, 'L2');
      expect(result[2].severity, 'L1');
    });
  });

  group('listRecentDiagnoses', () {
    test('#1 空 DB → 返回空列表', () async {
      final result = await repo.listRecentDiagnoses();
      expect(result, isEmpty);
    });

    test('#2 跨 session 查询 → 返回所有 session 的诊断', () async {
      final sidA = await sessionRepo.createBlankSession();
      final sidB = await sessionRepo.createBlankSession();
      await repo.commitDiagnosis(
        DiagnosisInput(
          sessionId: sidA,
          messageId: 'msg-a',
          syndromes: [
            {'syndrome_id': 'S001', 'name': '症候A', 'severity': 'L2'},
          ],
          suggestedActions: [],
          confidence: 0.8,
        ),
      );
      await Future.delayed(const Duration(seconds: 1));
      await repo.commitDiagnosis(
        DiagnosisInput(
          sessionId: sidB,
          messageId: 'msg-b',
          syndromes: [
            {'syndrome_id': 'S002', 'name': '症候B', 'severity': 'L3'},
          ],
          suggestedActions: [],
          confidence: 0.9,
        ),
      );

      final result = await repo.listRecentDiagnoses();
      expect(result.length, 2);
      // 按 timestamp DESC：sidB 的诊断在后创建，应排在前面
      expect(result[0].sessionId, sidB);
      expect(result[1].sessionId, sidA);
    });

    test('#3 limit 参数生效', () async {
      final sid = await sessionRepo.createBlankSession();
      for (var i = 0; i < 5; i++) {
        await repo.commitDiagnosis(
          DiagnosisInput(
            sessionId: sid,
            messageId: 'msg-$i',
            syndromes: [
              {'syndrome_id': 'S00$i', 'name': '症候$i', 'severity': 'L1'},
            ],
            suggestedActions: [],
            confidence: 0.5,
          ),
        );
        await Future.delayed(const Duration(seconds: 1));
      }

      final result = await repo.listRecentDiagnoses(limit: 3);
      expect(result.length, 3);
    });
  });

  group('hasResolvedHistory（D3 复发信号）', () {
    test('#1 无任何记录 → false', () async {
      final sid = await sessionRepo.createBlankSession();
      await repo.commitDiagnosis(
        DiagnosisInput(
          sessionId: sid,
          messageId: 'msg-1',
          syndromes: [
            {'syndrome_id': 'S001', 'name': '症候A', 'severity': 'L2'},
          ],
          suggestedActions: [],
          confidence: 0.8,
        ),
      );
      expect(await repo.hasResolvedHistory('S001'), isFalse);
      expect(await repo.hasResolvedHistory('S999'), isFalse);
    });

    test('#2 曾 resolved → true（跨 session 复发信号）', () async {
      final sidA = await sessionRepo.createBlankSession();
      await repo.commitDiagnosis(
        DiagnosisInput(
          sessionId: sidA,
          messageId: 'msg-a',
          syndromes: [
            {'syndrome_id': 'S001', 'name': '症候A', 'severity': 'L2'},
          ],
          suggestedActions: [],
          confidence: 0.8,
        ),
      );
      await repo.resolveProblem(sidA, 'S001');
      expect(await repo.hasResolvedHistory('S001'), isTrue);
    });

    test('#3 只查目标症候，不串其他症候', () async {
      final sid = await sessionRepo.createBlankSession();
      await repo.commitDiagnosis(
        DiagnosisInput(
          sessionId: sid,
          messageId: 'msg-1',
          syndromes: [
            {'syndrome_id': 'S001', 'name': '症候A', 'severity': 'L2'},
            {'syndrome_id': 'S002', 'name': '症候B', 'severity': 'L3'},
          ],
          suggestedActions: [],
          confidence: 0.8,
        ),
      );
      await repo.resolveProblem(sid, 'S001');
      expect(await repo.hasResolvedHistory('S001'), isTrue);
      expect(await repo.hasResolvedHistory('S002'), isFalse);
    });
  });

  group('批次75 removeProblem（移除条目）', () {
    test('#1 移除单个活跃条目 → 行物理删除 + 列表为空', () async {
      final sid = await sessionRepo.createBlankSession();
      await repo.commitDiagnosis(
        DiagnosisInput(
          sessionId: sid,
          messageId: 'msg-1',
          syndromes: [
            {'syndrome_id': 'S001', 'name': '症候A', 'severity': 'L2'},
            {'syndrome_id': 'S002', 'name': '症候B', 'severity': 'L1'},
          ],
          suggestedActions: [],
          confidence: 0.8,
        ),
      );

      await repo.removeProblem(sid, 'S001');

      final problems = await repo.listActiveProblems(sid);
      expect(problems, hasLength(1));
      expect(problems.first.syndromeId, 'S002');
      // DB 行物理删除（区别于 resolveProblem 的置 resolved）
      final rows = await db.select(db.activeProblems).get();
      expect(rows, hasLength(1));
      expect(rows.first.syndromeId, 'S002');
    });

    test('#2 移除全部 → 空列表 + summary 重算', () async {
      final sid = await sessionRepo.createBlankSession();
      await repo.commitDiagnosis(
        DiagnosisInput(
          sessionId: sid,
          messageId: 'msg-1',
          syndromes: [
            {'syndrome_id': 'S001', 'name': '症候A', 'severity': 'L2'},
          ],
          suggestedActions: [],
          confidence: 0.8,
        ),
      );

      await repo.removeProblem(sid, 'S001');

      expect(await repo.listActiveProblems(sid), isEmpty);
      // diagnosis_summary 同步重算（残留死数据不应存在）
      final rows = await db.select(db.activeProblems).get();
      expect(rows, isEmpty);
    });

    test('#3 移除不存在条目 → 幂等不抛错', () async {
      final sid = await sessionRepo.createBlankSession();
      await repo.commitDiagnosis(
        DiagnosisInput(
          sessionId: sid,
          messageId: 'msg-1',
          syndromes: [
            {'syndrome_id': 'S001', 'name': '症候A', 'severity': 'L2'},
          ],
          suggestedActions: [],
          confidence: 0.8,
        ),
      );

      await repo.removeProblem(sid, 'S999');

      expect(await repo.listActiveProblems(sid), hasLength(1));
    });
  });
}
