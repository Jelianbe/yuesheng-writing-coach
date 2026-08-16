// ─────────────────────────────────────────────────────────────
// TeacherSuggestionCard 组件测试
//
// 覆盖（记忆硬约束）：
//   1. 渲染症候名称（而非代号）+ 三按钮
//   2. 点击「开始练习」→ onStartPractice 回调（无回调时 SnackBar）
//   3. 点击「跳过此建议」→ 卡片隐藏 + teacher_suggestion 落库 resolved
//   4. 点击「查看详情」→ 展开任务类型 + 评估标准
//   5. fromMessageContent JSON 解析 + 兜底
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/data/repositories/teacher_suggestion_repository.dart';
import 'package:writingcoach/providers/app_providers.dart';
import 'package:writingcoach/providers/practice_providers.dart';
import 'package:writingcoach/services/message_card_service.dart';
import 'package:writingcoach/widgets/teacher_suggestion_card.dart';

/// 标准 payload（症候名称而非代号）
TeacherSuggestionCardPayload buildPayload({
  String suggestionId = 'sug-1',
  List<String> locationMarks = const [],
}) {
  return TeacherSuggestionCardPayload(
    suggestionId: suggestionId,
    teachingDecision: 'guide',
    naturalLanguage: '情绪标签化让读者出戏，试着把「他很生气」改成动作与细节。',
    taskType: 'rewrite',
    taskDescription: '找出章节中 3 处情绪标签化表达，改写成动作与感官细节。',
    difficulty: 'medium',
    evaluationCriteria: ['避免直接使用情绪词', '用动作/环境侧面烘托', '改写后不影响叙事节奏'],
    targetSyndromeId: 'P003',
    targetSyndromeName: '情绪标签化',
    source: 'diagnosis',
    locationMarks: locationMarks,
  );
}

