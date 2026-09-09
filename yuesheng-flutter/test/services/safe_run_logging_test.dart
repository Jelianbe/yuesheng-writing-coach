// ─────────────────────────────────────────────────────────────
// safe_run_logging_test — CR-53 [SafeRun] 降级统一留痕契约
//
// 背景：message_injector / chat_service 的「不阻断主流程」降级路径
// 此前只有 debugPrint（release 不输出→生产静默、无法归因），
// 与诊断编排（captureError 正确形态）形成实现分歧。
// 修复：抽 _logSafeRun helper + 替换全部降级点（CR-53）。
//
// 覆盖：
//   1. 源码契约：两文件各定义 _logSafeRun helper
//   2. 源码契约：降级点全部经 _logSafeRun（无裸 debugPrint('[SafeRun]）
//   3. 源码契约：catch 形态带 st（捕获栈传给 helper）
//   4. 行为契约：captureError 真实落 error_logs（level/category 归一）
// ─────────────────────────────────────────────────────────────

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/error_log_repository.dart';
import 'package:writingcoach/services/error_handler.dart';

void main() {
  group('CR-53 [SafeRun] 统一留痕契约', () {
    test('1. chat_service 与 message_injector 各定义 _logSafeRun helper', () {
      for (final f in [
        'lib/services/chat_service.dart',
        'lib/services/message_injector.dart',
      ]) {
        final src = File(f).readAsStringSync();
        expect(
          src,
          contains('void _logSafeRun(String stage, Object e, StackTrace s)'),
          reason: '$f 必须定义统一留痕 helper（CR-53）',
        );
      }
    });

    test('2. 降级点全部经 _logSafeRun，无裸 debugPrint([SafeRun])', () {
      for (final f in [
        'lib/services/chat_service.dart',
        'lib/services/message_injector.dart',
      ]) {
        final src = File(f).readAsStringSync();
        // helper 定义内 1 处 debugPrint('[SafeRun] $stage: $e') 合法
        final bare = RegExp(r"debugPrint\('\[SafeRun\]").allMatches(src).length;
        expect(
          bare,
          lessThanOrEqualTo(1),
          reason: '$f 中降级点必须走 _logSafeRun，不允许裸 debugPrint（允许 helper 内 1 处）',
        );
        // helper 定义自身也算 _logSafeRun 出现——调用数 = 总出现 - 1（本文件定义）
        final total = '_logSafeRun('.allMatches(src).length;
        final calls = total - 1;
        expect(calls, greaterThan(0), reason: '$f 至少一个降级点调用 helper');
      }
      // 全量：message_injector 25 + chat_service 2 = 27 处降级点。
      // 注：审查文档估算 30（含诊断编排 helper 或重复计数），
      // 实际全仓 grep 无裸 debugPrint('[SafeRun] 残留——27 为全部收敛点。
      final mi = File('lib/services/message_injector.dart').readAsStringSync();
      final cs = File('lib/services/chat_service.dart').readAsStringSync();
      final miCalls = '_logSafeRun('.allMatches(mi).length - 1;
      final csCalls = '_logSafeRun('.allMatches(cs).length - 1;
      expect(
        miCalls + csCalls,
        27,
        reason: 'CR-53 应覆盖全部降级点（实际 mi=$miCalls cs=$csCalls）',
      );
    });

    test('3. catch 形态带栈：降级 catch 均捕获 st 并传入 helper', () {
      final cs = File('lib/services/chat_service.dart').readAsStringSync();
      final mi = File('lib/services/message_injector.dart').readAsStringSync();
      // 降级点应形如 catch (e, st) { _logSafeRun('...', e, st); }
      final pattern = RegExp(
        r"catch \(e, st\) \{\s*_logSafeRun\('[^']*', e, st\);",
      );
      expect(
        pattern.allMatches(cs).length,
        2,
        reason: 'chat_service 2 处降级点必须带栈（CR-53）',
      );
      expect(
        pattern.allMatches(mi).length,
        greaterThanOrEqualTo(24),
        reason:
            'message_injector 降级点必须带栈（实测 ${pattern.allMatches(mi).length} 处）',
      );
    });
  });

  group('CR-53 行为：captureError 落库', () {
    test('captureError 经真实 ErrorLogRepository 落 error_logs', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      ErrorHandler.instance.resetForTesting();
      ErrorHandler.instance.attachRepository(ErrorLogRepository(db));

      ErrorHandler.instance.captureError(
        level: 'error',
        category: 'database',
        message: '[SafeRun] 测试降级留痕: boom',
        stack: 'test stack trace',
      );

      // flush 为异步（unawaited _persist）——轮询等待落库
      var rows = <ErrorLog>[];
      for (var i = 0; i < 50; i++) {
        rows = await db.select(db.errorLogs).get();
        if (rows.isNotEmpty) break;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(rows, hasLength(1), reason: 'captureError 应落库');
      expect(rows.single.message, contains('测试降级留痕'));
      expect(rows.single.level, 'error');
      expect(rows.single.category, 'database');
    });
  });
}
