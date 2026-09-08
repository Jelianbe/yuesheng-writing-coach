// ─────────────────────────────────────────────────────────────
// guardRepoWrite 单元测试 — CR-12 边界层写操作留痕
//
// 本包装的核心契约是「只补留痕、不改语义」，故测试锁三件事：
//   1. 成功路径：返回值透传，且**不**产生任何 error_logs（成功不污染日志）
//   2. 失败路径：异常**原样**抛出（同一对象、同类型、同消息），控制流零变更
//   3. 失败路径：落一条 error_logs，category='database' / level='error'
//   4. context 自定义定位字段进入日志；正文类敏感值不得进入（R-029）
//   5. 连续失败 → 逐条留痕，不合并、不丢弃
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/error_log_repository.dart';
import 'package:writingcoach/data/repositories/repository_write_guard.dart';
import 'package:writingcoach/services/error_handler.dart';

void main() {
  late AppDatabase db;
  late ErrorLogRepository logRepo;

  setUp(() {
    ErrorHandler.instance.resetForTesting();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    logRepo = ErrorLogRepository(db);
    ErrorHandler.instance.attachRepository(logRepo);
  });

  tearDown(() async {
    ErrorHandler.instance.resetForTesting();
    await db.close();
  });

  test('#1 成功：返回值透传，且不落任何 error_logs', () async {
    final result = await guardRepoWrite('chapter', 'createChapter', () async {
      return 'new-id';
    });

    expect(result, 'new-id', reason: '成功时返回值必须原样透传');
    await pumpEventQueue();
    expect(
      await logRepo.queryErrorLogs(),
      isEmpty,
      reason: '成功路径不应产生日志，否则会淹没真正的故障',
    );
  });

  test('#2 失败：异常原样抛出（同对象、同类型、同消息）', () async {
    final thrown = StateError('DB closed');

    Object? caught;
    try {
      await guardRepoWrite<void>('chapter', 'saveChapterContent', () async {
        throw thrown;
      });
    } catch (e) {
      caught = e;
    }

    expect(caught, isNotNull, reason: '包装不得吞异常——它只补留痕');
    expect(identical(caught, thrown), true, reason: '必须是同一异常对象（rethrow 语义）');
    expect(caught, isA<StateError>());
    expect((caught! as StateError).message, 'DB closed');
  });

  test('#3 失败：落一条 error_logs，category=database / level=error', () async {
    await expectLater(
      guardRepoWrite<void>('volume', 'deleteVolume', () async {
        throw StateError('boom');
      }),
      throwsA(isA<StateError>()),
    );
    await pumpEventQueue();

    final logs = await logRepo.queryErrorLogs();
    expect(logs.length, 1, reason: '失败应落一条可归因的日志');
    expect(logs.first.category, 'database');
    expect(logs.first.level, 'error');
    expect(logs.first.message, 'volume.deleteVolume 写操作失败');
    expect(logs.first.stack, isNotNull, reason: '留痕要带堆栈才能定位抛出点');
  });

  test('#4 context 透传定位字段，且不夹带正文内容', () async {
    await expectLater(
      guardRepoWrite<void>('chapter', 'updateChapterTitle', () async {
        throw StateError('boom');
      }, context: {'chapterId': 'c-1'}),
      throwsA(isA<StateError>()),
    );
    await pumpEventQueue();

    final log = (await logRepo.queryErrorLogs()).first;
    expect(log.context, isNotNull);
    expect(log.context!['repo'], 'chapter');
    expect(log.context!['op'], 'updateChapterTitle');
    expect(log.context!['chapterId'], 'c-1');
    final serialized = log.context.toString();
    expect(
      serialized.contains('正文'),
      false,
      reason: '包装本身不注入内容类字段（R-029 脱敏），调用方也禁止传正文',
    );
  });

  test('#5 连续失败两次 → 两条日志，不合并不丢弃', () async {
    for (var i = 0; i < 2; i++) {
      await expectLater(
        guardRepoWrite<void>('chapter', 'purgeChapter', () async {
          throw StateError('boom $i');
        }),
        throwsA(isA<StateError>()),
      );
    }
    await pumpEventQueue();

    final logs = await logRepo.queryErrorLogs();
    expect(logs.length, 2, reason: '每次失败都应独立留痕');
    expect(logs.map((e) => e.context?['op']).toSet(), {'purgeChapter'});
  });
}
