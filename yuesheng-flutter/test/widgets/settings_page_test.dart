// ─────────────────────────────────────────────────────────────
// SettingsPage widget 测试 — 设置页（缺口清单第 6 项）
//
// 覆盖路径：
//   1. 初始渲染 3 区块（API 配置/维护/关于）+ 未配置警告
//   2. 表单加载已有配置（fake storage）
//   3. 保存配置 → 写入 storage + 成功提示
//   4. 空表单保存 → 完整提示
//   5. 测试连接 → 成功结果框（fake llm）
//   6. 填充示例 → 字段填充
//   7. 清空配置 → 确认后字段 + storage 清空
//   8. 清除缓存 → 删除无消息的孤儿会话（保留有消息的）
//   9. 关于区块 → 应用名称/版本/包名
//  10. 反馈对话框 → 邮箱展示
// ─────────────────────────────────────────────────────────────

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/providers/app_providers.dart';
import 'package:writingcoach/router/app_router.dart';
import 'package:writingcoach/services/llm_client.dart';
import 'package:writingcoach/services/llm_config_storage.dart';
import 'package:writingcoach/widgets/settings_page.dart';

/// Fake 配置存储：内存 map，避免触碰 flutter_secure_storage
class _FakeConfigStorage extends LlmConfigStorage {
  LlmConfigValues? stored;

  @override
  Future<LlmConfigValues?> getLlmConfig() async => stored;

  @override
  Future<void> saveLlmConfig(LlmConfigValues config) async {
    stored = config;
  }

  @override
  Future<void> clearLlmConfig() async {
    stored = null;
  }
}

/// Fake LLM 客户端：固定返回成功，避免真实网络
class _FakeLlmClient extends LlmClient {
  TestConnectionResult? result;

  @override
  Future<TestConnectionResult> testLlmConnection({
    LlmConfigValues? config,
  }) async {
    return result ??
        const TestConnectionResult(success: true, message: '连接成功（42ms）');
  }
}

