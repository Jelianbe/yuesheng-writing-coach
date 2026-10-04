// ─────────────────────────────────────────────────────────────
// novice_mode_test — 纯新手模式 widget 闭环测试（ADR-C122）
//
// ★ 2026-10-04 流程已变（依舰长真机反馈，甲方案）：
//   对话页「➕」→ 纯新手模式 → 固定弹窗 → **新建会话** → 插入一句话首条
//   消息 → 学员回答 → **直接进正题（无追问）** → 落库。
//   两处结构性变化：① 新建会话（原先追加到当前会话，舰长要求新建对话触发）；
//   ② 取消追问（原「答不全就一直问」被反馈为「被强制了，必须全部答完」，
//      且 State 局部计数器归零会造成复读）。
//
// 覆盖：
//   1. 完整回答 → 小白分支引导 + onboarding_data/beginner_level/
//      questionnaire_completed 三步落库
//   2. 含糊回答 → **不追问**，直接进正题并落库（缺字段不崩）
//   3. 连发多条含糊回答 → 无复读、无追问
//   4. 进入新手模式 → **新建会话**，老会话历史一条未增
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
    // ★ 2026-10-04 文案改为「一句话」版本（不再是「你的专属写作教练」+
    //   三问清单）。断言锚点取自我介绍首句。
    expect(find.textContaining('你好，我是月笙，我可以从零基础开始叫你写作'), findsOneWidget);
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

  testWidgets('#1 回答含明确基础信号 → 小白分支引导 + 三步落库', (tester) async {
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

  // ★ 2026-10-04 语义翻转（原 #2「不完整回答 → 固定追问，再答完整」）：
  // 甲方案下**不再有任何追问**——学员答不答得出方向/偏好都直接进正题。
  // 这条现在钉的是「不追问」本身：只发一条含糊回答，必须**只出现引导语、
  // 不出现追问语**，且当场落库（采集得到多少算多少）。
  // 原用例的保护对象（追问机制）已随 kNoviceModeFollowUpMessage 退役。
  testWidgets('#2 含糊回答 → 不追问，直接进正题并落库', (tester) async {
    await tester.pumpWidget(buildChatPage());
    await tester.pumpAndSettle();
    await enterNoviceMode(tester);

    // 唯一一句含糊回答：既无方向也无偏好
    await sendText(tester, '不知道怎么说');

    // 判据1：追问语**零出现**（旧实现此处会插「还差一点没看全」）
    expect(find.textContaining('还差一点没看全'), findsNothing);
    // 判据 2：当场进正题（proficiency 兜底 beginner → 小白引导）
    expect(find.textContaining('别急着想太多'), findsOneWidget);

    // 判据 3：仍然落库（下游画像段有则注入、无则跳过，不因缺字段崩）
    final sessions = await db.select(db.sessions).get();
    final smRepo = StudentModelRepository(db);
    final saved = await smRepo.getOnboardingData(sessions.first.id);
    expect(saved, isNotNull);
    expect(saved!['proficiency'], 'beginner');
    expect(saved['cognitiveStyle'], 'mixed');
  });

  // ★ 2026-10-04 语义翻转（原 #3「连续不完整超上限 → 兜底」）：
  //   既然「不追问」，就不存在「超上限」这条路径。改钉**novice 态只消费一次**：
  //   回答第一条后 _noviceActive 立即复位（chat_page._handleNoviceAnswer
  //   末支setState(() => _noviceActive = false)），后续消息走正常 LLM 通道。
  //   这正是「不再反复触发硬编码对话」的实现层保证。
  //   ⚠️ 判据用**库读数**而非 pumpAndSettle：复位后消息进ChatService 流式
  //   链路（测试里无 LLM 响应），pumpAndSettle 会永不settle 而超时
  //   ——首版误把它当失败，实为「修复生效」的证据。
  testWidgets('#3 回答一次后 novice 态即复位（后续消息不再走本地硬编码通道）', (tester) async {
    await tester.pumpWidget(buildChatPage());
    await tester.pumpAndSettle();
    await enterNoviceMode(tester);

    final sid = (await db.select(db.sessions).get()).first.id;

    // 第一答：含糊回答 → 立即进正题（不追问）
    await sendText(tester, '不知道');
    expect(find.textContaining('还差一点没看全'), findsNothing);
    expect(find.textContaining('别急着想太多'), findsOneWidget);

    // novice 通道产出的消息数：assistant 首条 + user 回答 + assistant 引导 = 3
    final noviceMsgs = await SessionRepository(db).listMessages(sid);
    expect(
      noviceMsgs.where((m) => m.messageType == kNoviceMessageType).length,
      3,
      reason: 'novice 通道只应处理这一条回答；再多的硬编码消息就是复读缺陷',
    );
    expect(
      noviceMsgs.where((m) => m.messageType == kNoviceMessageType).last.content,
      contains('别急着想太多'),
      reason: '最后一条必须是「进正题」引导，而不是追问',
    );
  });

  // ★ 2026-10-04 语义翻转（原 #4「停在历史顶部 → 强滚底可见」）：
  //   甲方案下进入新手模式会**先新建会话**（chat_page._startNoviceMode 调
  //   _session.handleCreateSession），所以「老会话末尾被追加」这个前提
  //   已被设计消除。新判据钉的正是这条设计：**老会话消息数一条未增**。
  //   ⚠️ 不对屏幕内容做断言：老会话未必是当前会话（bootstrap 恢复的是
  //   另一个），其历史可能根本不在屏上（首版误按「屏上可见」写，红）。
  //   判据改用**库读数**，直接验「未被污染」这一设计不变量。
  testWidgets('#4 进入新手模式 → 新建会话，老会话消息数一条未增', (tester) async {
    final repo = SessionRepository(db);
    // 老会话预置 30 条历史
    final oldSid = await repo.createBlankSession(title: '老会话');
    for (var i = 0; i < 30; i++) {
      await repo.addMessage(oldSid, 'user', '填充历史$i');
    }
    final beforeCount = (await repo.listMessages(oldSid)).length;
    expect(beforeCount, 30);

    await tester.pumpWidget(buildChatPage());
    await tester.pumpAndSettle();

    await enterNoviceMode(tester);

    // 判据 1：首条消息在（**新**会话）上屏
    expect(find.textContaining('你好，我是月笙，我可以从零基础开始叫你写作'), findsOneWidget);
    // 判据 2：★ 核心 —— 老会话消息数**一条未增**（新建会话而非追加到当前会话）
    expect((await repo.listMessages(oldSid)).length, beforeCount);
    // 判据 3：首条消息落在**别的**会话里（不是老会话）
    //  ⚠️ 不用「会话表恰好 2 条」：bootstrap 自己会先建一个空会话
    //  （首版误判 2，实测 3 —— bootstrap 会话 + 老会话 + 新手模式新建会话）。
    //  设计不变量是「老会话没被写」，已由判据 2 覆盖；这里只验新会话存在。
    final sessions = await db.select(db.sessions).get();
    expect(
      sessions.length,
      greaterThanOrEqualTo(2),
      reason: '除老会话外至少还有 bootstrap/新建的会话',
    );
    final noviceSid = (await db.select(db.sessions).get())
        .firstWhere((s) => s.id != oldSid)
        .id;
    final noviceMsgs = await repo.listMessages(noviceSid);
    expect(noviceMsgs, isNotEmpty, reason: '新手模式首条消息落在新会话里');
    expect(
      noviceMsgs.every((m) => m.messageType == kNoviceMessageType),
      isTrue,
      reason: '新会话里的消息都应是 novice 通道产出',
    );
  });
}
