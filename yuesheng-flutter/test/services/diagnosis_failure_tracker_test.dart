// ─────────────────────────────────────────────────────────────
// diagnosis_failure_tracker_test — 诊断失败跟踪器行为判据（A2 真分解后补）
//
// 为什么需要本文件（此前**无法**单测）：
//   「连续失败计数 + 失败卡插入 + 原因留痕」三件事原本藏在
//   `DiagnosisFlowHandler` 的私有字段与私有方法里 —— 外部不可构造、不可观测，
//   只能靠端到端测试间接确认「插了几张卡」。A2 把它抽成
//   `DiagnosisFailureTracker` 后，状态与副作用都可以直接断言。
//
// 守的是什么（每条判据都有反例）：
//   ① 计数语义：attempted && !success 才 +1；成功清零；非诊断轮次不动。
//   ② 插卡时机：**每次**失败都插（首次也插），成功与非诊断轮次不插。
//   ③ 空匹配（empty_match）：只观测、**不计失败**、不插卡 —— 这是 A2 的
//      语义边界，若被误改成「算失败」会让「模型报 0 个症候」污染失败率。
//   ④ 隔离性：不同 session 的计数互不影响（Map 按 session 分桶）。
//   ⑤ 不留 sessionId 原文（只落布尔）。
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/error_log_repository.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/services/diagnosis_failure_reason.dart';
import 'package:writingcoach/services/diagnosis_failure_tracker.dart';
import 'package:writingcoach/services/error_handler.dart';

