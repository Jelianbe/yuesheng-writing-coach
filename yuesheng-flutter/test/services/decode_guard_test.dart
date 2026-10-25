// ─────────────────────────────────────────────────────────────
// decode_guard_test — C-3 批：数据解析失败的可观测降级守卫
//
// 覆盖对象：lib/services/decode_guard.dart（78 行，0 覆盖）
//   公开符号：logDecodeFailure · logSilentDegrade（各 2 个：debugPrint 半 + captureError 半）
//
// ★ 本文件只补 C-1 裁定（.ai/research/t13-c1-test-triage.md §⑦）点名的**三个缺口**，
//   不重复既有覆盖：
//   · logDecodeFailure 的 debugPrint 半 → 已由 test/services/character_identity_test.dart:315-353
//     覆盖 ⇒ 本文件**不再**重复断言 debugPrint 内容。
//   · logSilentDegrade 的 captureError 半 → 已由
//     test/widgets/chat_session_controller_test.dart:278-281 覆盖 ⇒ 本文件**不再**重复断言
//     level/category 落库。
//   本文件补的三个缺口：
//     ① logDecodeFailure 的 captureError 半（落库半）—— 从未被断言。
//     ② 两个函数的 category 归类 —— 从未被断言（teacher_parser 走 'api'，默认 'database'）。
//     ③ logSilentDegrade 的 debugPrint 半 —— 从未被断言（对称性）。
//
// ★ 可红判据（每条用例的「改哪一处必红」）—— 见文件末尾 _RED_MUTATIONS 说明与产物报告：
//   ① 删 lib/services/decode_guard.dart:44-52 的 captureError 调用 ⇒ 用例 A/B/C 必红。
//      把 :47 的 level:'warn' 改成 'error'            ⇒ 用例 A 必红。
//      把 :48 的 category: category 改成 'database'   ⇒ 用例 B 必红。
//   ② 删 lib/services/teacher_parser.dart:51 的 category:'api' 实参
//      ⇒ 用例 D 必红（落库 category 变 'database'）。
//   ③ 删 lib/services/decode_guard.dart:70 的 debugPrint ⇒ 用例 E 必红。
//
// ★ 竞态说明：ErrorHandler.captureError 内部是 unawaited 异步落库
//   （lib/services/error_handler.dart:149）⇒ 必须轮询等行出现，
//   不用固定 sleep。轮询 helper 形态复刻 test/services/editor_service_test.dart:212。
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/app_state_repository.dart';
import 'package:writingcoach/data/repositories/error_log_repository.dart';
import 'package:writingcoach/services/decode_guard.dart';
import 'package:writingcoach/services/error_handler.dart';
import 'package:writingcoach/services/teacher_parser.dart';

