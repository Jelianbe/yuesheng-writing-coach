// ─────────────────────────────────────────────────────────────
// ClosedLoopSmokeTest — 教学闭环冒烟（问→诊→教→练→评）
// 在真实 Android 模拟器/真机上运行：
//   真实 UI（WritingCoachPanel）+ 真实 DB + 真实 ChatService 12 步流水线，
//   仅 LLM 响应预置（FakeLlmClient 序列：诊断块 → 教学块 → 训练反馈）
//
// 覆盖（六步教学闭环）：
//   1. 问：面板打开 → 会话初始化
//   2. 写：章节内容（100+ 字过诊断门槛）
//   3. 诊：点「诊断本章」→ DiagnosisCard 出现（YS_DIAGNOSIS 块真实解析）
//   4. 教：TeacherSuggestionCard 出现（YS_TEACHER 块真实解析 + teacher_service 校验）
//   5. 练：点「开始练习」→ PracticeTaskCard 出现
//   6. 评：提交作答 → 训练结果（含「达标」）→ PracticeResultIndicator
//
// 运行：flutter test integration_test/closed_loop_smoke_test.dart -d <device>
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:drift/native.dart';
import 'package:dio/dio.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/chapter_repository.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/providers/app_providers.dart';
import 'package:writingcoach/providers/session_providers.dart';
import 'package:writingcoach/providers/writing_providers.dart';
import 'package:writingcoach/services/llm_client.dart';
import 'package:writingcoach/widgets/diagnosis_card.dart';
import 'package:writingcoach/widgets/evaluation_report_panel.dart';
import 'package:writingcoach/widgets/practice_result_indicator.dart';
import 'package:writingcoach/widgets/practice_task_card.dart';
import 'package:writingcoach/widgets/teacher_suggestion_card.dart';
import 'package:writingcoach/widgets/writing_coach_panel.dart';

/// 诊断 LLM 响应（合法 YS_DIAGNOSIS 块；severity L2 → 触发 Teacher 二次调用）
const String diagResponse = '诊断完成。本章的结构清晰，但情绪描写过于直白。'
    '\n[YS_DIAGNOSIS]'
    '\n{"syndromes":[{"syndrome_id":"s1","name":"叙事含糊","severity":"L2","evidence":[],"explanation":"情绪描写直接说出而非展现"}],"suggested_actions":[],"confidence":0.8}'
    '\n[/YS_DIAGNOSIS]';

/// Teacher LLM 响应（合法 YS_TEACHER 块：teaching_decision + training_task）
const String teacherResponse = '建议：针对「叙事含糊」做一次专项改写练习。'
    '\n[YS_TEACHER]'
    '\n{"teaching_decision":"train","teaching_reason":"症候已确认且需专项练习","natural_language":"建议针对「叙事含糊」做一次改写练习，把情绪写含蓄。","training_task":{"task_type":"rewrite","task_description":"请改写这段对话，让情绪描写更含蓄。","difficulty":"easy","evaluation_criteria":["情绪更含蓄","描写更具体"],"target_syndrome_id":"s1"}}'
    '\n[/YS_TEACHER]';

/// 训练反馈（含「达标」→ parseTrainingResult=passed，保守偏置不虚报）
const String feedbackResponse = '很好，这次练习达标了。情绪描写比之前含蓄多了，继续保持。';

/// 序列响应 Fake LLM：按 streamChat 调用次数依次返回预置响应
class FakeLlmClient extends LlmClient {
  final List<String> responses;
  int calls = 0;

  FakeLlmClient(this.responses);