void main() {
  late AppDatabase db;
  late SessionRepository sessionRepo;
  late DiagnosisFailureTracker tracker;
  late String sessionId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    sessionRepo = SessionRepository(db);
    tracker = DiagnosisFailureTracker(sessionRepo: sessionRepo);
    sessionId = await sessionRepo.createBlankSession(title: 'A2 tracker 测试');
    ErrorHandler.instance.resetForTesting();
    ErrorHandler.instance.attachRepository(ErrorLogRepository(db));
  });

  tearDown(() async {
    ErrorHandler.instance.resetForTesting();
    await db.close();
  });

  /// 数当前会话里的诊断失败卡条数（按 messageType 精确匹配）。
  Future<int> failedCardCount() async {
    final msgs = await sessionRepo.listMessages(sessionId);
    return msgs.where((m) => m.messageType == 'diagnosis_failed').length;
  }

  /// 查本会话落下的 diagnosis_failure 日志。
  ///
  /// captureError 是 unawaited 写库 ⇒ 先等一拍再查，否则会读到空集
  /// （这是本仓既有的时序陷阱，见 diagnosis_failure_reason_test 同型处理）。
  Future<List<dynamic>> failureLogs() async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final rows = await ErrorLogRepository(
      db,
    ).queryErrorLogs(query: ErrorLogQuery(limit: 100));
    return rows.where((r) {
      final ctx = r.context;
      return ctx != null && ctx['event'] == kDiagnosisFailureEvent;
    }).toList();
  }

  group('组1 计数语义', () {
    test('attempted && !success ⇒ 计数 +1 且插卡', () async {
      await tracker.record(
        sessionId: sessionId,
        attempted: true,
        success: false,
        rejectReason: 'missing_block',
      );
      expect(tracker.consecutiveFailsOf(sessionId), 1);
      expect(await failedCardCount(), 1, reason: '每次失败都插卡（首次也插）');
    });

    test('连续三次失败 ⇒ 计数到 3 且插 3 张卡', () async {
      for (var i = 0; i < 3; i++) {
        await tracker.record(
          sessionId: sessionId,
          attempted: true,
          success: false,
          rejectReason: 'missing_block',
        );
      }
      expect(tracker.consecutiveFailsOf(sessionId), 3);
      expect(await failedCardCount(), 3);
    });

    test('成功 ⇒ 计数清零（且不再插卡）', () async {
      await tracker.record(
        sessionId: sessionId,
        attempted: true,
        success: false,
        rejectReason: 'missing_block',
      );
      await tracker.record(
        sessionId: sessionId,
        attempted: true,
        success: true,
      );
      expect(tracker.consecutiveFailsOf(sessionId), 0, reason: '成功必须清零');
      expect(await failedCardCount(), 1, reason: '成功轮次不插卡');
    });

    test('反例：attempted=false（普通聊天）⇒ 计数不动、不插卡', () async {
      await tracker.record(
        sessionId: sessionId,
        attempted: false,
        success: false,
        rejectReason: 'missing_block',
      );
      expect(tracker.consecutiveFailsOf(sessionId), 0);
      expect(await failedCardCount(), 0, reason: '普通聊天不得误触发失败卡');
      expect(await failureLogs(), isEmpty, reason: '非诊断轮次不得留痕');
    });
  });

  group('组2 空匹配语义边界（A2 核心）', () {
    test('解析成功但零症候 ⇒ reason=empty_match，且【不计失败、不插卡】', () async {
      // syndromeCount=0 是「解析通过但一条症候都没匹配到」的形态。
      await tracker.record(
        sessionId: sessionId,
        attempted: true,
        success: true,
        syndromeCount: 0,
      );
      expect(
        tracker.consecutiveFailsOf(sessionId),
        0,
        reason: '空匹配是观测项，不是失败项（判定口径不变）',
      );
      expect(await failedCardCount(), 0, reason: '空匹配不得插失败卡');

      final logs = await failureLogs();
      expect(logs, hasLength(1), reason: '空匹配必须可被看见（A2 的目的）');
      expect(logs.single.context?['reason'], kDiagnosisFailureEmptyMatch);
      expect(logs.single.context?['path'], 'parse');
    });

    test('反例：success 且症候数 > 0 ⇒ 完全不留痕（正常诊断不产生噪音）', () async {
      await tracker.record(
        sessionId: sessionId,
        attempted: true,
        success: true,
        syndromeCount: 3,
      );
      expect(await failureLogs(), isEmpty);
      expect(tracker.consecutiveFailsOf(sessionId), 0);
    });

    test('反例：success 且 syndromeCount 未传 ⇒ 不写日志（缺参不臆造）', () async {
      await tracker.record(
        sessionId: sessionId,
        attempted: true,
        success: true,
      );
      expect(await failureLogs(), isEmpty);
    });
  });

  group('组3 失败原因归类', () {
    test('解析被拒 ⇒ reason=parse_failed + detail 保留原 reject 码', () async {
      await tracker.record(
        sessionId: sessionId,
        attempted: true,
        success: false,
        rejectReason: 'json_invalid',
        syndromeCount: null,
      );
      final log = (await failureLogs()).single;
      expect(log.context?['reason'], kDiagnosisFailureParseFailed);
      expect(log.context?['detail'], 'json_invalid', reason: '原码不得丢');
      expect(log.context?['failureCount'], 1);
    });

    test('无 rejectReason 且未传 syndromeCount ⇒ 兜底 unknown（不冒充已知）', () async {
      await tracker.record(
        sessionId: sessionId,
        attempted: true,
        success: false,
      );
      expect(
        (await failureLogs()).single.context?['reason'],
        kDiagnosisFailureUnknown,
      );
    });

    test('落库不带 sessionId 原文（防反查用户）', () async {
      await tracker.record(
        sessionId: sessionId,
        attempted: true,
        success: false,
        rejectReason: 'missing_block',
      );
      final log = (await failureLogs()).single;
      expect(log.context?.containsKey('sessionId'), isFalse);
      expect(log.context?['hasSession'], isTrue);
    });
  });

  group('组4 会话隔离', () {
    test('不同 session 的计数互不影响', () async {
      final other = await sessionRepo.createBlankSession(title: 'A2 另一个会话');
      await tracker.record(
        sessionId: sessionId,
        attempted: true,
        success: false,
        rejectReason: 'missing_block',
      );
      expect(tracker.consecutiveFailsOf(sessionId), 1);
      expect(tracker.consecutiveFailsOf(other), 0, reason: '计数必须按 session 分桶');
    });

    test('会话 A 失败后会话 B 成功，不得清掉 A 的计数', () async {
      final other = await sessionRepo.createBlankSession(title: 'A2 会话 B');
      await tracker.record(
        sessionId: sessionId,
        attempted: true,
        success: false,
        rejectReason: 'missing_block',
      );
      await tracker.record(sessionId: other, attempted: true, success: true);
      expect(
        tracker.consecutiveFailsOf(sessionId),
        1,
        reason: 'B 的成功不得清零 A 的失败计数',
      );
    });
  });
}
