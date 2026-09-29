// ─────────────────────────────────────────────────────────────
// CoachSelectorCard widget 测试 — 自定义教练（D1）编辑入口通路
//
// 覆盖路径（此前为孤儿能力，无测试守护）：
//   #1 渲染：加载完成后出现「自定义教练」入口
//   #2 新建：填名称+语气 → 保存 → 自定义人格入列
//      （2026-09-28 重构后：名称唯一必填，语气选填；
//       「列表简介/阈值」收进默认收起的高级折叠区 ⇒ 主界面仅 2 个 TextField）
//   #3 编辑入口：自定义人格行出现「编辑」图标（Icons.edit_outlined）
//   #4 编辑弹出：点编辑图标 → 对话框标题为「编辑自定义教练」且名称字段预填
//   #5 只填名称即可保存（语气留空 → 注入层回退默认态度档，由
//      coach_persona_injection_test 守护注入侧）
// ─────────────────────────────────────────────────────────────

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/features/app_settings/coach_selector_card.dart';
import 'package:writingcoach/providers/app_providers.dart';
import 'package:writingcoach/providers/session_providers.dart';
import 'package:writingcoach/services/llm_client.dart';
import 'package:writingcoach/services/llm_config_storage.dart';

/// 返回固定文案的假 LlmClient（仅覆盖 chatCompletion），供 AI 润色测试。
class _FakeLlmClient extends LlmClient {
  _FakeLlmClient(this._canned) : super();
  final String _canned;

