// ─────────────────────────────────────────────────────────────
// diagnosis_failure_reason_test — A2「诊断失败原因可区分」
//
// 任务来源：`.ai/reports/2026-11-16-SCREENING-REPORT.md` A2 节
// 验收标准（订正版）：内部日志中失败原因可分类（至少区分
//   LLM 调用失败 / 结构化输出解析失败 / 症候匹配结果为空 / 超时）；
//   对外展示保持模糊（`diagnosis_failed` 卡文案一字不动）。
//
// 测试策略（三组）：
//   ① 分类器组：异常 → 码；解析结果 → 码。**每条正例配反例**，
//      防「断言写得松、恒真通过」（`.ai/PRACTICES.md A3c`）。
//   ② 落库组：`recordDiagnosisFailureLog` 走真实 captureError ⇒
//      error_logs 能按 `event=diagnosis_failure` 查出，字段逐一可比。
//   ③ 源码契约组：发送侧确实在**原一行**上补了 event/path/reason 三键
//      （而不是另起一行）—— 该落点无法用行为断言覆盖（私有方法 + 需全量装配）。
//
// ★ 本测试**不修改任何既有测试断言**（任务书 §0.1-4），全部为新增。
// ─────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/error_log_repository.dart';
import 'package:writingcoach/services/diagnosis_failure_reason.dart';
import 'package:writingcoach/services/error_handler.dart';

String _src(String rel) => File(rel).readAsStringSync();

