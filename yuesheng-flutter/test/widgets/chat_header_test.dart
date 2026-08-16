// ─────────────────────────────────────────────────────────────
// ChatHeader widget 测试 — 聊天头部状态区
//
// 覆盖路径：
//   1. 标题「会话」+ 入口徽章「自由对话」
//   2. entryPoint='manuscript' → 「诊断模式」徽章
//   3. 汉堡按钮 → onOpenSessionDrawer
//   4. 更多菜单 → 阶段名 + 态度档位 + 子阶段 + 画像入口
//   5. 更多菜单选态度 → onAttitudeChange
//   6. 更多菜单点画像 → onOpenProfile
//   7. 更多菜单点切换 → onNextSubphase
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/types/teaching_types.dart';
import 'package:writingcoach/widgets/chat_header.dart';

void main() {
  Widget buildHeader({
    AttitudeLevel attitude = AttitudeLevel.doubao,
    TeachingPhase phase = TeachingPhase.p0Engage,
    TeachingSubphase? subphase,
    void Function(AttitudeLevel)? onAttitudeChange,
    VoidCallback? onNextSubphase,
    VoidCallback? onOpenSessionDrawer,
    VoidCallback? onOpenProfile,
    VoidCallback? onNewSession,
    VoidCallback? onOpenReferences,
    String? entryPoint,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: ChatHeader(
          currentAttitude: attitude,
          currentPhase: phase,
          currentSubphase: subphase,
          onAttitudeChange: onAttitudeChange ?? (_) {},
          onNextSubphase: onNextSubphase ?? () {},
          onOpenSessionDrawer: onOpenSessionDrawer ?? () {},
          onOpenProfile: onOpenProfile ?? () {},
          onNewSession: onNewSession ?? () {},
          onOpenReferences: onOpenReferences ?? () {},
          entryPoint: entryPoint,
        ),
      ),
    );
  }

  testWidgets('#1 标题「会话」+ 徽章「自由对话」', (tester) async {
    await tester.pumpWidget(buildHeader());

    expect(find.text('会话'), findsOneWidget);
    expect(find.text('自由对话'), findsOneWidget);
    expect(find.text('诊断模式'), findsNothing);
  });

  testWidgets('#2 entryPoint=manuscript → 「诊断模式」', (tester) async {
    await tester.pumpWidget(buildHeader(entryPoint: 'manuscript'));

    expect(find.text('诊断模式'), findsOneWidget);
    expect(find.text('自由对话'), findsNothing);
  });

  testWidgets('#3 汉堡按钮 → onOpenSessionDrawer', (tester) async {
    var opened = false;
    await tester.pumpWidget(
      buildHeader(onOpenSessionDrawer: () => opened = true),
    );

    await tester.tap(find.byIcon(Icons.menu));
    expect(opened, isTrue);
  });

  testWidgets('#4 更多菜单 → 阶段名 + 态度档位 + 子阶段 + 画像', (tester) async {
    await tester.pumpWidget(
      buildHeader(
        phase: TeachingPhase.p2PracticeLoop,
        subphase: TeachingSubphase.practice,
      ),
    );

    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();

    expect(find.text('当前阶段'), findsOneWidget);
    expect(find.text('训练循环'), findsOneWidget);
    expect(find.text('子阶段'), findsOneWidget);
    expect(find.text('练习中'), findsOneWidget);
    expect(find.text('态度档位'), findsOneWidget);
    expect(find.text('画像'), findsOneWidget);
  });

  testWidgets('#5 更多菜单选态度 → onAttitudeChange', (tester) async {
    AttitudeLevel? selected;
    await tester.pumpWidget(buildHeader(onAttitudeChange: (a) => selected = a));

    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    await tester.tap(find.text('sensei'));
    await tester.pumpAndSettle();

    expect(selected, AttitudeLevel.sensei);
  });

  testWidgets('#6 更多菜单点画像 → onOpenProfile', (tester) async {
    var opened = false;
    await tester.pumpWidget(buildHeader(onOpenProfile: () => opened = true));

    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    await tester.tap(find.text('画像'));
    await tester.pumpAndSettle();

    expect(opened, isTrue);
  });

  testWidgets('#7 更多菜单点切换 → onNextSubphase', (tester) async {
    var switched = false;
    await tester.pumpWidget(
      buildHeader(
        subphase: TeachingSubphase.diagnosis,
        onNextSubphase: () => switched = true,
      ),
    );

    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    await tester.tap(find.text('切换'));
    await tester.pumpAndSettle();

    expect(switched, isTrue);
  });

  testWidgets('#8 批次29 新建对话按钮（⋯ 左侧）→ onNewSession', (tester) async {
    var created = false;
    await tester.pumpWidget(buildHeader(onNewSession: () => created = true));

    // 按钮存在且可点击
    expect(find.byIcon(Icons.add_comment_outlined), findsOneWidget);
    await tester.tap(find.byIcon(Icons.add_comment_outlined));

    expect(created, isTrue);
  });
}
