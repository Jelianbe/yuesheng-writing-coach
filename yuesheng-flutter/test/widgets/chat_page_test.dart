// ─────────────────────────────────────────────────────────────
// ChatPage widget 测试 — bootstrap → onboarding 完整接线
//
// 方案2 迁移（T2d）：
//   - 构造函数注入 db/bootstrapService → ProviderScope override
//   - 测试通过 override appDatabaseProvider / bootstrapServiceProvider 注入依赖
//
// 覆盖路径：
//   1. 新用户：空 DB → 弹问卷 → 完成问卷 → 隐藏问卷
//   2. 新用户：空 DB → 弹问卷 → 跳过问卷 → 隐藏问卷
//   3. 老用户：已有 questionnaire_completed → 不弹问卷
//   4. 初始化中：CircularProgressIndicator 占位
//   5. 完成问卷后状态持久化（onboarding_data + beginner_level + questionnaire_completed）
//   6. 复用已有 session（覆盖 sessions.first.id 分支）
//   7. bootstrap 异常 → 显示错误 UI（覆盖 AsyncError 分支）
//   8. 发送消息集成：输入 → 发送 → 流式渲染（T6）
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/app_state_repository.dart';
import 'package:writingcoach/data/repositories/chapter_repository.dart';
import 'package:writingcoach/data/repositories/diagnosis_repository.dart';
import 'package:writingcoach/data/repositories/editor_observation_repository.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/data/repositories/reference_repository.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/data/repositories/student_model_repository.dart';
import 'package:writingcoach/data/repositories/teacher_suggestion_repository.dart';
import 'package:writingcoach/data/repositories/teaching_state_repository.dart';
import 'package:writingcoach/providers/app_providers.dart';
import 'package:writingcoach/router/app_router.dart';
import 'package:writingcoach/providers/chat_store.dart';
import 'package:writingcoach/providers/practice_providers.dart';
import 'package:writingcoach/providers/session_providers.dart';
import 'package:writingcoach/services/bootstrap_service.dart';
import 'package:writingcoach/services/chat_service.dart';
import 'package:writingcoach/services/llm_client.dart';
import 'package:writingcoach/types/teaching_types.dart';
import 'package:writingcoach/widgets/chat_page.dart';
import 'package:writingcoach/widgets/encouragement_text.dart';
import 'package:writingcoach/widgets/message_list.dart';
import 'package:writingcoach/widgets/partial_agreement_card.dart';
import 'package:writingcoach/widgets/practice_task_card.dart';
import 'package:writingcoach/widgets/reference_bar.dart';
import 'package:writingcoach/widgets/task_panel.dart';

