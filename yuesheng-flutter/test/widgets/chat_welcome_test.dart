// ─────────────────────────────────────────────────────────────
// ChatWelcome widget 测试 — 欢迎态
//
// 覆盖路径：
//   1. 精简后不渲染大头像「月」（批次：移除 72px 头像）
//   2. 渲染标题「你好，我是月笙」
//   3. 渲染副标题
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/widgets/chat_welcome.dart';

void main() {
  Widget buildWelcome() {
    return const MaterialApp(home: Scaffold(body: ChatWelcome()));
  }

  testWidgets('#1 精简后不渲染大头像「月」', (tester) async {
    await tester.pumpWidget(buildWelcome());

    // 批次：移除 72px 月笙头像，欢迎区仅保留标题 + 副标题 + 可选按钮
    expect(find.text('月'), findsNothing);
  });

  testWidgets('#2 渲染标题', (tester) async {
    await tester.pumpWidget(buildWelcome());

    expect(find.text('你好，我是月笙'), findsOneWidget);
  });

  testWidgets('#3 渲染副标题', (tester) async {
    await tester.pumpWidget(buildWelcome());

    expect(find.text('你的专属写作教练，随时帮你诊断和提升写作'), findsOneWidget);
  });

  testWidgets('#4 批次62 传 onStartWriting → 显示「去书架写一写」并可点击', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatWelcome(onStartWriting: () => tapped = true),
        ),
      ),
    );

    expect(find.text('去书架写一写'), findsOneWidget);
    await tester.tap(find.text('去书架写一写'));
    expect(tapped, isTrue);
  });

  testWidgets('#5 批次62 未传 onStartWriting → 不显示按钮', (tester) async {
    await tester.pumpWidget(buildWelcome());

    expect(find.text('去书架写一写'), findsNothing);
  });
}