/// 等待 captureError 的异步落库完成（内部 unawaited 写库，需轮询）。
Future<List<ErrorLogEntry>> _waitLogs(ErrorLogRepository repo) async {
  for (var i = 0; i < 50; i++) {
    final logs = await repo.queryErrorLogs();
    if (logs.isNotEmpty) return logs;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  return repo.queryErrorLogs();
}

/// 轮询等待 error_logs 出现指定条数。
Future<List<ErrorLogEntry>> _waitLogsAtLeast(
  ErrorLogRepository repo,
  int minCount,
) async {
  for (var i = 0; i < 50; i++) {
    final logs = await repo.queryErrorLogs();
    if (logs.length >= minCount) return logs;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  return repo.queryErrorLogs();
}

void main() {
  late AppDatabase db;
  late ErrorLogRepository errorLogRepo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    errorLogRepo = ErrorLogRepository(db);
    ErrorHandler.instance.resetForTesting();
    ErrorHandler.instance.attachRepository(errorLogRepo);
  });

  tearDown(() async {
    ErrorHandler.instance.resetForTesting();
    await db.close();
  });

  group('logDecodeFailure — 落库半（C-1 §⑦ 判据 A/B）', () {
    test(
      '#A1 解析失败 → error_logs 落一行：level=warn / category=database / message 与 context 带 field 与错误',
      () async {
        logDecodeFailure(
          field: 'teachingHistory',
          error: const FormatException('坏 JSON'),
          stack: StackTrace.current,
        );

        final logs = await _waitLogs(errorLogRepo);
        expect(logs.length, 1, reason: '降级必须留痕：恰好一条 error_logs');
        expect(logs.single.level, 'warn', reason: '降级未中断功能 ⇒ warn 而非 error');
        expect(
          logs.single.category,
          'database',
          reason: '默认 category 钉 database',
        );
        expect(
          logs.single.message,
          contains('teachingHistory'),
          reason: 'message 必须带 field 名，便于事后定位',
        );
        expect(
          logs.single.message,
          contains('解析失败'),
          reason: 'message 必须表明这是解析失败',
        );
        expect(
          logs.single.context?['field'],
          'teachingHistory',
          reason: 'context 必须带 field，便于按字段聚合',
        );
        expect(
          logs.single.context?['error'],
          contains('坏 JSON'),
          reason: 'context 必须带原始错误文本，否则无从判断损坏原因',
        );
      },
    );

    test('#A2 同一字段连续两次降级 → 落两行（留痕不被合并吞掉）', () async {
      logDecodeFailure(field: 'styleProfile', error: 'E1');
      logDecodeFailure(field: 'styleProfile', error: 'E2');

      final logs = await _waitLogsAtLeast(errorLogRepo, 2);
      expect(logs.length, 2, reason: '两次降级 = 两条独立留痕');
      final fields = logs.map((r) => r.context?['field']).toList();
      expect(fields, everyElement('styleProfile'));
      final errors = logs.map((r) => r.context?['error']).toList();
      expect(errors, containsAll(<String>['E1', 'E2']));
    });

    test('#B category 实参生效：显式传 api → 落库 category=api（不是默认 database）', () async {
      logDecodeFailure(field: 'teacherStream', error: 'boom', category: 'api');

      final logs = await _waitLogs(errorLogRepo);
      expect(logs.length, 1);
      expect(
        logs.single.category,
        'api',
        reason: 'category 实参必须透传到 error_logs —— 否则分流失效',
      );
      expect(logs.single.level, 'warn');
    });
  });

  group('logDecodeFailure — 消费链路的 category 归类（C-1 §⑦ 判据 B）', () {
    test('#D teacher_parser 解析坏 JSON → 落库 category=api（不是 database）', () async {
      // 走 lib/services/teacher_parser.dart:48-53 的 catch 分支：
      // 该处显式传 category:'api' ⇒ 落库行必须是 api。
      final result = parseTeacherDecision(
        '[YS_TEACHER]{这不是合法 JSON}[/YS_TEACHER]',
      );

      expect(result.teacher, isNull, reason: '解析失败 ⇒ 降级为无教学决策');
      expect(
        result.displayContent,
        isEmpty,
        reason: 'displayContent 仍保留（不因解析失败丢掉用户可见文本）',
      );

      final logs = await _waitLogs(errorLogRepo);
      expect(logs.length, 1, reason: '解析失败必须留痕');
      expect(
        logs.single.category,
        'api',
        reason: 'teacher_parser 显式传 category:api ⇒ 落库必须是 api',
      );
      expect(logs.single.level, 'warn');
      expect(logs.single.context?['field'], 'teacherStream');
    });
  });

  group('logSilentDegrade — debugPrint 半（C-1 §⑦ 判据 C）', () {
    test('#E 静默降级 → debugPrint 输出含 [degrade] 与 operation 名', () async {
      final printed = <String>[];
      final originalDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        printed.add(message ?? '');
      };
      addTearDown(() => debugPrint = originalDebugPrint);

      logSilentDegrade(operation: 'inferCognitiveStyle', error: 'E');

      expect(
        printed.any((l) => l.contains('[degrade]')),
        isTrue,
        reason: '静默降级必须留 console 痕迹（R-028）',
      );
      expect(
        printed.any(
          (l) => l.contains('inferCognitiveStyle') && l.contains('降级'),
        ),
        isTrue,
        reason: '痕迹必须带 operation 名与「降级」二字，否则事后无从归因',
      );
    });
  });

  group('logDecodeFailure — 真实降级链路（app_state 章节草稿损坏）', () {
    test(
      '#F getChapterDraft 解析损坏 JSON → 落库 field=app_state.chapter_draft + 返回 null（降级不崩）',
      () async {
        // 写入一份损坏的章节草稿（绕开 setValue 的正常路径，直接写脏数据）。
        final appState = AppStateRepository(db);
        await appState.setValue('chapter_draft:ch_1', '{这不是合法 JSON');

        final draft = await appState.getChapterDraft('ch_1');

        expect(draft, isNull, reason: '脏数据 ⇒ 降级为 null，不得抛异常');
        final logs = await _waitLogs(errorLogRepo);
        expect(logs.length, 1, reason: '真实降级链路必须留痕');
        expect(logs.single.level, 'warn');
        expect(
          logs.single.category,
          'database',
          reason: 'app_state 是 DB 内 JSON 字段损坏 ⇒ 默认 category=database',
        );
        expect(logs.single.context?['field'], 'app_state.chapter_draft');
      },
    );
  });
}
