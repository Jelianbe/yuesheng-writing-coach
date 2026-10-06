// ─────────────────────────────────────────────────────────────
// ChatPage widget 测试 — bootstrap → 对话完整接线
//
// ADR-C122：问卷/BootstrapService 退役，问卷相关用例移除；
// onboarding 三步迁移改由纯新手模式服务层测试覆盖。
//
// 覆盖路径：
//   1. 初始化中：CircularProgressIndicator 占位
//   2. 复用已有 session（覆盖 sessions.first.id 分支）
//   3. 发送消息集成：输入 → 发送 → 流式渲染（T6）
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
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/data/repositories/reference_repository.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/data/repositories/student_model_repository.dart';
import 'package:writingcoach/data/repositories/teacher_suggestion_repository.dart';
import 'package:writingcoach/data/repositories/teaching_state_repository.dart';
import 'package:writingcoach/providers/app_providers.dart';
import 'package:writingcoach/router/app_routes.dart';
import 'package:writingcoach/providers/chat_store.dart';
import 'package:writingcoach/providers/practice_providers.dart';
import 'package:writingcoach/providers/session_providers.dart';
import 'package:writingcoach/services/chat_service.dart';
import 'package:writingcoach/services/diagnosis_committer.dart';
import 'package:writingcoach/services/message_injector.dart';
import 'package:writingcoach/services/chat_context_builder.dart'
    show MaterialCapabilityImpl;
import 'package:writingcoach/services/llm_client.dart';
import 'package:writingcoach/types/teaching_types.dart';
import 'package:writingcoach/features/chat/chat_page.dart';
import 'package:writingcoach/features/chat/encouragement_text.dart';
import 'package:writingcoach/features/chat/message_list.dart';
import 'package:writingcoach/features/chat/partial_agreement_card.dart';
import 'package:writingcoach/widgets/practice_task_card.dart';
import 'package:writingcoach/features/chat/reference_bar.dart';
import 'package:writingcoach/features/chat/task_panel.dart';
import 'package:writingcoach/widgets/ui_overlay_host.dart';

import 'package:writingcoach/services/chat_message_types.dart'
    show SendMessageCallbacks, SendMessageOptions;
import 'package:writingcoach/services/diagnosis_flow_handler.dart';
import 'package:writingcoach/services/diagnosis_parser.dart'
    show DiagnosisCapabilityImpl;
