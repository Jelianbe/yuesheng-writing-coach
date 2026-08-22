// ─────────────────────────────────────────────────────────────
// UI 层端到端验证 — ChatPage 对话流全链路
//
// 补齐组件级（outline_confirmation_card_test）与页面级 seed
// （growth_detail_page_test）之间缺失的"真 UI 链路"：
//   用户输入 → ChatPage 发送 → 真实 ChatService 处理协议块 →
//   对话流渲染卡片 → 用户交互 → 数据真实落库 → UI 状态更新
//
// 覆盖：
//   E2E-1 确认卡接受链路：发送 → 对话流渲染确认卡 → 点「接受」
//         → outline_impression 落库 active + 卡片收起
//   E2E-2 确认卡拒绝链路：同上，点「拒绝」→ 落库 rejected + 卡片收起
//   E2E-3 诊断卡渲染 + 落库联动：对话流渲染诊断结果卡 +
//         diagnosis_results / active_problems 真实落库
//
// 装配：真实 ChatService（全仓储 + Fake LLM 输出协议块）+ ChatPage
//       ProviderScope override，模拟真实用户操作路径
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/app_state_repository.dart';
import 'package:writingcoach/data/repositories/chapter_repository.dart';
import 'package:writingcoach/data/repositories/character_fact_repository.dart';
import 'package:writingcoach/data/repositories/diagnosis_repository.dart';
import 'package:writingcoach/data/repositories/editor_observation_repository.dart';
import 'package:writingcoach/data/repositories/event_fact_repository.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/data/repositories/outline_repository.dart';
import 'package:writingcoach/data/repositories/reference_repository.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/data/repositories/student_model_repository.dart';
import 'package:writingcoach/data/repositories/subplot_fact_repository.dart';
import 'package:writingcoach/data/repositories/teacher_suggestion_repository.dart';
import 'package:writingcoach/data/repositories/teaching_state_repository.dart';
import 'package:writingcoach/providers/app_providers.dart';
import 'package:writingcoach/providers/session_providers.dart';
import 'package:writingcoach/services/chat_service.dart';
import 'package:writingcoach/services/llm_client.dart';
import 'package:writingcoach/widgets/chat_page.dart';

import '../helpers/mock_last_session_storage.dart';

