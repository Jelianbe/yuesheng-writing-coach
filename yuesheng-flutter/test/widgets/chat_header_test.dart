// ─────────────────────────────────────────────────────────────
// ChatHeader widget 测试 — 聊天头部状态区
//
// 覆盖路径：
//   1. 标题「会话」+ 主引用小字（未关联 / 书名）
//   2. entryPoint='manuscript' → 「诊断模式」徽章
//   3. 汉堡按钮 → onOpenSessionDrawer
//   4. 更多菜单 → 态度档位 + 思考档位 + 画像入口
//   5. 更多菜单选态度 → onAttitudeChange
//   6. 更多菜单点画像 → onOpenProfile
//   7. 批次29 新建对话按钮 → onNewSession
//   8. 批次 TH 三：更多菜单选思考档位 → onReasoningTierChange
//
// 批次 C78-3c：删除「子阶段」菜单相关用例（原子阶段断言 / 切换回调），
// 因 SubphaseIndicator 展示层已废弃（详见 lib/widgets/chat_header.dart 头注）。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/config/reasoning_tier.dart';
import 'package:writingcoach/types/teaching_types.dart';
import 'package:writingcoach/widgets/chat_header.dart';

void main() {
  Widget buildHeader({
    AttitudeLevel attitude = AttitudeLevel.doubao,
    void Function(AttitudeLevel)? onAttitudeChange,
    VoidCallback? onOpenSessionDrawer,
    VoidCallback? onOpenProfile,
    VoidCallback? onNewSession,
    String? entryPoint,
    String? primaryRefTitle,
    VoidCallback? onTapPrimaryRef,
    String reasoningTier = reasoningTierStandard,
    void Function(String)? onReasoningTierChange,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: ChatHeader(
          currentAttitude: attitude,
          onAttitudeChange: onAttitudeChange ?? (_) {},
          onOpenSessionDrawer: onOpenSessionDrawer ?? () {},
          onOpenProfile: onOpenProfile ?? () {},
          onNewSession: onNewSession ?? () {},
          entryPoint: entryPoint,
          primaryRefTitle: primaryRefTitle,
          onTapPrimaryRef: onTapPrimaryRef,
          reasoningTier: reasoningTier,
          onReasoningTierChange: onReasoningTierChange ?? (_) {},
        ),
      ),
    );
  }

  testWidgets('#1 标题「会话」+ 未关联小字', (tester) async {
    await tester.pumpWidget(buildHeader());

    expect(find.text('会话'), findsOneWidget);
    expect(find.text('未关联书籍 · 点此管理'), findsOneWidget);
    expect(find.text('自由对话'), findsNothing);
    expect(find.text('诊断模式'), findsNothing);
  });

  testWidgets('#1b 传 primaryRefTitle → 显示书名小字', (tester) async {
    await tester.pumpWidget(buildHeader(primaryRefTitle: '我的第一本书'));

    expect(find.text('会话'), findsOneWidget);
    expect(find.text('我的第一本书'), findsOneWidget);
    expect(find.text('未关联书籍 · 点此管理'), findsNothing);
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

  testWidgets('#4 更多菜单 → 态度档位 + 思考档位 + 画像', (tester) async {
    await tester.pumpWidget(buildHeader());

    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();

    expect(find.text('态度档位'), findsOneWidget);
    // 批次 TH 三：思考档位段（四档）
    expect(find.text('思考档位'), findsOneWidget);
    for (final preset in reasoningTierPresets) {
      expect(find.text(preset.label), findsOneWidget);
    }
    expect(find.text('画像'), findsOneWidget);
    // 批次 C78-3c：子阶段展示端已废弃，菜单不应再出现
    expect(find.text('子阶段'), findsNothing);
    // 批次 C78-3c-2：引用管理入口已并入标题下方主引用小字，菜单不应再出现
    expect(find.text('引用管理'), findsNothing);
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

  testWidgets('#7 批次29 新建对话按钮（⋯ 左侧）→ onNewSession', (tester) async {
    var created = false;
    await tester.pumpWidget(buildHeader(onNewSession: () => created = true));

    // 按钮存在且可点击
    expect(find.byIcon(Icons.add_comment_outlined), findsOneWidget);
    await tester.tap(find.byIcon(Icons.add_comment_outlined));

    expect(created, isTrue);
  });

  // ════════════════════════════════════════════════════════
  // 批次 TH 三：思考档位（与设置页「模型行为」同源的完整四档入口）
  // ════════════════════════════════════════════════════════

  testWidgets('#8 更多菜单选思考档位 → onReasoningTierChange(key)', (tester) async {
    String? picked;
    await tester.pumpWidget(
      buildHeader(onReasoningTierChange: (key) => picked = key),
    );

    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    await tester.tap(find.text('深度'));
    await tester.pumpAndSettle();

    expect(picked, reasoningTierDeep);
  });

  testWidgets('#8b 选中档位显示其 hint（用户能看到代价说明）', (tester) async {
    await tester.pumpWidget(buildHeader(reasoningTier: reasoningTierOff));

    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();

    expect(find.text(reasoningTierOf(reasoningTierOff).hint), findsOneWidget);
  });

  testWidgets('#8c 默认（未接线）也显示思考档位段（入口不忽隐忽现）', (tester) async {
    await tester.pumpWidget(buildHeader());

    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();

    expect(find.text('思考档位'), findsOneWidget);
    expect(find.text(reasoningTierOf(reasoningTierStandard).hint), findsOneWidget);
  });
}
