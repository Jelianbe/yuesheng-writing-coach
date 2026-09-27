import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/diagnosis_repository.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';

// Part B 信心系统：listActiveProblems 的弱证据把握度门控语义
//   - 弱把握（<0.4）且未确认 → 从活跃列表剔除（不进教学注入/焦点）
//   - 强把握（>=0.4）→ 保留
//   - 弱把握但已确认 → 保留（用户确认后进入教学）
//   - 无 evidence（旧数据/NULL 把握）→ 保留（不门控，兼容存量）
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

  Future<String> newSession() => sessionRepo.createBlankSession();

  Future<void> commit(
    String sid, {
    required List<Map<String, dynamic>> syndromes,
  }) => repo.commitDiagnosis(
    DiagnosisInput(
      sessionId: sid,
      messageId: 'msg-1',
      syndromes: syndromes,
      suggestedActions: const [],
      confidence: 0.8,
    ),
  );

  group('证据把握度门控（Part B）', () {
    test('弱把握 + 未确认 → 剔除出 listActiveProblems', () async {
      final sid = await newSession();
      // 单条短证据（<6 字）→ 把握 0.35 < 0.4
      await commit(
        sid,
        syndromes: [
          {
            'syndrome_id': 'S001',
            'name': '症候A',
            'severity': 'L2',
            'evidence': ['好'],
          },
        ],
      );
      expect(await repo.listActiveProblems(sid), isEmpty);
    });

    test('强把握 → 保留在 listActiveProblems', () async {
      final sid = await newSession();
      await commit(
        sid,
        syndromes: [
          {
            'syndrome_id': 'S001',
            'name': '症候A',
            'severity': 'L2',
            'evidence': ['这是第一条足够长的具体原文片段', '这是第二条足够长的具体原文片段'],
          },
        ],
      );
      final problems = await repo.listActiveProblems(sid);
      expect(problems, hasLength(1));
      expect(problems.first.syndromeId, 'S001');
      expect(problems.first.evidenceConfidence, isNotNull);
      expect(problems.first.evidenceConfidence!, greaterThanOrEqualTo(0.4));
    });

    test('弱把握但已确认 → 保留（用户确认后进入教学）', () async {
      final sid = await newSession();
      await commit(
        sid,
        syndromes: [
          {
            'syndrome_id': 'S001',
            'name': '症候A',
            'severity': 'L2',
            'evidence': ['好'],
          },
        ],
      );
      // 初始弱+未确认 → 剔除
      expect(await repo.listActiveProblems(sid), isEmpty);
      // 用户确认
      await repo.confirmDiagnosis(sid, 'S001', '症候A', 'L2');
      final problems = await repo.listActiveProblems(sid);
      expect(problems, hasLength(1));
      expect(problems.first.syndromeId, 'S001');
    });

    test('无 evidence（旧数据/NULL 把握）→ 保留，不门控', () async {
      final sid = await newSession();
      await commit(
        sid,
        syndromes: [
          {'syndrome_id': 'S001', 'name': '症候A', 'severity': 'L2'},
        ],
      );
      final problems = await repo.listActiveProblems(sid);
      expect(problems, hasLength(1));
      expect(problems.first.evidenceConfidence, isNull);
    });

    test('同一 session 强弱混合 → 只保留强把握', () async {
      final sid = await newSession();
      await commit(
        sid,
        syndromes: [
          {
            'syndrome_id': 'WEAK',
            'name': '弱症候',
            'severity': 'L1',
            'evidence': ['短'],
          },
          {
            'syndrome_id': 'STRONG',
            'name': '强症候',
            'severity': 'L2',
            'evidence': ['这是第一条足够长的具体原文片段', '这是第二条足够长的具体原文片段'],
          },
        ],
      );
      final problems = await repo.listActiveProblems(sid);
      expect(problems.map((p) => p.syndromeId), ['STRONG']);
    });
  });
}
