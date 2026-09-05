// ─────────────────────────────────────────────────────────────
// WritingCoachPanel widget 测试 — 半屏 AI 教练面板
//
// 覆盖路径：
//   #1 渲染：拖拽手柄 + 诊断按钮 + 关闭按钮 + 输入栏 + 空状态
//   #2 点击关闭 → 触发 onClose 回调
//   #3 输入消息 + 发送 → 用户消息出现在列表
//   #4 点击诊断 → 字数不足被拦截（D1 真链路改造）
//   #5 错误横幅：setError → 红色横幅 + 关闭按钮可消除
//   #6 双击拖拽手柄 → 面板高度变化
//   D1-1 诊断 → chat_service.sendMessage 被调用（phase=P1_WORLD）
//   D1-2 诊断 → 用户消息出现在列表
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/config/app_theme.dart';
import 'package:writingcoach/data/database/database.dart';
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
import 'package:writingcoach/providers/evaluation_providers.dart';
import 'package:writingcoach/providers/practice_providers.dart';
import 'package:writingcoach/providers/session_providers.dart';
import 'package:writingcoach/providers/writing_providers.dart';
import 'package:writingcoach/services/chat_service.dart';
import 'package:writingcoach/services/diagnosis_committer.dart';
import 'package:writingcoach/services/message_injector.dart';
import 'package:writingcoach/services/chat_context_builder.dart'
    show MaterialCapabilityImpl;
import 'package:writingcoach/services/llm_client.dart';
import 'package:writingcoach/services/realtime_observation_service.dart';
import 'package:writingcoach/widgets/partial_agreement_card.dart';
import 'package:writingcoach/widgets/practice_task_card.dart';
import 'package:writingcoach/widgets/writing_coach_panel.dart';

import 'package:writingcoach/services/diagnosis_flow_handler.dart';
import 'package:writingcoach/services/diagnosis_parser.dart'
    show DiagnosisCapabilityImpl;
import 'package:writingcoach/services/genui_parser.dart'
    show GenUiParser;
/// 测试用 Fake LLM：预设 streamChat 响应（复用 chat_service_send_message_test 模式）
class FakeLlmClient extends LlmClient {
  final String fullResponse;
  final Exception? error;

  FakeLlmClient(this.fullResponse, {this.error});

