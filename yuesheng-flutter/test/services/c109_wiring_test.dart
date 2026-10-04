// ─────────────────────────────────────────────────────────────
// c109_wiring_test — ADR-C109 装配层 / 源码扫描护栏
//
// 这些落点无法用「调公开 API + 收集 sink」单测覆盖（设置页 new LlmClient
// 的接线、四个调用点的 markCallContext、_logBudgetOutcome 的旁路日志），
// 故用源码扫描 + 可注入 ErrorHandler 的行为断言守住：
//   · B2：settings_page.dart 自建 LlmClient 接了持久 sink
//   · C13：4 个调用点各出现 markCallContext 恰好一次（逐处断言、不求和）
//   · C17：_logBudgetOutcome 调 recordBudgetOutcomeLog，且该函数把
//     event='llm_budget' 落进 error_logs（可查询）
// ─────────────────────────────────────────────────────────────

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/error_log_repository.dart';
import 'package:writingcoach/services/chat_service.dart';
import 'package:writingcoach/services/error_handler.dart';
import 'package:writingcoach/services/token_budget_guard.dart';

String _src(String rel) => File(rel).readAsStringSync();

void main() {
  group('C109 源码装配扫描', () {
    test('B2：API 配置侧自建 LlmClient 接持久 sink', () {
      //★ 2026-10-04 随 B5 第二批调整判据落点（B5-2）：API 表单与「测试连接/并保存」
      //  已从 settings_page.dart 下沉到 api_config_page.dart，`LlmClient` 自建
      //  （含 sink 接线）随之搬走。原判据**硬编码 settings_page.dart 路径**
      //  ⇒ 搬运后恒红，但功能其实没丢（已核 api_config_page.dart 仍在该行）。
      //  教训：判据若钉在「某个文件必须有某行」，重构搬运后它会变成假红；
      //  此类判据应钉「**该能力所在处**必须有该行」，且能力搬家时要同步改。
      //  这里不写死单一文件 —— 未来若再下沉一层，只需改这一处列表。
      const files = <String>[
        'lib/features/app_settings/api_config_page.dart',
        'lib/providers/session_providers.dart',
      ];
      for (final f in files) {
        expect(
          _src(f).contains('LlmCallLogSink().call'),
          isTrue,
          reason:
              '$f 自建/提供的 LlmClient 必须接 LlmCallLogSink().call，'
              '否则连通性测试用量零落库',
        );
      }
    });

    test('C13：调用点各出现 markCallContext 恰好 N 次（逐处断言、不求和）', () {
      const files = <String, int>{
        'lib/services/editor_service.dart': 1,
        'lib/services/setting_assertion_extractor.dart': 1,
        // ADR-C132 批3：coach_selector_card 增「试听语气」链路（与润色
        // 同一教练人格 AI 辅助语义）→ 2 处。
        'lib/features/app_settings/coach_selector_card.dart': 2,
        'lib/features/character/character_detail_page.dart': 1,
      };
      for (final e in files.entries) {
        final src = _src(e.key);
        final count = 'markCallContext'.allMatches(src).length;
        expect(
          count,
          e.value,
          reason: '${e.key} 应标注 ${e.value} 处业务链路（实测 $count 处）',
        );
      }
    });

    test(
      'C17：_logBudgetOutcome 调 recordBudgetOutcomeLog，且载荷 event=llm_budget',
      () {
        final svc = _src('lib/services/chat_service.dart');
        expect(
          svc.contains('recordBudgetOutcomeLog(guardReport)'),
          isTrue,
          reason: '_logBudgetOutcome 触发降级/超警告时必须旁路落 error_logs',
        );
        expect(
          svc.contains("'event': 'llm_budget'"),
          isTrue,
          reason: '预算旁路日志必须带 event=llm_budget 供查询侧归类',
        );
      },
    );
  });

  group('C17 行为：预算旁路日志可查询', () {
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

    test(
      'triggered 报告 ⇒ error_logs 落 1 条 category=api/event=llm_budget',
      () async {
        recordBudgetOutcomeLog(
          const BudgetGuardReport(
            overBudget: true,
            triggered: true,
            overWarning: false,
            totalBefore: 90000,
            totalAfter: 70000,
            droppedStages: ['L2 按需组（仅当前 mode 一组）'],
            droppedMessageCount: 3,
          ),
        );
        // captureError 是 unawaited 写库 ⇒ 等一拍
        await Future<void>.delayed(const Duration(milliseconds: 50));

        final rows = await ErrorLogRepository(
          db,
        ).queryErrorLogs(query: ErrorLogQuery(category: 'api', limit: 50));
        final budgetRows = rows.where((r) {
          final ctx = r.context;
          return ctx != null && ctx['event'] == 'llm_budget';
        }).toList();
        expect(budgetRows, hasLength(1));
        expect(budgetRows.single.context?['triggered'], isTrue);
        expect(budgetRows.single.context?['droppedMessageCount'], 3);
      },
    );
  });
}
