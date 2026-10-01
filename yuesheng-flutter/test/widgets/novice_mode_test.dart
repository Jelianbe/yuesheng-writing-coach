// ─────────────────────────────────────────────────────────────
// novice_mode_test — 纯新手模式 widget 闭环测试（ADR-C122）
//
// 流程：对话页「➕」面板 → 纯新手模式 → 固定弹窗确认 → AI 固定首条
// 消息（本地插入，不经 LLM）→ 学员回答 → 本地解析 → 落库（复用
// onboarding 三步迁移）→ 分支引导 / 追问 / 兜底。
//
// 覆盖：
//   1. 完整回答 → 小白分支引导 + onboarding_data/beginner_level/
//      questionnaire_completed 三步落库
//   2. 不完整回答 → 固定追问（kNoviceMaxRetries 内），再答完整 → 落库
//   3. 连续不完整超上限 → 默认值落库 + 兜底引导（不让学员卡死）
//
// R-009：引导语断言只验「引导学员写 + 不替写」形态（无范文/无评分）。
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/app_state_repository.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/data/repositories/student_model_repository.dart';
import 'package:writingcoach/data/repositories/teaching_state_repository.dart';
import 'package:writingcoach/features/chat/chat_page.dart';
import 'package:writingcoach/features/onboarding/novice_mode_guide.dart';
import 'package:writingcoach/providers/app_providers.dart';
import 'package:writingcoach/providers/session_providers.dart';
import 'package:writingcoach/types/teaching_types.dart';

