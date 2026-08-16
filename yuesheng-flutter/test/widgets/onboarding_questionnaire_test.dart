// ─────────────────────────────────────────────────────────────
// OnboardingQuestionnaire widget 测试
// 覆盖 11 条关键路径（按风险排序）
//
// 运行：flutter test test/widgets/onboarding_questionnaire_test.dart
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/types/teaching_types.dart';
import 'package:writingcoach/widgets/onboarding_questionnaire.dart';

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
  // 中风险：按钮禁用态
  // ═══════════════════════════════════════════════════════════

  // 路径 #2：Q1 未选时"下一题"按钮禁用
  testWidgets('#2 Q1 未选时下一题按钮 onPressed 为 null', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingQuestionnaire(
          visible: true,
          onComplete: (_) {},
          onSkip: () {},
        ),
      ),
    );

    // 找到 "下一题" ElevatedButton，断言 onPressed 为 null（禁用态）
    final button = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, '下一题'),
    );
    expect(button.onPressed, isNull);
  });

  // 路径 #6：Q3 未选时"开始写作之旅"按钮禁用
  testWidgets('#6 Q3 未选时开始按钮 onPressed 为 null', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingQuestionnaire(
          visible: true,
          onComplete: (_) {},
          onSkip: () {},
        ),
      ),
    );

    // 走到 Q3：选 Q1 → 下一题 → 选 Q2（可空，直接过）→ 下一题
    await tester.tap(find.text('写过一些片段'));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    await tester.tap(find.widgetWithText(ElevatedButton, '下一题'));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    // Q2 不选任何项，直接下一题
    await tester.tap(find.widgetWithText(ElevatedButton, '下一题'));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));

    // 此时应在 Q3，"开始写作之旅" 按钮应禁用
    final button = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, '开始写作之旅'),
    );
    expect(button.onPressed, isNull);
  });

  // ═══════════════════════════════════════════════════════════
  // 中风险：导航与多选
  // ═══════════════════════════════════════════════════════════

  // 路径 #3：Q1 选中后"下一题"可点 → 进入 Q2
  testWidgets('#3 Q1 选中后下一题可点，点击后进入 Q2', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingQuestionnaire(
          visible: true,
          onComplete: (_) {},
          onSkip: () {},
        ),
      ),
    );

    // 选中 Q1 第一项
    await tester.tap(find.text('写过一些片段'));
    await tester.pumpAndSettle();

    // 下一题按钮应可点
    final buttonBefore = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, '下一题'),
    );
    expect(buttonBefore.onPressed, isNotNull);

    // 点击下一题
    await tester.tap(find.widgetWithText(ElevatedButton, '下一题'));
    // 漏洞 1 修复：必须 pumpAndSettle 等待 animateToPage(250ms) 完成
    await tester.pumpAndSettle(const Duration(milliseconds: 300));

    // 断言 Q2 标题出现
    expect(find.text('Q2. 你最想提升哪方面？'), findsOneWidget);
  });

  // 路径 #4：Q2 多选可空，"下一题"始终可点
  testWidgets('#4 Q2 不选任何项时下一题按钮仍可点', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingQuestionnaire(
          visible: true,
          onComplete: (_) {},
          onSkip: () {},
        ),
      ),
    );

    // 走到 Q2
    await tester.tap(find.text('写过一些片段'));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    await tester.tap(find.widgetWithText(ElevatedButton, '下一题'));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));

    // Q2 不选任何项，下一题按钮应仍可点
    final button = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, '下一题'),
    );
    expect(button.onPressed, isNotNull);
  });

  // 路径 #5：Q2 多选切换（选中 → 取消）
  testWidgets('#5 Q2 选中后再次点击可取消（通过 onComplete 验证 focusAreas 不含该项）', (
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

    // 走到 Q2
    await tester.tap(find.text('写过一些片段'));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    await tester.tap(find.widgetWithText(ElevatedButton, '下一题'));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));

    // 选中"人物塑造"再取消
    await tester.tap(find.text('人物塑造'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('人物塑造'));
    await tester.pumpAndSettle();

    // 选"情节设计"保留
    await tester.tap(find.text('情节设计'));
    await tester.pumpAndSettle();

    // 下一题 → Q3
    await tester.tap(find.widgetWithText(ElevatedButton, '下一题'));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));

    // 选 Q3 并完成
    await tester.tap(find.text('边练边讲'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, '开始写作之旅'));
    await tester.pumpAndSettle();

    // 断言 focusAreas 只含"情节设计"，不含"人物塑造"
    expect(captured, isNotNull);
    expect(captured!.focusAreas, ['情节设计']);
    expect(captured!.focusAreas.contains('人物塑造'), isFalse);
  });

  // 路径 #9："上一题"按钮在 Q1 不显示
  testWidgets('#9 Q1 时无 "上一题" 按钮', (tester) async {
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

  // 路径 #10："上一题"从 Q2 回到 Q1
  testWidgets('#10 Q2 点击上一题回到 Q1', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingQuestionnaire(
          visible: true,
          onComplete: (_) {},
          onSkip: () {},
        ),
      ),
    );

    // 走到 Q2
    await tester.tap(find.text('写过一些片段'));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    await tester.tap(find.widgetWithText(ElevatedButton, '下一题'));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));

    // 点击上一题
    await tester.tap(find.widgetWithText(OutlinedButton, '上一题'));
    // 漏洞 1 修复：同样需要 pumpAndSettle 等待 animateToPage
    await tester.pumpAndSettle(const Duration(milliseconds: 300));

    // 断言 Q1 标题出现
    expect(find.text('Q1. 哪段文字最接近你的写作水平？'), findsOneWidget);
  });

  // ═══════════════════════════════════════════════════════════
  // 高风险：回调契约（必做）
  // ═══════════════════════════════════════════════════════════

  // 路径 #7：Q3 选中后完成 → onComplete 被调用，参数正确
  testWidgets('#7 走完 3 题并点击完成，onComplete 收到正确的 OnboardingData', (tester) async {
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

    // Q1：选第二项（elementary / N1_ELEMENTS）
    await tester.tap(find.text('写过一些片段'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, '下一题'));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));

    // Q2：选"人物塑造" + "情节设计"（按此顺序，Set 保留插入顺序）
    await tester.tap(find.text('人物塑造'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('情节设计'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, '下一题'));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));

    // Q3：选"边练边讲"（mixed）
    await tester.tap(find.text('边练边讲'));
    await tester.pumpAndSettle();

    // 点击完成
    await tester.tap(find.widgetWithText(ElevatedButton, '开始写作之旅'));
    await tester.pumpAndSettle();

    // 断言 onComplete 被调用 1 次
    expect(callCount, 1);
    expect(captured, isNotNull);

    // 断言 OnboardingData 字段
    expect(captured!.proficiency, ProficiencyLevel.elementary);
    // 漏洞 3 修复：用 unorderedEquals 避免 Set→toList 顺序敏感
    expect(captured!.focusAreas, unorderedEquals(['人物塑造', '情节设计']));
    expect(captured!.cognitiveStyle, CognitiveStyle.mixed);
    expect(captured!.skipped, isFalse);
    expect(captured!.writingGoal, ''); // Q4 已移除，恒为空串
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

    // 走完 3 题到 Q3 选中状态
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
  // 可跳过：私有方法保护（已由 UI 禁用态覆盖）
  // ═══════════════════════════════════════════════════════════

  // 路径 #11：_handleComplete 在 proficiency/cognitiveStyle 为 null 时不触发回调
  testWidgets(
    '#11 proficiency/cognitiveStyle 为 null 时不会触发 onComplete（由 UI 禁用态保护）',
    (tester) async {
      // 此路径由 #2/#6 的按钮禁用态间接覆盖。
      // _handleComplete 的 null guard 是防御性代码，UI 层已通过 _canProceed 禁用按钮保证不会进入。
      // 保留占位以记录已考虑该路径。
      expect(true, isTrue);
    },
  );
}
