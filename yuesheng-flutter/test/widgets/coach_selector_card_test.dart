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

import 'package:writingcoach/data/coach_persona_templates.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/app_state_repository.dart';
import 'package:writingcoach/features/app_settings/coach_selector_card.dart';
import 'package:writingcoach/providers/app_providers.dart';
import 'package:writingcoach/providers/session_providers.dart';
import 'package:writingcoach/services/llm_client.dart';
import 'package:writingcoach/services/llm_config_storage.dart';
import 'package:writingcoach/widgets/yue_sheet.dart';

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

  // ════════════════════════════════════════════════════════
  // C129：断点 B 设置页生效范围说明 + 断点 A revision 信号写入
  // ════════════════════════════════════════════════════════

  testWidgets('#10 C129 副标题说明全局教练的生效范围', (tester) async {
    await tester.pumpWidget(buildHost());
    await tester.pumpAndSettle();

    expect(
      find.text('对新会话生效；已锁定态度的会话保持不变。'),
      findsOneWidget,
      reason: '需向用户说明：对新会话生效；已有锁定态度会话不受影响',
    );
    expect(
      find.text('换一种说话方式。切换后下次启动沿用。'),
      findsNothing,
      reason: '旧文案未说明锁定会话语义，已替换',
    );
  });

  testWidgets('#11 C129 选系统预设教练成功 → coachPersonaRevisionProvider 递增', (
    tester,
  ) async {
    await tester.pumpWidget(buildHost());
    await tester.pumpAndSettle();
    expect(container.read(coachPersonaRevisionProvider), 0);

    await tester.tap(find.text('月笙如歌'));
    await tester.pumpAndSettle();

    expect(
      container.read(coachPersonaRevisionProvider),
      1,
      reason: '设置侧写入全局教练后应递增 revision，对话页据此重载重 resolve',
    );
    expect(
      await AppStateRepository(db).getActiveCoachPersonaId(),
      'yuesheng',
      reason: '写库确证（系统预设双写）',
    );
  });

  // ── #12 角色预设「猫娘」chip：只填语气框、不写回 ──
  testWidgets('#12 点「猫娘」角色预设 → 语气框填入模板全文（不触发保存）', (tester) async {
    await tester.pumpWidget(buildHost());
    await tester.pumpAndSettle();

    await tester.tap(find.text('自定义教练'));
    await tester.pumpAndSettle();

    // 角色预设区与「猫娘」chip 可达
    expect(find.text('角色预设（试听用）'), findsOneWidget);
    expect(find.text('猫娘'), findsOneWidget);

    final fields = find.byType(TextField);
    // 主界面仍仅 2 个 TextField（角色预设 chip 不引入新输入框）
    expect(fields, findsNWidgets(2));
    // 语气框初始为空
    expect(tester.widget<TextField>(fields.at(1)).controller?.text, '');

    await tester.tap(find.text('猫娘'));
    await tester.pump();

    // 语气框被填入猫娘模板全文（引用常量，与真源保持一致）
    expect(
      tester.widget<TextField>(fields.at(1)).controller?.text,
      kCharacterPresetTemplates.first.toneText,
    );
    // 只填框不写回：给出「可继续修改或试听」提示，未触发保存
    expect(find.text('已填入「猫娘」语气，可继续修改或试听'), findsOneWidget);
  });

  // ════════════════════════════════════════════════════════
  // ADR-C132 批3（R8）：空语气自定义人格 → 「将使用默认语气」徽标
  // ════════════════════════════════════════════════════════

  testWidgets('#13 初始仅系统预设 → 不出现「将使用默认语气」徽标', (tester) async {
    await tester.pumpWidget(buildHost());
    await tester.pumpAndSettle();

    // 3 个系统预设都有内置 fragment ⇒ 永不回退徽标
    expect(find.text('将使用默认语气'), findsNothing);
  });

  testWidgets('#14 自定义人格语气留空 → 列表行显示「将使用默认语气」徽标', (tester) async {
    await tester.pumpWidget(buildHost());
    await tester.pumpAndSettle();

    // 只填名称、语气留空 → 保存
    await tester.tap(find.text('自定义教练'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '空语气教练'); // 名称
    // fields.at(1) 语气框保持空
    await tester.tap(find.widgetWithText(TextButton, '保存'));
    await tester.pumpAndSettle();

    // 自定义行出现回退徽标（空 fragment ⇒ 注入层回退默认态度档）
    expect(find.text('空语气教练'), findsWidgets);
    expect(find.text('将使用默认语气'), findsOneWidget);
  });

  testWidgets('#15 自定义人格填了语气 → 不显示徽标', (tester) async {
    await tester.pumpWidget(buildHost());
    await tester.pumpAndSettle();

    await tester.tap(find.text('自定义教练'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '有语气教练');
    await tester.enterText(fields.at(1), '说话带刺，直给'); // 语气非空
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, '保存'));
    await tester.pumpAndSettle();

    expect(find.text('有语气教练'), findsWidgets);
    // fragment 非空 ⇒ 无回退徽标
    expect(find.text('将使用默认语气'), findsNothing);
  });

  // ════════════════════════════════════════════════════════
  // ADR-C132 批3：从系统档开始（B 派生入口）
  // ════════════════════════════════════════════════════════

  testWidgets('#16 新建态出现「从系统档开始」chip 行，点豆包 → 语气框填入系统模板', (tester) async {
    await tester.pumpWidget(buildHost());
    await tester.pumpAndSettle();

    await tester.tap(find.text('自定义教练'));
    await tester.pumpAndSettle();

    // 弹层内查找（底层选人卡仍渲染系统预设行 ⇒ '豆包' 等文本全树出现两次，
    // 必须限定在 YueSheetScaffold 弹层内，否则 tap 歧义）。
    Finder inSheet(String text) => find.descendant(
      of: find.byType(YueSheetScaffold),
      matching: find.text(text),
    );

    // 新建态才展示派生入口（3 个系统档 chip）
    expect(find.text('从系统档开始'), findsOneWidget);
    expect(inSheet('豆包'), findsOneWidget);
    expect(inSheet('月笙如歌'), findsOneWidget);
    expect(inSheet('sensei'), findsOneWidget);

    final fields = find.byType(TextField);
    expect(tester.widget<TextField>(fields.at(1)).controller?.text, '');

    await tester.tap(inSheet('豆包'));
    await tester.pump();

    // 语气框填入 doubao 静态模板（引用真源常量）
    expect(
      tester.widget<TextField>(fields.at(1)).controller?.text,
      kSystemToneTemplates['doubao'],
    );
    expect(find.textContaining('的语气起点，可继续修改'), findsOneWidget);
  });

  testWidgets('#17 编辑态不出现「从系统档开始」派生入口', (tester) async {
    await tester.pumpWidget(buildHost());
    await tester.pumpAndSettle();

    // 先建一个自定义人格
    await tester.tap(find.text('自定义教练'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '待编辑教练');
    await tester.tap(find.widgetWithText(TextButton, '保存'));
    await tester.pumpAndSettle();

    // 打开编辑对话框
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    expect(find.text('编辑自定义教练'), findsOneWidget);

    // 派生入口仅新建态 ⇒ 编辑态不渲染
    expect(find.text('从系统档开始'), findsNothing);
  });

  // ════════════════════════════════════════════════════════
  // ADR-C132 批3（A）：结构化偏好四组 SegmentedButton（可空单选）
  // ════════════════════════════════════════════════════════

  testWidgets(
    '#18 高级区展开 → 4 组 SegmentedButton（可空单选）；选「简洁」落库 expressionDensity=low',
    (tester) async {
      await tester.pumpWidget(buildHost());
      await tester.pumpAndSettle();

      await tester.tap(find.text('自定义教练'));
      await tester.pumpAndSettle();

      // 展开高级选项
      await tester.tap(find.text('高级选项'));
      await tester.pumpAndSettle();

      // 四组：表达密度 / 提问直给 / 缓冲词 / emoji
      expect(find.text('结构化偏好（选填）'), findsOneWidget);
      final segs = find.byType(SegmentedButton<String>);
      expect(segs, findsNWidgets(3), reason: '前 3 组是 String 泛型');
      expect(
        find.byType(SegmentedButton<bool>),
        findsOneWidget,
        reason: 'emoji 组是 bool 泛型',
      );
      // 可空单选：emptySelectionAllowed = true（点已选 = 取消 = 不指定）
      for (final seg in segs.evaluate()) {
        expect(
          (seg.widget as SegmentedButton<String>).emptySelectionAllowed,
          isTrue,
        );
      }

      // 选「简洁」（表达密度 low）
      await tester.tap(find.text('简洁'));
      await tester.pump();

      // 名称必填 → 保存
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), '密度教练');
      await tester.tap(find.widgetWithText(TextButton, '保存'));
      await tester.pumpAndSettle();

      // 落库确证：结构化字段经表单写进 CoachPersona
      final saved = await AppStateRepository(db).getCustomCoachPersonas();
      expect(saved.single.expressionDensity, 'low');
    },
  );

  testWidgets('#19 不碰结构化偏好直接保存 → 四字段均为 null（不覆盖默认）', (tester) async {
    await tester.pumpWidget(buildHost());
    await tester.pumpAndSettle();

    await tester.tap(find.text('自定义教练'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '默认偏好教练');
    await tester.tap(find.widgetWithText(TextButton, '保存'));
    await tester.pumpAndSettle();

    final saved = await AppStateRepository(db).getCustomCoachPersonas();
    final p = saved.single;
    expect(p.expressionDensity, isNull);
    expect(p.questionPreference, isNull);
    expect(p.bufferWordPreference, isNull);
    expect(p.emojiAllowed, isNull);
  });

  // ════════════════════════════════════════════════════════
  // ADR-C132 批3（D）：试听语气按钮与结果框
  // ════════════════════════════════════════════════════════

  testWidgets('#20 空语气且无结构化偏好 → 点试听语气给出引导（不发请求）', (tester) async {
    await tester.pumpWidget(buildHost());
    await tester.pumpAndSettle();

    await tester.tap(find.text('自定义教练'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextButton, '试听语气'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '试听语气'));
    await tester.pump();

    expect(find.text('先填个语气或选几项结构化偏好，才能试听'), findsOneWidget);
  });

  testWidgets('#21 已配 Key + 假 client → 试听结果框展示口吻示范（不自动保存）', (tester) async {
    const canned = '这句写得有画面感，再补一个动作就立住了。';
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

    // 填一句语气（非空才走真试听分支）
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(1), '犀利直接');
    await tester.pump();

    await tester.tap(find.widgetWithText(TextButton, '试听语气'));
    await tester.pumpAndSettle();

    // 结果框出现 + 展示模型返回的口吻示范
    expect(find.text('口吻示范（仅预览，不会自动保存）'), findsOneWidget);
    expect(find.text(canned), findsOneWidget);
  });
}
