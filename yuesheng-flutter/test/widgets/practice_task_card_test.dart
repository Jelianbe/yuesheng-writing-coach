// ─────────────────────────────────────────────────────────────
// PracticeTaskCard widget 测试 — 练习任务卡片（T3 训练系统）
//
// 覆盖路径：
//   #1 渲染：Header + 症候 chip + 任务描述 + 目标 + 作答输入 + 跳过/提交
//   #2 空作答提交 → 不触发 onSubmit
//   #3 输入作答后提交 → 触发 onSubmit（内容已 trim）
//   #4 点击跳过 → 触发 onSkip
//   #5 submitting=true → 按钮禁用 + 提交中指示器
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/providers/practice_providers.dart';
import 'package:writingcoach/types/teaching_types.dart';
import 'package:writingcoach/widgets/practice_task_card.dart';

/// 标准练习任务
PracticeTask buildTask() {
  return const PracticeTask(
    syndromeId: 'P003',
    syndromeName: '情绪标签化',
    taskDescription: '找出章节中 3 处情绪标签化表达，改写成动作与感官细节。',
    taskGoal: '对照评估标准：避免直接使用情绪词；用动作/环境侧面烘托',
  );
}

Widget buildCard({
  required void Function(String content, TrainingSelfAssessment? assessment)
  onSubmit,
  required VoidCallback onSkip,
  bool submitting = false,
}) {
  return MaterialApp(
    home: Scaffold(
      body: PracticeTaskCard(
        task: buildTask(),
        submitting: submitting,
        onSubmit: onSubmit,
        onSkip: onSkip,
      ),
    ),
  );
}

