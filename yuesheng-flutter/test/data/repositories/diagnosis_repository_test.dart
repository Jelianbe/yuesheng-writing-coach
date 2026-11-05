import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
// drift 与 flutter_test 都导出 isNull / isNotNull（前者是顶层函数
// `isNull(Expression)`，后者经 matcher 导出同名 Matcher）。具名导入以消歧 ——
// T-20261105-03 是本文件首次用到这两个 matcher 的位置。
import 'package:matcher/matcher.dart' as matcher;
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
      await Future<void>.delayed(const Duration(seconds: 1));

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
      await Future<void>.delayed(const Duration(seconds: 1));
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
        await Future<void>.delayed(const Duration(seconds: 1));
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

  // ── 批次 H：_updateDiagnosisSummary（top_syndromes 截断——此前无 active>2 场景）──

  group('批次 H diagnosis_summary（top_syndromes 截断/排序/status 过滤）', () {
    Future<Map<String, dynamic>> readSummary(String sid) async {
      final session = await (db.select(
        db.sessions,
      )..where((t) => t.id.equals(sid))).getSingle();
      return jsonDecode(session.diagnosisSummary) as Map<String, dynamic>;
    }

    test('#1 active 4 个 → top_syndromes 截断前 3 且 L3 排首', () async {
      final sid = await sessionRepo.createBlankSession();
      await repo.commitDiagnosis(
        DiagnosisInput(
          sessionId: sid,
          messageId: 'msg-1',
          syndromes: [
            {'syndrome_id': 'S001', 'name': 'L2症候A', 'severity': 'L2'},
            {'syndrome_id': 'S002', 'name': 'L3症候', 'severity': 'L3'},
            {'syndrome_id': 'S003', 'name': 'L2症候B', 'severity': 'L2'},
            {'syndrome_id': 'S004', 'name': 'L1症候', 'severity': 'L1'},
          ],
          suggestedActions: [],
          confidence: 0.8,
        ),
      );

      final summary = await readSummary(sid);
      final top = (summary['top_syndromes'] as List)
          .cast<Map<String, dynamic>>();

      expect(top, hasLength(3), reason: '4 个 active 截断到前 3');
      expect(top.first['syndrome_id'], 'S002', reason: '按 L3>L2>L1 排序，L3 首位');
      expect(top.first['severity'], 'L3');
      expect(
        top.map((s) => s['syndrome_id']),
        isNot(contains('S004')),
        reason: 'L1 被截出局',
      );
      expect(summary['total_problems'], 4);
      expect(summary['resolved_problems'], 0);
    });

    test('#2 resolved 症候不进 top_syndromes，计数分离', () async {
      final sid = await sessionRepo.createBlankSession();
      await repo.commitDiagnosis(
        DiagnosisInput(
          sessionId: sid,
          messageId: 'msg-1',
          syndromes: [
            {'syndrome_id': 'S001', 'name': 'L2症候A', 'severity': 'L2'},
            {'syndrome_id': 'S002', 'name': 'L3症候', 'severity': 'L3'},
            {'syndrome_id': 'S003', 'name': 'L1症候', 'severity': 'L1'},
          ],
          suggestedActions: [],
          confidence: 0.8,
        ),
      );
      await repo.resolveProblem(sid, 'S002');

      final summary = await readSummary(sid);
      final top = (summary['top_syndromes'] as List)
          .cast<Map<String, dynamic>>();

      expect(top, hasLength(2), reason: 'resolved 不算 active，不进 top');
      expect(top.map((s) => s['syndrome_id']), isNot(contains('S002')));
      expect(summary['total_problems'], 3);
      expect(summary['resolved_problems'], 1);
    });
  });

  group('D-W1：syndromeName 由注册表按 id 反查（不信用库内 name）', () {
    // v46 只归一 syndrome_id 未动 syndrome_name，存量行 id/name 可能错配。
    // 修法：读时统一用 syndromeNameOf(id) 反查，查不到才 fallback 库内 name。

    test('#1 注册表 ID 配错误 name → 读出注册表正确 name', () async {
      final sid = await sessionRepo.createBlankSession();
      // P003 在注册表中 name='视角漂移'，这里故意传入错误 name
      await repo.commitDiagnosis(
        DiagnosisInput(
          sessionId: sid,
          messageId: 'msg-1',
          syndromes: [
            {'syndrome_id': 'P003', 'name': '错误的名字', 'severity': 'L2'},
          ],
          suggestedActions: [],
          confidence: 0.8,
        ),
      );

      final result = await repo.listAllActiveProblems();
      expect(result.length, 1);
      expect(result.first.syndromeId, 'P003');
      // 关键断言：读出的是注册表的正确 name，不是库内存的错误 name
      expect(result.first.syndromeName, '视角漂移');
    });

    test('#2 非注册表 ID → fallback 库内 name', () async {
      final sid = await sessionRepo.createBlankSession();
      // S001 不在注册表中，应 fallback 到传入的 name
      await repo.commitDiagnosis(
        DiagnosisInput(
          sessionId: sid,
          messageId: 'msg-1',
          syndromes: [
            {'syndrome_id': 'S001', 'name': '自定义症候', 'severity': 'L2'},
          ],
          suggestedActions: [],
          confidence: 0.8,
        ),
      );

      final result = await repo.listAllActiveProblems();
      expect(result.length, 1);
      expect(result.first.syndromeId, 'S001');
      expect(result.first.syndromeName, '自定义症候');
    });

    test('#3 diagnosis_summary.top_syndromes 同样走注册表反查', () async {
      final sid = await sessionRepo.createBlankSession();
      await repo.commitDiagnosis(
        DiagnosisInput(
          sessionId: sid,
          messageId: 'msg-1',
          syndromes: [
            {'syndrome_id': 'P003', 'name': '错误的名字', 'severity': 'L3'},
          ],
          suggestedActions: [],
          confidence: 0.8,
        ),
      );

      final session = await (db.select(
        db.sessions,
      )..where((t) => t.id.equals(sid))).getSingle();
      final summary =
          jsonDecode(session.diagnosisSummary) as Map<String, dynamic>;
      final top = (summary['top_syndromes'] as List)
          .cast<Map<String, dynamic>>();

      expect(top.first['syndrome_id'], 'P003');
      expect(top.first['name'], '视角漂移', reason: 'summary 也须走注册表反查');
    });
  });

  group('listRejectedProblems（A4 ③类 · T-20261016-05 人裁冲突事实源）', () {
    test('#1 rejected ⇒ 返回；跨 session 不串（等值条件）', () async {
      final sidA = await sessionRepo.createBlankSession();
      final sidB = await sessionRepo.createBlankSession();
      for (final sid in [sidA, sidB]) {
        await repo.commitDiagnosis(
          DiagnosisInput(
            sessionId: sid,
            messageId: 'msg-$sid',
            syndromes: [
              {'syndrome_id': 'P003', 'name': '视角漂移', 'severity': 'L2'},
            ],
            suggestedActions: [],
            confidence: 0.8,
          ),
        );
      }
      await repo.disputeDiagnosis(sidA, 'P003', '视角漂移');
      await repo.disputeDiagnosis(sidB, 'P003', '视角漂移');

      final a = await repo.listRejectedProblems(sidA);
      expect(a.length, 1);
      expect(a.single.syndromeId, 'P003');
      expect(a.single.confirmationStatus, 'rejected');
    });

    test('#2 ignored / suspected / confirmed 不在结果内', () async {
      final sid = await sessionRepo.createBlankSession();
      await repo.commitDiagnosis(
        DiagnosisInput(
          sessionId: sid,
          messageId: 'msg-1',
          syndromes: [
            {'syndrome_id': 'P003', 'name': '视角漂移', 'severity': 'L2'},
          ],
          suggestedActions: [],
          confidence: 0.8,
        ),
      );
      // ignored 态无仓储写入方（CHECK 预留态）⇒ 直插一行证过滤
      await db
          .into(db.activeProblems)
          .insert(
            ActiveProblemsCompanion.insert(
              id: 'ap-ignored',
              sessionId: sid,
              syndromeId: 'P018',
              syndromeName: const Value(' somebody '),
              confirmationStatus: const Value('ignored'),
            ),
          );
      // suspected = 未裁决的 P003 原态
      final suspectedOnly = await repo.listRejectedProblems(sid);
      expect(suspectedOnly, isEmpty);

      await repo.confirmDiagnosis(sid, 'P003', '视角漂移', 'L2');
      expect(await repo.listRejectedProblems(sid), isEmpty);
    });

    test('#3 resolved 的驳回症候不返回（张力已消，仅 active）', () async {
      final sid = await sessionRepo.createBlankSession();
      await repo.commitDiagnosis(
        DiagnosisInput(
          sessionId: sid,
          messageId: 'msg-1',
          syndromes: [
            {'syndrome_id': 'P003', 'name': '视角漂移', 'severity': 'L2'},
          ],
          suggestedActions: [],
          confidence: 0.8,
        ),
      );
      await repo.disputeDiagnosis(sid, 'P003', '视角漂移');
      expect((await repo.listRejectedProblems(sid)).length, 1);
      await repo.resolveSyndromesBatch(sid, ['P003']);
      expect(await repo.listRejectedProblems(sid), isEmpty);
    });

    test('#4 空 DB ⇒ 空列表', () async {
      expect(await repo.listRejectedProblems('no-such-session'), isEmpty);
    });
  });

  // ───────────────────────────────────────────────────────────
  // T-20261105-03：nextFocus 落库侧（diagnosis_results.next_focus）
  //
  // 真源（现场重取）：
  //   列定义 `lib/data/database/tables.dart:161` `TextColumn get nextFocus => text().nullable()();`
  //   写入点 `lib/data/repositories/diagnosis_repository.dart:190` `nextFocus: Value(input.nextFocus),`
  //   上游接线 `lib/services/diagnosis_flow_handler.dart:776`（`_buildDiagnosisInput`）
  //
  // 本组钉的是**这一层能钉的**：写入显式性 + 持久化往返 + 逐字保真。
  // 「接线是否把值送进来」（handler → DiagnosisInput）**不在本层**——
  // 本层夹具直接构造 DiagnosisInput，按 §第 3 步分层判定，那个条件由
  // 呈现侧 C6（消息通道）与上游 handler 用例承担，此处不双写声称。
  //
  // 负向实测（见报告）：把 :190 改成 `const Value(null)` ⇒ D1 / D3 红，
  //   D2 不红（D2 的输入本就是 null ⇒ 变异体与原实现同值，机制已导出）。
  // ───────────────────────────────────────────────────────────
  group('T-20261105-03 落库侧：nextFocus 写/读回往返', () {
    DiagnosisInput input({
      required String sessionId,
      required String messageId,
      String? nextFocus,
    }) {
      return DiagnosisInput(
        sessionId: sessionId,
        messageId: messageId,
        syndromes: const [
          {'syndrome_id': 'P002', 'name': '信息倾泻', 'severity': 'L2'},
        ],
        suggestedActions: const [],
        confidence: 0.8,
        nextFocus: nextFocus,
      );
    }

    test('D1 整句（含首尾空格）写后读回逐字一致 —— repo 不 trim / 不截断 / 不改写', () async {
      const sentence = ' 下一轮把第三段的两句对话拆开，删掉中间那句解释性独白 ';
      final sid = await sessionRepo.createBlankSession();
      await repo.commitDiagnosis(
        input(sessionId: sid, messageId: 'msg-nf-1', nextFocus: sentence),
      );

      final row = await repo.getLatestDiagnosis(sid);
      expect(row, matcher.isNotNull);
      expect(
        row!.nextFocus,
        sentence,
        reason:
            'Value(input.nextFocus) 被改成 Value(null) / 被套上 trim —— 本条红。'
            '首尾空格是有意留的：任何归一化都会在此暴露',
      );
      expect(row.nextFocus!.length, sentence.length, reason: '长度逐字相等（防静默截断）');
    });

    test('D2 nextFocus=null 写后读回仍为 null（不得变成空串）', () async {
      final sid = await sessionRepo.createBlankSession();
      await repo.commitDiagnosis(input(sessionId: sid, messageId: 'msg-nf-2'));

      final row = await repo.getLatestDiagnosis(sid);
      expect(row, matcher.isNotNull);
      expect(row!.nextFocus, matcher.isNull, reason: 'null 被写成空串 ⇒ 本条红');
      // 显式排除「空串代替 null」这一种最常见的退化
      expect(row.nextFocus, isNot(''));
    });

    test('D3 同 session 两条诊断各自独立（后写不覆盖前一条的值）', () async {
      final sid = await sessionRepo.createBlankSession();
      await repo.commitDiagnosis(
        input(sessionId: sid, messageId: 'msg-nf-3a', nextFocus: '第一条的下步焦点'),
      );
      await repo.commitDiagnosis(
        input(sessionId: sid, messageId: 'msg-nf-3b', nextFocus: '第二条的下步焦点'),
      );

      final rows = await repo.listDiagnosisHistory(sid);
      String? focusOf(String messageId) =>
          rows.firstWhere((r) => r.messageId == messageId).nextFocus;

      expect(rows, hasLength(2));
      expect(focusOf('msg-nf-3a'), '第一条的下步焦点');
      expect(
        focusOf('msg-nf-3b'),
        '第二条的下步焦点',
        reason: '若实现改成 UPDATE 行/沿用上一行值 ⇒ 此处读到第一条的值 ⇒ 红',
      );
    });
  });
}