Widget wrap(Widget child, {ProviderContainer? container}) {
  if (container != null) {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: Scaffold(body: child)),
    );
  }
  return ProviderScope(
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

void main() {
  group('TeacherSuggestionCard', () {
    testWidgets('#1 渲染症候名称（而非代号）+ 三按钮 + 任务描述', (tester) async {
      await tester.pumpWidget(
        wrap(
          SingleChildScrollView(
            child: TeacherSuggestionCard(payload: buildPayload()),
          ),
        ),
      );

      // 症候名称 chip（不是 P003）
      expect(find.text('情绪标签化'), findsOneWidget);
      expect(find.text('P003'), findsNothing);
      // 难度徽标（medium → 进阶）
      expect(find.text('进阶'), findsOneWidget);
      // 任务描述
      expect(find.textContaining('找出章节中 3 处'), findsOneWidget);
      // 三按钮
      expect(find.text('开始练习'), findsOneWidget);
      expect(find.text('跳过此建议'), findsOneWidget);
      expect(find.text('查看详情'), findsOneWidget);
      // 详情初始收起
      expect(find.text('任务类型：'), findsNothing);
    });

    testWidgets('#2 点击「开始练习」→ 触发 onStartPractice 回调', (tester) async {
      bool started = false;
      await tester.pumpWidget(
        wrap(
          TeacherSuggestionCard(
            payload: buildPayload(),
            onStartPractice: () => started = true,
          ),
        ),
      );

      await tester.tap(find.text('开始练习'));
      await tester.pump();

      expect(started, isTrue);
    });

    testWidgets('#3 无回调时点击「开始练习」→ 启动练习任务（T3 接入训练系统）', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        wrap(
          TeacherSuggestionCard(payload: buildPayload()),
          container: container,
        ),
      );

      await tester.tap(find.text('开始练习'));
      await tester.pump();

      // T3：不再弹 SnackBar 占位，而是写入 practiceStore 启动练习任务
      final practiceState = container.read(practiceStoreProvider);
      expect(practiceState.activePracticeTask, isNotNull);
      expect(practiceState.activePracticeTask!.syndromeName, '情绪标签化');
      expect(
        practiceState.activePracticeTask!.taskDescription,
        contains('找出章节中 3 处'),
      );
    });

    testWidgets('#4 点击「查看详情」→ 展开任务类型 + 评估标准', (tester) async {
      await tester.pumpWidget(
        wrap(
          SingleChildScrollView(
            child: TeacherSuggestionCard(payload: buildPayload()),
          ),
        ),
      );

      await tester.tap(find.text('查看详情'));
      await tester.pumpAndSettle();

      // 展开后可见
      expect(find.text('任务类型：'), findsOneWidget);
      expect(find.text('改写'), findsOneWidget);
      expect(find.text('评估标准：'), findsOneWidget);
      expect(find.textContaining('避免直接使用情绪词'), findsOneWidget);
      // 按钮变「收起详情」
      expect(find.text('收起详情'), findsOneWidget);
    });

    testWidgets('#5 点击「跳过此建议」→ 卡片隐藏 + 落库 dismissed（批次62）', (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final container = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
      );
      addTearDown(() {
        container.dispose();
        db.close();
      });

      final sessionId = await SessionRepository(db).createBlankSession();
      final repo = TeacherSuggestionRepository(db);
      // messageId 外键指向 messages 表，需先创建真实消息
      final messageId = await SessionRepository(
        db,
      ).addMessage(sessionId, 'assistant', '诊断说明');
      final suggestionId = await repo.insertTeacherSuggestion(
        InsertTeacherSuggestionParams(
          sessionId: sessionId,
          messageId: messageId,
          source: 'diagnosis',
          teachingDecision: 'guide',
          targetSyndromeId: 'P003',
          taskType: 'rewrite',
          taskDescription: '找出章节中 3 处情绪标签化表达，改写成动作与感官细节。',
          difficulty: 'medium',
          evaluationCriteria: const ['避免直接使用情绪词'],
        ),
      );

      await tester.pumpWidget(
        wrap(
          SingleChildScrollView(
            child: TeacherSuggestionCard(
              payload: buildPayload(suggestionId: suggestionId),
            ),
          ),
          container: container,
        ),
      );

      await tester.tap(find.text('跳过此建议'));
      await tester.pumpAndSettle();

      // 卡片隐藏
      expect(find.text('开始练习'), findsNothing);
      // 落库 dismissed（不再仅是 resolved）
      final active = await repo.getActiveSuggestions(sessionId);
      expect(active, isEmpty);
      final rows = await db.select(db.teacherSuggestions).get();
      expect(rows, hasLength(1));
      expect(rows.first.dismissedAt, isNotNull);
      expect(rows.first.adoptedAt, isNull);
    });

    testWidgets('#5b 批次75 跳过已持久化 → 卡片重建不重现（滚动回收不再出现）', (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final container = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
      );
      addTearDown(() {
        container.dispose();
        db.close();
      });

      final sessionId = await SessionRepository(db).createBlankSession();
      final repo = TeacherSuggestionRepository(db);
      final messageId = await SessionRepository(
        db,
      ).addMessage(sessionId, 'assistant', '诊断说明');
      final suggestionId = await repo.insertTeacherSuggestion(
        InsertTeacherSuggestionParams(
          sessionId: sessionId,
          messageId: messageId,
          source: 'diagnosis',
          teachingDecision: 'guide',
          targetSyndromeId: 'P003',
          taskType: 'rewrite',
          taskDescription: '找出章节中 3 处情绪标签化表达，改写成动作与感官细节。',
          difficulty: 'medium',
          evaluationCriteria: const ['避免直接使用情绪词'],
        ),
      );
      // 模拟上一轮已跳过（落库持久态）
      await repo.markDismissed(suggestionId);

      // 重建卡片（如滚动回收后重新构建）→ 初始即隐藏
      await tester.pumpWidget(
        wrap(
          SingleChildScrollView(
            child: TeacherSuggestionCard(
              payload: buildPayload(suggestionId: suggestionId),
            ),
          ),
          container: container,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('开始练习'), findsNothing);
      expect(find.text('跳过此建议'), findsNothing);
      // isDismissed 反查正确
      expect(await repo.isDismissed(suggestionId), isTrue);
    });

    testWidgets('#10 批次62 点击「开始练习」→ 落库 adoptedAt', (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final container = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
      );
      addTearDown(() {
        container.dispose();
        db.close();
      });

      final sessionId = await SessionRepository(db).createBlankSession();
      final repo = TeacherSuggestionRepository(db);
      final messageId = await SessionRepository(
        db,
      ).addMessage(sessionId, 'assistant', '诊断说明');
      final suggestionId = await repo.insertTeacherSuggestion(
        InsertTeacherSuggestionParams(
          sessionId: sessionId,
          messageId: messageId,
          source: 'diagnosis',
          teachingDecision: 'guide',
          targetSyndromeId: 'P003',
          taskType: 'rewrite',
          taskDescription: '找出章节中 3 处情绪标签化表达，改写成动作与感官细节。',
          difficulty: 'medium',
          evaluationCriteria: const ['避免直接使用情绪词'],
        ),
      );

      await tester.pumpWidget(
        wrap(
          SingleChildScrollView(
            child: TeacherSuggestionCard(
              payload: buildPayload(suggestionId: suggestionId),
            ),
          ),
          container: container,
        ),
      );

      await tester.tap(find.text('开始练习'));
      await tester.pump();

      // 采纳回写：adoptedAt 非空 + 状态 resolved
      final rows = await db.select(db.teacherSuggestions).get();
      expect(rows, hasLength(1));
      expect(rows.first.adoptedAt, isNotNull);
      expect(rows.first.dismissedAt, isNull);
      expect(rows.first.status, 'resolved');
      // 批次75：采纳 ≠ 跳过，isDismissed 应为 false（不影响采纳卡片持久态）
      expect(await repo.isDismissed(suggestionId), isFalse);
    });

    testWidgets('#6 fromMessageContent JSON 解析 + 非法 JSON 兜底', (tester) async {
      // 正常解析
      final content =
          '{"suggestionId":"sug-2","teachingDecision":"train","naturalLanguage":"继续训练","taskType":"analyze","taskDescription":"分析节奏","difficulty":"easy","evaluationCriteria":["标准1"],"targetSyndromeId":"P005","targetSyndromeName":"视角漂移","source":"diagnosis"}';
      await tester.pumpWidget(
        wrap(TeacherSuggestionCard.fromMessageContent(content)),
      );

      expect(find.text('视角漂移'), findsOneWidget);
      expect(find.text('入门'), findsOneWidget);
      expect(find.textContaining('分析节奏'), findsOneWidget);

      // 非法 JSON → 兜底空卡（不崩溃）
      await tester.pumpWidget(
        wrap(TeacherSuggestionCard.fromMessageContent('not-json')),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('TeacherSuggestionCard 教我原理（批次61）', () {
    testWidgets('#7 渲染「教我原理」按钮（两行布局，四按钮齐全）', (tester) async {
      await tester.pumpWidget(
        wrap(
          TeacherSuggestionCard(
            payload: buildPayload(),
            onTeachPrinciple: (_) {},
          ),
        ),
      );

      expect(find.text('开始练习'), findsOneWidget);
      expect(find.text('跳过此建议'), findsOneWidget);
      expect(find.text('查看详情'), findsOneWidget);
      expect(find.text('教我原理'), findsOneWidget);
    });

    testWidgets('#8 点击「教我原理」→ 触发 onTeachPrinciple 回调（传症候名）', (tester) async {
      String? received;
      await tester.pumpWidget(
        wrap(
          TeacherSuggestionCard(
            payload: buildPayload(),
            onTeachPrinciple: (name) => received = name,
          ),
        ),
      );

      await tester.tap(find.text('教我原理'));
      await tester.pump();

      expect(received, '情绪标签化');
    });

    testWidgets('#9 无回调时点击「教我原理」→ SnackBar 兜底提示', (tester) async {
      await tester.pumpWidget(
        wrap(TeacherSuggestionCard(payload: buildPayload())),
      );

      await tester.tap(find.text('教我原理'));
      await tester.pump();

      expect(find.textContaining('情绪标签化'), findsWidgets);
      expect(find.textContaining('会在后续对话中讲解'), findsOneWidget);
    });
  });

  group('TeacherSuggestionCard 标注位置（批次63 B62d）', () {
    testWidgets('#11 有 locationMarks → 渲染「标注位置」按钮', (tester) async {
      await tester.pumpWidget(
        wrap(
          SingleChildScrollView(
            child: TeacherSuggestionCard(
              payload: buildPayload(
                locationMarks: const ['第2段：他低声说道……', '第5段：她看着窗外……'],
              ),
            ),
          ),
        ),
      );

      expect(find.text('标注位置'), findsOneWidget);
    });

    testWidgets('#12 点击「标注位置」→ 展开位置清单（自查不改写）', (tester) async {
      await tester.pumpWidget(
        wrap(
          SingleChildScrollView(
            child: TeacherSuggestionCard(
              payload: buildPayload(
                locationMarks: const ['第2段：他低声说道……', '第5段：她看着窗外……'],
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('标注位置'));
      await tester.pump();

      // 位置清单展开
      expect(find.textContaining('问题位置'), findsOneWidget);
      expect(find.text('第2段：他低声说道……'), findsOneWidget);
      expect(find.text('第5段：她看着窗外……'), findsOneWidget);
      // 按钮切换为「收起位置」
      expect(find.text('收起位置'), findsOneWidget);
    });

    testWidgets('#13 无 locationMarks → 不渲染「标注位置」按钮（向后兼容）', (tester) async {
      await tester.pumpWidget(
        wrap(TeacherSuggestionCard(payload: buildPayload())),
      );

      expect(find.text('标注位置'), findsNothing);
      // 原有四按钮仍在
      expect(find.text('开始练习'), findsOneWidget);
      expect(find.text('跳过此建议'), findsOneWidget);
      expect(find.text('查看详情'), findsOneWidget);
      expect(find.text('教我原理'), findsOneWidget);
    });
  });
}