void main() {
  group('PracticeTaskCard', () {
    testWidgets('#1 渲染 Header + 症候 chip + 描述 + 目标 + 输入 + 按钮', (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(buildCard(onSubmit: (_, _) {}, onSkip: () {}));

      expect(find.text('练习任务'), findsOneWidget);
      expect(find.text('情绪标签化'), findsOneWidget);
      expect(find.text('任务描述'), findsOneWidget);
      expect(find.textContaining('找出章节中 3 处'), findsOneWidget);
      expect(find.text('练习目标'), findsOneWidget);
      expect(find.textContaining('避免直接使用情绪词'), findsOneWidget);
      expect(find.byType(TextField), findsNWidgets(3));
      expect(find.text('跳过'), findsOneWidget);
      expect(find.text('提交作答'), findsOneWidget);
    });

    testWidgets('#2 空作答提交 → 不触发 onSubmit', (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      bool submitted = false;
      await tester.pumpWidget(
        buildCard(onSubmit: (_, _) => submitted = true, onSkip: () {}),
      );

      await tester.tap(find.text('提交作答'));
      await tester.pump();

      expect(submitted, isFalse);
    });

    testWidgets('#3 输入作答后提交 → 触发 onSubmit（trim 后内容）', (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      String? submittedContent;
      await tester.pumpWidget(
        buildCard(onSubmit: (c, _) => submittedContent = c, onSkip: () {}),
      );

      await tester.enterText(find.byType(TextField).first, '  他攥紧拳头，指节发白。  ');
      await tester.tap(find.text('提交作答'));
      await tester.pump();

      expect(submittedContent, '他攥紧拳头，指节发白。');
    });

    testWidgets('#4 点击跳过 → 触发 onSkip', (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      bool skipped = false;
      await tester.pumpWidget(
        buildCard(onSubmit: (_, _) {}, onSkip: () => skipped = true),
      );

      await tester.tap(find.text('跳过'));
      await tester.pump();

      expect(skipped, isTrue);
    });

    testWidgets('#5 submitting=true → 输入禁用 + 提交按钮显示加载中', (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        buildCard(onSubmit: (_, _) {}, onSkip: () {}, submitting: true),
      );

      final textField = tester.widget<TextField>(find.byType(TextField).first);
      expect(textField.enabled, isFalse);
      // 提交中不显示文字按钮（显示 CircularProgressIndicator）
      expect(find.text('提交作答'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('#6 自评区渲染：信心 1-5 + 解释 + 迁移', (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(buildCard(onSubmit: (_, _) {}, onSkip: () {}));

      expect(find.text('提交前自评（可选）'), findsOneWidget);
      expect(find.textContaining('你觉得这次改得怎么样'), findsOneWidget);
      for (var i = 1; i <= 5; i++) {
        expect(find.text('$i'), findsOneWidget);
      }
      expect(find.byType(TextField), findsNWidgets(3));
      expect(find.textContaining('为什么这样改'), findsOneWidget);
      expect(find.textContaining('如果换个写法'), findsOneWidget);
    });

    testWidgets('#7 填完自评后提交 → onSubmit 收到 assessment', (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      TrainingSelfAssessment? captured;
      String? content;
      await tester.pumpWidget(
        buildCard(
          onSubmit: (c, a) {
            content = c;
            captured = a;
          },
          onSkip: () {},
        ),
      );

      await tester.enterText(find.byType(TextField).first, '他攥紧拳头。');
      await tester.enterText(find.byType(TextField).at(1), '因为写出了动作。');
      await tester.enterText(find.byType(TextField).at(2), '换成环境先写声音。');
      await tester.tap(find.text('3'));
      await tester.pump();
      await tester.tap(find.text('提交作答'));
      await tester.pump();

      expect(content, '他攥紧拳头。');
      expect(captured, isNotNull);
      expect(captured!.confidenceRating, 3);
      expect(captured!.explanationText, contains('动作'));
      expect(captured!.transferText, contains('声音'));
    });

    testWidgets('#8 不填自评提交 → assessment = null', (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      TrainingSelfAssessment? captured;
      await tester.pumpWidget(
        buildCard(onSubmit: (_, a) => captured = a, onSkip: () {}),
      );

      await tester.enterText(find.byType(TextField).first, '只写作答不自评。');
      await tester.tap(find.text('提交作答'));
      await tester.pump();

      expect(captured, isNull);
    });

    // ── 批1·N2：回忆难度自评 4 按钮 ──
    testWidgets('#9 回忆难度 4 按钮渲染', (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(buildCard(onSubmit: (_, _) {}, onSkip: () {}));

      expect(find.textContaining('这次练习对你来说有多难'), findsOneWidget);
      expect(find.text('再来一次'), findsOneWidget);
      expect(find.text('有点难'), findsOneWidget);
      expect(find.text('还行'), findsOneWidget);
      expect(find.text('很轻松'), findsOneWidget);
    });

    testWidgets('#10 仅选难度提交 → assessment 非 null 且 userRating 落库值正确', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      TrainingSelfAssessment? captured;
      await tester.pumpWidget(
        buildCard(onSubmit: (_, a) => captured = a, onSkip: () {}),
      );

      await tester.enterText(find.byType(TextField).first, '只选难度。');
      await tester.tap(find.text('很轻松'));
      await tester.pump();
      await tester.tap(find.text('提交作答'));
      await tester.pump();

      // 难度单独也算「填了自评」（hasAny 判据含 _userRating）
      expect(captured, isNotNull);
      expect(captured!.userRating, 'easy');
      // 三维互不干扰：未填仍为 null
      expect(captured!.confidenceRating, isNull);
      expect(captured!.explanationText, isNull);
      expect(captured!.transferText, isNull);
    });

    testWidgets('#11 难度为单选：改选后只保留最后一档', (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      TrainingSelfAssessment? captured;
      await tester.pumpWidget(
        buildCard(onSubmit: (_, a) => captured = a, onSkip: () {}),
      );

      await tester.enterText(find.byType(TextField).first, '先选再改。');
      await tester.tap(find.text('有点难'));
      await tester.pump();
      await tester.tap(find.text('再来一次'));
      await tester.pump();
      await tester.tap(find.text('提交作答'));
      await tester.pump();

      expect(captured!.userRating, 'again');
    });
  });
}