import '../helpers/mock_last_session_storage.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async => db.close());

  // 辅助：构造 ChatPage 并通过 ProviderScope 注入内存 DB
  Widget buildChatPage({BootstrapService? bootstrapService}) {
    return ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        // 批次 50：隔离 flutter_secure_storage 平台通道（testWidgets 下挂起）
        lastSessionStorageProvider.overrideWithValue(
          MemoryLastSessionStorage(),
        ),
        if (bootstrapService != null)
          bootstrapServiceProvider.overrideWithValue(bootstrapService),
      ],
      child: const MaterialApp(home: ChatPage()),
    );
  }

  group('新用户：空 DB → 弹问卷', () {
    testWidgets('#1 完成问卷 → 隐藏 + 状态迁移', (tester) async {
      await tester.pumpWidget(buildChatPage());

      // 初始化中：应显示 loading
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // 等待 bootstrap 完成（listSessions + shouldShowQuestionnaire）
      await tester.pumpAndSettle();

      // 应弹出问卷
      expect(find.text('写作偏好问卷'), findsOneWidget);

      // 走完 3 题
      await tester.tap(find.text('写过一些片段'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, '下一题'));
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      await tester.tap(find.text('人物塑造'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, '下一题'));
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      await tester.tap(find.text('边练边讲'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, '开始写作之旅'));
      await tester.pumpAndSettle();

      // 问卷应隐藏
      expect(find.text('写作偏好问卷'), findsNothing);

      // 应显示消息列表和输入框
      expect(find.byType(MessageList), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);

      // 状态迁移验证
      final appStateRepo = AppStateRepository(db);
      expect(await appStateRepo.getQuestionnaireCompleted(), true);
    });

    testWidgets('#2 跳过问卷 → 隐藏 + 状态迁移', (tester) async {
      await tester.pumpWidget(buildChatPage());
      await tester.pumpAndSettle();

      // 应弹出问卷
      expect(find.text('写作偏好问卷'), findsOneWidget);

      // 点击跳过
      await tester.tap(find.text('跳过问卷'));
      await tester.pumpAndSettle();

      // 问卷应隐藏
      expect(find.text('写作偏好问卷'), findsNothing);

      // 状态迁移验证
      final appStateRepo = AppStateRepository(db);
      expect(await appStateRepo.getQuestionnaireCompleted(), true);
    });
  });

  group('老用户：已有 questionnaire_completed → 不弹问卷', () {
    testWidgets('#3 老用户启动直接看到主页', (tester) async {
      // 预置：标记已完成
      final appStateRepo = AppStateRepository(db);
      await appStateRepo.setQuestionnaireCompleted(true);

      await tester.pumpWidget(buildChatPage());
      await tester.pumpAndSettle();

      // 不应弹问卷
      expect(find.text('写作偏好问卷'), findsNothing);

      // 应直接显示消息列表和输入框
      expect(find.byType(MessageList), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });
  });

  group('批次4：作品导入入口（+ 按钮）', () {
    testWidgets('#B4-1 + 按钮出现，点击打开作品导入弹层', (tester) async {
      final appStateRepo = AppStateRepository(db);
      await appStateRepo.setQuestionnaireCompleted(true);

      await tester.pumpWidget(buildChatPage());
      await tester.pumpAndSettle();

      // 批次3 接线：onUploadFile 传入后 + 按钮显示
      final plus = find.byIcon(Icons.add);
      expect(plus, findsOneWidget);

      await tester.tap(plus);
      await tester.pumpAndSettle();

      expect(find.text('导入作品'), findsOneWidget);
      expect(find.text('选择文件'), findsOneWidget);
      expect(find.text('粘贴文本'), findsOneWidget);
    });

    testWidgets('#B4-2 弹层粘贴文本导入 → 提示成功 + 主引用落库', (tester) async {
      final appStateRepo = AppStateRepository(db);
      await appStateRepo.setQuestionnaireCompleted(true);

      await tester.pumpWidget(buildChatPage());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      await tester.tap(find.text('粘贴文本'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        '第一章 启程\n启程正文',
      );
      await tester.tap(find.text('确认导入'));
      await tester.pumpAndSettle();

      // 成功引导弹层（批次 16 替代原 SnackBar）+ 弹层关闭
      expect(find.text('导入成功！'), findsOneWidget);
      expect(find.text('导入作品'), findsNothing);

      // 主引用已建（session → chapter）
      final sessionRepo = SessionRepository(db);
      final sessions = await sessionRepo.listSessions();
      final refs = await db.select(db.sessionReferences).get();
      expect(refs, hasLength(1));
      expect(refs.single.sessionId, sessions.single.id);
      expect(refs.single.refType, 'chapter');
      expect(refs.single.isPrimary, 1);
    });

    testWidgets('#B4-3 @ 按钮 mention 模式 → 插入 @路径 → 发送 → 首条自动设主 + SnackBar 反馈', (
      tester,
    ) async {
      final appStateRepo = AppStateRepository(db);
      await appStateRepo.setQuestionnaireCompleted(true);
      final msRepo = ManuscriptRepository(db);
      final chRepo = ChapterRepository(db);
      final msId = await msRepo.createManuscript(title: '测试小说');
      final chId = await chRepo.createChapter(
        msId,
        title: '第一章',
        content: '正文',
        sortOrder: 0,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            lastSessionStorageProvider.overrideWithValue(
              MemoryLastSessionStorage(),
            ),
            chatServiceProvider.overrideWithValue(_FakeChatService(db)),
          ],
          child: const MaterialApp(home: ChatPage()),
        ),
      );
      await tester.pumpAndSettle();

      // 批次70：输入 "@" 字符 → 触发引用选择器（替代独立 @ 按钮）
      await tester.enterText(find.byType(TextField), '@');
      await tester.pumpAndSettle();
      expect(find.text('选择引用'), findsOneWidget);

      // mention 模式：选章节 → 输入框插入稳定 ID 标记 @[chapter:<id>]（A-2：改名免疫）
      await tester.tap(find.text('测试小说'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('第一章'));
      await tester.pumpAndSettle();

      expect(find.textContaining('@[chapter:$chId]'), findsOneWidget);

      // 发送 → 解析 @ 引用 → 首条引用自动设主（批次 39：修复引用死数据，
      // 无主引用时 @ 首条设主，使保存到文件/相关对话等主引用链路可用）
      // 批次62：发送按钮用图标精确匹配（空态 ChatWelcome 新增 FilledButton）
      await tester.tap(find.widgetWithIcon(FilledButton, Icons.arrow_upward));
      await tester.pumpAndSettle();

      final refs = await db.select(db.sessionReferences).get();
      expect(refs, hasLength(1));
      expect(refs.single.refType, 'chapter');
      expect(refs.single.refId, chId);
      expect(refs.single.isPrimary, 1); // 无主引用时 @ 首条自动设主
      // @ 引用反馈（批次 39：修复引用死数据的无反馈问题）
      expect(find.textContaining('已引用'), findsOneWidget);
    });

    testWidgets('#B4-4 批次33 对话页不显示 ReferenceBar（顶部引用条已移除，只保留 @）', (
      tester,
    ) async {
      final appStateRepo = AppStateRepository(db);
      await appStateRepo.setQuestionnaireCompleted(true);
      final msRepo = ManuscriptRepository(db);
      await msRepo.createManuscript(title: '测试小说');

      await tester.pumpWidget(buildChatPage());
      await tester.pumpAndSettle();

      // 顶部引用条已移除（批次 33：只保留 @ mention 引用入口，主引用机制保留在数据层）
      expect(find.byType(ReferenceBar), findsNothing);
      expect(find.text('还没有引用作品，点下方按钮添加'), findsNothing);
    });
  });

  group('批次5：会话抽屉 SessionDrawer', () {
    testWidgets('#B5-1 汉堡打开抽屉 → 切换会话 → 消息列表刷新', (tester) async {
      final appStateRepo = AppStateRepository(db);
      await appStateRepo.setQuestionnaireCompleted(true);
      final sessionRepo = SessionRepository(db);
      // 会话 A 有消息，会话 B 为空（默认会话可能是 A 或 B，断言不依赖初始）
      final aId = await sessionRepo.createBlankSession(title: '会话A');
      await sessionRepo.addMessage(aId, 'user', 'A的独有消息');
      final bId = await sessionRepo.createBlankSession(title: '会话B');

      await tester.pumpWidget(buildChatPage());
      await tester.pumpAndSettle();

      // 汉堡打开抽屉 → 两个会话显示
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      expect(find.text('对话'), findsOneWidget);
      expect(find.text('会话A'), findsOneWidget);
      expect(find.text('会话B'), findsOneWidget);

      // 切到会话 B（空）→ A 的消息不显示
      await tester.tap(find.text('会话B'));
      await tester.pumpAndSettle();
      expect(find.text('对话'), findsNothing);
      expect(find.text('A的独有消息'), findsNothing);

      // 切回会话 A → 消息列表加载 A 的消息
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      await tester.tap(find.text('会话A'));
      await tester.pumpAndSettle();
      expect(find.text('A的独有消息'), findsOneWidget);

      // DB 验证：messages 仍只属于 A
      final msgs = await sessionRepo.listMessages(bId);
      expect(msgs, isEmpty);
    });

    testWidgets('#B5-2 新建会话 → 数量 +1 且可发送', (tester) async {
      final appStateRepo = AppStateRepository(db);
      await appStateRepo.setQuestionnaireCompleted(true);
      final sessionRepo = SessionRepository(db);
      await sessionRepo.createBlankSession(title: '会话A');
      final before = (await db.select(db.sessions).get()).length;

      await tester.pumpWidget(buildChatPage());
      await tester.pumpAndSettle();

      // 打开抽屉 → 新建会话
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      await tester.tap(find.text('新建会话'));
      await tester.pumpAndSettle();

      final after = (await db.select(db.sessions).get()).length;
      expect(after, before + 1);
      // 抽屉已关闭
      expect(find.text('对话'), findsNothing);
    });

    testWidgets('#B5-3 批次73 长按删除当前会话 → DB 删除 + 切到剩余会话 + 消息清空', (
      tester,
    ) async {
      final appStateRepo = AppStateRepository(db);
      await appStateRepo.setQuestionnaireCompleted(true);
      final sessionRepo = SessionRepository(db);
      // 当前会话 A 带消息，另建会话 B
      final aId = await sessionRepo.createBlankSession(title: '会话A');
      await sessionRepo.addMessage(aId, 'user', 'A的独有消息');
      final bId = await sessionRepo.createBlankSession(title: '会话B');

      await tester.pumpWidget(buildChatPage());
      await tester.pumpAndSettle();

      // 切到会话 A（确保删除的是当前会话）
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      await tester.tap(find.text('会话A'));
      await tester.pumpAndSettle();
      expect(find.text('A的独有消息'), findsOneWidget);

      // 长按「会话A」→ 确认删除
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      await tester.longPress(find.text('会话A'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();

      // A 已删除，B 保留；A 的消息不再显示
      final sessions = await sessionRepo.listSessions();
      expect(sessions.any((s) => s.id == aId), isFalse);
      expect(sessions.any((s) => s.id == bId), isTrue);
      expect(find.text('A的独有消息'), findsNothing);
    });
  });

  group('初始化中', () {
    testWidgets('#4 显示 CircularProgressIndicator', (tester) async {
      await tester.pumpWidget(buildChatPage());

      // 不 pump/pumpAndSettle：pumpWidget 只触发首帧，
      // sessionBootstrapProvider 的 build 异步尚未完成，状态为 AsyncLoading
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });

  group('完成问卷后状态持久化', () {
    testWidgets('#5 elementary → N1_ELEMENTS + onboarding_data 完整', (
      tester,
    ) async {
      await tester.pumpWidget(buildChatPage());
      await tester.pumpAndSettle();

      // 走完 3 题，选 elementary
      await tester.tap(find.text('写过一些片段'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, '下一题'));
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      await tester.tap(find.text('人物塑造'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('情节设计'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, '下一题'));
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      await tester.tap(find.text('边练边讲'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, '开始写作之旅'));
      await tester.pumpAndSettle();

      // 验证 onboarding_data
      final sessions = await db.select(db.sessions).get();
      expect(sessions.length, 1);
      final sessionId = sessions.first.id;

      final smRepo = StudentModelRepository(db);
      final saved = await smRepo.getOnboardingData(sessionId);
      expect(saved, isNotNull);
      expect(saved!['proficiency'], 'elementary');
      expect(saved['focusAreas'], ['人物塑造', '情节设计']);
      expect(saved['cognitiveStyle'], 'mixed');
      expect(saved['skipped'], false);

      // 验证 beginner_level
      final stateRepo = TeachingStateRepository(db);
      final ts = await stateRepo.getTeachingState(sessionId);
      expect(ts, isNotNull);
      expect(ts!.beginnerLevel, BeginnerLevel.n1Elements.value);
    });
  });

  group('复用已有 session（覆盖 sessions.first.id 分支）', () {
    testWidgets('#6 DB 中已有 session → 复用而非新建', (tester) async {
      // 预置：DB 中已存在一条 session（模拟老用户首次启动）
      // 同时标记 questionnaire_completed=false，让 bootstrap 走完整流程
      final sessionRepo = SessionRepository(db);
      final presetSessionId = await sessionRepo.createBlankSession();
      final appStateRepo = AppStateRepository(db);
      // 注意：不设 questionnaire_completed，让 shouldShowQuestionnaire 返回 true
      // 这样可以同时验证"复用 session"和"新用户问卷"两个分支
      expect(await appStateRepo.getQuestionnaireCompleted(), false);

      await tester.pumpWidget(buildChatPage());
      await tester.pumpAndSettle();

      // 不应新建 session，应复用预置的 sessionId
      final sessions = await db.select(db.sessions).get();
      expect(sessions.length, 1);
      expect(sessions.first.id, presetSessionId);

      // 仍应弹问卷（questionnaire_completed 未设）
      expect(find.text('写作偏好问卷'), findsOneWidget);
    });
  });

  group('bootstrap 异常路径', () {
    testWidgets('#7 bootstrapService 抛异常 → 显示错误 UI', (tester) async {
      // 注入一个会抛错的 fake BootstrapService，覆盖 AsyncError 分支
      // 注意：不能用 db.close() 方案，drift NativeDatabase.memory() 关闭后
      // 会自动重建 in-memory schema，查询仍返回空列表而非抛错
      final throwingService = _ThrowingBootstrapService();

      await tester.pumpWidget(buildChatPage(bootstrapService: throwingService));
      await tester.pumpAndSettle();

      // 应显示错误信息（覆盖 AsyncError 分支）
      expect(find.textContaining('初始化失败'), findsOneWidget);
      expect(find.textContaining('bootstrap failed'), findsOneWidget);

      // 不应显示问卷
      expect(find.text('写作偏好问卷'), findsNothing);

      // 不应显示"会话已就绪"
      expect(find.textContaining('会话已就绪'), findsNothing);
    });
  });

  group('发送消息集成（T6）', () {
    testWidgets('#8 输入消息 + 点击发送 → 触发流式渲染', (tester) async {
      // 预置：标记已完成问卷，跳过 onboarding
      final appStateRepo = AppStateRepository(db);
      await appStateRepo.setQuestionnaireCompleted(true);

      final fakeChatService = _FakeChatService(db);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            lastSessionStorageProvider.overrideWithValue(
              MemoryLastSessionStorage(),
            ),
            chatServiceProvider.overrideWithValue(fakeChatService),
          ],
          child: const MaterialApp(home: ChatPage()),
        ),
      );
      await tester.pumpAndSettle();

      // 应显示输入框
      expect(find.byType(TextField), findsOneWidget);

      // 输入消息
      await tester.enterText(find.byType(TextField), '测试消息');
      await tester.pump();

      // 点击发送按钮（批次62：图标精确匹配，空态 ChatWelcome 新增 FilledButton）
      await tester.tap(find.widgetWithIcon(FilledButton, Icons.arrow_upward));
      // 驱动 frame：pump() 处理 setStreaming(true) 的 rebuild
      await tester.pump();
      // 推进时间但仍在 FakeChatService 的初始 50ms 延迟内
      await tester.pump(const Duration(milliseconds: 30));

      // 应显示 ThinkingIndicator（streaming 启动但内容为空）
      expect(find.byType(ThinkingIndicator), findsOneWidget);

      // 等待流式完成
      await tester.pumpAndSettle(const Duration(milliseconds: 500));

      // 应显示 assistant 回复
      expect(find.text('你好，我是月笙。'), findsOneWidget);
    });

    testWidgets('#9 发送空消息 → 按钮禁用', (tester) async {
      final appStateRepo = AppStateRepository(db);
      await appStateRepo.setQuestionnaireCompleted(true);

      await tester.pumpWidget(buildChatPage());
      await tester.pumpAndSettle();

      // 空输入时发送按钮应禁用（批次62：图标精确匹配，空态 ChatWelcome 新增 FilledButton）
      final button = tester.widget<FilledButton>(
        find.widgetWithIcon(FilledButton, Icons.arrow_upward),
      );
      expect(button.enabled, false);
    });
  });

  group('删除消息（T9 #14）', () {
    testWidgets('#10 长按消息 → 弹出删除确认对话框', (tester) async {
      final appStateRepo = AppStateRepository(db);
      await appStateRepo.setQuestionnaireCompleted(true);

      // 预置：直接写入一条 user 消息
      final sessionRepo = SessionRepository(db);
      final sessionId = await sessionRepo.createBlankSession();
      await sessionRepo.addMessage(
        sessionId,
        'user',
        '待删除的消息',
        messageType: 'chat',
      );

      await tester.pumpWidget(buildChatPage());
      await tester.pumpAndSettle();

      // 应显示预置消息
      expect(find.text('待删除的消息'), findsOneWidget);

      // 长按消息
      await tester.longPress(find.text('待删除的消息'));
      await tester.pumpAndSettle();

      // 应弹出删除确认对话框
      expect(find.text('确认删除'), findsOneWidget);
      expect(find.text('删除'), findsOneWidget);
      expect(find.text('取消'), findsOneWidget);
    });

    testWidgets('#11 点击删除 → 消息从 UI 和 DB 移除', (tester) async {
      final appStateRepo = AppStateRepository(db);
      await appStateRepo.setQuestionnaireCompleted(true);

      final sessionRepo = SessionRepository(db);
      final sessionId = await sessionRepo.createBlankSession();
      await sessionRepo.addMessage(
        sessionId,
        'user',
        '要删掉的消息',
        messageType: 'chat',
      );

      await tester.pumpWidget(buildChatPage());
      await tester.pumpAndSettle();

      // 长按 → 弹窗 → 点击删除
      await tester.longPress(find.text('要删掉的消息'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();

      // UI 中消息应消失
      expect(find.text('要删掉的消息'), findsNothing);

      // DB 中消息也应删除
      final messages = await sessionRepo.listMessages(sessionId);
      expect(messages, isEmpty);
    });

    testWidgets('#12 点击取消 → 消息保留', (tester) async {
      final appStateRepo = AppStateRepository(db);
      await appStateRepo.setQuestionnaireCompleted(true);

      final sessionRepo = SessionRepository(db);
      final sessionId = await sessionRepo.createBlankSession();
      await sessionRepo.addMessage(
        sessionId,
        'user',
        '不删的消息',
        messageType: 'chat',
      );

      await tester.pumpWidget(buildChatPage());
      await tester.pumpAndSettle();

      // 长按 → 弹窗 → 点击取消
      await tester.longPress(find.text('不删的消息'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      // 消息应仍在 UI 中
      expect(find.text('不删的消息'), findsOneWidget);

      // DB 中消息也应保留
      final messages = await sessionRepo.listMessages(sessionId);
      expect(messages.length, 1);
    });
  });

  group('态度切换（T6 persistAttitude 双写）', () {
    testWidgets('#13 切换态度 → UI 更新 + teaching_state/student_model 双写', (
      tester,
    ) async {
      // 预置：老用户，跳过问卷
      final appStateRepo = AppStateRepository(db);
      await appStateRepo.setQuestionnaireCompleted(true);

      await tester.pumpWidget(buildChatPage());
      await tester.pumpAndSettle();

      // 打开更多菜单（批次 10：态度切换迁入 ChatHeader 更多菜单行内选择）
      await tester.tap(find.byIcon(Icons.more_horiz));
      await tester.pumpAndSettle();
      expect(find.text('态度档位'), findsOneWidget);

      // 默认档位 doubao 在行内选项中出现
      expect(find.text('豆包'), findsOneWidget);

      // 切换到「月笙如歌」（点击后菜单关闭，态度已切换）
      await tester.tap(find.text('月笙如歌'));
      await tester.pumpAndSettle();

      // 验证 DB 双写（teaching_state + student_model 自动建行）
      final sessionId = (await db.select(db.sessions).get()).first.id;
      final stateRepo = TeachingStateRepository(db);
      final ts = await stateRepo.getTeachingState(sessionId);
      expect(ts!.attitudeLevel, 'yuesheng');

      final model = await (db.select(
        db.studentModels,
      )..where((t) => t.sessionId.equals(sessionId))).getSingleOrNull();
      expect(model, isNotNull, reason: '切换态度应自动创建 student_model 行');
      expect(model!.attitudePreference, 'yuesheng');
    });
  });

  group('批次10：QuickChips/头部状态区', () {
    testWidgets('#B10-1 ChatHeader 渲染 + 更多菜单', (tester) async {
      final appStateRepo = AppStateRepository(db);
      await appStateRepo.setQuestionnaireCompleted(true);

      await tester.pumpWidget(buildChatPage());
      await tester.pumpAndSettle();

      // 头部：标题「会话」+ 徽章「自由对话」
      expect(find.text('会话'), findsOneWidget);
      expect(find.text('自由对话'), findsOneWidget);

      // 更多菜单 → 阶段（P0 建立投入）/ 态度档位 / 画像
      await tester.tap(find.byIcon(Icons.more_horiz));
      await tester.pumpAndSettle();
      expect(find.text('当前阶段'), findsOneWidget);
      expect(find.text('建立投入'), findsOneWidget);
      expect(find.text('态度档位'), findsOneWidget);
      expect(find.text('画像'), findsOneWidget);
    });

    testWidgets('#B10-2 空会话 → ChatWelcome 欢迎态', (tester) async {
      final appStateRepo = AppStateRepository(db);
      await appStateRepo.setQuestionnaireCompleted(true);

      await tester.pumpWidget(buildChatPage());
      await tester.pumpAndSettle();

      expect(find.text('你好，我是月笙'), findsOneWidget);
      expect(find.text('你的专属写作教练，随时帮你诊断和提升写作'), findsOneWidget);
    });

    testWidgets('#B10-4 诊断结果消息 → 鼓励文案显示', (tester) async {
      final appStateRepo = AppStateRepository(db);
      await appStateRepo.setQuestionnaireCompleted(true);
      final sessionRepo = SessionRepository(db);
      final sId = await sessionRepo.createBlankSession(title: '测试会话');
      await sessionRepo.addMessage(
        sId,
        'assistant',
        '诊断内容',
        messageType: 'diagnosis_result',
      );

      await tester.pumpWidget(buildChatPage());
      await tester.pumpAndSettle();

      expect(find.byType(EncouragementText), findsOneWidget);
    });
  });

  group('批次12：态度建议横幅', () {
    /// 预置：已完成问卷 + sensei 态度 + 10 条消息 + 1 条 L1 诊断
    /// （sensei + 低严重度 + ≤1症候 + ≥10 消息 → 触发降级建议）
    Future<String> seedDowngradeEnv() async {
      final appStateRepo = AppStateRepository(db);
      await appStateRepo.setQuestionnaireCompleted(true);
      final sessionRepo = SessionRepository(db);
      final sId = await sessionRepo.createBlankSession(title: '建议会话');
      await TeachingStateRepository(db).persistAttitude(sId, 'sensei');
      for (var i = 0; i < 5; i++) {
        await sessionRepo.addMessage(sId, 'user', '问题 $i');
        await sessionRepo.addMessage(sId, 'assistant', '回复 $i');
      }
      final payload = jsonEncode({
        'syndromes': [
          {
            'syndrome_id': 'P001',
            'name': '逻辑跳跃',
            'severity': 'L1',
            'evidence_count': 1,
          },
        ],
      });
      await sessionRepo.addMessage(
        sId,
        'system',
        payload,
        messageType: 'diagnosis_result',
      );
      return sId;
    }

    testWidgets('#B12-1 发送后触发降级建议横幅 + QuickChips 隐藏', (tester) async {
      await seedDowngradeEnv();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            lastSessionStorageProvider.overrideWithValue(
              MemoryLastSessionStorage(),
            ),
            chatServiceProvider.overrideWithValue(_FakeChatService(db)),
          ],
          child: const MaterialApp(home: ChatPage()),
        ),
      );
      await tester.pumpAndSettle();

      // 发送一条消息 → onComplete 后延迟 500ms 检查 → 横幅出现
      await tester.enterText(find.byType(TextField), '再来一轮');
      await tester.pump();
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle(const Duration(milliseconds: 600));

      expect(find.text('建议调整为轻松模式'), findsOneWidget);
      expect(find.text('切换到月笙'), findsOneWidget);
      expect(find.textContaining('当前问题较少'), findsOneWidget);
      // 横幅显示时 QuickChips 隐藏（对齐 RN !attitudeSuggestion）
      expect(find.text('诊断节奏问题'), findsNothing);
    });

    testWidgets('#B12-2 点击「切换到月笙」→ 态度双写 + 横幅消失', (tester) async {
      final sId = await seedDowngradeEnv();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            lastSessionStorageProvider.overrideWithValue(
              MemoryLastSessionStorage(),
            ),
            chatServiceProvider.overrideWithValue(_FakeChatService(db)),
          ],
          child: const MaterialApp(home: ChatPage()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '接受建议');
      await tester.pump();
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle(const Duration(milliseconds: 600));

      // 接受 → 横幅消失
      await tester.tap(find.text('切换到月笙'));
      await tester.pumpAndSettle();

      expect(find.text('建议调整为轻松模式'), findsNothing);
      // 态度双写验证（teaching_state.attitude_level → yuesheng）
      final rows = await (db.select(
        db.teachingState,
      )..where((t) => t.sessionId.equals(sId))).get();
      expect(rows.single.attitudeLevel, 'yuesheng');
    });

    testWidgets('#B12-3 点击「暂不」→ 横幅消失 + 态度不变', (tester) async {
      final sId = await seedDowngradeEnv();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            lastSessionStorageProvider.overrideWithValue(
              MemoryLastSessionStorage(),
            ),
            chatServiceProvider.overrideWithValue(_FakeChatService(db)),
          ],
          child: const MaterialApp(home: ChatPage()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '暂不切换');
      await tester.pump();
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle(const Duration(milliseconds: 600));

      await tester.tap(find.text('暂不'));
      await tester.pumpAndSettle();

      expect(find.text('建议调整为轻松模式'), findsNothing);
      final rows = await (db.select(
        db.teachingState,
      )..where((t) => t.sessionId.equals(sId))).get();
      expect(rows.single.attitudeLevel, 'sensei');
      // 批次（QuickChips 移除后无恢复显示断言；态度保持 sensei 即验证「暂不」不改变）
    });
  });

  group('批次13：诊断确认/选择（自动诊断）', () {
    const diagContent =
        '这是一个大雪纷飞的夜晚，北风呼啸着穿过空旷的原野，'
        '远处的山峦在暮色中显得格外孤寂。一位旅人独自走在雪地里，'
        '身后留下一串深深浅浅的脚印，很快又被新雪覆盖。'
        '他裹紧了身上的斗篷，目光投向远方那点若隐若现的灯火。';

    testWidgets('#B13-1 成长页选章 → 切 Tab 自动发送诊断', (tester) async {
      final appStateRepo = AppStateRepository(db);
      await appStateRepo.setQuestionnaireCompleted(true);
      final msRepo = ManuscriptRepository(db);
      final chRepo = ChapterRepository(db);
      final msId = await msRepo.createManuscript(title: '测试作品');
      final chapterId = await chRepo.createChapter(
        msId,
        title: '第一章：启程',
        content: diagContent,
      );

      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          lastSessionStorageProvider.overrideWithValue(
            MemoryLastSessionStorage(),
          ),
          chatServiceProvider.overrideWithValue(_FakeChatService(db)),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: ChatPage()),
        ),
      );
      await tester.pumpAndSettle();

      // 模拟成长页：记录待诊断章节 → 切 Tab（startDiagnosis 语义）
      container.read(pendingDiagnosisChapterProvider.notifier).state =
          chapterId;
      await tester.pumpAndSettle(const Duration(milliseconds: 600));

      // 自动诊断：user 消息（诊断 prompt）已落库
      final messages = await db.select(db.messages).get();
      expect(
        messages.any((m) => m.role == 'user' && m.content.contains('写作诊断分析')),
        isTrue,
        reason: '选章后应自动发送诊断请求',
      );
    });

    testWidgets('#B13-2 短章节选章 → 提示且不发送诊断', (tester) async {
      final appStateRepo = AppStateRepository(db);
      await appStateRepo.setQuestionnaireCompleted(true);
      final msRepo = ManuscriptRepository(db);
      final chRepo = ChapterRepository(db);
      final msId = await msRepo.createManuscript(title: '短作品');
      final chapterId = await chRepo.createChapter(
        msId,
        title: '短章',
        content: '太短了。',
      );

      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          lastSessionStorageProvider.overrideWithValue(
            MemoryLastSessionStorage(),
          ),
          chatServiceProvider.overrideWithValue(_FakeChatService(db)),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: ChatPage()),
        ),
      );
      await tester.pumpAndSettle();

      container.read(pendingDiagnosisChapterProvider.notifier).state =
          chapterId;
      await tester.pumpAndSettle(const Duration(milliseconds: 600));

      // 短章节：提示 + 无 user 诊断消息落库
      expect(find.text('章节内容少于 100 字，请先编辑章节'), findsOneWidget);
      final messages = await db.select(db.messages).get();
      expect(messages.where((m) => m.role == 'user'), isEmpty);
    });
  });

  group('批次14：保存到文件', () {
    const assistantContent = '这是教练的回复内容，包含写作建议。';

    /// 预置：完成问卷 + 作品 + 章节 + 空白会话 + assistant 消息
    /// [withPrimary] 是否为主引用建立引用关系（chapter 主引用 → manuscript_id 回填）
    Future<String> seedSession({required bool withPrimary}) async {
      final appStateRepo = AppStateRepository(db);
      await appStateRepo.setQuestionnaireCompleted(true);
      final sRepo = SessionRepository(db);
      final sessionId = await sRepo.createBlankSession(title: '测试会话');
      final msRepo = ManuscriptRepository(db);
      final msId = await msRepo.createManuscript(title: '测试作品');
      final chRepo = ChapterRepository(db);
      final chapterId = await chRepo.createChapter(
        msId,
        title: '第一章',
        content: assistantContent,
      );
      if (withPrimary) {
        await ReferenceRepository(
          db,
        ).addReference(sessionId, 'chapter', chapterId, isPrimary: true);
      }
      await sRepo.addMessage(sessionId, 'assistant', assistantContent);
      return sessionId;
    }

    testWidgets('#B14-1 无引用 → 点「保存到文件」提示先关联书籍且不打开弹层', (tester) async {
      await seedSession(withPrimary: false);

      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          lastSessionStorageProvider.overrideWithValue(
            MemoryLastSessionStorage(),
          ),
          chatServiceProvider.overrideWithValue(_FakeChatService(db)),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: ChatPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(assistantContent), findsOneWidget);
      await tester.tap(find.text('保存到文件'));
      await tester.pumpAndSettle();

      expect(find.text('请先关联一本书籍'), findsOneWidget);
      expect(find.text('保存到《第一章》'), findsNothing);
    });

    testWidgets('#B14-3 无主引用但有 @ 附加引用 → 保存到文件回退到第一条引用（批次39 死数据修复）', (
      tester,
    ) async {
      // 预置：无主引用，仅 @ 附加引用（模拟 @ 引用后未设主场景）
      final appStateRepo = AppStateRepository(db);
      await appStateRepo.setQuestionnaireCompleted(true);
      final sRepo = SessionRepository(db);
      final sessionId = await sRepo.createBlankSession(title: '测试会话');
      final msRepo = ManuscriptRepository(db);
      final msId = await msRepo.createManuscript(title: '测试作品');
      final chRepo = ChapterRepository(db);
      final chapterId = await chRepo.createChapter(
        msId,
        title: '第一章',
        content: assistantContent,
      );
      // @ 附加引用（isPrimary=0）
      await ReferenceRepository(
        db,
      ).addReference(sessionId, 'chapter', chapterId);
      await sRepo.addMessage(sessionId, 'assistant', assistantContent);

      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          lastSessionStorageProvider.overrideWithValue(
            MemoryLastSessionStorage(),
          ),
          chatServiceProvider.overrideWithValue(_FakeChatService(db)),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: ChatPage()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('保存到文件'));
      await tester.pumpAndSettle();

      // 回退到第一条引用 → 弹层正常打开（目标为章节所属作品）
      expect(find.text('保存到《第一章》'), findsOneWidget);
      expect(find.text('请先关联一本书籍'), findsNothing);

      // 保存落库：bookId = 章节所属作品
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      final rows = await db.select(db.attachedFiles).get();
      expect(rows, hasLength(1));
      expect(rows.single.bookId, msId);
      expect(rows.single.content, assistantContent);
    });

    testWidgets('#B14-2 有主引用 → 保存 AI 内容到文件（含角色切换）', (tester) async {
      await seedSession(withPrimary: true);

      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          lastSessionStorageProvider.overrideWithValue(
            MemoryLastSessionStorage(),
          ),
          chatServiceProvider.overrideWithValue(_FakeChatService(db)),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: ChatPage()),
        ),
      );
      await tester.pumpAndSettle();

      // 打开弹层：标题 + 副标题（主引用章节名）
      await tester.tap(find.text('保存到文件'));
      await tester.pumpAndSettle();
      expect(find.text('保存到文件'), findsWidgets);
      expect(find.text('保存到《第一章》'), findsOneWidget);

      // 切换「素材」角色 → 保存
      await tester.tap(find.text('素材'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      // attached_files 落库：bookId=作品ID、role=material、content=AI 内容
      final rows = await db.select(db.attachedFiles).get();
      expect(rows, hasLength(1));
      expect(rows.single.fileRole, 'material');
      expect(rows.single.content, assistantContent);
      expect(rows.single.fileName, assistantContent.split('\n').first);
      // 弹层关闭
      expect(find.text('保存到《第一章》'), findsNothing);
    });
  });

  group('批次15：放弃练习确认', () {
    const task = PracticeTask(
      syndromeId: 's1',
      syndromeName: '症候A',
      taskDescription: '描写堆砌导致节奏拖沓',
      taskGoal: '用 3 句话替换 1 段冗余描写',
    );

    /// 预置：完成问卷 + 空白会话（ChatPage bootstrap 复用）
    /// 预置一条 user 消息避免空态（空态 ChatWelcome + 练习卡叠加会溢出，
    /// 非本次批次范围，用真实消息场景聚焦弹窗流程）
    Future<String> seedSession() async {
      final appStateRepo = AppStateRepository(db);
      await appStateRepo.setQuestionnaireCompleted(true);
      final sRepo = SessionRepository(db);
      final sessionId = await sRepo.createBlankSession(title: '测试会话');
      await sRepo.addMessage(sessionId, 'user', '你好，开始练习');
      return sessionId;
    }

    Future<ProviderContainer> pumpChatWithTask(WidgetTester tester) async {
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          lastSessionStorageProvider.overrideWithValue(
            MemoryLastSessionStorage(),
          ),
          chatServiceProvider.overrideWithValue(_FakeChatService(db)),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: ChatPage()),
        ),
      );
      await tester.pumpAndSettle();
      // 注入练习任务（对齐 RN 训练启动）
      container.read(practiceStoreProvider.notifier).startPractice(task);
      await tester.pumpAndSettle();
      // 练习卡渲染在列表底部 → 滚动到「跳过」按钮可点击
      await tester.ensureVisible(find.text('跳过'));
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets('#B15-1 点「跳过」→ 出现确认弹窗且任务仍在', (tester) async {
      await seedSession();
      await pumpChatWithTask(tester);

      expect(find.text('跳过'), findsOneWidget);
      await tester.tap(find.text('跳过'));
      await tester.pumpAndSettle();

      expect(find.text('确定跳过本次练习？'), findsOneWidget);
      expect(find.text('继续练习'), findsOneWidget);
      expect(find.text('确认跳过'), findsOneWidget);
    });

    testWidgets('#B15-2 点「继续练习」→ 弹窗关闭 + 任务保留', (tester) async {
      await seedSession();
      final container = await pumpChatWithTask(tester);

      await tester.tap(find.text('跳过'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('继续练习'));
      await tester.pumpAndSettle();

      expect(find.text('确定跳过本次练习？'), findsNothing);
      final state = container.read(practiceStoreProvider);
      expect(state.activePracticeTask, isNotNull);
    });

    testWidgets('#B15-3 点「确认跳过」→ 任务清空 + 子阶段落库 DIAGNOSIS', (tester) async {
      final sessionId = await seedSession();
      final container = await pumpChatWithTask(tester);

      await tester.tap(find.text('跳过'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认跳过'));
      await tester.pumpAndSettle();

      expect(find.text('确定跳过本次练习？'), findsNothing);
      final state = container.read(practiceStoreProvider);
      expect(state.activePracticeTask, isNull);

      // teaching_state 子阶段持久化为 DIAGNOSIS
      final rows = await (db.select(
        db.teachingState,
      )..where((t) => t.sessionId.equals(sessionId))).get();
      expect(rows.single.currentSubphase, 'DIAGNOSIS');
    });
  });

  group('批次16：导入成功反馈', () {
    const importLongText =
        '第一章 启程\n'
        '这是一个大雪纷飞的夜晚，北风呼啸着穿过空旷的原野，'
        '远处的山峦在暮色中显得格外孤寂。一位旅人独自走在雪地里，'
        '身后留下一串深深浅浅的脚印，很快又被新雪覆盖。'
        '他裹紧了身上的斗篷，目光投向远方那点若隐若现的灯火。';

    Future<String> seedSession() async {
      final appStateRepo = AppStateRepository(db);
      await appStateRepo.setQuestionnaireCompleted(true);
      final sRepo = SessionRepository(db);
      return sRepo.createBlankSession(title: '测试会话');
    }

    Future<ProviderContainer> pumpChat(WidgetTester tester) async {
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          lastSessionStorageProvider.overrideWithValue(
            MemoryLastSessionStorage(),
          ),
          chatServiceProvider.overrideWithValue(_FakeChatService(db)),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: ChatPage()),
        ),
      );
      await tester.pumpAndSettle();
      return container;
    }

    /// 走完整导入流程：+ 按钮 → WorkImportSheet → 粘贴文本 → 确认导入
    Future<void> importViaSheet(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      await tester.tap(find.text('粘贴文本'));
      await tester.pumpAndSettle();
      // 粘贴对话框内的输入框（ChatInput 主输入框也是 TextField，需精确到对话框内）
      final pasteField = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(pasteField, importLongText);
      await tester.tap(find.text('确认导入'));
      await tester.pumpAndSettle();
    }

    testWidgets('#B16-1 导入完成 → 显示成功引导弹层（章节数 + 双按钮）', (tester) async {
      await seedSession();
      await pumpChat(tester);

      await importViaSheet(tester);

      expect(find.text('导入成功！'), findsOneWidget);
      expect(find.textContaining('已成功导入 1 个章节到'), findsOneWidget);
      expect(find.text('立即诊断'), findsOneWidget);
      expect(find.text('稍后再说'), findsOneWidget);
    });

    testWidgets('#B16-2 点「立即诊断」→ 自动诊断发送（user 诊断消息落库）', (tester) async {
      await seedSession();
      await pumpChat(tester);

      await importViaSheet(tester);
      await tester.tap(find.text('立即诊断'));
      await tester.pumpAndSettle(const Duration(milliseconds: 600));

      // 弹层关闭 + 自动诊断 user 消息落库
      expect(find.text('导入成功！'), findsNothing);
      final messages = await db.select(db.messages).get();
      expect(
        messages.any((m) => m.role == 'user' && m.content.contains('写作诊断分析')),
        isTrue,
        reason: '立即诊断应触发自动诊断',
      );
    });

    testWidgets('#B16-3 点「稍后再说」→ 弹层关闭 + 不发送诊断', (tester) async {
      await seedSession();
      await pumpChat(tester);

      await importViaSheet(tester);
      await tester.tap(find.text('稍后再说'));
      await tester.pumpAndSettle(const Duration(milliseconds: 600));

      expect(find.text('导入成功！'), findsNothing);
      final messages = await db.select(db.messages).get();
      expect(
        messages.any((m) => m.role == 'user' && m.content.contains('写作诊断分析')),
        isFalse,
        reason: '稍后再说不应触发诊断',
      );
    });
  });

  group('批次18：活跃问题面板', () {
    /// 预置：完成问卷 + 会话 + teaching_state 阶段置为 P2
    Future<String> seedP2Session() async {
      final appStateRepo = AppStateRepository(db);
      await appStateRepo.setQuestionnaireCompleted(true);
      final sRepo = SessionRepository(db);
      final sessionId = await sRepo.createBlankSession(title: 'P2会话');
      await TeachingStateRepository(
        db,
      ).updatePhase(sessionId, 'P2_PRACTICE_LOOP');
      return sessionId;
    }

    /// 直接插入一条活跃问题（active_problem 表）
    Future<void> insertActiveProblem(
      String sessionId,
      String syndromeId,
      String syndromeName,
      String severity,
    ) async {
      await db
          .into(db.activeProblems)
          .insert(
            ActiveProblemsCompanion.insert(
              id: 'ap-$syndromeId',
              sessionId: sessionId,
              syndromeId: syndromeId,
              syndromeName: Value(syndromeName),
              severity: Value(severity),
            ),
          );
    }

    Future<ProviderContainer> pumpChat(WidgetTester tester) async {
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          lastSessionStorageProvider.overrideWithValue(
            MemoryLastSessionStorage(),
          ),
          chatServiceProvider.overrideWithValue(_FakeChatService(db)),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: ChatPage()),
        ),
      );
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets('#B18-1 P2 阶段 → 任务开关 + 展开显示活跃问题', (tester) async {
      final sessionId = await seedP2Session();
      await insertActiveProblem(sessionId, 'P001', '视角跳跃症', 'L2');
      await pumpChat(tester);

      // toggle 显示数量
      expect(find.text('任务 (1)'), findsOneWidget);

      // 点击展开 → TaskPanel 显示问题
      await tester.tap(find.text('任务 (1)'));
      await tester.pumpAndSettle();

      expect(find.byType(TaskPanel), findsOneWidget);
      expect(find.text('练习任务'), findsOneWidget);
      expect(find.text('视角跳跃症'), findsOneWidget);
      expect(find.text('注意'), findsOneWidget); // L2 严重度中文标签
      expect(find.text('完成'), findsOneWidget);

      // 再点收起
      await tester.tap(find.text('收起任务'));
      await tester.pumpAndSettle();
      expect(find.byType(TaskPanel), findsNothing);
    });

    testWidgets('#B18-2 点击完成 → resolveProblem 落库 + 面板刷新为空态', (tester) async {
      final sessionId = await seedP2Session();
      await insertActiveProblem(sessionId, 'P001', '视角跳跃症', 'L2');
      await pumpChat(tester);

      await tester.tap(find.text('任务 (1)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();

      // active_problem status 落库为 resolved
      final rows = await db.select(db.activeProblems).get();
      expect(rows.single.status, 'resolved');

      // 面板刷新 → 空态（面板仍展开，toggle 显示「收起任务」）
      expect(find.text('暂无活跃问题'), findsOneWidget);
      expect(find.text('收起任务'), findsOneWidget);

      // 收起后 toggle 显示数量 0
      await tester.tap(find.text('收起任务'));
      await tester.pumpAndSettle();
      expect(find.text('任务 (0)'), findsOneWidget);
    });

    testWidgets('#B18-3 非 P2 阶段 → 不显示任务开关', (tester) async {
      final appStateRepo = AppStateRepository(db);
      await appStateRepo.setQuestionnaireCompleted(true);
      final sRepo = SessionRepository(db);
      await sRepo.createBlankSession(title: 'P0会话');
      await pumpChat(tester);

      expect(find.textContaining('任务 ('), findsNothing);
      expect(find.byType(TaskPanel), findsNothing);
    });

    testWidgets('#B18-4 批次75 点击移除 → 确认弹窗 → 物理删行 + 面板刷新为空态', (tester) async {
      final sessionId = await seedP2Session();
      await insertActiveProblem(sessionId, 'P001', '视角跳跃症', 'L2');
      await pumpChat(tester);

      await tester.tap(find.text('任务 (1)'));
      await tester.pumpAndSettle();

      // 移除按钮可见（与「完成」并存）
      expect(find.text('完成'), findsOneWidget);
      expect(find.text('移除'), findsOneWidget);

      // 点击移除 → 确认弹窗
      await tester.tap(find.text('移除'));
      await tester.pumpAndSettle();
      expect(find.text('移除问题'), findsOneWidget);

      // 取消 → 不删
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      var rows = await db.select(db.activeProblems).get();
      expect(rows, hasLength(1));

      // 再次移除 → 确认 → 物理删行（弹窗确认按钮是 FilledButton，列表按钮是描边容器）
      await tester.tap(find.text('移除'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '移除'));
      await tester.pumpAndSettle();

      rows = await db.select(db.activeProblems).get();
      expect(rows, isEmpty);
      // 面板刷新 → 空态
      expect(find.text('暂无活跃问题'), findsOneWidget);
      expect(find.text('收起任务'), findsOneWidget);
    });
  });

  group('批次52：Teacher 建议卡片交互（三按钮接线）', () {
    /// 预置：完成问卷 + 会话 + teacher_suggestion 消息 + 表记录
    Future<void> seedSuggestion() async {
      final appStateRepo = AppStateRepository(db);
      await appStateRepo.setQuestionnaireCompleted(true);
      final sRepo = SessionRepository(db);
      final sessionId = await sRepo.createBlankSession(title: '建议会话');
      final payload = {
        'suggestionId': 'sug-52',
        'teachingDecision': 'guide',
        'naturalLanguage': '针对你的情绪标签化问题，建议进行改写练习。',
        'taskType': 'rewrite',
        'taskDescription': '请改写这段对话，让情绪描写更含蓄。',
        'difficulty': 'medium',
        'evaluationCriteria': ['含蓄自然', '有画面感'],
        'targetSyndromeId': 'P001',
        'targetSyndromeName': '情绪标签化',
        'source': 'diagnosis',
      };
      final messageId = await sRepo.addMessage(
        sessionId,
        'assistant',
        jsonEncode(payload),
        messageType: 'teacher_suggestion',
      );
      // teacher_suggestion 表记录（「跳过此建议」markResolved 的目标）
      await db
          .into(db.teacherSuggestions)
          .insert(
            TeacherSuggestionsCompanion.insert(
              id: 'sug-52',
              sessionId: sessionId,
              messageId: messageId,
              source: 'diagnosis',
              teachingDecision: 'guide',
              targetSyndromeId: const Value('P001'),
              taskType: 'rewrite',
              taskDescription: '请改写这段对话，让情绪描写更含蓄。',
              difficulty: 'medium',
            ),
          );
    }

    Future<ProviderContainer> pumpChat(WidgetTester tester) async {
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          lastSessionStorageProvider.overrideWithValue(
            MemoryLastSessionStorage(),
          ),
          chatServiceProvider.overrideWithValue(_FakeChatService(db)),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: ChatPage()),
        ),
      );
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets('#B52-1 teacher_suggestion 消息 → 三按钮建议卡片渲染', (tester) async {
      await seedSuggestion();
      await pumpChat(tester);

      // 症候名称 chip（显示名称而非代号）
      expect(find.text('情绪标签化'), findsOneWidget);
      // 三按钮
      expect(find.text('开始练习'), findsOneWidget);
      expect(find.text('跳过此建议'), findsOneWidget);
      expect(find.text('查看详情'), findsOneWidget);
      // 任务描述
      expect(find.text('请改写这段对话，让情绪描写更含蓄。'), findsOneWidget);
    });

    testWidgets('#B52-2 点「开始练习」→ 训练任务启动（PracticeTaskCard）', (tester) async {
      await seedSuggestion();
      await pumpChat(tester);

      await tester.tap(find.text('开始练习'));
      await tester.pumpAndSettle();

      // 消息列表顶部渲染训练任务卡（practiceStore 已接线）
      expect(find.byType(PracticeTaskCard), findsOneWidget);
    });

    testWidgets('#B52-3 点「跳过此建议」→ 落库 resolved + 卡片隐藏', (tester) async {
      await seedSuggestion();
      await pumpChat(tester);

      await tester.tap(find.text('跳过此建议'));
      await tester.pumpAndSettle();

      // 卡片隐藏（本地 _dismissed）
      expect(find.text('开始练习'), findsNothing);
      // teacher_suggestion 表 status → resolved
      final rows = await db.select(db.teacherSuggestions).get();
      expect(rows, isNotEmpty);
      expect(rows.first.status, 'resolved');
    });
  });

  group('引用管理弹层链路（ReferenceBar 挂载 + 变更卡片接线）', () {
    /// 预置：完成问卷 + 会话 + 稿 + 章 + 章节主引用
    Future<void> seedPrimaryReference() async {
      final appStateRepo = AppStateRepository(db);
      await appStateRepo.setQuestionnaireCompleted(true);
      final sRepo = SessionRepository(db);
      await sRepo.createBlankSession();
      final msRepo = ManuscriptRepository(db);
      final msId = await msRepo.createManuscript(title: '引用管理测试稿');
      final chRepo = ChapterRepository(db);
      final chapterId = await chRepo.createChapter(
        msId,
        title: '第一章：启程',
        content: '这是章节内容。',
      );
      final refRepo = ReferenceRepository(db);
      await refRepo.addReference(
        (await sRepo.listSessions()).single.id,
        'chapter',
        chapterId,
        isPrimary: true,
      );
    }

    Future<ProviderContainer> pumpChat(WidgetTester tester) async {
      // 更多菜单项较多（阶段/子阶段/态度/画像/引用管理），放大视口防超出屏幕
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          lastSessionStorageProvider.overrideWithValue(
            MemoryLastSessionStorage(),
          ),
          chatServiceProvider.overrideWithValue(_FakeChatService(db)),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: ChatPage()),
        ),
      );
      await tester.pumpAndSettle();
      return container;
    }

    /// 打开更多菜单 → 点击「引用管理」
    Future<void> openRefSheet(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.more_horiz));
      await tester.pumpAndSettle();
      await tester.tap(find.text('引用管理'));
      await tester.pumpAndSettle(const Duration(milliseconds: 500));
    }

    testWidgets('#R1 更多菜单 → 引用管理 → ReferenceBar 弹层渲染（含主引用）', (
      tester,
    ) async {
      await seedPrimaryReference();
      await pumpChat(tester);

      await openRefSheet(tester);

      // ReferenceBar 已挂载（弹层内）
      expect(find.byType(ReferenceBar), findsOneWidget);
      // 主引用行
      expect(find.text('章节（主引用）'), findsOneWidget);
      expect(find.text('第一章：启程'), findsOneWidget);
    });

    testWidgets('#R2 移除引用 → 落库删除 + reference_change 卡片写入', (
      tester,
    ) async {
      await seedPrimaryReference();
      await pumpChat(tester);

      await openRefSheet(tester);

      // 展开列表 → 点移除（close 图标）
      await tester.tap(find.text('章节（主引用）'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.close).first);
      await tester.pumpAndSettle();

      // 引用已删除
      final refRepo = ReferenceRepository(db);
      final sessionId = (await SessionRepository(db).listSessions()).single.id;
      final refs = await refRepo.listReferencesOfSession(sessionId);
      expect(refs, isEmpty, reason: '移除后引用应清空');

      // reference_change 卡片已写入消息
      final messages = await SessionRepository(db).listMessages(sessionId);
      expect(
        messages.any((m) => m.messageType == 'reference_change'),
        isTrue,
        reason: '移除引用后应插入 reference_change 卡片',
      );
      expect(messages.last.content, contains('"action":"remove"'));
    });

    testWidgets('#R3 添加引用 → 引用落库 + reference_change 卡片写入', (
      tester,
    ) async {
      // 预置：无引用（空会话 + 待引用作品）
      final appStateRepo = AppStateRepository(db);
      await appStateRepo.setQuestionnaireCompleted(true);
      final sRepo = SessionRepository(db);
      final sessionId = await sRepo.createBlankSession();
      final msRepo = ManuscriptRepository(db);
      final msId = await msRepo.createManuscript(title: '待引用作品');
      final chRepo = ChapterRepository(db);
      await chRepo.createChapter(msId, title: '第一章', content: '内容');

      await pumpChat(tester);
      await openRefSheet(tester);

      // 无引用时占位行可展开 → 显示「+ 添加引用」→ 选择器 → 引用整本书
      await tester.tap(find.text('还没有引用作品，点下方按钮添加'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('+ 添加引用'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('待引用作品'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('引用整本书'));
      await tester.pumpAndSettle();

      final refs = await ReferenceRepository(
        db,
      ).listReferencesOfSession(sessionId);
      expect(refs, isNotEmpty, reason: '添加后引用应落库');
      final messages = await SessionRepository(db).listMessages(sessionId);
      expect(
        messages.any((m) => m.messageType == 'reference_change'),
        isTrue,
        reason: '添加引用后应插入 reference_change 卡片',
      );
    });
  });

  group('批次78：画像入口死路由修复', () {
    testWidgets('#H1 更多菜单点「画像」→ 跳转成长详情（不再 pushNamed 死入口）', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final appStateRepo = AppStateRepository(db);
      await appStateRepo.setQuestionnaireCompleted(true);

      // 最小路由：宿主 = ChatPage；growth-detail 用 Marker 校验跳转是否到达
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(path: '/', builder: (_, _) => const ChatPage()),
          GoRoute(
            path: AppRoutes.growthDetail,
            builder: (_, _) => const Scaffold(body: Text('GROWTH_REAL')),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            lastSessionStorageProvider.overrideWithValue(
              MemoryLastSessionStorage(),
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      // 更多菜单 → 画像 → 跳转成长详情页（pushNamed 时代此处必失败）
      await tester.tap(find.byIcon(Icons.more_horiz));
      await tester.pumpAndSettle();
      await tester.tap(find.text('画像'));
      await tester.pumpAndSettle();

      expect(find.text('GROWTH_REAL'), findsOneWidget);
    });
  });

  group('批次81：三卡回调接线', () {
    /// 预置：完成问卷 + 会话 + 一条指定 messageType 的卡片消息
    Future<void> seedCardMessage(String messageType, String payloadJson) async {
      final appStateRepo = AppStateRepository(db);
      await appStateRepo.setQuestionnaireCompleted(true);
      final sRepo = SessionRepository(db);
      await sRepo.createBlankSession();
      final sessionId = (await sRepo.listSessions()).single.id;
      await sRepo.addMessage(
        sessionId,
        'assistant',
        payloadJson,
        messageType: messageType,
      );
    }

    Future<ProviderContainer> pumpChat(WidgetTester tester) async {
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          lastSessionStorageProvider.overrideWithValue(
            MemoryLastSessionStorage(),
          ),
          chatServiceProvider.overrideWithValue(_FakeChatService(db)),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: ChatPage()),
        ),
      );
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets('#B81-1 phase_summary「继续训练」→ 重开练习任务', (tester) async {
      await seedCardMessage(
        'phase_summary',
        jsonEncode({
          'result': 'partial',
          'resolvedSyndromeCount': 1,
          'trainingCount': 4,
          'trend': 'improving',
          'syndromeChanges': <Object>[],
        }),
      );
      final container = await pumpChat(tester);

      // 预置一轮练习任务并跳过（_lastTask 保留），模拟「上一轮训练已结束」
      final practice = container.read(practiceStoreProvider.notifier);
      practice.startPractice(
        PracticeTask(
          syndromeId: 'P001',
          syndromeName: '视角跳跃症',
          taskDescription: '针对性写作练习',
          taskGoal: '对照标准完成练习',
        ),
      );
      practice.skipPractice();
      await tester.pump();
      expect(find.byType(PracticeTaskCard), findsNothing);

      await tester.tap(find.text('继续训练'));
      await tester.pump();

      // retryPractice 重开上次任务 → 练习任务卡出现
      expect(find.byType(PracticeTaskCard), findsOneWidget);
    });

    testWidgets('#B81-2 phase_summary「查看学员画像」→ 能力画像页', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await seedCardMessage(
        'phase_summary',
        jsonEncode({
          'result': 'passed',
          'resolvedSyndromeCount': 2,
          'trainingCount': 5,
          'trend': 'improving',
          'syndromeChanges': <Object>[],
        }),
      );

      // 复用批次78 画像入口修复的最小路由模式（Marker 校验跳转到达）
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(path: '/', builder: (_, _) => const ChatPage()),
          GoRoute(
            path: AppRoutes.growthDetail,
            builder: (_, _) => const Scaffold(body: Text('GROWTH_REAL')),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            lastSessionStorageProvider.overrideWithValue(
              MemoryLastSessionStorage(),
            ),
            chatServiceProvider.overrideWithValue(_FakeChatService(db)),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('查看学员画像'));
      await tester.pumpAndSettle();

      expect(find.text('GROWTH_REAL'), findsOneWidget);
    });

    testWidgets('#B81-3 diagnosis_failed「补充内容」→ 聚焦输入框', (tester) async {
      await seedCardMessage(
        'diagnosis_failed',
        jsonEncode({'failureCount': 1}),
      );
      await pumpChat(tester);

      await tester.tap(find.text('补充内容'));
      await tester.pump();

      final editable = tester.widget<EditableText>(find.byType(EditableText));
      expect(editable.focusNode.hasFocus, isTrue);
    });

    testWidgets('#B81-4 partial_agreement 提交反馈 → 用户消息落库（杜绝静默清空）', (
      tester,
    ) async {
      await seedCardMessage(
        'partial_agreement',
        jsonEncode({
          'syndromeId': 'P001',
          'syndromeName': '视角跳跃症',
          'severity': 'L2',
        }),
      );
      await pumpChat(tester);

      await tester.enterText(
        find.descendant(
          of: find.byType(PartialAgreementCard),
          matching: find.byType(TextField),
        ),
        '我觉得问题不严重',
      );
      await tester.pump();
      await tester.tap(find.text('提交反馈'));
      await tester.pumpAndSettle();

      // 反馈已作为用户消息真实落库（非静默清空）
      final sRepo = SessionRepository(db);
      final sessionId = (await sRepo.listSessions()).single.id;
      final msgs = await sRepo.listMessages(sessionId);
      final userMsg = msgs.where((m) => m.role == 'user').last;
      expect(
        userMsg.content,
        contains('我对刚才的诊断结果有不同看法：我觉得问题不严重'),
      );
      // 卡片输入框已清空（反馈已送出）
      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: find.byType(PartialAgreementCard),
                matching: find.byType(TextField),
              ),
            )
            .controller!
            .text,
        isEmpty,
      );
    });

    testWidgets('#B81-5 partial_agreement 跳过 → 用户消息请求重新诊断', (
      tester,
    ) async {
      await seedCardMessage(
        'partial_agreement',
        jsonEncode({
          'syndromeId': 'P001',
          'syndromeName': '视角跳跃症',
          'severity': 'L2',
        }),
      );
      await pumpChat(tester);

      await tester.tap(find.text('跳过此症候'));
      await tester.pumpAndSettle();

      final sRepo = SessionRepository(db);
      final sessionId = (await sRepo.listSessions()).single.id;
      final msgs = await sRepo.listMessages(sessionId);
      final userMsg = msgs.where((m) => m.role == 'user').last;
      expect(userMsg.content, contains('请跳过这个症候，重新给出诊断结果'));
    });
  });
}