import '../helpers/mock_last_session_storage.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    // C2：发送入口会先弹一次性「配置 API」引导，与本文件测的
    // 纯新手模式无关 ⇒ 预置「已展示」标记。
    await AppStateRepository(db).setApiConfigHintSeen(true);
  });

  tearDown(() async => db.close());

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

  /// 打开 ➕ 面板并点击「纯新手模式」，确认固定弹窗
  Future<void> enterNoviceMode(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.tap(find.text('纯新手模式'));
    await tester.pumpAndSettle();
    // 固定弹窗（告知 AI 将主动询问）
    expect(find.text(kNoviceModeDialogTitle), findsOneWidget);
    await tester.tap(find.text('开始引导'));
    await tester.pumpAndSettle();
    // AI 固定首条消息已上屏（本地插入，非 LLM）
    expect(find.textContaining('我是月笙，你的专属写作教练'), findsOneWidget);
  }

  /// 发送一条消息（输入 → 发送按钮）
  /// 首次落库会触发一次性隐私告知弹窗（_commitNoviceData 内 await）：
  /// 弹出则点「我知道了」继续，否则直接通过。
  Future<void> sendText(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    // 等一帧：发送按钮 onPressed 就绪（_canSend 实时求值 + 回调快照）
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.arrow_upward));
    await tester.pumpAndSettle();
    if (find.text('开始之前，请了解').evaluate().isNotEmpty) {
      await tester.tap(find.text('我知道了'));
      await tester.pumpAndSettle();
    }
  }

  testWidgets('#1 完整回答 → 小白分支引导 + 三步落库', (tester) async {
    await tester.pumpWidget(buildChatPage());
    await tester.pumpAndSettle();
    await enterNoviceMode(tester);

    // 学员回答（覆盖三字段；proficiency 命中「刚开始」→ beginner）
    await sendText(tester, '我刚接触写作，想提升情节设计，喜欢先理解再练');

    // 小白分支引导（无时间压力、不替写、只引导）
    expect(find.textContaining('别急着想太多'), findsOneWidget);
    expect(find.textContaining('写完直接发给我，我帮你看'), findsOneWidget);

    // 三步落库验证
    final sessions = await db.select(db.sessions).get();
    expect(sessions.length, 1);
    final sessionId = sessions.first.id;

    final smRepo = StudentModelRepository(db);
    final saved = await smRepo.getOnboardingData(sessionId);
    expect(saved, isNotNull);
    expect(saved!['proficiency'], 'beginner');
    expect(saved['focusAreas'], contains('情节设计'));
    expect(saved['skipped'], false);

    final stateRepo = TeachingStateRepository(db);
    final ts = await stateRepo.getTeachingState(sessionId);
    expect(ts, isNotNull);
    expect(ts!.beginnerLevel, BeginnerLevel.n0Engage.value);

    final appStateRepo = AppStateRepository(db);
    expect(await appStateRepo.getQuestionnaireCompleted(), true);

    // C123：novice 流程产生的消息（固定首条引导 + 学员回答 + 分支引导）
    // 落库 messageType 均为 kNoviceMessageType（不喂 LLM 诊断上下文；UI 仍全量显示）。
    final noviceMsgs = await SessionRepository(db).listMessages(sessionId);
    expect(noviceMsgs.length, 3); // assistant 首条 + user 回答 + assistant 小白引导
    expect(
      noviceMsgs.every((m) => m.messageType == kNoviceMessageType),
      isTrue,
    );
  });

  testWidgets('#2 不完整回答 → 固定追问，再答完整 → 落库', (tester) async {
    await tester.pumpWidget(buildChatPage());
    await tester.pumpAndSettle();
    await enterNoviceMode(tester);

    // 第一答：识别不出方向/偏好 → 固定追问
    await sendText(tester, '不知道怎么说');
    expect(find.textContaining('还差一点没看全'), findsOneWidget);

    // 第二答：完整 → 落库 + 引导
    await sendText(tester, '我想提升文笔，喜欢多练');
    expect(find.textContaining('别急着想太多'), findsOneWidget);

    final sessions = await db.select(db.sessions).get();
    final smRepo = StudentModelRepository(db);
    final saved = await smRepo.getOnboardingData(sessions.first.id);
    expect(saved, isNotNull);
    expect(saved!['focusAreas'], contains('文笔修辞'));
    expect(saved['cognitiveStyle'], 'intuitive');
  });

  testWidgets('#3 连续不完整超上限 → 默认值落库 + 兜底引导', (tester) async {
    await tester.pumpWidget(buildChatPage());
    await tester.pumpAndSettle();
    await enterNoviceMode(tester);

    // 三次「不知道」：第 1 次追问、第 2 次追问（retries=2 用尽）、
    // 第 3 次触发兜底（默认 beginner/mixed 落库，不让学员卡死）
    await sendText(tester, '不知道');
    expect(find.textContaining('还差一点没看全'), findsOneWidget);
    await sendText(tester, '不知道');
    // 第二次追问：追问消息累计 2 条
    expect(find.textContaining('还差一点没看全'), findsNWidgets(2));
    await sendText(tester, '不知道');

    // 兜底引导（无时间压力、低门槛）
    expect(find.textContaining('我们先不纠结这些'), findsOneWidget);

    // 默认值落库（proficiency 兜底 beginner、cognitiveStyle 兜底 mixed）
    final sessions = await db.select(db.sessions).get();
    final smRepo = StudentModelRepository(db);
    final saved = await smRepo.getOnboardingData(sessions.first.id);
    expect(saved, isNotNull);
    expect(saved!['proficiency'], 'beginner');
    expect(saved['cognitiveStyle'], 'mixed');
    expect(saved['skipped'], false);
  });

  // 回归：强制滚底 flag 通用化改名（_noviceScrollRequested → _forceScrollRequested）
  // 后，新手注入强滚底不得退化。会话已有溢出历史、且用户停在顶部读历史时，新手
  // 注入的固定首条消息落在列表末尾——必须靠强制滚底拉回到底才可见。若 flag 未
  // 设置/未透传，列表停在顶部，末尾消息不被 ListView.builder 构建，断言失败。
  testWidgets('#4 停在历史顶部进入新手模式 → 注入首条消息强滚到底可见', (tester) async {
    final repo = SessionRepository(db);
    // 当前会话（bootstrap 唯一会话）预置 30 条填充历史，溢出视口
    final sid = await repo.createBlankSession(title: '老会话');
    for (var i = 0; i < 30; i++) {
      await repo.addMessage(sid, 'user', '填充历史$i');
    }

    await tester.pumpWidget(buildChatPage());
    await tester.pumpAndSettle();

    // 用户正在读历史：把列表从底部跳回顶部
    tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .jumpTo(0);
    await tester.pumpAndSettle();
    expect(find.text('填充历史0'), findsOneWidget);

    // 进入新手模式 → 末尾注入固定首条消息（本地插入，不经 LLM）
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.tap(find.text('纯新手模式'));
    await tester.pumpAndSettle();
    expect(find.text(kNoviceModeDialogTitle), findsOneWidget);
    await tester.tap(find.text('开始引导'));
    await tester.pumpAndSettle();

    // 末尾注入的首条消息必须被强滚入视口（停在顶部时不可见）
    expect(find.textContaining('我是月笙，你的专属写作教练'), findsOneWidget);
  });
}