void main() {
  late AppDatabase db;
  late _FakeConfigStorage storage;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    storage = _FakeConfigStorage();
  });

  tearDown(() async => db.close());

  Widget buildSettings({_FakeLlmClient? llm}) {
    return ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: MaterialApp(
        home: SettingsPage(
          configStorage: storage,
          llmClient: llm ?? _FakeLlmClient(),
        ),
      ),
    );
  }

  testWidgets('#1 初始渲染 API 配置区块 + 未配置警告', (tester) async {
    await tester.pumpWidget(buildSettings());
    await tester.pumpAndSettle();

    // 首屏（ListView 懒加载：「维护」「关于」在 #9 滚动后验证）
    expect(find.text('API 配置'), findsOneWidget);
    expect(find.text('尚未配置 API，请填写以下信息以启用对话功能'), findsOneWidget);
  });

  testWidgets('#2 表单加载已有配置', (tester) async {
    storage.stored = const LlmConfigValues(
      apiKey: 'sk-existing',
      baseUrl: 'https://api.example.com',
      model: 'model-x',
    );

    await tester.pumpWidget(buildSettings());
    await tester.pumpAndSettle();

    // 表单已填充 → 未配置警告消失
    expect(find.text('尚未配置 API，请填写以下信息以启用对话功能'), findsNothing);
    final keyField = tester.widget<TextField>(find.byType(TextField).at(0));
    expect(keyField.controller!.text, 'sk-existing');
    expect(
      tester.widget<TextField>(find.byType(TextField).at(1)).controller!.text,
      'https://api.example.com',
    );
    expect(
      tester.widget<TextField>(find.byType(TextField).at(2)).controller!.text,
      'model-x',
    );
  });

  testWidgets('#3 保存配置 → 写入 storage', (tester) async {
    await tester.pumpWidget(buildSettings());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'sk-abc');
    await tester.enterText(
      find.byType(TextField).at(1),
      'https://api.deepseek.com/',
    );
    await tester.enterText(find.byType(TextField).at(2), 'deepseek-v4-flash');
    await tester.tap(find.text('保存配置'));
    await tester.pumpAndSettle();

    expect(storage.stored, isNotNull);
    expect(storage.stored!.apiKey, 'sk-abc');
    expect(storage.stored!.baseUrl, 'https://api.deepseek.com'); // 去尾部斜杠
    expect(storage.stored!.model, 'deepseek-v4-flash');
    expect(find.text('API 配置已保存'), findsOneWidget);
  });

  testWidgets('#4 空表单保存 → 完整提示', (tester) async {
    await tester.pumpWidget(buildSettings());
    await tester.pumpAndSettle();

    await tester.tap(find.text('保存配置'));
    await tester.pumpAndSettle();

    expect(find.text('请填写完整的 API 配置'), findsOneWidget);
    expect(storage.stored, isNull);
  });

  testWidgets('#5 测试连接 → 成功结果框', (tester) async {
    await tester.pumpWidget(buildSettings());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'sk-abc');
    await tester.enterText(
      find.byType(TextField).at(1),
      'https://api.deepseek.com',
    );
    await tester.enterText(find.byType(TextField).at(2), 'deepseek-v4-flash');
    await tester.tap(find.text('测试连接'));
    await tester.pumpAndSettle();

    expect(find.textContaining('✓ 连接成功'), findsOneWidget);
    // 测试连接前自动保存了表单
    expect(storage.stored, isNotNull);
  });

  testWidgets('#6 填充示例 → 字段填充', (tester) async {
    await tester.pumpWidget(buildSettings());
    await tester.pumpAndSettle();

    await tester.tap(find.text('填充示例配置'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(find.byType(TextField).at(1)).controller!.text,
      'https://api.deepseek.com',
    );
    expect(
      tester.widget<TextField>(find.byType(TextField).at(2)).controller!.text,
      'deepseek-v4-flash',
    );
  });

  testWidgets('#7 清空配置 → 确认后字段 + storage 清空', (tester) async {
    storage.stored = const LlmConfigValues(
      apiKey: 'sk-x',
      baseUrl: 'https://api.example.com',
      model: 'model-x',
    );
    await tester.pumpWidget(buildSettings());
    await tester.pumpAndSettle();

    await tester.tap(find.text('清空配置'));
    await tester.pumpAndSettle();
    expect(find.text('确定清空所有 API 配置吗？'), findsOneWidget);

    await tester.tap(find.text('清空'));
    await tester.pumpAndSettle();

    expect(storage.stored, isNull);
    expect(
      tester.widget<TextField>(find.byType(TextField).at(0)).controller!.text,
      '',
    );
  });

  testWidgets('#8 清除缓存 → 删除孤儿会话（保留有消息的）', (tester) async {
    final sessionRepo = SessionRepository(db);
    final withMsg = await sessionRepo.createBlankSession(title: '有消息');
    await sessionRepo.createBlankSession(title: '空会话');
    await sessionRepo.addMessage(withMsg, 'user', '你好');

    await tester.pumpWidget(buildSettings());
    await tester.pumpAndSettle();

    // 滚动到维护区块（ListView 懒加载：先挂载，再精确滚动到可视区）
    await tester.dragUntilVisible(
      find.text('清除缓存'),
      find.byType(ListView),
      const Offset(0, -200),
    );
    await tester.ensureVisible(find.text('清除缓存'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清除缓存'));
    await tester.pumpAndSettle();
    expect(find.textContaining('确定继续吗'), findsOneWidget);

    await tester.tap(find.text('清除'));
    await tester.pumpAndSettle();

    final remaining = await db.select(db.sessions).get();
    expect(remaining.length, 1);
    expect(remaining.single.id, withMsg);
    expect(find.textContaining('缓存已清除'), findsOneWidget);
  });

  testWidgets('#9 关于区块 → 应用名称/版本/包名', (tester) async {
    await tester.pumpWidget(buildSettings());
    await tester.pumpAndSettle();

    // 维护 + 关于区块（滚动到关于区）
    await tester.dragUntilVisible(
      find.text('应用名称'),
      find.byType(ListView),
      const Offset(0, -120),
    );
    expect(find.text('维护'), findsOneWidget);
    expect(find.text('关于'), findsOneWidget);
    expect(find.text('月笙写作教练'), findsOneWidget);
    expect(find.text('v1.0.0'), findsOneWidget);
    expect(find.text('com.yuesheng.writingcoach'), findsOneWidget);
  });

  testWidgets('#10 反馈对话框 → 邮箱展示 + 一键复制', (tester) async {
    // 批次78 L3：mock platform channel，Clipboard.setData 不落真实平台通道
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => null,
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });

    await tester.pumpWidget(buildSettings());
    await tester.pumpAndSettle();

    await tester.dragUntilVisible(
      find.text('反馈建议'),
      find.byType(ListView),
      const Offset(0, -200),
    );
    await tester.ensureVisible(find.text('反馈建议'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('反馈建议'));
    await tester.pumpAndSettle();

    expect(find.textContaining('feedback@yuesheng.app'), findsOneWidget);
    // 批次78 L3：新增「复制邮箱」按钮
    expect(find.text('复制邮箱'), findsOneWidget);
    await tester.tap(find.text('复制邮箱'));
    await tester.pumpAndSettle();

    // 复制成功轻提示 + 弹窗关闭
    expect(find.text('邮箱已复制'), findsOneWidget);
    expect(find.textContaining('feedback@yuesheng.app'), findsNothing);
  });

  // ── 批次 38: 学习进度区块（学习进度从书架移至设置页） ──

  testWidgets('#11 批次38 无会话 → 设置页不显示学习进度区块', (tester) async {
    await tester.pumpWidget(buildSettings());
    await tester.pumpAndSettle();

    expect(find.text('学习进度'), findsNothing);
  });

  testWidgets('#12 批次38 有会话 → 设置页显示学习进度区块（阶段/完成度/统计）', (tester) async {
    final sessionId = await SessionRepository(db).createBlankSession();
    // 教学状态 → P2
    await (db.update(
      db.teachingState,
    )..where((t) => t.sessionId.equals(sessionId))).write(
      TeachingStateCompanion(currentPhase: const Value('P2_PRACTICE_LOOP')),
    );
    // 问题：1 active + 1 resolved → 完成度 50%
    await db
        .into(db.activeProblems)
        .insert(
          ActiveProblemsCompanion.insert(
            id: 'ap-a',
            sessionId: sessionId,
            syndromeId: 's1',
            syndromeName: const Value('情绪标签化'),
            severity: const Value('L3'),
            status: const Value('active'),
          ),
        );
    await db
        .into(db.activeProblems)
        .insert(
          ActiveProblemsCompanion.insert(
            id: 'ap-b',
            sessionId: sessionId,
            syndromeId: 's2',
            syndromeName: const Value('情节断裂'),
            severity: const Value('L2'),
            status: const Value('resolved'),
          ),
        );

    await tester.pumpWidget(buildSettings());
    await tester.pumpAndSettle();

    // 进度区块：标题 + 阶段徽章 + 完成度 + 统计
    expect(find.text('学习进度'), findsOneWidget);
    expect(find.text('训练循环'), findsOneWidget);
    expect(find.text('50%'), findsOneWidget);
    expect(find.text('总问题'), findsOneWidget);
    expect(find.text('已解决'), findsOneWidget);
    expect(find.text('待改进'), findsOneWidget);
    expect(find.text('诊断 0 次'), findsOneWidget);
  });

  testWidgets('#13 批次38 点击进度区块「查看详情」→ 跳转学习进度详情页', (tester) async {
    await SessionRepository(db).createBlankSession();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp.router(routerConfig: appRouter),
      ),
    );
    await tester.pumpAndSettle();

    // 进入设置页
    appRouter.go(AppRoutes.settings);
    await tester.pumpAndSettle();

    expect(find.text('学习进度'), findsOneWidget);
    await tester.tap(find.text('查看详情'));
    await tester.pumpAndSettle();

    // 进入学习进度详情页
    expect(find.text('当前阶段'), findsOneWidget);
    expect(find.text('诊断次数'), findsOneWidget);
  });
}
