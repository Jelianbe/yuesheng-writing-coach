// ─────────────────────────────────────────────────────────────
// ErrorHandler 单元测试 — 批次2（2.1）错误日志接线
//
// 覆盖路径：
//   1. DB ready 前 captureError → 入内存队列（不直接写库）
//   2. attachRepository → 队列 flush 写入 error_logs
//   3. attach 后 captureError → 直接写库
//   4. 队列溢出（>200）→ 丢弃最旧，内存有界
//   5. A12 安全红线：错误体中的凭据落库前脱敏（宪法 §八）
//   6. context 为 null → 落库保持 null；非字符串值原样保留
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/error_log_repository.dart';
import 'package:writingcoach/services/error_handler.dart';

void main() {
  setUp(() {
    ErrorHandler.instance.resetForTesting();
  });

  test('#1 DB ready 前入队，attachRepository 后 flush 写入', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = ErrorLogRepository(db);

    // 未 attach：两条错误入内存队列
    ErrorHandler.instance.captureError(
      level: 'error',
      category: 'render',
      message: '错误A：构建失败',
      stack: 'StackA',
    );
    ErrorHandler.instance.captureError(
      level: 'warning',
      category: 'general',
      message: '错误B：平台异常',
      context: {'code': 500},
    );
    expect(
      await repo.queryErrorLogs(),
      isEmpty,
      reason: 'DB ready 前不直接写库（先入队列防丢）',
    );

    // attach → 异步 flush
    ErrorHandler.instance.attachRepository(repo);
    await pumpEventQueue();

    final logs = await repo.queryErrorLogs();
    expect(logs.length, 2, reason: '队列应在 attach 后 flush 写入');
    expect(logs.any((e) => e.message == '错误A：构建失败'), true);
    expect(logs.any((e) => e.message == '错误B：平台异常'), true);
    final b = logs.firstWhere((e) => e.message == '错误B：平台异常');
    expect(b.category, 'general');
    expect(b.context, {'code': 500});
    expect(b.stack, isNull);
  });

  test('#2 attach 后 captureError → 直接写库', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = ErrorLogRepository(db);
    ErrorHandler.instance.attachRepository(repo);

    ErrorHandler.instance.captureError(
      level: 'error',
      category: 'general',
      message: '异步未捕获异常',
      stack: 'StackX',
    );
    await pumpEventQueue();

    final logs = await repo.queryErrorLogs();
    expect(logs.length, 1);
    expect(logs.first.level, 'error');
    expect(logs.first.category, 'general');
    expect(logs.first.stack, 'StackX');
  });

  test('#3 队列溢出（>200）→ 丢弃最旧，内存有界', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = ErrorLogRepository(db);

    // 未 attach 时塞 205 条
    for (int i = 0; i < 205; i++) {
      ErrorHandler.instance.captureError(
        level: 'error',
        category: 'general',
        message: '溢出测试#$i',
      );
    }

    ErrorHandler.instance.attachRepository(repo);
    await pumpEventQueue();

    final logs = await repo.queryErrorLogs(query: ErrorLogQuery(limit: 1000));
    expect(logs.length, 200, reason: '队列上限 200，超出的最旧 5 条应被丢弃');
    // 最旧的 0-4 被丢弃，保留 5-204
    expect(logs.any((e) => e.message == '溢出测试#0'), false);
    expect(logs.any((e) => e.message == '溢出测试#5'), true);
    expect(logs.any((e) => e.message == '溢出测试#204'), true);
  });

  test('#5 A12 安全红线：错误体中的凭据落库前已脱敏', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = ErrorLogRepository(db);
    ErrorHandler.instance.attachRepository(repo);

    ErrorHandler.instance.captureError(
      level: 'error',
      category: 'network',
      message: '请求失败 Authorization: Bearer sk-abcdef123456',
      stack: 'at client.dart:12 api_key=live_secret_789',
      context: {'url': 'https://api.example.com', 'retry': 2},
    );
    await pumpEventQueue();

    final logs = await repo.queryErrorLogs();
    expect(logs.length, 1);
    final log = logs.first;

    // 核心断言：裸凭据一律不得出现在任何落库字段里
    expect(log.message, isNot(contains('sk-abcdef123456')));
    expect(log.stack, isNot(contains('live_secret_789')));
    expect(log.message, contains('***'));
    expect(log.stack, contains('***'));
    // 无敏感信息的 context 应原样保留（非字符串值不被脱敏碰到）
    expect(log.context?['url'], 'https://api.example.com');
    expect(log.context?['retry'], 2);
  });

  test('#6 A12：context 为 null 时落库保持 null（不被 coerce 成空 Map）', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = ErrorLogRepository(db);
    ErrorHandler.instance.attachRepository(repo);

    ErrorHandler.instance.captureError(
      level: 'error',
      category: 'general',
      message: '无上下文错误',
      // context 与 stack 均不传
    );
    await pumpEventQueue();

    final logs = await repo.queryErrorLogs();
    expect(logs.length, 1);
    expect(logs.first.context, isNull);
    expect(logs.first.stack, isNull);
  });
}
