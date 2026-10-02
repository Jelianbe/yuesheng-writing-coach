// ─────────────────────────────────────────────────────────────
// diagnosis_pending_commit_test — C126 教学态落库 + pending 标记测试
//
// 锁定 UI-写库分离修复：
//   1. 教学轮（isTeachingRound=true）→ syndromes 全量 + status='pending'
//   2. 正常轮 → status='confirmed'
//   3. NO_OP 基线：先写 pending 行，再同症候正常轮 → 不被去重、写全量 confirmed
//   4. 生命周期升级：pending [P034,P017] → confirmed [P034,P017] → pending 行升 confirmed
//   5. 生命周期替换：pending [P034] → confirmed [P005] → pending 行变 replaced
//   6. 教学轮 active_problem 的 confirmation_status='suspected'
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/diagnosis_repository.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';

DiagnosisInput _input(
  String sessionId,
  String messageId,
  List<Map<String, dynamic>> syndromes, {
  bool isTeachingRound = false,
}) {
  return DiagnosisInput(
    sessionId: sessionId,
    messageId: messageId,
    syndromes: syndromes,
    suggestedActions: [],
    confidence: 0.8,
    isTeachingRound: isTeachingRound,
  );
}

Map<String, dynamic> _s(String id, String severity) => {
  'syndrome_id': id,
  'name': '$id 症',
  'severity': severity,
};

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

  test('#1 教学轮 → syndromes 全量写 + status=pending', () async {
    final sid = await sessionRepo.createBlankSession();
    await repo.commitDiagnosis(
      _input(sid, 'msg-teach', [
        _s('P034', 'L2'),
        _s('P017', 'L2'),
      ], isTeachingRound: true),
    );

    final rows = await repo.listDiagnosisHistory(sid);
    expect(rows.length, 1);
    expect(rows.first.status, 'pending');
    // 全量：两条症候都在（不是 NO_OP 清空后的 '[]'）
    expect(rows.first.syndromes, contains('P034'));
    expect(rows.first.syndromes, contains('P017'));
  });

  test('#2 正常轮 → status=confirmed', () async {
    final sid = await sessionRepo.createBlankSession();
    await repo.commitDiagnosis(_input(sid, 'msg-normal', [_s('P005', 'L2')]));

    final rows = await repo.listDiagnosisHistory(sid);
    expect(rows.first.status, 'confirmed');
  });

  test('#3 NO_OP 基线：pending 行不压制后续同症候 confirmed 写入', () async {
    final sid = await sessionRepo.createBlankSession();
    // 先写一条 pending 行（同症候 P005/L2）
    await repo.commitDiagnosis(
      _input(sid, 'msg-pending', [_s('P005', 'L2')], isTeachingRound: true),
    );
    // 再写同症候正常轮 → 因最新行是 pending，不做 NO_OP，应落一条全量 confirmed
    await repo.commitDiagnosis(
      _input(sid, 'msg-confirmed', [_s('P005', 'L2')]),
    );

    final rows = await repo.listDiagnosisHistory(sid);
    expect(rows.length, 2, reason: 'pending 行不得压制后续正式诊断');
    final confirmed = rows.firstWhere((r) => r.messageId == 'msg-confirmed');
    expect(confirmed.status, 'confirmed');
    expect(
      confirmed.syndromes,
      contains('P005'),
      reason: 'confirmed 行应含全量症候，非 []',
    );
  });

  test('#4 生命周期升级：pending 症候集 ⊆ confirmed → pending 升 confirmed', () async {
    final sid = await sessionRepo.createBlankSession();
    await repo.commitDiagnosis(
      _input(sid, 'msg-pending', [
        _s('P034', 'L2'),
        _s('P017', 'L2'),
      ], isTeachingRound: true),
    );
    await repo.commitDiagnosis(
      _input(sid, 'msg-confirmed', [_s('P034', 'L2'), _s('P017', 'L2')]),
    );

    final oldPending = (await repo.listDiagnosisHistory(
      sid,
    )).firstWhere((r) => r.messageId == 'msg-pending');
    expect(
      oldPending.status,
      'confirmed',
      reason: 'pending 症候集被后续正式诊断完整覆盖 → 升级 confirmed',
    );
  });

  test('#5 生命周期替换：pending 症候集 ⊄ confirmed → pending 变 replaced', () async {
    final sid = await sessionRepo.createBlankSession();
    await repo.commitDiagnosis(
      _input(sid, 'msg-pending', [_s('P034', 'L2')], isTeachingRound: true),
    );
    await repo.commitDiagnosis(
      _input(sid, 'msg-confirmed', [_s('P005', 'L2')]),
    );

    final oldPending = (await repo.listDiagnosisHistory(
      sid,
    )).firstWhere((r) => r.messageId == 'msg-pending');
    expect(
      oldPending.status,
      'replaced',
      reason: 'pending 症候未被后续正式诊断覆盖 → 置 replaced',
    );
  });

  test('#6 教学轮 active_problem 的 confirmation_status=suspected', () async {
    final sid = await sessionRepo.createBlankSession();
    await repo.commitDiagnosis(
      _input(sid, 'msg-teach', [_s('P034', 'L2')], isTeachingRound: true),
    );

    final ap = await repo.getActiveProblem(sid, 'P034');
    expect(ap, isNotNull);
    expect(
      ap!.confirmationStatus,
      'suspected',
      reason: '教学轮写入但消费方区分：active_problem 仍 suspected，不冒充 confirmed',
    );
  });
}
