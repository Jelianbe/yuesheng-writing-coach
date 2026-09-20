// ─────────────────────────────────────────────────────────────
// TaskPanel widget 测试 — 活跃问题面板
//
// 真源：RN TaskPanel.tsx（教学建议部分已按记忆约束移除）
// 覆盖：
//   1. 空列表 → 空态（暂无活跃问题 + 完成诊断后会显示需要解决的问题）
//   2. 有列表 → 练习任务 + N 个问题徽标 + 症候名 + 严重度标签
//   3. severity 中文标签映射（L1 建议 / L2 注意 / L3 严重）
//   4. 有 onMarkComplete → 完成按钮；点击触发回调
//   5. 无 onMarkComplete → 不显示完成按钮
// ─────────────────────────────────────────────────────────────

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/data/repositories/diagnosis_repository.dart';
import 'package:writingcoach/widgets/task_panel.dart';

void main() {
  Widget buildPanel(TaskPanel panel) {
    return MaterialApp(home: Scaffold(body: panel));
  }

  ActiveProblemView problem(String id, String name, String severity) {
    return ActiveProblemView(
      syndromeId: id,
      syndromeName: name,
      severity: severity,
      confirmationStatus: 'suspected',
    );
  }

  testWidgets('#1 空列表 → 空态', (tester) async {
    await tester.pumpWidget(buildPanel(const TaskPanel(problems: [])));

    expect(find.text('暂无活跃问题'), findsOneWidget);
    expect(find.text('完成诊断后会显示需要解决的问题'), findsOneWidget);
    expect(find.text('练习任务'), findsNothing);
  });

  testWidgets('#2 有列表 → 练习任务 + N 个问题 + 症候名 + 严重度标签', (tester) async {
    await tester.pumpWidget(
      buildPanel(
        TaskPanel(
          problems: [
            problem('P001', '视角跳跃症', 'L1'),
            problem('P002', '对话生硬', 'L2'),
          ],
          onMarkComplete: (_) {},
        ),
      ),
    );

    expect(find.text('练习任务'), findsOneWidget);
    expect(find.text('2 个问题'), findsOneWidget);
    expect(find.text('视角跳跃症'), findsOneWidget);
    expect(find.text('对话生硬'), findsOneWidget);
    // 严重度中文标签
    expect(find.text('建议'), findsOneWidget);
    expect(find.text('注意'), findsOneWidget);
  });

  testWidgets('#3 severity 标签映射：L3 → 严重', (tester) async {
    await tester.pumpWidget(
      buildPanel(
        TaskPanel(
          problems: [problem('P001', '逻辑断裂', 'L3')],
          onMarkComplete: (_) {},
        ),
      ),
    );

    expect(find.text('严重'), findsOneWidget);
  });

  testWidgets('#4 点击完成 → onMarkComplete(syndromeId)', (tester) async {
    String? completedId;

    await tester.pumpWidget(
      buildPanel(
        TaskPanel(
          problems: [problem('P001', '视角跳跃症', 'L2')],
          onMarkComplete: (id) => completedId = id,
        ),
      ),
    );

    await tester.tap(find.text('完成'));
    await tester.pump();

    expect(completedId, 'P001');
  });

  testWidgets('#5 无 onMarkComplete → 不显示完成按钮', (tester) async {
    await tester.pumpWidget(
      buildPanel(TaskPanel(problems: [problem('P001', '视角跳跃症', 'L2')])),
    );

    expect(find.text('完成'), findsNothing);
    expect(find.text('视角跳跃症'), findsOneWidget);
  });

  testWidgets('#6 批次75 有 onRemove → 渲染移除按钮；点击触发回调', (tester) async {
    String? removedId;
    await tester.pumpWidget(
      buildPanel(
        TaskPanel(
          problems: [problem('P001', '视角跳跃症', 'L2')],
          onMarkComplete: (_) {},
          onRemove: (id) => removedId = id,
        ),
      ),
    );

    expect(find.text('移除'), findsOneWidget);
    await tester.tap(find.text('移除'));
    await tester.pump();
    expect(removedId, 'P001');
  });

  testWidgets('#7 批次75 无 onRemove → 不显示移除按钮', (tester) async {
    await tester.pumpWidget(
      buildPanel(
        TaskPanel(
          problems: [problem('P001', '视角跳跃症', 'L2')],
          onMarkComplete: (_) {},
        ),
      ),
    );

    expect(find.text('移除'), findsNothing);
    expect(find.text('完成'), findsOneWidget);
  });

  // ── 交互批 #5：「练」常驻可达点（页脚自选入口）三态钉 ──

  testWidgets('#8 非空 + onSelfPractice → 页脚入口在场且点击可达', (tester) async {
    var opened = 0;
    await tester.pumpWidget(
      buildPanel(
        TaskPanel(
          problems: [problem('P001', '视角跳跃症', 'L2')],
          onSelfPractice: () => opened++,
        ),
      ),
    );
    expect(find.text('换个问题练？自选练习'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('self-practice-footer')));
    expect(opened, 1);
  });

  testWidgets('#9 判别：非空但未注入回调 → 页脚不渲染（不留假按钮）', (tester) async {
    await tester.pumpWidget(
      buildPanel(
        TaskPanel(
          problems: [problem('P001', '视角跳跃症', 'L2')],
          onMarkComplete: (_) {},
        ),
      ),
    );
    expect(find.text('换个问题练？自选练习'), findsNothing);
    // 阳性对照：列表本身在场（防「整列没渲染」冒充 findsNothing 假绿）
    expect(find.text('练习任务'), findsOneWidget);
  });

  testWidgets('#10 判别：空态即使注入回调也不显示页脚（空候选给按钮=假按钮）', (tester) async {
    await tester.pumpWidget(
      buildPanel(TaskPanel(problems: const [], onSelfPractice: () {})),
    );
    expect(find.text('暂无活跃问题'), findsOneWidget); // 阳性对照：空态已渲染
    expect(find.text('换个问题练？自选练习'), findsNothing);
  });

  test('#11 源码对账：自选练习唯一实存在，两处接线引用同一函数（防 copy 复辟）', () {
    // #6/V-5 教训：共享逻辑一旦私有化在消费文件里，第二处必然复制。
    final impl = File('lib/widgets/chat_self_practice.dart').readAsStringSync();
    final sections = File(
      'lib/widgets/chat_page_sections.dart',
    ).readAsStringSync();
    final body = File('lib/widgets/chat_page_body.dart').readAsStringSync();
    expect(impl.contains('void openSelfPracticeSheet('), isTrue);
    expect(sections.contains('openSelfPracticeSheet(context, ref'), isTrue);
    expect(body.contains('openSelfPracticeSheet(context, ref'), isTrue);
    // 旧私有实现必须绝迹（出现 = 有人把逻辑抄回了消费文件）
    expect(sections.contains('_openSelfPractice'), isFalse);
    expect(body.contains('_openSelfPractice'), isFalse);
  });
}