import 'package:writingcoach/services/genui_parser.dart' show GenUiParser;
import '../helpers/mock_last_session_storage.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    // C2（批次 1f4abb61）：发送入口会先弹一次性「配置 API」引导。
    // 本文件测的是对话/横幅/回调接线，与首次引导无关 ⇒ 预置「已展示」标记。
    // （引导自身行为见 test/widgets/api_config_nudge_test.dart）
    await AppStateRepository(db).setApiConfigHintSeen(true);
  });

  tearDown(() async => db.close());

  // 辅助：构造 ChatPage 并通过 ProviderScope 注入内存 DB
  Widget buildChatPage() {
    return ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        // 批次 50：隔离 flutter_secure_storage 平台通道（testWidgets 下挂起）
        lastSessionStorageProvider.overrideWithValue(
          MemoryLastSessionStorage(),
        ),
      ],
      child: const MaterialApp(home: ChatPage()),
    );
  }

  group('批次4：作品导入入口（+ 按钮）', () {
    testWidgets('#B4-1 + 按钮出现，点击打开作品导入弹层', (tester) async {
      final appStateRepo = AppStateRepository(db);
      await appStateRepo.setQuestionnaireCompleted(true);

      await tester.pumpWidget(buildChatPage());
      await tester.pumpAndSettle();

      // 批次3 接线：onUploadFile 传入后 + 按钮显示
      final plus = find.byIcon(Icons.add);
      expect(plus, findsOneWidget);

      // 2026-09-15：+ 改为在「+」上方浮出功能面板，导入入口在面板内
      await tester.tap(plus);
      await tester.pumpAndSettle();

      expect(find.text('上传作品'), findsOneWidget);
      await tester.tap(find.text('上传作品'));
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
      // 2026-09-15：先经「+」上方面板选择上传
      await tester.tap(find.text('上传作品'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('粘贴文本'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('work-import-paste-field')),
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

      // mention 模式：选章节 → 输入框插入 @作品标题/章节标题（批次71 文字格式）
      await tester.tap(find.text('测试小说'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('第一章'));
      await tester.pumpAndSettle();

      expect(find.textContaining('@测试小说/第一章'), findsOneWidget);

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

    testWidgets('#B5-2 appbar 新建对话 → 当前会话不空时数量 +1（真机#4 复用逻辑）', (tester) async {
      final appStateRepo = AppStateRepository(db);
      await appStateRepo.setQuestionnaireCompleted(true);
      final sessionRepo = SessionRepository(db);
      // 当前会话带消息（不空），新建才开新会话；空会话会被复用不 +1
      final aId = await sessionRepo.createBlankSession(title: '会话A');
      await sessionRepo.addMessage(aId, 'user', 'A的消息');
      final before = (await db.select(db.sessions).get()).length;

      await tester.pumpWidget(buildChatPage());
      await tester.pumpAndSettle();

      // appbar「+ 新建对话」（drawer 底部入口已按真机#4 移除）
      await tester.tap(find.byIcon(Icons.add_comment_outlined));
      await tester.pumpAndSettle();

      final after = (await db.select(db.sessions).get()).length;
      expect(after, before + 1, reason: '当前会话已不空，新建应开新会话');
    });

    testWidgets('#B5-3 批次73 长按删除当前会话 → DB 删除 + 切到剩余会话 + 消息清空', (tester) async {
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
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();

      // A 已删除，B 保留；A 的消息不再显示
      final sessions = await sessionRepo.listSessions();
      expect(sessions.any((s) => s.id == aId), isFalse);
      expect(sessions.any((s) => s.id == bId), isTrue);
      expect(find.text('A的独有消息'), findsNothing);
    });
  });

  group('会话切换自动滚到底', () {
    // 判别性场景：两个会话各埋等量（30+1 条，溢出视口）历史，末条标记互不相同。
    // 用户先停在会话 A 的底部、再把列表跳回顶部（正在读历史），随后切到等长的
    // 会话 B。
    // 修复前分支分析：长度等长（31==31）⇒ hasNewUserMessage 第一子句不成立；
    // 旧 forced 条件只看「长度增长」亦不成立（且旧代码切换路径根本不设 flag）；
    // else-if 常规滚动分支因「长度未变 + streamingContent 未变」短路，且即便走到
    // _isAtBottom() 此时也在顶部 ⇒ 不触发任何滚动，列表停在顶部，B 末条不被
    // ListView.builder 构建 ⇒ 断言失败。
    // 修复后：会话切换设单帧 flag + MessageList「首条 sessionId 不同 = 整体替换」
    // 分支触发强滚底 ⇒ B 末条滚入视口，断言通过。
    testWidgets('#SW1 切到等长会话且列表停在顶部 → 强制滚到新会话末条', (tester) async {
      final appStateRepo = AppStateRepository(db);
      await appStateRepo.setQuestionnaireCompleted(true);
      final repo = SessionRepository(db);

      // 两个会话各 30 条填充 + 1 条末条标记（等量，溢出视口）
      final aId = await repo.createBlankSession(title: '会话A');
      for (var i = 0; i < 30; i++) {
        await repo.addMessage(aId, 'user', 'A第$i条');
      }
      await repo.addMessage(aId, 'assistant', 'A末尾标记');
      final bId = await repo.createBlankSession(title: '会话B');
      for (var i = 0; i < 30; i++) {
        await repo.addMessage(bId, 'user', 'B第$i条');
      }
      await repo.addMessage(bId, 'assistant', 'B末尾标记');

      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          lastSessionStorageProvider.overrideWithValue(
            MemoryLastSessionStorage(),
          ),
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

      // 固定停在会话 A（无论 bootstrap 初始落在哪边）；首屏滚到底 ⇒ A 末条可见
      await container.read(sessionBootstrapProvider.notifier).switchTo(aId);
      await tester.pumpAndSettle();
      expect(container.read(sessionBootstrapProvider).value?.sessionId, aId);
      expect(find.text('A末尾标记'), findsOneWidget);

      // 模拟用户正在读历史：把列表从底部跳回顶部
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .jumpTo(0);
      await tester.pumpAndSettle();
      // 顶部首条可见、末条不可见（证明停在顶部而非底部）
      expect(find.text('A第0条'), findsOneWidget);
      expect(find.text('A末尾标记'), findsNothing);

      // 切到等长会话 B
      await container.read(sessionBootstrapProvider.notifier).switchTo(bId);
      await tester.pumpAndSettle();
      expect(container.read(sessionBootstrapProvider).value?.sessionId, bId);

      // 判别性断言：B 末条必须被强滚入视口
      expect(find.text('B末尾标记'), findsOneWidget);
    });

    // 真机缺陷加固（2026-10-02 emulator-5554 logcat 定位）：
    // #SW1 用短而均匀的单行长文本，首帧 maxScrollExtent 已≈真实值，掩盖了
    // ListView.builder 懒加载「首帧只布局视口+缓存区、max 被严重低估」的问题。
    // 真机欢迎会话是异构高消息（实测首帧 max=1370、真实底部=3536），旧实现
    // animateTo 锁死被低估的 1370 → 落到半路。本用例用多行长文本高消息复现，
    // 且部分 pump（不一次 pumpAndSettle）模拟真机逐帧时序。
    testWidgets('#SW2 切到异构高消息会话 → 收敛滚到真实底部（复现真机 max 低估）', (tester) async {
      final appStateRepo = AppStateRepository(db);
      await appStateRepo.setQuestionnaireCompleted(true);
      final repo = SessionRepository(db);

      // 异构高消息：奇数条超长段落（~多屏高），偶数条极短单行。
      // 高度参差 → ListView.builder 首帧对剩余 item 高度估计失真，
      // maxScrollExtent 被低估（复现真机 max=1370 vs 真实 3536）。
      String tall(int i) =>
          '欢迎长段落 $i\n'
              '这是一段较长的正文，用于撑高单条消息高度使其多行换行显示。'
              '换行后会占多行，模拟真机里欢迎语那种长段落消息。' *
          8;
      String shortMsg(int i) => '短问 $i';

      final aId = await repo.createBlankSession(title: '会话A');
      for (var i = 0; i < 10; i++) {
        await repo.addMessage(
          aId,
          'assistant',
          i.isEven ? tall(i) : shortMsg(i),
        );
      }
      await repo.addMessage(aId, 'assistant', 'A末尾标记');

      final bId = await repo.createBlankSession(title: '会话B');
      for (var i = 0; i < 10; i++) {
        await repo.addMessage(
          bId,
          'assistant',
          i.isEven ? tall(i) : shortMsg(i),
        );
      }
      await repo.addMessage(bId, 'assistant', 'B末尾标记');

      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          lastSessionStorageProvider.overrideWithValue(
            MemoryLastSessionStorage(),
          ),
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

      // 固定停在 A，首屏滚到底 ⇒ A 末条可见
      await container.read(sessionBootstrapProvider.notifier).switchTo(aId);
      await tester.pumpAndSettle();
      expect(find.text('A末尾标记'), findsOneWidget);

      // 模拟用户读历史：跳回顶部（末条不可见）
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .jumpTo(0);
      await tester.pumpAndSettle();
      expect(find.text('A末尾标记'), findsNothing);

      // 切到 B；部分 pump 模拟真机逐帧时序（收敛跨多 postFrame）
      await container.read(sessionBootstrapProvider.notifier).switchTo(bId);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      // 判别性断言 1：B 末条标记必须被收敛滚入视口
      // （旧实现锁死被低估 max → 末条不可见，本断言必然失败）
      expect(find.text('B末尾标记'), findsOneWidget);
      // 判别性断言 2：滚动位置必须贴真实底部（pixels≈maxScrollExtent）
      final pos = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;
      expect(pos.pixels, moreOrLessEquals(pos.maxScrollExtent, epsilon: 2.0));
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

  group('复用已有 session（覆盖 sessions.first.id 分支）', () {
    testWidgets('#6 DB 中已有 session → 复用而非新建', (tester) async {
      // 预置：DB 中已存在一条 session（模拟老用户首次启动）
      final sessionRepo = SessionRepository(db);
      final presetSessionId = await sessionRepo.createBlankSession();

      await tester.pumpWidget(buildChatPage());
      await tester.pumpAndSettle();

      // 不应新建 session，应复用预置的 sessionId
      final sessions = await db.select(db.sessions).get();
      expect(sessions.length, 1);
      expect(sessions.first.id, presetSessionId);
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
    // A4：流式中途切会话——旧会话流的 chunk/onComplete 不得污染刚切到的新会话 UI。
    // DB 仍按原 session 落库（不落库串台），此处只断言守卫丢弃了迟到回调。
    // （切会话时 cancel+reset 流式 UI 的部分由 chat_session_controller_test 单元覆盖。）
    testWidgets('#A4 流式中途切会话：旧流 chunk/完成不污染新会话', (tester) async {
      final appStateRepo = AppStateRepository(db);
      await appStateRepo.setQuestionnaireCompleted(true);
      final repo = SessionRepository(db);

      // 两个会话各埋一条专属历史（无论 bootstrap 落在哪边，切过去都能认出）
      final s1 = await repo.createBlankSession(title: 'S1');
      await repo.addMessage(s1, 'user', 'S1专属历史', messageType: 'chat');
      final s2 = await repo.createBlankSession(title: 'S2');
      await repo.addMessage(s2, 'user', 'S2专属历史', messageType: 'chat');

      final fake = _PausableFakeChatService(db);
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          lastSessionStorageProvider.overrideWithValue(
            MemoryLastSessionStorage(),
          ),
          chatServiceProvider.overrideWithValue(fake),
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

      final active = container.read(sessionBootstrapProvider).value?.sessionId;
      expect(active, isNotNull);
      final other = active == s1 ? s2 : s1;
      final otherMarker = active == s1 ? 'S2专属历史' : 'S1专属历史';

      // 在当前会话发起发送：fake 捕获回调后不自动完成（手动控制时序）
      await tester.enterText(find.byType(TextField), '你好教练');
      await tester.pump();
      await tester.tap(find.widgetWithIcon(FilledButton, Icons.arrow_upward));
      await tester.pump();
      expect(fake.callbacks, isNotNull, reason: 'fake 应捕获到流式回调');

      // 仍在当前会话：旧流 chunk 应上屏
      fake.callbacks!.onStream('当前流式片段');
      await tester.pump();
      expect(find.textContaining('当前流式片段'), findsOneWidget);

      // 切到另一边（bootstrap 指向 other）
      await container.read(sessionBootstrapProvider.notifier).switchTo(other);
      await tester.pumpAndSettle();
      expect(container.read(sessionBootstrapProvider).value?.sessionId, other);
      expect(find.text(otherMarker), findsOneWidget);

      // 旧流迟到 chunk：守卫按闭包 sessionId != 当前 active 丢弃，不得追加到新会话
      fake.callbacks!.onStream('迟到chunk');
      await tester.pump();
      expect(
        find.textContaining('迟到chunk'),
        findsNothing,
        reason: '旧会话迟到 chunk 不得串到新会话流式气泡',
      );

      // 旧流迟到 onComplete：守卫丢弃，不得用旧会话消息列表覆盖新会话
      final assistantId = await repo.addMessage(
        active!,
        'assistant',
        '旧会话专属回复',
      );
      await fake.callbacks!.onComplete('旧会话专属回复', assistantId);
      await tester.pump();
      expect(find.text(otherMarker), findsOneWidget);
      expect(
        find.text('旧会话专属回复'),
        findsNothing,
        reason: '旧会话 onComplete 不得把其 assistant 灌进当前会话',
      );
    });

    // A5：重试失败消息——重试前删除旧失败 user 行，保证只产生一条 user 气泡
    // （旧行为：每点一次重试就多一条重复 user 消息，并被 listMessages 喂回上下文）。
    testWidgets('#A5 重试失败消息：不产生重复 user 气泡', (tester) async {
      final appStateRepo = AppStateRepository(db);
      await appStateRepo.setQuestionnaireCompleted(true);
      final repo = SessionRepository(db);
      final fake = _RetryFakeChatService(db);

      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          lastSessionStorageProvider.overrideWithValue(
            MemoryLastSessionStorage(),
          ),
          chatServiceProvider.overrideWithValue(fake),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: ChatPage()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      // 发送 → 首轮失败（露出重试按钮）
      await tester.enterText(find.byType(TextField), '我的问题');
      await tester.pump();
      await tester.tap(find.widgetWithIcon(FilledButton, Icons.arrow_upward));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('发送失败，点击重试'), findsOneWidget);

      // 点重试 → 应成功
      await tester.tap(find.text('发送失败，点击重试'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('重试后回复'), findsOneWidget);

      // UI：内容为「我的问题」的 user 气泡只有一条
      expect(find.text('我的问题'), findsOneWidget, reason: '重试不得复制出第二条 user 气泡');

      // DB：当前会话里内容为「我的问题」的 user 行也只有一条
      final sessionId = container
          .read(sessionBootstrapProvider)
          .value
          ?.sessionId;
      expect(sessionId, isNotNull);
      final rows = await repo.listMessages(sessionId!);
      final userRows = rows
          .where((m) => m.role == 'user' && m.content == '我的问题')
          .toList();
      expect(userRows, hasLength(1), reason: '旧失败 user 行应在重试前删除，不得残留重复问句污染上下文');
    });
  });

  group('删除消息（T9 #14）', () {
    testWidgets('#10 长按消息 → 弹出操作菜单（复制 / 删除）', (tester) async {
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

      // 应弹出操作菜单（复制内容 + 删除）
      expect(find.text('复制内容'), findsOneWidget);
      expect(find.text('删除'), findsOneWidget);
    });

    testWidgets('#11 点击删除 → 确认弹窗 → 消息从 UI 和 DB 移除', (tester) async {
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

      // 长按 → 菜单 → 删除 → 确认弹窗 → 删除
      await tester.longPress(find.text('要删掉的消息'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      expect(find.text('确认删除'), findsOneWidget);
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

      // 长按 → 菜单 → 删除 → 确认弹窗 → 取消
      await tester.longPress(find.text('不删的消息'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      expect(find.text('确认删除'), findsOneWidget);
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

      // 默认档位 gentle 在行内选项中出现
      expect(find.text('温柔语气'), findsOneWidget);

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

      // 头部：标题「会话」+ 主引用小字（未关联时为提示文案）
      expect(find.text('会话'), findsOneWidget);
      expect(find.text('未关联书籍 · 点此管理'), findsOneWidget);

      // 更多菜单 → 态度档位 / 画像（阶段名已按真机三批收敛）
      await tester.tap(find.byIcon(Icons.more_horiz));
      await tester.pumpAndSettle();
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
            'syndrome_id': 'P002',
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
      expect(find.text('切换到月笙如歌'), findsOneWidget);
      expect(find.textContaining('当前问题较少'), findsOneWidget);
      // 横幅显示时 QuickChips 隐藏（对齐 RN !attitudeSuggestion）
      expect(find.text('诊断节奏问题'), findsNothing);
    });

    testWidgets('#B12-2 点击「切换到月笙如歌」→ 态度双写 + 横幅消失', (tester) async {
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
      await tester.tap(find.text('切换到月笙如歌'));
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

      // 自动诊断：user 消息（简洁诊断请求）已落库
      final messages = await db.select(db.messages).get();
      expect(
        messages.any((m) => m.role == 'user' && m.content.contains('请诊断本章')),
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
          child: MaterialApp(
            home: const ChatPage(),
            builder: (context, child) => Stack(
              children: [child ?? const SizedBox(), const UiOverlayHost()],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(assistantContent), findsOneWidget);
      await tester.tap(find.text('保存到文件'));
      await tester.pumpAndSettle();

      expect(find.text('请先关联一本书籍'), findsOneWidget);
      expect(find.text('保存到《第一章》'), findsNothing);

      // toast 2s 自动消失；推进时间清掉 pending Timer 再收尾
      await tester.pump(const Duration(seconds: 3));
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

    /// 走完整导入流程：+ 按钮 → 上方面板「上传作品」→ WorkImportSheet
    /// → 粘贴文本 → 确认导入
    Future<void> importViaSheet(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      await tester.tap(find.text('上传作品'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('粘贴文本'));
      await tester.pumpAndSettle();
      // 粘贴输入框（WorkImportSheet 内 YueInputSheet，用 Key 定位）
      final pasteField = find.byKey(const Key('work-import-paste-field'));
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
        messages.any((m) => m.role == 'user' && m.content.contains('请诊断本章')),
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
      await insertActiveProblem(sessionId, 'P002', '视角跳跃症', 'L2');
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
      await insertActiveProblem(sessionId, 'P002', '视角跳跃症', 'L2');
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
      await insertActiveProblem(sessionId, 'P002', '视角跳跃症', 'L2');
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
        'targetSyndromeId': 'P002',
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
              targetSyndromeId: const Value('P002'),
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

    /// 打开引用管理弹层 → 点标题下方主引用小字
    /// （批次 C78-3c-2：更多菜单里的「引用管理」重复入口已删，
    ///   唯一入口为头部主引用小字 onTapPrimaryRef）
    /// 小字文案随状态变化：有主引用 → 书名；无引用 → 「未关联书籍 · 点此管理」
    Future<void> openRefSheet(
      WidgetTester tester, {
      String? expectedTitle,
    }) async {
      final target = find.text(expectedTitle ?? '未关联书籍 · 点此管理');
      expect(target, findsOneWidget, reason: '头部主引用小字应存在且可点');
      await tester.tap(target);
      await tester.pumpAndSettle(const Duration(milliseconds: 500));
    }

    testWidgets('#R1 头部主引用小字 → 引用管理 → ReferenceBar 弹层渲染（含主引用）', (tester) async {
      await seedPrimaryReference();
      await pumpChat(tester);

      await openRefSheet(tester, expectedTitle: '第一章：启程');

      // ReferenceBar 已挂载（弹层内）
      expect(find.byType(ReferenceBar), findsOneWidget);
      // 主引用行（弹层内）；头部小字也显示同一主引用书名，故全书名出现 2 次
      expect(find.text('章节（主引用）'), findsOneWidget);
      expect(find.text('第一章：启程'), findsNWidgets(2));
    });

    testWidgets('#R2 移除引用 → 落库删除 + reference_change 卡片写入', (tester) async {
      await seedPrimaryReference();
      await pumpChat(tester);

      await openRefSheet(tester, expectedTitle: '第一章：启程');

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

    testWidgets('#R3 添加引用 → 引用落库 + reference_change 卡片写入', (tester) async {
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
      await openRefSheet(tester); // 无主引用 → 小字为「未关联书籍 · 点此管理」

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
    testWidgets('#H1 更多菜单点「画像」→ 跳转成长详情（不再 pushNamed 死入口）', (tester) async {
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
          syndromeId: 'P002',
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
          'syndromeId': 'P002',
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
      expect(userMsg.content, contains('我对刚才的诊断结果有不同看法：我觉得问题不严重'));
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

    testWidgets('#B81-5 partial_agreement 跳过 → 用户消息请求重新诊断', (tester) async {
      await seedCardMessage(
        'partial_agreement',
        jsonEncode({
          'syndromeId': 'P002',
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
        referenceRepo: ReferenceRepository(_db),
        llmClient: LlmClient(),

        messageInjector: MessageInjector(
          sessionRepo: SessionRepository(_db),

          diagnosisRepo: DiagnosisRepository(_db),

          studentModelRepo: StudentModelRepository(_db),

          referenceRepo: ReferenceRepository(_db),

          chapterRepo: ChapterRepository(_db),

          manuscriptRepo: ManuscriptRepository(_db),

          diagnosisCommitter: DiagnosisCommitter(
            sessionRepo: SessionRepository(_db),

            stateRepo: TeachingStateRepository(_db),

            diagnosisRepo: DiagnosisRepository(_db),

            studentModelRepo: StudentModelRepository(_db),

            referenceRepo: ReferenceRepository(_db),

            chapterRepo: ChapterRepository(_db),
          ),

          material: const MaterialCapabilityImpl(),
        ),

        diagnosisFlowHandler: DiagnosisFlowHandler(
          sessionRepo: SessionRepository(_db),
          stateRepo: TeachingStateRepository(_db),
          diagnosisRepo: DiagnosisRepository(_db),
          studentModelRepo: StudentModelRepository(_db),
          referenceRepo: ReferenceRepository(_db),
          chapterRepo: ChapterRepository(_db),
          teacherSuggestionRepo: TeacherSuggestionRepository(_db),
          llmClient: LlmClient(),

          messageInjector: MessageInjector(
            sessionRepo: SessionRepository(_db),

            diagnosisRepo: DiagnosisRepository(_db),

            studentModelRepo: StudentModelRepository(_db),

            referenceRepo: ReferenceRepository(_db),

            chapterRepo: ChapterRepository(_db),

            manuscriptRepo: ManuscriptRepository(_db),

            diagnosisCommitter: DiagnosisCommitter(
              sessionRepo: SessionRepository(_db),

              stateRepo: TeachingStateRepository(_db),

              diagnosisRepo: DiagnosisRepository(_db),

              studentModelRepo: StudentModelRepository(_db),

              referenceRepo: ReferenceRepository(_db),

              chapterRepo: ChapterRepository(_db),
            ),

            material: const MaterialCapabilityImpl(),
          ),
          diagnosisCommitter: DiagnosisCommitter(
            sessionRepo: SessionRepository(_db),
            stateRepo: TeachingStateRepository(_db),
            diagnosisRepo: DiagnosisRepository(_db),
            studentModelRepo: StudentModelRepository(_db),
            referenceRepo: ReferenceRepository(_db),
            chapterRepo: ChapterRepository(_db),
          ),
          diagnosis: const DiagnosisCapabilityImpl(),
          genUi: const GenUiParser(),
        ),
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
    await Future<void>.delayed(const Duration(milliseconds: 50));

    // 模拟流式分块推送
    callbacks.onStream('你好，');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    callbacks.onStream('我是月笙。');
    await Future<void>.delayed(const Duration(milliseconds: 100));

    // 写入 assistant 消息并触发完成
    final messageId = await sessionRepo.addMessage(
      sessionId,
      'assistant',
      '你好，我是月笙。',
    );
    callbacks.onComplete('你好，我是月笙。', messageId);
  }
}

/// A4 测试替身：捕获 sendMessage 回调后不自动完成，由测试手动触发 onStream/onComplete，
/// 用于复现「流式中途切会话」的迟到回调场景。
class _PausableFakeChatService extends _FakeChatService {
  _PausableFakeChatService(AppDatabase db) : _db = db, super(db);

  final AppDatabase _db;
  SendMessageCallbacks? callbacks;
  String? sessionId;

  @override
  Future<void> sendMessage(
    String sessionId,
    String content,
    SendMessageCallbacks callbacks,
    SendMessageOptions options, {
    TeachingSubphase? subphase,
  }) async {
    this.sessionId = sessionId;
    this.callbacks = callbacks;
    // 模拟真实流程：user 消息落库并上屏（之后不再自动推流/完成）
    final repo = SessionRepository(_db);
    final id = await repo.addMessage(sessionId, 'user', content);
    final msg = await repo.getMessage(id);
    if (msg != null) callbacks.onUserMessagePersisted?.call(msg);
  }
}

/// A5 测试替身：首次发送失败，重试成功。用于断言「重试只产生一条 user 气泡」。
class _RetryFakeChatService extends _FakeChatService {
  _RetryFakeChatService(AppDatabase db) : _db = db, super(db);

  final AppDatabase _db;
  int calls = 0;

  @override
  Future<void> sendMessage(
    String sessionId,
    String content,
    SendMessageCallbacks callbacks,
    SendMessageOptions options, {
    TeachingSubphase? subphase,
  }) async {
    calls++;
    final repo = SessionRepository(_db);
    final id = await repo.addMessage(sessionId, 'user', content);
    final msg = await repo.getMessage(id);
    if (msg != null) callbacks.onUserMessagePersisted?.call(msg);

    if (calls == 1) {
      // 首轮失败：user 消息已落库上屏，随后报错（标记 failed，露出重试按钮）
      callbacks.onError('network down');
      return;
    }
    // 重试成功：assistant 落库并完成
    final aid = await repo.addMessage(sessionId, 'assistant', '重试后回复');
    await callbacks.onComplete('重试后回复', aid);
  }
}
