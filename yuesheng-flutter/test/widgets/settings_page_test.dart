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
//  11. `N7` 本周调用统计区块 → 总消耗/次数/token 拆解/命中率与坏行提示
//      （★ 埋点由**真写入方** `LlmCallLogEntry.toJson()` 生成，见 #N7 段注释）
//      （2026-09-20 改造：原「金额 / 峰时提示」断言随计价移除而重写）
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/ai_account_repository.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/providers/app_providers.dart';
import 'package:writingcoach/providers/session_providers.dart';
import '../helpers/mock_last_session_storage.dart';
import 'package:writingcoach/router/app_router.dart';
import 'package:writingcoach/router/app_routes.dart';
import 'package:writingcoach/services/llm_call_log_sink.dart';
import 'package:writingcoach/services/llm_client.dart';
import 'package:writingcoach/services/llm_config_storage.dart';
import 'package:writingcoach/services/llm_cost.dart';
import 'package:writingcoach/services/llm_usage.dart';
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
  LlmConfigValues? lastConfig;

  @override
  Future<TestConnectionResult> testLlmConnection({
    LlmConfigValues? config,
  }) async {
    lastConfig = config;
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
    // ADR-C91：多账号 key map 走 flutter_secure_storage，测试环境必须 mock
    // platform channel（否则 createAccount 写 key map 抛 MissingPluginException）。
    // 用内存 map 落盘，保证 seedAccounts 写入的 key 可被 _editAccount 读回。
    final secure = <String, String>{};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (call) async {
            final key = (call.arguments as Map?)?['key'] as String?;
            switch (call.method) {
              case 'read':
                return secure[key];
              case 'write':
                secure[key!] = (call.arguments as Map)['value'] as String;
                return null;
              case 'delete':
                secure.remove(key);
                return null;
            }
            return null;
          },
        );
  });

  tearDown(() async => db.close());

  Widget buildSettings({
    _FakeLlmClient? llm,
    MemoryLastSessionStorage? lastStorage,
  }) {
    return ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        lastSessionStorageProvider.overrideWithValue(
          lastStorage ?? MemoryLastSessionStorage(),
        ),
      ],
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
    expect(find.text('尚未配置 API，当前为免费测试模式（离线示例）。填写以下信息以启用完整功能'), findsOneWidget);
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
    expect(find.text('尚未配置 API，当前为免费测试模式（离线示例）。填写以下信息以启用完整功能'), findsNothing);
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

  testWidgets('#3 保存配置 → 建账号（ADR-C91 多账号）', (tester) async {
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

    expect(find.text('API 配置已保存'), findsOneWidget);
    // 多账号：保存落 DB 账号（而非旧三键 storage）
    final accounts = await AIAccountRepository(db).listAccounts();
    expect(accounts, hasLength(1));
    expect(accounts.first.isDefault, isTrue); // 首建自动默认
    expect(accounts.first.baseUrl, 'https://api.deepseek.com'); // 去尾部斜杠
    expect(accounts.first.model, 'deepseek-v4-flash');
  });

  testWidgets('#4 空表单保存 → 完整提示', (tester) async {
    await tester.pumpWidget(buildSettings());
    await tester.pumpAndSettle();

    await tester.tap(find.text('保存配置'));
    await tester.pumpAndSettle();

    expect(find.text('请填写完整的 API 配置'), findsOneWidget);
    expect(storage.stored, isNull);
  });

  testWidgets('#5 测试连接 → 成功结果框（直接用当前表单，不依赖保存）', (tester) async {
    final llm = _FakeLlmClient();
    await tester.pumpWidget(buildSettings(llm: llm));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'sk-abc');
    await tester.enterText(
      find.byType(TextField).at(1),
      'https://api.deepseek.com/',
    );
    await tester.enterText(find.byType(TextField).at(2), 'deepseek-v4-flash');
    await tester.tap(find.text('测试连接'));
    await tester.pumpAndSettle();

    expect(find.textContaining('✓ 连接成功'), findsOneWidget);
    // 测试连接直接使用当前表单（所见即所得），尾斜杠已清洗，不落库
    expect(llm.lastConfig?.apiKey, 'sk-abc');
    expect(llm.lastConfig?.baseUrl, 'https://api.deepseek.com');
    expect(llm.lastConfig?.model, 'deepseek-v4-flash');
    final accounts = await AIAccountRepository(db).listAccounts();
    expect(accounts, isEmpty);
  });

  testWidgets('#6 填充示例 → 字段填充', (tester) async {
    await tester.pumpWidget(buildSettings());
    await tester.pumpAndSettle();

    await tester.dragUntilVisible(
      find.text('填充示例配置'),
      find.byType(ListView),
      const Offset(0, -200),
    );
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

    await tester.dragUntilVisible(
      find.text('清空配置'),
      find.byType(ListView),
      const Offset(0, -200),
    );
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

  testWidgets('#8b 清除缓存 → LAST_SESSION 指向被删孤儿会话时同步清理', (tester) async {
    final sessionRepo = SessionRepository(db);
    final orphan = await sessionRepo.createBlankSession(title: '空会话');
    final withMsg = await sessionRepo.createBlankSession(title: '有消息');
    await sessionRepo.addMessage(withMsg, 'user', '你好');
    final lastStorage = MemoryLastSessionStorage();
    await lastStorage.setLastSessionId(orphan);

    await tester.pumpWidget(buildSettings(lastStorage: lastStorage));
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
      find.text('清除缓存'),
      find.byType(ListView),
      const Offset(0, -200),
    );
    await tester.ensureVisible(find.text('清除缓存'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清除缓存'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清除'));
    await tester.pumpAndSettle();

    expect(await lastStorage.getLastSessionId(), isNull);
  });

  testWidgets('#8c 清除缓存 → LAST_SESSION 指向保留会话时保留', (tester) async {
    final sessionRepo = SessionRepository(db);
    await sessionRepo.createBlankSession(title: '空会话');
    final withMsg = await sessionRepo.createBlankSession(title: '有消息');
    await sessionRepo.addMessage(withMsg, 'user', '你好');
    final lastStorage = MemoryLastSessionStorage();
    await lastStorage.setLastSessionId(withMsg);

    await tester.pumpWidget(buildSettings(lastStorage: lastStorage));
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
      find.text('清除缓存'),
      find.byType(ListView),
      const Offset(0, -200),
    );
    await tester.ensureVisible(find.text('清除缓存'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清除缓存'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清除'));
    await tester.pumpAndSettle();

    expect(await lastStorage.getLastSessionId(), withMsg);
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
    expect(find.text('v0.1.0'), findsOneWidget);
    expect(find.text('com.yuesheng.writingcoach'), findsOneWidget);
  });

  testWidgets('#10 反馈对话框 → QQ 群展示 + 一键复制', (tester) async {
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

    expect(find.textContaining('470562649'), findsOneWidget);
    // 新增「复制群号」按钮
    expect(find.text('复制群号'), findsOneWidget);
    await tester.tap(find.text('复制群号'));
    await tester.pumpAndSettle();

    // 复制成功轻提示 + 弹窗关闭
    expect(find.text('群号已复制'), findsOneWidget);
    expect(find.textContaining('470562649'), findsNothing);
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

  group('v0.1 发布准备批：Key 指引 / 隐私告知 / 会话导出', () {
    /// 滚动到维护/关于区块并确保目标行可见
    Future<void> scrollTo(WidgetTester tester, String label) async {
      await tester.dragUntilVisible(
        find.text(label),
        find.byType(ListView),
        const Offset(0, -200),
      );
      await tester.ensureVisible(find.text(label));
      await tester.pumpAndSettle();
    }

    testWidgets('#E1 三个新入口存在（API 区 / 维护区 / 关于区）', (tester) async {
      await tester.pumpWidget(buildSettings());
      await tester.pumpAndSettle();

      // API 区在首屏
      expect(find.text('如何获取 API Key →'), findsOneWidget);

      await scrollTo(tester, '导出会话记录（JSON）');
      expect(find.text('导出会话记录（JSON）'), findsOneWidget);

      await scrollTo(tester, '隐私与费用说明');
      expect(find.text('隐私与费用说明'), findsOneWidget);
    });

    testWidgets('#E2 Key 指引：平台路径 + 费用一句话', (tester) async {
      await tester.pumpWidget(buildSettings());
      await tester.pumpAndSettle();

      // API 区在首屏但按钮贴近视口底部，先滚动确保命中
      await scrollTo(tester, '如何获取 API Key →');
      await tester.tap(find.text('如何获取 API Key →'));
      await tester.pumpAndSettle();

      expect(find.text('如何获取 API Key'), findsOneWidget);
      expect(find.textContaining('platform.deepseek.com'), findsOneWidget);
      expect(find.textContaining('账户余额'), findsOneWidget);

      await tester.tap(find.text('知道了'));
      await tester.pumpAndSettle();
      expect(find.text('如何获取 API Key'), findsNothing);
    });

    testWidgets('#E3 隐私与费用说明（设置页常驻入口）', (tester) async {
      await tester.pumpWidget(buildSettings());
      await tester.pumpAndSettle();

      await scrollTo(tester, '隐私与费用说明');
      await tester.tap(find.text('隐私与费用说明'));
      await tester.pumpAndSettle();

      expect(find.text('开始之前，请了解'), findsOneWidget);
      expect(find.textContaining('发送至你所选的 AI 服务商 API'), findsOneWidget);
      await tester.tap(find.text('我知道了'));
      await tester.pumpAndSettle();
      expect(find.text('开始之前，请了解'), findsNothing);
    });

    testWidgets('#E4 导出：确认框含作品内容提示 + 取消不动', (tester) async {
      await tester.pumpWidget(buildSettings());
      await tester.pumpAndSettle();

      await scrollTo(tester, '导出会话记录（JSON）');
      await tester.tap(find.text('导出会话记录（JSON）'));
      await tester.pumpAndSettle();

      expect(find.text('导出会话记录'), findsOneWidget);
      expect(find.textContaining('作品原文与练习内容'), findsOneWidget);

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.text('导出会话记录'), findsNothing);
      expect(find.textContaining('导出失败'), findsNothing);
      expect(find.textContaining('还没有可导出的会话'), findsNothing);
    });

    testWidgets('#E5 导出：空库 → 提示无会话', (tester) async {
      await tester.pumpWidget(buildSettings());
      await tester.pumpAndSettle();

      await scrollTo(tester, '导出会话记录（JSON）');
      await tester.tap(find.text('导出会话记录（JSON）'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('导出'));
      await tester.pumpAndSettle();

      expect(find.textContaining('还没有可导出的会话'), findsOneWidget);
    });

    testWidgets('#E6 导出：临时目录通道失败 → 失败提示（R-028）', (tester) async {
      await SessionRepository(db).createBlankSession(title: '反馈素材');

      // share_plus 对平台层失败静默降级（返回 unavailable，不抛），
      // 故让更前置的 path_provider 通道抛异常，真正走导出层 catch。
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (call) async => throw PlatformException(code: 'unavailable'),
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );

      await tester.pumpWidget(buildSettings());
      await tester.pumpAndSettle();

      await scrollTo(tester, '导出会话记录（JSON）');
      await tester.tap(find.text('导出会话记录（JSON）'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('导出'));
      await tester.pumpAndSettle();

      expect(find.text('导出失败，请稍后再试'), findsOneWidget);
    });
  });

  testWidgets('#A 预设点选 → Kimi 自动填 kimi-k3 + api.moonshot.cn（批次A 时效性锚定）', (
    tester,
  ) async {
    await tester.pumpWidget(buildSettings());
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ActionChip, 'Kimi（月之暗面）'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(find.byType(TextField).at(1)).controller!.text,
      'https://api.moonshot.cn/v1',
    );
    expect(
      tester.widget<TextField>(find.byType(TextField).at(2)).controller!.text,
      'kimi-k3',
    );
  });

  testWidgets('#B 预设点选 → 智谱/豆包新模型名生效（批次A 时效性锚定）', (tester) async {
    await tester.pumpWidget(buildSettings());
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ActionChip, '智谱 GLM'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField).at(2)).controller!.text,
      'glm-4.6',
    );

    await tester.tap(find.widgetWithText(ActionChip, '豆包（火山方舟）'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField).at(2)).controller!.text,
      'doubao-seed-2.1-turbo',
    );
  });

  // ── ADR-C91 多账号（批次 D-1） ──

  Future<void> seedAccounts(AppDatabase target) async {
    final repo = AIAccountRepository(target);
    await repo.createAccount(
      name: 'DeepSeek 主账号',
      baseUrl: 'https://api.deepseek.com',
      model: 'deepseek-v4-flash',
      apiKey: 'sk-main',
    );
    await repo.createAccount(
      name: 'Kimi 备选',
      baseUrl: 'https://api.moonshot.cn/v1',
      model: 'kimi-k3',
      apiKey: 'sk-kimi',
    );
  }

  testWidgets('#M1 已有账号 → 列表渲染（名称/默认徽标/model·baseUrl）', (tester) async {
    await seedAccounts(db);
    await tester.pumpWidget(buildSettings());
    await tester.pumpAndSettle();

    expect(find.text('已保存的账号（2）'), findsOneWidget);
    expect(find.text('DeepSeek 主账号'), findsOneWidget);
    expect(find.text('Kimi 备选'), findsOneWidget);
    expect(find.text('默认'), findsOneWidget); // 仅首建账号
    expect(
      find.text('deepseek-v4-flash · https://api.deepseek.com'),
      findsOneWidget,
    );
    expect(find.text('kimi-k3 · https://api.moonshot.cn/v1'), findsOneWidget);
  });

  testWidgets('#M2 添加新账号 → 表单清空 + 保存后列表 +1', (tester) async {
    await seedAccounts(db);
    await tester.pumpWidget(buildSettings());
    await tester.pumpAndSettle();

    // 当前编辑默认账号 → 点「添加新账号」清空表单
    await tester.tap(find.text('添加新账号'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField).at(0)).controller!.text,
      '',
    );

    // 填新账号并保存（账号列表推高内容 → 先滚到保存按钮）
    await tester.enterText(find.byType(TextField).at(0), 'sk-new');
    await tester.enterText(
      find.byType(TextField).at(1),
      'https://new.example.com',
    );
    await tester.enterText(find.byType(TextField).at(2), 'new-model');
    await tester.ensureVisible(find.text('保存配置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存配置'));
    await tester.pumpAndSettle();

    expect(find.text('API 配置已保存'), findsOneWidget);
    expect(find.text('已保存的账号（3）'), findsOneWidget);
    expect(find.text('new-model · https://new.example.com'), findsOneWidget);
  });

  testWidgets('#M3 删除非默认账号 → 确认后列表 -1', (tester) async {
    await seedAccounts(db);
    await tester.pumpWidget(buildSettings());
    await tester.pumpAndSettle();

    // Kimi 备选行的删除按钮（第一个删除图标 = DeepSeek 行，第二个 = Kimi 行）
    await tester.tap(find.byIcon(Icons.delete_outline).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    expect(find.text('账号已删除'), findsOneWidget);
    expect(find.text('已保存的账号（1）'), findsOneWidget);
    expect(find.text('Kimi 备选'), findsNothing);
    expect(find.text('DeepSeek 主账号'), findsOneWidget);
  });

  testWidgets('#M4 删除最后账号 → 拒绝并提示', (tester) async {
    await seedAccounts(db);
    await tester.pumpWidget(buildSettings());
    await tester.pumpAndSettle();

    // 删掉 Kimi（非默认）
    await tester.tap(find.byIcon(Icons.delete_outline).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    // 只剩 DeepSeek（默认）→ 再删被拒。
    // 先等上一条「账号已删除」snackbar 过期，避免排队遮挡新提示。
    await tester.pump(const Duration(seconds: 5));
    await tester.tap(find.byIcon(Icons.delete_outline).at(0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    expect(find.text('删除失败：至少保留一个账号'), findsOneWidget);
    expect(find.text('已保存的账号（1）'), findsOneWidget);
  });

  testWidgets('#M5 设默认 → 默认徽标切换', (tester) async {
    await seedAccounts(db);
    await tester.pumpWidget(buildSettings());
    await tester.pumpAndSettle();

    // Kimi 行「设默认」
    await tester.tap(find.text('设默认'));
    await tester.pumpAndSettle();

    expect(find.text('已设为默认账号'), findsOneWidget);
    // 默认徽标仍只有一个（从 DeepSeek 移到 Kimi）
    expect(find.text('默认'), findsOneWidget);
    final kimiRow = find.ancestor(
      of: find.text('Kimi 备选'),
      matching: find.byType(Container),
    );
    expect(kimiRow, findsWidgets);
  });

  testWidgets('#M6 点击账号行 → 编辑模式（表单载入该账号）', (tester) async {
    await seedAccounts(db);
    await tester.pumpWidget(buildSettings());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Kimi 备选'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(find.byType(TextField).at(0)).controller!.text,
      'sk-kimi',
    );
    expect(
      tester.widget<TextField>(find.byType(TextField).at(1)).controller!.text,
      'https://api.moonshot.cn/v1',
    );
    expect(
      tester.widget<TextField>(find.byType(TextField).at(2)).controller!.text,
      'kimi-k3',
    );
  });

  // ── `N7`（批次 3）：设置页「本周调用统计」 ──
  //
  // ★ 本段的**鉴别力设计**：埋点载荷由**真写入方** `LlmCallLogEntry.toJson()`
  //   生成，**不手抄键名**。手抄一份 = 把「context 键口径」推算两遍，写入方
  //   改名后手抄副本静默不同步（同 `DECISIONS §4-41`）。走真写入方，则
  //   「写入方 ↔ 查询方键名不一致」会被本段直接判红。

  /// 落一条**真** llm_call 埋点（level=info / category=api，与
  /// `LlmCallLogSink._defaultWriter` 同形）。
  Future<void> insertLlmCall({
    required String id,
    required int at,
    required int cached,
    required int miss,
    required int completion,
    int reasoning = 0,
  }) async {
    final entry = LlmCallLogEntry(
      sessionId: 's1',
      purpose: LlmCallPurpose.mainChat,
      kind: LlmUsageKind.stream,
      promptTokens: cached + miss,
      completionTokens: completion,
      cachedTokens: cached,
      reasoningTokens: reasoning,
      latencyMs: 1200,
      model: 'deepseek-v4-flash',
    );
    await db
        .into(db.errorLogs)
        .insert(
          ErrorLogsCompanion.insert(
            id: id,
            level: const Value('info'),
            category: const Value('api'),
            message: '[llm_call] mainChat/stream',
            context: Value(jsonEncode(entry.toJson())),
            createdAt: Value(at),
          ),
        );
  }

  /// 滚到「本周调用统计」区块（它在 API 区块之后 ⇒ 首屏外，必须滚动；
  /// `ListView` 惰性构建，不滚动则节点**根本不在树里**）。
  Future<void> scrollToUsage(WidgetTester tester) async {
    await tester.dragUntilVisible(
      find.text('本周调用统计'),
      find.byType(ListView),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('#N7-1 两次调用 → 总消耗/次数/拆解/命中率（全模型通用口径）', (tester) async {
    // 2026-09-20 改造：原用例断言「峰时金额」，随计价移除而重写。
    // 现断言**总 token 消耗**（不依赖任何厂商计价规则）。
    final since = weekStartEpochSecCst(DateTime.now().toUtc());
    await insertLlmCall(
      id: 'u-1',
      at: since + 3600,
      cached: 1000,
      miss: 2000,
      completion: 3000,
    );
    // 第二笔刻意落在「周一 11:00」—— 旧口径下这是峰时；新口径**不区分时段**
    // ⇒ 若有人把时段逻辑加回来，本用例的总额断言仍成立但语义已变，
    //   故下方另有一条「无峰时提示」的负例断言兜住。
    await insertLlmCall(
      id: 'u-2',
      at: since + 11 * 3600,
      cached: 1000,
      miss: 2000,
      completion: 3000,
    );

    await tester.pumpWidget(buildSettings());
    await tester.pumpAndSettle();
    await scrollToUsage(tester);

    expect(find.text('2 次调用'), findsOneWidget);
    expect(find.text('2.0k'), findsOneWidget); // 命中 1000+1000
    expect(find.text('4.0k'), findsOneWidget); // 未命中 2000+2000
    expect(find.text('6.0k'), findsOneWidget); // 输出 3000+3000
    expect(find.text('33%'), findsOneWidget); // 2000 / 6000 命中率
    // 总消耗 = 2000 + 4000 + 6000 = 12000 → 紧凑写 12.0k
    expect(find.text('12.0k'), findsOneWidget);
    expect(find.text('tokens'), findsOneWidget);
    // ★ 负例：计价与峰时提示必须**彻底消失**
    expect(find.textContaining('¥'), findsNothing);
    expect(find.textContaining('高峰时段'), findsNothing);
  });

  testWidgets('#N7-2 窗口前一行不计入；坏行单列（不是 0 消耗）', (tester) async {
    final since = weekStartEpochSecCst(DateTime.now().toUtc());
    // 负例①：起点前 1 秒 ⇒ 若实现漏了 since 过滤，次数会变 2
    await insertLlmCall(
      id: 'u-before',
      at: since - 1,
      cached: 100,
      miss: 100,
      completion: 100,
    );
    await insertLlmCall(
      id: 'u-in',
      at: since + 3600,
      cached: 100,
      miss: 100,
      completion: 100,
    );
    // 负例②：category 对但 event 不是 llm_call ⇒ 只计 skipped，不吞成 0 token
    await db
        .into(db.errorLogs)
        .insert(
          ErrorLogsCompanion.insert(
            id: 'u-bad',
            level: const Value('info'),
            category: const Value('api'),
            message: '[other] 非调用埋点',
            context: const Value('{"event":"other"}'),
            createdAt: Value(since + 3600),
          ),
        );
    // 负例③：**event 对但关键字段缺失** —— 与②是**两个不同分支**。
    // ★ 本行由负向验证 `NEG-D` 补出：最初本用例只有②，而 `NEG-D`
    //   （把「字段缺失」从 `return null` 改成补 0）**red 不到本用例**
    //   ⇒ 说明本用例当时**只覆盖了 event 分支**。补上「缺 `miss_tokens`」
    //   后才真正覆盖「字段缺失 ⇒ 不补零」这一支。
    await db
        .into(db.errorLogs)
        .insert(
          ErrorLogsCompanion.insert(
            id: 'u-bad2',
            level: const Value('info'),
            category: const Value('api'),
            message: '[llm_call] 缺字段',
            context: const Value(
              '{"event":"llm_call","cached_tokens":10,"completion_tokens":10}',
            ),
            createdAt: Value(since + 3600),
          ),
        );

    await tester.pumpWidget(buildSettings());
    await tester.pumpAndSettle();
    await scrollToUsage(tester);

    expect(find.text('1 次调用'), findsOneWidget);
    // ②③两类坏行**都**要进同一条提示（2 条）
    expect(find.textContaining('另有 2 条调用埋点缺少 token 明细'), findsOneWidget);
    // 坏行**没有**被当成 0 消耗增计次数
    expect(find.text('2 次调用'), findsNothing);
  });

  testWidgets('#N7-3 零埋点 → 仍渲染空读数（诚实报 0），无坏行提示', (tester) async {
    await tester.pumpWidget(buildSettings());
    await tester.pumpAndSettle();
    await scrollToUsage(tester);

    // 「这周确实没调用」= 真 0，应如实显示（与「查询失败整块不渲染」区分开）
    expect(find.text('0 次调用'), findsOneWidget);
    // 总消耗是「数字」与「tokens」两个相邻 Text，不是一个拼接串。
    // ⚠️ 不能写 findsOneWidget：四个统计格（命中/未命中/输出）也都是 0
    // ⇒ 单查 `find.text('0')` 会命中 4 个。此处只钉「存在且未崩」。
    expect(find.text('0'), findsWidgets);
    expect(find.text('tokens'), findsOneWidget);
    expect(find.text('0%'), findsOneWidget); // 命中率不产生 NaN
    expect(find.textContaining('缺少 token 明细'), findsNothing);
    expect(find.textContaining('¥'), findsNothing);
  });
}
