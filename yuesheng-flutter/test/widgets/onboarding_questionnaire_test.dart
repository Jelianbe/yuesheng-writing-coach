// ─────────────────────────────────────────────────────────────
// OnboardingQuestionnaire widget 测试
// 覆盖关键路径（按风险排序）
//
// ★ 8f6aaf29（2026-09-24）把问卷简化为 1 题：只留关注领域（可多选、可选空），
//   等级/学习偏好走默认值（beginner / mixed）。本文件已同步到单题制语义。
//
// 运行：flutter test test/widgets/onboarding_questionnaire_test.dart
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/types/teaching_types.dart';
import 'package:writingcoach/features/onboarding/onboarding_questionnaire.dart';

void main() {
  // ═══════════════════════════════════════════════════════════
  // 低风险：渲染与可见性
  // ═══════════════════════════════════════════════════════════

  // 路径 #1：visible=false 返回 SizedBox.shrink
  testWidgets('#1 visible=false 时返回零尺寸占位，不渲染 Scaffold', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingQuestionnaire(
          visible: false,
          onComplete: (_) {},
          onSkip: () {},
        ),
      ),
    );

    // 不应渲染问卷标题
    expect(find.text('写作偏好问卷'), findsNothing);
  });

  // ═══════════════════════════════════════════════════════════
  // 单题制：按钮可用性与页面结构
  // ═══════════════════════════════════════════════════════════

  // 路径 #2：单题制下完成按钮初始即可点（关注领域可选空，_canProceed 恒 true）
  testWidgets('#2 单题制：完成按钮初始即可点', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingQuestionnaire(
          visible: true,
          onComplete: (_) {},
          onSkip: () {},
        ),
      ),
    );

    final button = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, '开始写作之旅'),
    );
    expect(button.onPressed, isNotNull);
  });

  // 路径 #3：初始即渲染关注领域题；旧 Q1 文本示例已随简化移除
  testWidgets('#3 初始即渲染 Q2 关注领域页，旧 Q1 不再出现', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingQuestionnaire(
          visible: true,
          onComplete: (_) {},
          onSkip: () {},
        ),
      ),
    );

    expect(find.text('Q2. 你最想提升哪方面？'), findsOneWidget);
    // 旧 3 题制的 Q1 文本示例选项不应再渲染
    expect(find.text('写过一些片段'), findsNothing);
    // 单题制：不存在「下一题」按钮（首页即末页）
    expect(find.widgetWithText(ElevatedButton, '下一题'), findsNothing);
  });

  // 路径 #4：不选任何项，「开始写作之旅」仍可点
  testWidgets('#4 不选任何项时完成按钮仍可点', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingQuestionnaire(
          visible: true,
          onComplete: (_) {},
          onSkip: () {},
        ),
      ),
    );

    final button = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, '开始写作之旅'),
    );
    expect(button.onPressed, isNotNull);
  });

  // ═══════════════════════════════════════════════════════════
  // 中风险：多选行为
  // ═══════════════════════════════════════════════════════════

  // 路径 #5：多选切换（选中 → 取消 → 换选），onComplete 只收到保留项
  testWidgets('#5 选中后再次点击可取消（通过 onComplete 验证 focusAreas 不含该项）', (
    tester,
  ) async {
    OnboardingData? captured;
    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingQuestionnaire(
          visible: true,
          onComplete: (data) => captured = data,
          onSkip: () {},
        ),
      ),
    );

    // 选中"人物塑造"再取消
    await tester.tap(find.text('人物塑造'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('人物塑造'));
    await tester.pumpAndSettle();

    // 选"情节设计"保留
    await tester.tap(find.text('情节设计'));
    await tester.pumpAndSettle();

    // 直接完成（单题制，无下一题）
    await tester.tap(find.widgetWithText(ElevatedButton, '开始写作之旅'));
    await tester.pumpAndSettle();

    // 断言 focusAreas 只含"情节设计"，不含"人物塑造"
    expect(captured, isNotNull);
    expect(captured!.focusAreas, ['情节设计']);
    expect(captured!.focusAreas.contains('人物塑造'), isFalse);
  });

  // 路径 #6：不选任何项直接完成 → onComplete 收到空 focusAreas
  testWidgets('#6 不选任何项直接完成，onComplete 收到空 focusAreas', (tester) async {
    OnboardingData? captured;
    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingQuestionnaire(
          visible: true,
          onComplete: (data) => captured = data,
          onSkip: () {},
        ),
      ),
    );

    await tester.tap(find.widgetWithText(ElevatedButton, '开始写作之旅'));
    await tester.pumpAndSettle();

    expect(captured, isNotNull);
    expect(captured!.focusAreas, isEmpty);
  });

  // ═══════════════════════════════════════════════════════════
  // 高风险：回调契约（必做）
  // ═══════════════════════════════════════════════════════════

  // 路径 #7：完成 → onComplete 被调用，默认值契约正确（单题制：beginner/mixed）
  testWidgets('#7 点击完成，onComplete 收到正确的 OnboardingData（单题制默认值）', (
    tester,
  ) async {
    // 漏洞 2 修复：记录开始时间戳，验证 completedAt 为秒级非毫秒
    final startTs = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    OnboardingData? captured;
    var callCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingQuestionnaire(
          visible: true,
          onComplete: (data) {
            captured = data;
            callCount++;
          },
          onSkip: () {},
        ),
      ),
    );

    // 选两个关注领域（Set 保留插入顺序）
    await tester.tap(find.text('人物塑造'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('情节设计'));
    await tester.pumpAndSettle();

    // 点击完成
    await tester.tap(find.widgetWithText(ElevatedButton, '开始写作之旅'));
    await tester.pumpAndSettle();

    // 断言 onComplete 被调用 1 次
    expect(callCount, 1);
    expect(captured, isNotNull);

    // 断言 OnboardingData 字段（单题制：等级/偏好走默认值）
    expect(captured!.proficiency, ProficiencyLevel.beginner);
    // 漏洞 3 修复：用 unorderedEquals 避免 Set→toList 顺序敏感
    expect(captured!.focusAreas, unorderedEquals(['人物塑造', '情节设计']));
    expect(captured!.cognitiveStyle, CognitiveStyle.mixed);
    expect(captured!.skipped, isFalse);
    expect(captured!.writingGoal, ''); // 写作目标已移除，恒为空串
    // 漏洞 2 修复：验证 completedAt 为秒级时间戳，>= startTs
    expect(captured!.completedAt, greaterThanOrEqualTo(startTs));
    // 额外验证：completedAt 不应是毫秒级（若为毫秒会比 startTs 大 1000 倍以上）
    expect(captured!.completedAt < startTs + 1000, isTrue);
  });

  // 路径 #7b：连点"开始写作之旅"不会重复触发 onComplete
  testWidgets('#7b 连点完成按钮 2 次，onComplete 只被调用 1 次（漏洞 4 修复）', (tester) async {
    var callCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingQuestionnaire(
          visible: true,
          onComplete: (_) {
            callCount++;
          },
          onSkip: () {},
        ),
      ),
    );

    // 快速连续 tap "开始写作之旅" 2 次（中间不 pump）
    await tester.tap(find.widgetWithText(ElevatedButton, '开始写作之旅'));
    await tester.tap(find.widgetWithText(ElevatedButton, '开始写作之旅'));

    // 让 setState 和回调执行
    await tester.pumpAndSettle();

    // 断言 onComplete 只被调用 1 次
    expect(callCount, 1);
  });

  // 路径 #8："跳过问卷"按钮 → onSkip 被调用
  testWidgets('#8 点击跳过问卷触发 onSkip 回调', (tester) async {
    var skipCalled = false;
    var callCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingQuestionnaire(
          visible: true,
          onComplete: (_) {},
          onSkip: () {
            skipCalled = true;
            callCount++;
          },
        ),
      ),
    );

    // 点击"跳过问卷"
    await tester.tap(find.text('跳过问卷'));
    await tester.pumpAndSettle();

    // 断言 onSkip 被调用过一次
    expect(skipCalled, isTrue);
    expect(callCount, 1);
  });

  // ═══════════════════════════════════════════════════════════
  // 可跳过：私有方法保护（已由 UI 行为覆盖）
  // ═══════════════════════════════════════════════════════════

  // 路径 #9：单题制下任何时刻都不存在「上一题」按钮
  testWidgets('#9 单题制无 "上一题" 按钮', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingQuestionnaire(
          visible: true,
          onComplete: (_) {},
          onSkip: () {},
        ),
      ),
    );

    expect(find.text('上一题'), findsNothing);
  });

  // 路径 #11：_handleComplete 的提交中防重入由 #7b 覆盖
  test('#11 提交中防重入（_isSubmitting guard）由 #7b 行为级覆盖，保留占位记录已考虑该路径', () {
    expect(true, isTrue);
  });
}
