// R-1 验证测试（D5 / cross-validation 20 号文件 §四 推导风险）
//
// 背景：20-诊断链路状态转移表-D4-3补做.md §四 标了一条**推导风险 R-1**：
//   「rejected + evidenceConfidence IS NULL 可穿过注入门」
// 本测试把它变成可证伪判据。追码时同时发现一个**比 R-1 更宽的形态**，一并测。
//
// 门的实际语义（diagnosis_repository.dart:456-468）：
//   status = 'active'
//   AND ( evidenceConfidence IS NULL
//         OR evidenceConfidence >= 0.4
//         OR confirmationStatus = 'confirmed' )
//
// 而 disputeDiagnosis（:707-723）**只写 confirmation_status='rejected'**，
// 不改 status、不改 evidenceConfidence。
//
// ⇒ 推论：只要 (evidenceConfidence IS NULL) 或 (>= 0.4) 成立，
//   用户的「不认同」**不会**把该症候从 listActiveProblems 中移除。
//   现有 evidence_gating_test.dart 五条用例**无一覆盖 rejected 组合**
//   （其文件头只声明了「无 evidence → 保留，兼容存量」，未涉及 rejected）。
//
// 本测试的性质 = **表征测试（characterization test）**：
//   断言的是「现状确实如此」，不是「应该如此」。
//   若日后判定为缺陷并修复，本测试会红 —— 那是**有意的**，
//   逼使修复者明确选择：改门控，或改 disputeDiagnosis 的副作用边界。
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

  group('R-1：rejected 症候在 listActiveProblems 中的可见性', () {
    // ── R-1 原形态：无 evidence（NULL 把握）+ 驳回 ──
    test('无 evidence + 驳回 → 仍在活跃列表（R-1 原形态）', () async {
      final sid = await newSession();
      await commit(
        sid,
        syndromes: [
          {'syndrome_id': 'S001', 'name': '症候A', 'severity': 'L2'},
        ],
      );
      // 前置：NULL 把握确实成立
      final before = await repo.listActiveProblems(sid);
      expect(before, hasLength(1));
      expect(before.first.evidenceConfidence, isNull);

      // 用户驳回
      await repo.disputeDiagnosis(sid, 'S001', '症候A');

      // 断言现状：仍可见
      final after = await repo.listActiveProblems(sid);
      expect(
        after,
        hasLength(1),
        reason:
            'R-1：rejected + NULL 把握穿过了注入门。'
            '若此断言失败，说明门控已被修改 —— 请同步更新 '
            'cross-validation/20-诊断链路状态转移表-D4-3补做.md §四',
      );
      expect(after.first.confirmationStatus, 'rejected');
      // 注：ActiveProblemView 不暴露 status 字段（视图仅含
      // syndromeId/syndromeName/severity/confirmationStatus/teachingState/
      // evidenceConfidence/confirmedAt）⇒ 流进注入层的视图**看不到** active/resolved，
      // 只能靠 listActiveProblems 的门控预先过滤。此点亦记入 20 号文件 §一 V1。
    });

    // ── 比 R-1 更宽的形态：强证据 + 驳回 ──
    test('强证据 + 驳回 → 仍在活跃列表（比 R-1 更宽）', () async {
      final sid = await newSession();
      await commit(
        sid,
        syndromes: [
          {
            'syndrome_id': 'S002',
            'name': '症候B',
            'severity': 'L2',
            'evidence': ['这是第一条足够长的具体原文片段', '这是第二条足够长的具体原文片段'],
          },
        ],
      );
      final before = await repo.listActiveProblems(sid);
      expect(before.first.evidenceConfidence, isNotNull);
      expect(before.first.evidenceConfidence!, greaterThanOrEqualTo(0.4));

      await repo.disputeDiagnosis(sid, 'S002', '症候B');

      final after = await repo.listActiveProblems(sid);
      expect(
        after,
        hasLength(1),
        reason:
            '强证据 + 驳回同样穿过门控 —— 说明「用户不认同」'
            '对 listActiveProblems 的可见性完全无影响',
      );
      expect(after.first.confirmationStatus, 'rejected');
    });

    // ── 对照组：弱证据 + 驳回 → 被剔除（门控的 rejected 无关性证明）──
    test('弱证据 + 驳回 → 被剔除（证明剔除与 rejected 无关，只与把握度有关）', () async {
      final sid = await newSession();
      await commit(
        sid,
        syndromes: [
          {
            'syndrome_id': 'S003',
            'name': '症候C',
            'severity': 'L1',
            'evidence': ['短'], // 把握 < 0.4
          },
        ],
      );
      expect(await repo.listActiveProblems(sid), isEmpty);
      await repo.disputeDiagnosis(sid, 'S003', '症候C');
      // 仍然为空 —— 不是因为 rejected，是因为本来就被弱证据门挡掉
      expect(await repo.listActiveProblems(sid), isEmpty);
    });

    // ── 确认态对照：确认能把它带回来（证明 confirmed 是显式通道）──
    test('弱证据 + 确认 → 回到活跃列表（对照：confirmed 是显式放行通道）', () async {
      final sid = await newSession();
      await commit(
        sid,
        syndromes: [
          {
            'syndrome_id': 'S004',
            'name': '症候D',
            'severity': 'L1',
            'evidence': ['短'],
          },
        ],
      );
      expect(await repo.listActiveProblems(sid), isEmpty);
      await repo.confirmDiagnosis(sid, 'S004', '症候D', 'L2');
      final problems = await repo.listActiveProblems(sid);
      expect(problems, hasLength(1));
      expect(problems.first.confirmationStatus, 'confirmed');
    });
  });
}