  @override
  Future<String> chatCompletion(
    List<ChatMessage> messages, {
    int? maxTokens,
    Map<String, dynamic>? extraBody,
    CancelToken? cancelToken,
  }) async => _canned;
}

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
  });

  tearDown(() {
    container.dispose();
    db.close();
  });

  Widget buildHost([ProviderContainer? c]) => UncontrolledProviderScope(
    container: c ?? container,
    child: MaterialApp(home: Scaffold(body: const CoachSelectorCard())),
  );

  testWidgets('#1 加载后渲染「自定义教练」入口', (tester) async {
    await tester.pumpWidget(buildHost());
    await tester.pumpAndSettle();
    expect(find.text('自定义教练'), findsOneWidget);
    // 系统预设 3 个，无编辑图标（仅自定义才有）
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
  });

  testWidgets('#2-#4 新建后可点编辑图标打开预填对话框', (tester) async {
    await tester.pumpWidget(buildHost());
    await tester.pumpAndSettle();

    // #2 新建自定义教练
    await tester.tap(find.text('自定义教练'));
    await tester.pumpAndSettle();
    expect(find.text('新建自定义教练'), findsOneWidget);

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '毒舌编辑'); // 名称
    await tester.enterText(fields.at(1), '说话带刺，直给'); // 语气设定（选填）
    await tester.pump();

    await tester.tap(find.widgetWithText(TextButton, '保存'));
    await tester.pumpAndSettle();

    // 自定义人格入列
    expect(find.text('毒舌编辑'), findsWidgets);

    // #3 自定义人格行出现编辑图标
    expect(find.byIcon(Icons.edit_outlined), findsOneWidget);

    // #4 点编辑图标 → 预填对话框
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    expect(find.text('编辑自定义教练'), findsOneWidget);
    expect(tester.widget<TextField>(fields.at(0)).controller?.text, '毒舌编辑');
  });

  testWidgets('#5 只填名称即可保存（语气留空合法）', (tester) async {
    await tester.pumpWidget(buildHost());
    await tester.pumpAndSettle();

    await tester.tap(find.text('自定义教练'));
    await tester.pumpAndSettle();

    // 主界面折叠收起时只有 2 个字段：名称 + 语气
    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(2));
    // 高级选项默认收起：列表简介/阈值不在主界面
    expect(find.text('高级选项'), findsOneWidget);
    expect(find.text('列表简介（选填，仅展示）'), findsNothing);

    await tester.enterText(fields.at(0), '只取名教练');
    await tester.pump();

    await tester.tap(find.widgetWithText(TextButton, '保存'));
    await tester.pumpAndSettle();

    // 保存成功（不再要求语气必填）
    expect(find.text('只取名教练'), findsWidgets);
  });

  testWidgets('#6a 空输入点 AI 润色 → 提示先填名字或语气', (tester) async {
    await tester.pumpWidget(buildHost());
    await tester.pumpAndSettle();

    await tester.tap(find.text('自定义教练'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'AI 润色'));
    await tester.pumpAndSettle();

    expect(find.text('先填个名字或几句语气，AI 才能帮你润色'), findsOneWidget);
  });

  testWidgets('#6b 未配 API Key 点 AI 润色 → 引导去设置', (tester) async {
    // 用 provider override 确定性模拟「未配置 Key」，不依赖本机安全存储状态。
    final c = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        llmConfigResolvedProvider.overrideWith((ref) async => null),
      ],
    );
    addTearDown(c.dispose);

    await tester.pumpWidget(buildHost(c));
    await tester.pumpAndSettle();

    await tester.tap(find.text('自定义教练'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '毒舌编辑'); // 名称，触发配置检测
    await tester.pump();

    await tester.tap(find.widgetWithText(TextButton, 'AI 润色'));
    await tester.pumpAndSettle();

    // resolveLlmConfig 返回 null ⇒ 免费模式降级，给出引导
    expect(find.text('请先在「设置 → API 配置」填好 Key，才能用 AI 润色'), findsOneWidget);
  });

  testWidgets('#7 配置齐全 → AI 润色回填语气设定', (tester) async {
    const canned =
        '一位刀子嘴豆腐心的老编辑，开口就戳破你最想藏的破绽，'
        '但从不空谈，句句带着具体的改法。';
    // 复用 setUp 的 db，避免新建第二个 AppDatabase 实例触发 drift 警告；
    // 用 provider override 模拟「已配置 API Key」，不触碰安全存储。
    final c = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        llmConfigResolvedProvider.overrideWith(
          (ref) async => const LlmConfigValues(
            apiKey: 'k',
            baseUrl: 'https://api.example.com',
            model: 'gpt-4o',
          ),
        ),
        llmClientProvider.overrideWithValue(_FakeLlmClient(canned)),
      ],
    );
    addTearDown(c.dispose);

    await tester.pumpWidget(buildHost(c));
    await tester.pumpAndSettle();

    await tester.tap(find.text('自定义教练'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '毒舌编辑'); // 名称
    await tester.pump();

    await tester.tap(find.widgetWithText(TextButton, 'AI 润色'));
    await tester.pumpAndSettle();

    // 语气设定框被回填为模型返回值
    expect(tester.widget<TextField>(fields.at(1)).controller?.text, canned);
    expect(find.text('已填好「语气设定」，可继续修改后保存'), findsOneWidget);
  });

  // ── #8 UI 层验收（2026-09-28 收尾后续项 1）──
  // 不验证行为，只验证「对话框静态结构完整 + AI 润色按钮已接入」这一 UI 事实。
  // 像素级视觉走查需舰长在场（本会话 adb 不可用），功能结构由本例守护。
  testWidgets('#8 UI 验收：对话框静态结构 + AI 润色按钮同屏可达', (tester) async {
    await tester.pumpWidget(buildHost());
    await tester.pumpAndSettle();

    await tester.tap(find.text('自定义教练'));
    await tester.pumpAndSettle();

    // 对话框标题
    expect(find.text('新建自定义教练'), findsOneWidget);
    // 主界面仅 2 个 TextField（名称 + 语气），高级选项默认收起
    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.text('高级选项'), findsOneWidget);
    // AI 润色按钮已接入对话框且可定位
    expect(find.widgetWithText(TextButton, 'AI 润色'), findsOneWidget);
    // 保存按钮同屏
    expect(find.widgetWithText(TextButton, '保存'), findsOneWidget);
    // 未交互时不应出现任何引导报错文案
    expect(find.text('先填个名字或几句语气，AI 才能帮你润色'), findsNothing);
    expect(find.text('请先在「设置 → API 配置」填好 Key，才能用 AI 润色'), findsNothing);
  });

  // ── #9 删除入口二次确认（2026-09-28 补：垃圾桶不再一键即删）──
  testWidgets('#9 删除自定义教练需二次确认：取消不删、确认才删', (tester) async {
    await tester.pumpWidget(buildHost());
    await tester.pumpAndSettle();

    // 新建一个自定义教练
    await tester.tap(find.text('自定义教练'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '待删教练');
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, '保存'));
    await tester.pumpAndSettle();

    // 自定义人格行出现删除图标
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);

    // 点删除 → 出现二次确认弹窗（含不可恢复提示）
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    expect(find.text('删除自定义教练'), findsOneWidget);
    expect(find.textContaining('此操作不可恢复'), findsOneWidget);

    // 取消 → 弹窗关闭，教练仍在
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();
    expect(find.text('待删教练'), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);

    // 再点删除 → 确认「删除」→ 教练被移除
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '删除'));
    await tester.pumpAndSettle();
    expect(find.text('待删教练'), findsNothing);
    expect(find.byIcon(Icons.delete_outline), findsNothing);
  });
}