/// Fake LLM：一次返回含 [YS_DIAGNOSIS] + [YS_ENTITY] 协议块的完整回复，
/// 驱动 ChatService 走真实诊断落库 + 大纲提取 + 确认卡写入链路
class _ProtocolLlmClient extends LlmClient {
  @override
  Future<void> streamChat(
    List<ChatMessage> messages,
    void Function(LlmStreamResponse response) callback, {
    CancelToken? cancelToken,
  }) async {
    const body =
        '王建国这个人物目前的塑造偏单薄，情绪表达直接。\n'
        '[YS_DIAGNOSIS]\n'
        '{"syndromes":[{"syndrome_id":"P001","name":"情绪标签化","severity":"L2",'
        '"evidence":["王建国很生气"],"explanation":"情绪直接点破，未转化为动作"}],'
        '"suggested_actions":["将情绪转化为动作"],"confidence":0.85}\n'
        '[/YS_DIAGNOSIS]\n'
        '[YS_ENTITY]\n'
        '{"entities":[{"type":"character","key":"王建国",'
        '"impressions":[{"text":"巷口沉默，攥拳"}]}]}\n'
        '[/YS_ENTITY]';
    callback(LlmStreamResponse(content: body, isDone: false));
    callback(const LlmStreamResponse(content: '', isDone: true));
  }
}

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async => db.close());

  /// 预置：已完成问卷 + session + 稿 + 章 + 章节主引用
  /// （章节主引用是确认卡写入的硬前置：_applyOutlineEntitiesFromContent
  ///  要求 primaryRef.refType == 'chapter'）
  Future<void> seedSessionWithChapter() async {
    final appStateRepo = AppStateRepository(db);
    await appStateRepo.setQuestionnaireCompleted(true);
    final sessionRepo = SessionRepository(db);
    final sessionId = await sessionRepo.createBlankSession();
    final msRepo = ManuscriptRepository(db);
    final manuscriptId = await msRepo.createManuscript(title: 'UI端到端稿');
    final chRepo = ChapterRepository(db);
    final chapterId = await chRepo.createChapter(
      manuscriptId,
      title: '第一章：巷口',
      content: '王建国站在巷口，夜色沉沉。他想起母亲临终前的话。',
    );
    final refRepo = ReferenceRepository(db);
    await refRepo.addReference(
      sessionId,
      'chapter',
      chapterId,
      isPrimary: true,
    );
  }

  /// 真实 ChatService（全仓储装配）+ Fake LLM 协议块输出
  ChatService buildRealService() {
    return ChatService(
      sessionRepo: SessionRepository(db),
      stateRepo: TeachingStateRepository(db),
      diagnosisRepo: DiagnosisRepository(db),
      studentModelRepo: StudentModelRepository(db),
      referenceRepo: ReferenceRepository(db),
      chapterRepo: ChapterRepository(db),
      manuscriptRepo: ManuscriptRepository(db),
      llmClient: _ProtocolLlmClient(),
      teacherSuggestionRepo: TeacherSuggestionRepository(db),
      editorObservationRepo: EditorObservationRepository(db),
      characterFactRepo: CharacterFactRepository(db),
      eventFactRepo: EventFactRepository(db),
      subplotFactRepo: SubplotFactRepository(db),
      outlineRepo: OutlineRepository(db),
    );
  }

  /// 装配 ChatPage（真实 ChatService + 大视口防懒加载）
  Future<void> pumpChatPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          lastSessionStorageProvider.overrideWithValue(
            MemoryLastSessionStorage(),
          ),
          chatServiceProvider.overrideWithValue(buildRealService()),
        ],
        child: const MaterialApp(home: ChatPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 用户输入 → 点发送（圆形箭头按钮）→ 等待协议块处理完成
  Future<void> sendAndSettle(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.pump();
    await tester.tap(find.widgetWithIcon(FilledButton, Icons.arrow_upward));
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
  }

  /// 读取刚沉淀的大纲实体（E2E 用）
  Future<OutlineEntity?> firstEntity() async {
    final ms = await ManuscriptRepository(db).listManuscripts();
    if (ms.isEmpty) return null;
    final entities = await OutlineRepository(db).listEntities(ms.first.id);
    return entities.isNotEmpty ? entities.first : null;
  }

  group('UI 端到端：确认卡对话流全链路', () {
    testWidgets('E2E-1 发送 → 确认卡渲染 → 点「接受」→ 落库 active + 卡片收起', (tester) async {
      await seedSessionWithChapter();
      await pumpChatPage(tester);

      await sendAndSettle(tester, '帮我分析这段人物描写');

      // 对话流渲染确认卡（服务层写卡 → MessageList 分派）
      expect(find.text('大纲记忆待确认'), findsOneWidget);
      expect(find.text('王建国'), findsOneWidget);
      expect(find.text('巷口沉默，攥拳'), findsOneWidget);
      expect(find.text('新实体'), findsOneWidget);

      // 点「接受」
      await tester.tap(find.text('接受'));
      await tester.pumpAndSettle();

      // 落库：印象 status=active
      final entity = await firstEntity();
      expect(entity, isNotNull, reason: '大纲实体应已沉淀');
      final impressions = await OutlineRepository(
        db,
      ).listImpressions(entity!.id);
      expect(impressions.single.status, 'active');

      // UI：卡片收起为已确认态
      expect(find.text('已确认 1/1 条印象'), findsOneWidget);
      expect(find.text('接受'), findsNothing);
      expect(find.text('拒绝'), findsNothing);
    });

    testWidgets('E2E-2 发送 → 确认卡渲染 → 点「拒绝」→ 落库 rejected + 卡片收起', (tester) async {
      await seedSessionWithChapter();
      await pumpChatPage(tester);

      await sendAndSettle(tester, '帮我分析这段人物描写');

      expect(find.text('大纲记忆待确认'), findsOneWidget);

      await tester.tap(find.text('拒绝'));
      await tester.pumpAndSettle();

      final entity = await firstEntity();
      expect(entity, isNotNull);
      final impressions = await OutlineRepository(
        db,
      ).listImpressions(entity!.id);
      expect(impressions.single.status, 'rejected');

      expect(find.text('已确认 1/1 条印象'), findsOneWidget);
      expect(find.text('接受'), findsNothing);
    });
  });

  group('UI 端到端：诊断卡渲染 + 数据落库联动', () {
    testWidgets('E2E-3 发送 → 诊断结果卡渲染 + diagnosis_results / active_problems 落库', (
      tester,
    ) async {
      await seedSessionWithChapter();
      await pumpChatPage(tester);

      await sendAndSettle(tester, '帮我分析这段人物描写');

      // 对话流渲染诊断结果卡（症候名同时出现在诊断卡与活跃问题面板 → findsWidgets）
      expect(find.text('本次诊断'), findsOneWidget);
      expect(find.text('1 个问题'), findsOneWidget);
      expect(find.text('情绪标签化'), findsWidgets);

      // 数据真实落库（非 seed，走 ChatService.sendMessage 链路）
      final diagRepo = DiagnosisRepository(db);
      final history = await diagRepo.listDiagnosisHistory(
        (await SessionRepository(db).listSessions()).single.id,
      );
      expect(history, isNotEmpty, reason: '诊断结果应落库');
      final active = await diagRepo.listActiveProblems(
        (await SessionRepository(db).listSessions()).single.id,
      );
      expect(
        active.map((p) => p.syndromeId),
        contains('P001'),
        reason: '活跃症候 P001 应落库',
      );
    });
  });
}