void main() {
  group('A2 分类器：异常 → 原因码', () {
    test('超时（TimeoutException）→ timeout', () {
      expect(
        classifyDiagnosisFailureError(TimeoutException('连接超时')),
        kDiagnosisFailureTimeout,
      );
    });

    test('Dio 三类 timeout → timeout（逐类型断言，不求和）', () {
      const types = <DioExceptionType>[
        DioExceptionType.connectionTimeout,
        DioExceptionType.sendTimeout,
        DioExceptionType.receiveTimeout,
      ];
      for (final t in types) {
        final e = DioException(
          requestOptions: RequestOptions(path: '/x'),
          type: t,
        );
        expect(
          classifyDiagnosisFailureError(e),
          kDiagnosisFailureTimeout,
          reason: '$t 应归 timeout',
        );
      }
    });

    test('Dio 非超时错误 → llm_call_failed（与超时形成反例对照）', () {
      final e = DioException(
        requestOptions: RequestOptions(path: '/x'),
        type: DioExceptionType.badResponse,
      );
      expect(classifyDiagnosisFailureError(e), kDiagnosisFailureLlmCallFailed);
      // 反例：若上面误归 timeout，本行立刻红 —— 两码不可能同真。
      expect(classifyDiagnosisFailureError(e), isNot(kDiagnosisFailureTimeout));
    });

    test('普通 Exception → llm_call_failed', () {
      expect(
        classifyDiagnosisFailureError(Exception('401 unauthorized')),
        kDiagnosisFailureLlmCallFailed,
      );
    });

    test('不可归类对象 → unknown（不冒充已知）', () {
      // 「裸字符串」不是 Exception ⇒ 归 unknown。若实现图省事塞进
      // llm_call_failed，本条即红。
      expect(classifyDiagnosisFailureError('裸字符串'), kDiagnosisFailureUnknown);
    });

    test('码表含报告要求的四类 + unknown，且无重复', () {
      for (final must in <String>[
        kDiagnosisFailureLlmCallFailed,
        kDiagnosisFailureParseFailed,
        kDiagnosisFailureEmptyMatch,
        kDiagnosisFailureTimeout,
      ]) {
        expect(
          kDiagnosisFailureReasons.contains(must),
          isTrue,
          reason: '码表缺 $must',
        );
      }
      expect(
        kDiagnosisFailureReasons.toSet(),
        hasLength(kDiagnosisFailureReasons.length),
        reason: '码表有重复项',
      );
      expect(
        kDiagnosisFailureReasons.contains(kDiagnosisFailureUnknown),
        isTrue,
      );
    });
  });

  group('A2 分类器：解析结果 → 原因码', () {
    test('rejectReason 非空 → parse_failed', () {
      expect(
        classifyParseOutcome(
          rejectReason: 'json_decode_failed',
          syndromeCount: null,
        ),
        kDiagnosisFailureParseFailed,
      );
    });

    test('任意 reject 码都归 parse_failed（不按码分支，防漏一码）', () {
      for (final code in <String>[
        'marker_end_missing',
        'json_decode_failed',
        'root_not_object',
        'syndromes_not_list',
        'confidence_invalid',
      ]) {
        expect(
          classifyParseOutcome(rejectReason: code, syndromeCount: null),
          kDiagnosisFailureParseFailed,
          reason: '$code 应归 parse_failed',
        );
      }
    });

    test('解析通过但症候为 0 → empty_match', () {
      expect(
        classifyParseOutcome(rejectReason: null, syndromeCount: 0),
        kDiagnosisFailureEmptyMatch,
      );
    });

    test('解析通过且症候非空 → null（不写日志，防噪声）', () {
      expect(
        classifyParseOutcome(rejectReason: null, syndromeCount: 3),
        isNull,
      );
    });

    test('反例：症候为 0 时绝不能归 parse_failed', () {
      // 空匹配是模型的有效输出（一条症候都没报），语义上**不是解析失败**。
      // 若实现混为一类，本轮断言立刻红。
      expect(
        classifyParseOutcome(rejectReason: null, syndromeCount: 0),
        isNot(kDiagnosisFailureParseFailed),
      );
    });
  });

  group('A2 落库：诊断失败原因可查询', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      ErrorHandler.instance.resetForTesting();
      ErrorHandler.instance.attachRepository(ErrorLogRepository(db));
    });

    tearDown(() async {
      ErrorHandler.instance.resetForTesting();
      await db.close();
    });

    /// 按 event 键查全部诊断失败行。
    Future<List<dynamic>> queryFailures() async {
      // captureError 是 unawaited 写库 ⇒ 等一拍
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final rows = await ErrorLogRepository(
        db,
      ).queryErrorLogs(query: ErrorLogQuery(limit: 100));
      return rows.where((r) {
        final ctx = r.context;
        return ctx != null && ctx['event'] == kDiagnosisFailureEvent;
      }).toList();
    }

    test('超时 ⇒ 1 条 · path=send · reason=timeout', () async {
      recordDiagnosisFailureLog(
        reason: classifyDiagnosisFailureError(TimeoutException('idle timeout')),
        path: 'send',
      );
      final hits = await queryFailures();
      expect(hits, hasLength(1), reason: '超时失败必须落且只落 1 条');
      expect(hits.single.context?['path'], 'send');
      expect(hits.single.context?['reason'], kDiagnosisFailureTimeout);
    });

    test('网络失败 ⇒ reason=llm_call_failed，不冒充 timeout', () async {
      recordDiagnosisFailureLog(
        reason: classifyDiagnosisFailureError(
          DioException(
            requestOptions: RequestOptions(path: '/x'),
            type: DioExceptionType.connectionError,
          ),
        ),
        path: 'send',
      );
      final hits = await queryFailures();
      expect(hits, hasLength(1));
      expect(hits.single.context?['reason'], kDiagnosisFailureLlmCallFailed);
      expect(
        hits.single.context?['reason'],
        isNot(kDiagnosisFailureTimeout),
        reason: '网络错误不得冒充超时',
      );
    });

    test('解析被拒 ⇒ path=parse · detail 保留原 reject 码', () async {
      recordDiagnosisFailureLog(
        reason: kDiagnosisFailureParseFailed,
        path: 'parse',
        failureCount: 2,
        detail: 'marker_end_missing',
      );
      final hits = await queryFailures();
      expect(hits, hasLength(1));
      final ctx = hits.single.context!;
      expect(ctx['path'], 'parse');
      expect(ctx['reason'], kDiagnosisFailureParseFailed);
      expect(ctx['failureCount'], 2);
      // 原码不丢：上位分类后仍能追到 12 个 reject 码中的哪一个。
      expect(ctx['detail'], 'marker_end_missing');
    });

    test('空匹配 ⇒ reason=empty_match · syndromeCount=0', () async {
      recordDiagnosisFailureLog(
        reason: kDiagnosisFailureEmptyMatch,
        path: 'parse',
        syndromeCount: 0,
      );
      final hits = await queryFailures();
      expect(hits.single.context?['reason'], kDiagnosisFailureEmptyMatch);
      expect(hits.single.context?['syndromeCount'], 0);
    });

    test('不落 sessionId 原文（只落布尔），防反查用户', () async {
      recordDiagnosisFailureLog(
        reason: kDiagnosisFailureTimeout,
        path: 'send',
        hasSession: true,
      );
      final hits = await queryFailures();
      final ctx = hits.single.context!;
      expect(ctx.containsKey('hasSession'), isTrue);
      // 判据：context 里不得出现任何疑似会话标识的键。
      expect(ctx.containsKey('sessionId'), isFalse);
    });

    test('四类原因两两不同（一次查询即可区分）', () async {
      for (final r in <String>[
        kDiagnosisFailureLlmCallFailed,
        kDiagnosisFailureParseFailed,
        kDiagnosisFailureEmptyMatch,
        kDiagnosisFailureTimeout,
      ]) {
        recordDiagnosisFailureLog(reason: r, path: 'parse');
      }
      final hits = await queryFailures();
      expect(hits, hasLength(4));
      final reasons = hits.map((r) => r.context?['reason']).toSet();
      expect(reasons, hasLength(4), reason: '四类原因必须互不相同，否则「可区分」不成立');
    });
  });

  group('A2 源码契约：落库形状唯一真源 + 两侧只委托', () {
    test('发送侧落库函数带 event/path/reason，且只落一条日志', () {
      // A2 真分解后，发送侧落库形状的**唯一真源**在 diagnosis_failure_reason.dart。
      final src = _src('lib/services/diagnosis_failure_reason.dart');
      final start = src.indexOf('void recordSendFailureLog(');
      expect(start, greaterThan(-1), reason: '找不到 recordSendFailureLog');
      final body = src.substring(start); // 到文件末尾：本函数是文件最后一个声明

      expect(
        body.contains("'event': kDiagnosisFailureEvent"),
        isTrue,
        reason: '发送侧必须带 event 键，否则与解析侧无法一次查全',
      );
      expect(
        body.contains("'path': 'send'"),
        isTrue,
        reason: '必须标 path=send 以区分来源',
      );
      expect(
        body.contains('classifyDiagnosisFailureError(error)'),
        isTrue,
        reason: 'reason 必须来自分类器，不得硬编码',
      );
      // 反例：同一次失败只许落一条 —— 超过 1 次 captureError 即为重复留痕。
      expect('captureError'.allMatches(body).length, 1, reason: '同一次失败不得落两条日志');
      // 判据：改造前的 category 语义未被改写（网络类仍走 network）。
      expect(
        body.contains("error is DioException ? 'network' : 'api'"),
        isTrue,
        reason: 'category 取值必须保持改造前语义',
      );
    });

    test('发送侧调用点只委托，不自行拼 context', () {
      final svc = _src('lib/services/chat_service.dart');
      final start = svc.indexOf('void _logSendFailure(');
      expect(start, greaterThan(-1), reason: '找不到 _logSendFailure');
      final body = svc.substring(start, start + 400);
      expect(
        body.contains('recordSendFailureLog('),
        isTrue,
        reason: '发送侧必须复用同一落库函数',
      );
      expect(
        'captureError'.allMatches(body).length,
        0,
        reason: '落库形状只许一处表述（chat_service 不得内联）',
      );
    });

    test('解析侧（tracker）只复用落库函数，不自行拼 context', () {
      // A2 真分解后解析侧落点迁到 tracker（原 handler 的 _logDiagnosisFailure）。
      final tracker = _src('lib/services/diagnosis_failure_tracker.dart');
      expect(
        tracker.contains('recordDiagnosisFailureLog('),
        isTrue,
        reason: '解析侧必须复用同一落库函数，不得自行拼 context',
      );
      expect(
        'captureError'.allMatches(tracker).length,
        0,
        reason: '落库形状只许一处表述',
      );
      // 反例：handler 不得再有**诊断失败**落库形状。
      // 注：handler 里仍有 `_logSafeRun` 的 captureError（SafeRun 降级留痕，
      // 属既有实现、与本任务的失败原因留痕无关），故只断言诊断失败 event 不出现。
      final handler = _src('lib/services/diagnosis_flow_handler.dart');
      expect(
        handler.contains('recordDiagnosisFailureLog('),
        isFalse,
        reason: 'handler 不得再持有落库形状（已迁至 tracker）',
      );
      expect(
        handler.contains('kDiagnosisFailureEvent'),
        isFalse,
        reason: 'handler 不得自行写 event 键',
      );
    });
  });
}