/// Fake ChatService：模拟流式回复
class _FakeChatService extends ChatService {
  _FakeChatService(this._db)
    : super(
        sessionRepo: SessionRepository(_db),
        stateRepo: TeachingStateRepository(_db),
        diagnosisRepo: DiagnosisRepository(_db),
        studentModelRepo: StudentModelRepository(_db),
        referenceRepo: ReferenceRepository(_db),
        chapterRepo: ChapterRepository(_db),
        manuscriptRepo: ManuscriptRepository(_db),
        llmClient: LlmClient(),
        teacherSuggestionRepo: TeacherSuggestionRepository(_db),
        editorObservationRepo: EditorObservationRepository(_db),
      );

  final AppDatabase _db;

  @override
  Future<void> sendMessage(
    String sessionId,
    String content,
    SendMessageCallbacks callbacks,
    SendMessageOptions options, {
    TeachingSubphase? subphase,
  }) async {
    // 先写入 user 消息（模拟真实流程）
    final sessionRepo = SessionRepository(_db);
    await sessionRepo.addMessage(sessionId, 'user', content);

    // 初始延迟，让 UI 有机会显示 ThinkingIndicator
    await Future.delayed(const Duration(milliseconds: 50));

    // 模拟流式分块推送
    callbacks.onStream('你好，');
    await Future.delayed(const Duration(milliseconds: 100));
    callbacks.onStream('我是月笙。');
    await Future.delayed(const Duration(milliseconds: 100));

    // 写入 assistant 消息并触发完成
    final messageId = await sessionRepo.addMessage(
      sessionId,
      'assistant',
      '你好，我是月笙。',
    );
    callbacks.onComplete('你好，我是月笙。', messageId);
  }
}

/// Fake BootstrapService：shouldShowQuestionnaire 总是抛异常
/// 用于覆盖 sessionBootstrapProvider 的 AsyncError 分支
class _ThrowingBootstrapService implements BootstrapService {
  @override
  Future<bool> shouldShowQuestionnaire(String? sessionId) async {
    throw Exception('bootstrap failed');
  }
}