  @override
  Future<void> streamChat(
    List<ChatMessage> messages,
    void Function(LlmStreamResponse response) callback, {
    CancelToken? cancelToken,
  }) async {
    if (error != null) throw error!;

    const chunkSize = 10;
    for (int i = 0; i < fullResponse.length; i += chunkSize) {
      final end = i + chunkSize < fullResponse.length
          ? i + chunkSize
          : fullResponse.length;
      callback(
        LlmStreamResponse(
          content: fullResponse.substring(i, end),
          isDone: false,
        ),
      );
    }
    callback(const LlmStreamResponse(content: '', isDone: true));
  }
}

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late String chapterId;
  late String msId;

  /// 字数 ≥100 的章节内容（D1 真链路要求字数校验通过）
  const longContent =
      '这是一个大雪纷飞的夜晚，北风呼啸着穿过空旷的原野，'
      '远处的山峦在暮色中显得格外孤寂。一位旅人独自走在雪地里，'
      '身后留下一串深深浅浅的脚印，很快又被新雪覆盖。'
      '他裹紧了身上的斗篷，目光投向远方那点若隐若现的灯火。';

  /// 字数 <100 的章节内容（用于 D1 字数校验测试）
  const shortContent = '这是一个大雪纷飞的夜晚。';

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    final msRepo = ManuscriptRepository(db);
    final chRepo = ChapterRepository(db);
    msId = await msRepo.createManuscript(title: '测试作品');
    chapterId = await chRepo.createChapter(
      msId,
      title: '第一章：启程',
      content: longContent,
    );
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        // D1：注入 FakeLlmClient，避免真实 LLM 调用
        chatServiceProvider.overrideWith((ref) {
          return ChatService(
            sessionRepo: SessionRepository(db),
            stateRepo: TeachingStateRepository(db),
            diagnosisRepo: DiagnosisRepository(db),
            studentModelRepo: StudentModelRepository(db),
            referenceRepo: ReferenceRepository(db),
            chapterRepo: ChapterRepository(db),
            manuscriptRepo: ManuscriptRepository(db),
            llmClient: FakeLlmClient('诊断完成。本章结构清晰，节奏明快。'),
            teacherSuggestionRepo: TeacherSuggestionRepository(db),
            editorObservationRepo: EditorObservationRepository(db),
            // ADR-C74 K-5：诊断提交编排器收紧为 required
            diagnosisCommitter: DiagnosisCommitter(
              sessionRepo: SessionRepository(db),
              stateRepo: TeachingStateRepository(db),
              diagnosisRepo: DiagnosisRepository(db),
              studentModelRepo: StudentModelRepository(db),
              referenceRepo: ReferenceRepository(db),
              chapterRepo: ChapterRepository(db),
            ),

            messageInjector: MessageInjector(
              sessionRepo: SessionRepository(db),

              diagnosisRepo: DiagnosisRepository(db),

              studentModelRepo: StudentModelRepository(db),

              referenceRepo: ReferenceRepository(db),

              chapterRepo: ChapterRepository(db),

              manuscriptRepo: ManuscriptRepository(db),

              diagnosisCommitter: DiagnosisCommitter(
                sessionRepo: SessionRepository(db),

                stateRepo: TeachingStateRepository(db),

                diagnosisRepo: DiagnosisRepository(db),

                studentModelRepo: StudentModelRepository(db),

                referenceRepo: ReferenceRepository(db),

                chapterRepo: ChapterRepository(db),
              ),

              material: const MaterialCapabilityImpl(),
            ),
            diagnosisFlowHandler: DiagnosisFlowHandler(
              sessionRepo: SessionRepository(db),
              stateRepo: TeachingStateRepository(db),
              diagnosisRepo: DiagnosisRepository(db),
              studentModelRepo: StudentModelRepository(db),
              referenceRepo: ReferenceRepository(db),
              chapterRepo: ChapterRepository(db),
              teacherSuggestionRepo: TeacherSuggestionRepository(db),
              llmClient: FakeLlmClient('诊断完成。本章结构清晰，节奏明快。'),

              messageInjector: MessageInjector(
                sessionRepo: SessionRepository(db),

                diagnosisRepo: DiagnosisRepository(db),

                studentModelRepo: StudentModelRepository(db),

                referenceRepo: ReferenceRepository(db),

                chapterRepo: ChapterRepository(db),

                manuscriptRepo: ManuscriptRepository(db),

                diagnosisCommitter: DiagnosisCommitter(
                  sessionRepo: SessionRepository(db),

                  stateRepo: TeachingStateRepository(db),

                  diagnosisRepo: DiagnosisRepository(db),

                  studentModelRepo: StudentModelRepository(db),

                  referenceRepo: ReferenceRepository(db),

                  chapterRepo: ChapterRepository(db),
                ),

                material: const MaterialCapabilityImpl(),
              ),
              diagnosisCommitter: DiagnosisCommitter(
                sessionRepo: SessionRepository(db),
                stateRepo: TeachingStateRepository(db),
                diagnosisRepo: DiagnosisRepository(db),
                studentModelRepo: StudentModelRepository(db),
                referenceRepo: ReferenceRepository(db),
                chapterRepo: ChapterRepository(db),
              ),
              diagnosis: const DiagnosisCapabilityImpl(),
              genUi: const GenUiParser(),
            ),
          );
        }),
        // 批次69（A7 双通道）：快速观察实时通道注入 Fake LLM
        realtimeObservationServiceProvider.overrideWith((ref) {
          return RealtimeObservationService(
            llmClient: FakeLlmClient('快速观察反馈：这句的节奏偏快。'),
            sessionRepo: SessionRepository(db),
            editorObservationRepo: EditorObservationRepository(db),
          );
        }),
      ],
    );
    // D1：让 WritingStore 加载章节内容到 localContent（_handleDiagnose 从 store 读取内容）
    await container
        .read(writingStoreProvider(chapterId).notifier)
        .loadChapter();
  });

  tearDown(() {
    container.dispose();
    db.close();
  });

  Widget buildPanel({
    VoidCallback? onClose,
    void Function(String)? onAdopt,
    String? customChapterId,
    String? customChapterTitle,
    String? pendingDiagnoseText,
  }) {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: WritingCoachPanel(
            chapterId: customChapterId ?? chapterId,
            manuscriptId: msId,
            chapterTitle: customChapterTitle ?? '第一章：启程',
            onClose: onClose ?? () {},
            onAdopt: onAdopt,
            pendingDiagnoseText: pendingDiagnoseText,
          ),
        ),
      ),
    );
  }

  group('WritingCoachPanel', () {
    testWidgets('#1 渲染按钮行、关闭按钮、输入栏、空状态', (tester) async {
      await tester.pumpWidget(buildPanel());
      await tester.pumpAndSettle();

      // 批次82 P0-④：侧栏形态，不再有拖拽手柄
      expect(find.byKey(const Key('dragHandle')), findsNothing);
      // 诊断本章按钮
      expect(find.text('诊断本章'), findsOneWidget);
      // 关闭按钮
      expect(find.byIcon(Icons.close), findsOneWidget);
      // 输入栏
      expect(find.byType(TextField), findsOneWidget);
      // 发送按钮
      expect(find.byIcon(Icons.send), findsOneWidget);
      // 空状态
      expect(find.text('有问题问教练'), findsOneWidget);
    });

    testWidgets('#2 点击关闭按钮 → 触发 onClose 回调', (tester) async {
      bool closeCalled = false;
      await tester.pumpWidget(buildPanel(onClose: () => closeCalled = true));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(closeCalled, isTrue);
    });

    testWidgets('#3 输入消息 + 发送 → 用户消息出现在列表', (tester) async {
      await tester.pumpWidget(buildPanel());
      await tester.pumpAndSettle();

      // 空状态初始显示
      expect(find.text('有问题问教练'), findsOneWidget);

      // 输入消息
      await tester.enterText(find.byType(TextField), '测试消息');
      await tester.pump();

      // 点击发送
      await tester.tap(find.byIcon(Icons.send));
      await tester.pump();

      // 用户消息应出现在列表中
      expect(find.text('测试消息'), findsOneWidget);
      // 空状态应消失
      expect(find.text('有问题问教练'), findsNothing);
    });

    testWidgets('#4 点击诊断 → 字数不足被 SnackBar 拦截（D1 真链路改造）', (tester) async {
      // 创建短内容章节
      final chRepo = ChapterRepository(db);
      final shortChapterId = await chRepo.createChapter(
        msId,
        title: '短章节',
        content: shortContent,
      );
      // 让 WritingStore 加载短内容（_handleDiagnose 从 store 读取 localContent 做字数校验）
      await container
          .read(writingStoreProvider(shortChapterId).notifier)
          .loadChapter();

      await tester.pumpWidget(
        buildPanel(customChapterId: shortChapterId, customChapterTitle: '短章节'),
      );
      await tester.pumpAndSettle();

      // 点击诊断本章
      await tester.tap(find.text('诊断本章'));
      await tester.pump();
      await tester.pumpAndSettle();

      // 应弹出 SnackBar 提示字数不足
      expect(find.text('请至少输入 100 字后再提交诊断'), findsOneWidget);
      // 不应出现诊断用户消息（被拦截）
      expect(find.text('请诊断本章内容'), findsNothing);
    });

    testWidgets('#5 错误横幅：setError → 红色横幅 + 可关闭', (tester) async {
      await tester.pumpWidget(buildPanel());
      await tester.pumpAndSettle();

      // 初始无错误横幅
      expect(find.byIcon(Icons.error_outline), findsNothing);

      // 设置错误状态
      container
          .read(writingCoachStoreProvider(chapterId).notifier)
          .setError('测试错误信息');
      await tester.pump();

      // 错误横幅应显示
      expect(find.text('测试错误信息'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      // 此时应有 2 个 close 图标（面板关闭 + 横幅关闭）
      expect(find.byIcon(Icons.close), findsNWidgets(2));

      // 点击横幅内的关闭按钮消除错误
      final banner = find.byWidgetPredicate(
        (w) => w is Container && w.color == AppColors.dangerBg,
      );
      final dismissBtn = find.descendant(
        of: banner,
        matching: find.byIcon(Icons.close),
      );
      await tester.tap(dismissBtn);
      await tester.pump();

      // 错误横幅应消失
      expect(find.text('测试错误信息'), findsNothing);
      expect(find.byIcon(Icons.error_outline), findsNothing);
      // 恢复为 1 个 close 图标（仅面板关闭）
      expect(find.byIcon(Icons.close), findsOneWidget);
    });

    testWidgets('#6 批次82 P0-④ 侧栏形态：面板填满父容器高度', (tester) async {
      await tester.pumpWidget(buildPanel());
      await tester.pumpAndSettle();

      // 面板高度 = Scaffold body 高度（600 - AppBar 0 = 600）
      final size = tester.getSize(find.byType(WritingCoachPanel));
      expect(size.height, 600, reason: '侧栏面板应填满父容器高度');
      // 无拖拽手柄（收起由页面侧 FAB/关闭开关）
      expect(find.byKey(const Key('dragHandle')), findsNothing);
    });

    testWidgets('#7 渲染「快速观察」按钮（A7 实时通道入口）', (tester) async {
      await tester.pumpWidget(buildPanel());
      await tester.pumpAndSettle();

      expect(find.text('快速观察'), findsOneWidget);
      expect(find.text('诊断本章'), findsOneWidget);
    });

    testWidgets('#8 点击快速观察 → 实时观察反馈写入消息列表（A7 轻通道）', (tester) async {
      await tester.pumpWidget(buildPanel());
      await tester.pumpAndSettle();

      // 点击快速观察（章节内容 longContent ≥50 字）
      await tester.tap(find.text('快速观察'));
      await tester.pump();
      await tester.pumpAndSettle();

      // 实时观察反馈应出现在消息列表（observe 写入 assistant 消息 + 刷新列表）
      expect(find.text('快速观察反馈：这句的节奏偏快。'), findsOneWidget);

      // 不触发全量诊断：无「诊断本章」的完整诊断 prompt 用户消息
      final chatState = container.read(writingCoachStoreProvider(chapterId));
      expect(chatState.messages.length, greaterThanOrEqualTo(1));
      expect(chatState.messages.last.role, 'assistant');
    });

    testWidgets('#9 点击快速观察 → 字数不足被 SnackBar 拦截', (tester) async {
      // 创建短内容章节（<50 字）
      final chRepo = ChapterRepository(db);
      final shortChapterId = await chRepo.createChapter(
        msId,
        title: '短章节',
        content: shortContent,
      );
      await container
          .read(writingStoreProvider(shortChapterId).notifier)
          .loadChapter();

      await tester.pumpWidget(
        buildPanel(customChapterId: shortChapterId, customChapterTitle: '短章节'),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('快速观察'));
      await tester.pump();
      await tester.pumpAndSettle();

      // 应弹出 SnackBar 提示字数不足，且不写入观察消息
      expect(find.text('请至少写 50 字后再快速观察'), findsOneWidget);
      final chatState = container.read(
        writingCoachStoreProvider(shortChapterId),
      );
      expect(chatState.messages.isEmpty, isTrue);
    });
  });

  // ── D1: 诊断本章真链路集成测试 ──
  // 验证 _handleDiagnose 接通 chat_service 真链路后的行为
  group('诊断本章真链路集成测试', () {
    testWidgets('D1-1 诊断 → chat_service.sendMessage 被调用（phase=P1_WORLD）', (
      tester,
    ) async {
      await tester.pumpWidget(buildPanel());
      await tester.pumpAndSettle();

      // 初始 phase 应为 P0_ENGAGE（createBlankSession 默认值）
      final stateRepo = TeachingStateRepository(db);
      final sessionRepo = SessionRepository(db);
      final sid = await sessionRepo.getOrCreateSessionForChapter(
        msId,
        chapterId,
      );
      final stateBefore = await stateRepo.getTeachingState(sid);
      expect(stateBefore?.currentPhase, 'P0_ENGAGE');

      // 点击诊断本章，等待真链路 sendMessage 完成
      await tester.tap(find.text('诊断本章'));
      await tester.pump();
      await tester.pumpAndSettle();

      // DB 中 phase 应被更新为 P1_WORLD（对齐 RN updatePhase 前置）
      final stateAfter = await stateRepo.getTeachingState(sid);
      expect(stateAfter?.currentPhase, 'P1_WORLD');

      // 章节内容应已落库（saveNow 前置）+ lastDiagnosedAt 非空
      final chRepo = ChapterRepository(db);
      final chapterAfter = await chRepo.getChapter(chapterId);
      expect(chapterAfter?.lastDiagnosedAt, isNotNull);
    });

    testWidgets('D1-2 诊断 → 用户消息出现在列表 + 流式回复触发', (tester) async {
      await tester.pumpWidget(buildPanel());
      await tester.pumpAndSettle();

      // 点击诊断本章
      await tester.tap(find.text('诊断本章'));
      await tester.pump();
      await tester.pumpAndSettle();

      // 内存 store 应有用户消息 + assistant 消息
      // onComplete 后 setMessages 用 DB 消息替换内存（DB user 消息是完整 diagPrompt）
      final chatState = container.read(writingCoachStoreProvider(chapterId));
      expect(chatState.messages.length, greaterThanOrEqualTo(2));
      expect(chatState.messages[0].role, 'user');
      // DB 中 user 消息是完整诊断 prompt（含章节内容）
      expect(chatState.messages[0].content, contains('写作诊断分析'));
      expect(chatState.messages[1].role, 'assistant');

      // 由于 FakeLlmClient 返回 "诊断完成..."，streaming 应最终为 false
      expect(chatState.isStreaming, isFalse);
    });

    testWidgets('D1-3 诊断 prompt 含 [YS_DIAGNOSIS] 格式要求', (tester) async {
      await tester.pumpWidget(buildPanel());
      await tester.pumpAndSettle();

      // 点击诊断，等待完成
      await tester.tap(find.text('诊断本章'));
      await tester.pump();
      await tester.pumpAndSettle();

      // 验证 DB 中的 user 消息含 [YS_DIAGNOSIS] 格式要求（对齐 RN chat.tsx#L212）
      final sessionRepo = SessionRepository(db);
      final sid = await sessionRepo.getOrCreateSessionForChapter(
        msId,
        chapterId,
      );
      final messages = await sessionRepo.listMessages(sid);
      final userMsg = messages.firstWhere((m) => m.role == 'user');
      expect(userMsg.content, contains('[YS_DIAGNOSIS]'));
      expect(userMsg.content, contains('syndromes'));
      expect(userMsg.content, contains('severity'));
    });

    testWidgets('D1-4 会话隔离：两章节各自诊断，teaching_state 互不影响', (tester) async {
      // 创建第二个章节（长内容，通过字数校验）
      final chRepo = ChapterRepository(db);
      final chapterId2 = await chRepo.createChapter(
        msId,
        title: '第二章：夜行',
        content: longContent,
      );
      // D1：让第二章的 WritingStore 也加载内容
      await container
          .read(writingStoreProvider(chapterId2).notifier)
          .loadChapter();

      // 第一步：诊断第一章
      await tester.pumpWidget(buildPanel());
      await tester.pumpAndSettle();
      await tester.tap(find.text('诊断本章'));
      await tester.pump();
      await tester.pumpAndSettle();

      // 第二步：切换到第二章面板并诊断
      await tester.pumpWidget(
        buildPanel(customChapterId: chapterId2, customChapterTitle: '第二章：夜行'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('诊断本章'));
      await tester.pump();
      await tester.pumpAndSettle();

      // 验证两个章节的 teaching_state 都被更新为 P1_WORLD（各自独立）
      final stateRepo = TeachingStateRepository(db);
      final sid1 = await SessionRepository(
        db,
      ).getOrCreateSessionForChapter(msId, chapterId);
      final sid2 = await SessionRepository(
        db,
      ).getOrCreateSessionForChapter(msId, chapterId2);
      final state1 = await stateRepo.getTeachingState(sid1);
      final state2 = await stateRepo.getTeachingState(sid2);

      expect(state1?.currentPhase, 'P1_WORLD');
      expect(state2?.currentPhase, 'P1_WORLD');
      // 会话 ID 应不同（隔离）
      expect(sid1, isNot(sid2));
    });

    // ── 批次6 M1：整章诊断阶段回退拦截 ──

    testWidgets('M1-1 已到 P2 学员整章诊断 → 阶段不回退到 P1（批次6）', (tester) async {
      await tester.pumpWidget(buildPanel());
      await tester.pumpAndSettle();

      final stateRepo = TeachingStateRepository(db);
      final sid = await SessionRepository(
        db,
      ).getOrCreateSessionForChapter(msId, chapterId);
      // 模拟学员已进入 P2 训练阶段（FSM 单调前进的中间态）
      await stateRepo.updatePhase(sid, 'P2_PRACTICE_LOOP');

      // 整章诊断
      await tester.tap(find.text('诊断本章'));
      await tester.pump();
      await tester.pumpAndSettle();

      final stateAfter = await stateRepo.getTeachingState(sid);
      expect(
        stateAfter?.currentPhase,
        'P2_PRACTICE_LOOP',
        reason: 'M1: P2 学员整章诊断不应被非法回退到 P1（validatePhaseTransition 拦截降级）',
      );
    });

    testWidgets('M1-2 P0 学员整章诊断 → 正常推进到 P1（不破坏既有行为）', (tester) async {
      await tester.pumpWidget(buildPanel());
      await tester.pumpAndSettle();

      final stateRepo = TeachingStateRepository(db);
      final sid = await SessionRepository(
        db,
      ).getOrCreateSessionForChapter(msId, chapterId);
      // 初始 P0（createBlankSession 默认）

      await tester.tap(find.text('诊断本章'));
      await tester.pump();
      await tester.pumpAndSettle();

      final stateAfter = await stateRepo.getTeachingState(sid);
      expect(
        stateAfter?.currentPhase,
        'P1_WORLD',
        reason: 'M1: P0→P1 是合法递进，应正常推进（回归 D1-1 行为）',
      );
    });

    // ── 批次6 E1：面板初始化恢复该章节会话评估报告 ──

    testWidgets('E1-1 面板初始化恢复章节会话评估报告（批次6）', (tester) async {
      // 先为章节会话种子诊断 + 构建评估报告（落库 app_state）
      final sessionRepo = SessionRepository(db);
      final sid = await sessionRepo.getOrCreateSessionForChapter(
        msId,
        chapterId,
      );
      final msgId = await sessionRepo.addMessage(
        sid,
        'assistant',
        '诊断内容',
        messageType: 'diagnosis_result',
      );
      final diagRepo = DiagnosisRepository(db);
      await diagRepo.commitDiagnosis(
        DiagnosisInput(
          sessionId: sid,
          messageId: msgId,
          syndromes: [
            {'syndrome_id': 's1', 'name': '叙事含糊', 'severity': 'L2'},
          ],
          suggestedActions: const [],
          confidence: 0.8,
        ),
      );
      // 构建评估报告（写入 app_state KV，模拟训练反馈后的持久化）
      final evalStore = container.read(evaluationReportsProvider.notifier);
      await evalStore.buildEvaluationReport(sid, msgId);
      expect(evalStore.state.reports.containsKey(msgId), isTrue);

      // 打开面板 → _initSession → restoreForSession 从 DB 恢复
      await tester.pumpWidget(buildPanel());
      await tester.pumpAndSettle();

      final restored = container.read(evaluationReportsProvider);
      expect(
        restored.reports.containsKey(msgId),
        isTrue,
        reason: 'E1: 面板初始化应从 app_state KV 恢复该章节会话的历史评估报告',
      );
      expect(restored.currentRound, greaterThanOrEqualTo(1));
    });
  });

  // ── D5-A: 教练面板卡片化 + 中间态优化测试 ──
  group('D5-A 教练面板卡片化 + 中间态', () {
    testWidgets('D5A-1 diagnosis_result 消息 → 渲染 DiagnosisCard（而非 JSON 文本）', (
      tester,
    ) async {
      await tester.pumpWidget(buildPanel());
      await tester.pumpAndSettle();

      // 注入一条 diagnosis_result 类型消息（模拟诊断落库后的卡片消息）
      final resultMsg = Message(
        id: 'diag-1',
        sessionId: chapterId,
        role: 'system',
        content: jsonEncode({
          'syndromeCount': 2,
          'syndromes': [
            {
              'syndrome_id': 'S001',
              'name': '情绪标签化',
              'severity': 'L2',
              'evidence_count': 2,
            },
            {
              'syndrome_id': 'S002',
              'name': '视角漂移',
              'severity': 'L1',
              'evidence_count': 1,
            },
          ],
          'suggestedActions': ['先处理情绪标签化'],
          'confidence': 0.85,
        }),
        timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        messageType: 'diagnosis_result',
      );
      container
          .read(writingCoachStoreProvider(chapterId).notifier)
          .addMessage(resultMsg);
      await tester.pump();

      // 渲染 DiagnosisCard header + 症候 chip
      expect(find.text('本次诊断'), findsOneWidget);
      expect(find.text('2 个问题'), findsOneWidget);
      expect(find.text('85% 信心'), findsOneWidget);
      expect(find.text('情绪标签化').hitTestable(), findsOneWidget);
      expect(find.text('视角漂移').hitTestable(), findsOneWidget);

      // 不应以原始 JSON 文本渲染
      expect(find.textContaining('syndromeCount'), findsNothing);
      expect(find.textContaining('suggestedActions'), findsNothing);
    });

    testWidgets('D5A-2 流式/诊断中 → 诊断按钮禁用（防重复触发）', (tester) async {
      await tester.pumpWidget(buildPanel());
      await tester.pumpAndSettle();

      // 手动置流式状态（模拟诊断进行中）
      container
          .read(writingCoachStoreProvider(chapterId).notifier)
          .setStreaming(true);
      await tester.pump();

      // 诊断按钮应禁用（onPressed == null）
      final btn = tester.widget<TextButton>(
        find.ancestor(of: find.text('诊断本章'), matching: find.byType(TextButton)),
      );
      expect(btn.onPressed, isNull);
    });

    testWidgets('D5A-3 流式无内容 → 显示「思考中…」占位', (tester) async {
      await tester.pumpWidget(buildPanel());
      await tester.pumpAndSettle();

      // 置流式状态但 streamingContent 为空
      container
          .read(writingCoachStoreProvider(chapterId).notifier)
          .setStreaming(true);
      await tester.pump();

      // 列表末尾出现思考中占位
      expect(find.text('思考中…'), findsOneWidget);
    });
  });

  // ── B3: 划词诊断（选段诊断）测试 ──
  group('B3 划词诊断（选段诊断）', () {
    /// ≥20 字的选中文本
    const selectedText = '这是一个大雪纷飞的夜晚，北风呼啸着穿过空旷的原野，远处的山峦在暮色中显得格外孤寂。';

    testWidgets('B3-1 pendingDiagnoseText 注入 → 自动触发选段诊断', (tester) async {
      await tester.pumpWidget(buildPanel(pendingDiagnoseText: selectedText));
      await tester.pumpAndSettle();

      // onComplete 后内存消息被 DB 完整 prompt 替换 → 验证消息 role + 内容
      final chatState = container.read(writingCoachStoreProvider(chapterId));
      expect(chatState.messages.length, greaterThanOrEqualTo(2));
      expect(chatState.messages[0].role, 'user');
      expect(chatState.messages[0].content, contains('选中文本'));

      // DB 中 user 消息是选段诊断 prompt（含「选中文本」与选中内容）
      final sessionRepo = SessionRepository(db);
      final sid = await sessionRepo.getOrCreateSessionForChapter(
        msId,
        chapterId,
      );
      final messages = await sessionRepo.listMessages(sid);
      final userMsg = messages.firstWhere((m) => m.role == 'user');
      expect(userMsg.content, contains('选中文本'));
      expect(userMsg.content, contains('【选段】'));
      expect(userMsg.content, contains('[YS_DIAGNOSIS]'));
      // 诊断内容为选中文本而非整章
      expect(userMsg.content, contains(selectedText));
    });

    testWidgets('B3-2 选段 <20 字 → SnackBar 拦截，不触发诊断', (tester) async {
      await tester.pumpWidget(buildPanel(pendingDiagnoseText: '太短了这段'));
      await tester.pumpAndSettle();

      // 应弹出 SnackBar 提示（选段下限 20 字，对齐 RN）
      expect(find.text('请至少选择 20 字以上的文本进行诊断'), findsOneWidget);
      // 不应出现选段诊断用户消息
      expect(find.text('请诊断以下选中文本'), findsNothing);
    });

    testWidgets('B3-3 pendingDiagnoseText 为 null → 不触发选段诊断', (tester) async {
      await tester.pumpWidget(buildPanel());
      await tester.pumpAndSettle();

      // 无选中文本注入 → 无选段诊断用户消息，仍为空状态
      expect(find.text('请诊断以下选中文本'), findsNothing);
      expect(find.text('有问题问教练'), findsOneWidget);
    });
  });

  // ── 批次74：长按删除消息 ──
  group('批次74 教练面板消息长按删除', () {
    testWidgets('B74-1 长按普通气泡 → 确认删除 → DB 删除 + 列表刷新', (tester) async {
      final sessionRepo = SessionRepository(db);
      final sid = await sessionRepo.getOrCreateSessionForChapter(
        msId,
        chapterId,
      );
      await sessionRepo.addMessage(sid, 'user', '待删除的教练消息');

      await tester.pumpWidget(buildPanel());
      await tester.pumpAndSettle();

      expect(find.text('待删除的教练消息'), findsOneWidget);

      // 长按气泡 → 确认弹窗
      await tester.longPress(find.text('待删除的教练消息'));
      await tester.pumpAndSettle();
      expect(find.text('删除消息'), findsOneWidget);

      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();

      // DB 已删除 + 列表回到空状态
      final messages = await sessionRepo.listMessages(sid);
      expect(messages, isEmpty);
      expect(find.text('待删除的教练消息'), findsNothing);
      expect(find.text('有问题问教练'), findsOneWidget);
    });

    testWidgets('B74-2 长按卡片消息 → 确认删除 → 卡片消失', (tester) async {
      final sessionRepo = SessionRepository(db);
      final sid = await sessionRepo.getOrCreateSessionForChapter(
        msId,
        chapterId,
      );
      await sessionRepo.addMessage(
        sid,
        'system',
        jsonEncode({
          'syndromeCount': 1,
          'syndromes': [
            {
              'syndrome_id': 'S001',
              'name': '情绪标签化',
              'severity': 'L2',
              'evidence_count': 1,
            },
          ],
          'suggestedActions': ['先处理情绪标签化'],
          'confidence': 0.8,
        }),
        messageType: 'diagnosis_result',
      );

      await tester.pumpWidget(buildPanel());
      await tester.pumpAndSettle();

      // 卡片已渲染
      expect(find.text('本次诊断'), findsOneWidget);

      // 长按卡片 → 确认删除
      await tester.longPress(find.text('本次诊断'));
      await tester.pumpAndSettle();
      expect(find.text('删除消息'), findsOneWidget);

      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();

      expect(find.text('本次诊断'), findsNothing);
      expect(find.text('有问题问教练'), findsOneWidget);
    });

    testWidgets('B74-3 长按 → 取消不删除', (tester) async {
      final sessionRepo = SessionRepository(db);
      final sid = await sessionRepo.getOrCreateSessionForChapter(
        msId,
        chapterId,
      );
      await sessionRepo.addMessage(sid, 'user', '保留这条消息');

      await tester.pumpWidget(buildPanel());
      await tester.pumpAndSettle();

      await tester.longPress(find.text('保留这条消息'));
      await tester.pumpAndSettle();
      expect(find.text('删除消息'), findsOneWidget);

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      // 消息仍在（DB 未删 + 列表保留）
      final messages = await sessionRepo.listMessages(sid);
      expect(messages, hasLength(1));
      expect(find.text('保留这条消息'), findsOneWidget);
    });
  });

  group('批次81：三卡回调接线', () {
    /// 三卡卡片较高，放大视口防面板消息区溢出（卡片按钮超出可点区）
    void enlargeViewport(WidgetTester tester) {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
    }

    testWidgets('phase_summary「继续训练」→ 重开练习任务', (tester) async {
      enlargeViewport(tester);
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

      final sessionRepo = SessionRepository(db);
      final sid = await sessionRepo.getOrCreateSessionForChapter(
        msId,
        chapterId,
      );
      await sessionRepo.addMessage(
        sid,
        'assistant',
        jsonEncode({
          'result': 'partial',
          'resolvedSyndromeCount': 1,
          'trainingCount': 4,
          'trend': 'improving',
          'syndromeChanges': <Object>[],
        }),
        messageType: 'phase_summary',
      );

      await tester.pumpWidget(buildPanel());
      await tester.pumpAndSettle();

      expect(find.text('继续训练'), findsOneWidget);
      await tester.tap(find.text('继续训练'));
      await tester.pump();

      // retryPractice 重开上次任务 → 练习任务卡出现
      expect(find.byType(PracticeTaskCard), findsOneWidget);
    });

    testWidgets('diagnosis_failed「继续对话」→ 聚焦输入栏', (tester) async {
      enlargeViewport(tester);
      final sessionRepo = SessionRepository(db);
      final sid = await sessionRepo.getOrCreateSessionForChapter(
        msId,
        chapterId,
      );
      await sessionRepo.addMessage(
        sid,
        'assistant',
        jsonEncode({'failureCount': 1}),
        messageType: 'diagnosis_failed',
      );

      await tester.pumpWidget(buildPanel());
      await tester.pumpAndSettle();

      await tester.tap(find.text('继续对话'));
      await tester.pump();

      final editable = tester.widget<EditableText>(find.byType(EditableText));
      expect(editable.focusNode.hasFocus, isTrue);
    });

    testWidgets('partial_agreement 提交反馈 → 用户消息进列表（杜绝静默清空）', (tester) async {
      enlargeViewport(tester);
      final sessionRepo = SessionRepository(db);
      final sid = await sessionRepo.getOrCreateSessionForChapter(
        msId,
        chapterId,
      );
      await sessionRepo.addMessage(
        sid,
        'assistant',
        jsonEncode({
          'syndromeId': 'P001',
          'syndromeName': '视角跳跃症',
          'severity': 'L2',
        }),
        messageType: 'partial_agreement',
      );

      await tester.pumpWidget(buildPanel());
      await tester.pumpAndSettle();

      // 卡片输入框输入反馈 → 提交
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

      // 反馈作为用户消息真实进入消息列表（非静默清空）
      expect(find.textContaining('我对刚才的诊断结果有不同看法：我觉得问题不严重'), findsOneWidget);
    });
  });
}