  @override
  Future<void> streamChat(
    List<ChatMessage> messages,
    void Function(LlmStreamResponse response) callback, {
    CancelToken? cancelToken,
  }) async {
    final body = responses[calls.clamp(0, responses.length - 1)];
    calls++;
    for (var i = 0; i < body.length; i += 10) {
      final end = i + 10 < body.length ? i + 10 : body.length;
      callback(
        LlmStreamResponse(content: body.substring(i, end), isDone: false),
      );
    }
    callback(const LlmStreamResponse(content: '', isDone: true));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late ProviderContainer container;
  late String chapterId;
  late String manuscriptId;

  /// 章节内容（>100 字，过「诊断本章」字数门槛）
  const longContent =
      '这是一个大雪纷飞的夜晚，北风呼啸着穿过空旷的原野。远处的山峦在暮色中显得格外孤寂。'
      '一位旅人独自走在雪地里，身后留下一串深深浅浅的脚印。他裹紧了衣领，呼出的白气在冷风中迅速消散。'
      '前方的村庄亮着几点灯火，像散落在黑绸上的碎金。他加快脚步，靴子踩在积雪上发出咯吱咯吱的声响。'
      '这条路他已经走了整整三天，此刻终于看到了尽头。';

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    final msRepo = ManuscriptRepository(db);
    final chRepo = ChapterRepository(db);
    manuscriptId = await msRepo.createManuscript(title: '闭环冒烟稿');
    chapterId = await chRepo.createChapter(
      manuscriptId,
      title: '第一章：雪夜',
      content: longContent,
    );
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        llmClientProvider.overrideWithValue(
          FakeLlmClient(const [diagResponse, teacherResponse, feedbackResponse]),
        ),
      ],
    );
    // 面板从 WritingStore 读章节内容 → 先加载（否则字数校验拦截诊断）
    await container
        .read(writingStoreProvider(chapterId).notifier)
        .loadChapter();
  });

  tearDown(() {
    container.dispose();
    db.close();
  });

  /// 轮询等待 finder 命中（真实链路多轮异步 await，pumpAndSettle 不足）
  Future<void> waitFor(
    WidgetTester tester,
    Finder finder, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 120));
      if (finder.evaluate().isNotEmpty) return;
    }
    fail('等待超时: $finder');
  }

  testWidgets('教学闭环冒烟：诊→教→练→评 卡片全链路出现', (tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: WritingCoachPanel(
              chapterId: chapterId,
              manuscriptId: manuscriptId,
              chapterTitle: '第一章：雪夜',
              onClose: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // ── 3. 诊：点「诊断本章」→ 等待 DiagnosisCard ──
    await tester.tap(find.text('诊断本章'));
    await waitFor(tester, find.byType(DiagnosisCard));
    expect(find.byType(DiagnosisCard), findsOneWidget, reason: '诊断卡应出现（诊）');

    // ── 4. 教：TeacherSuggestionCard（YS_TEACHER 二次调用解析）──
    await waitFor(tester, find.byType(TeacherSuggestionCard));
    expect(find.text('开始练习'), findsOneWidget, reason: '教学建议卡应出现（教）');
    expect(find.text('叙事含糊'), findsWidgets, reason: '教学卡应显示症候名称');

    // ── 5. 练：点「开始练习」→ PracticeTaskCard ──
    await tester.tap(find.text('开始练习'));
    await waitFor(tester, find.byType(PracticeTaskCard));
    expect(find.byType(PracticeTaskCard), findsOneWidget, reason: '练习任务卡应出现（练）');

    // ── 6. 评：作答 → 提交 → 训练结果指示器 ──
    // 任务卡内作答输入框（限任务卡范围内）
    final answerField = find.descendant(
      of: find.byType(PracticeTaskCard),
      matching: find.byType(TextField),
    );
    expect(answerField, findsOneWidget);
    await tester.enterText(answerField, '他沉默了很久，才缓缓开口，声音比夜色还轻。');
    await tester.tap(find.text('提交作答'));
    await waitFor(tester, find.byType(PracticeResultIndicator));
    expect(
      find.byType(PracticeResultIndicator),
      findsOneWidget,
      reason: '训练结果指示器应出现（评）',
    );
    // 评估报告（T4：训练反馈落库后构建）可能紧随出现
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(
      find.byType(EvaluationReportPanel).evaluate().isNotEmpty ||
          find.byType(PracticeResultIndicator).evaluate().isNotEmpty,
      isTrue,
      reason: '评估报告或结果指示器至少其一在场',
    );
  });
}
