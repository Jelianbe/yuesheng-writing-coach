// ─────────────────────────────────────────────────────────────
// setting_description_card_test — 设定库第四批：正文卡 Widget 测试
//
// 覆盖：
//   1. 有正文 → 展示正文 + 编辑按钮
//   2. 无正文 → 占位引导（点按触发 onEdit）
//   3. 编辑弹窗 → 取消 null / 保存返回 trim 后正文
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/widgets/setting/setting_description_card.dart';

void main() {
  Widget host({String description = '', required VoidCallback onEdit}) {
    return MaterialApp(
      home: Scaffold(
        body: SettingDescriptionCard(description: description, onEdit: onEdit),
      ),
    );
  }

  testWidgets('#1 有正文 → 展示正文 + 编辑按钮', (tester) async {
    await tester.pumpWidget(host(description: '灵气浓度由北方向南方递减。', onEdit: () {}));
    expect(find.text('设定正文'), findsOneWidget);
    expect(find.textContaining('灵气浓度'), findsOneWidget);
    expect(find.text('编辑'), findsOneWidget);
    expect(find.textContaining('尚未写设定正文'), findsNothing);
  });

  testWidgets('#2 无正文 → 占位引导，点按触发编辑', (tester) async {
    var edited = false;
    await tester.pumpWidget(
      host(description: '   ', onEdit: () => edited = true),
    );
    expect(find.textContaining('尚未写设定正文'), findsOneWidget);
    await tester.tap(find.textContaining('尚未写设定正文'));
    expect(edited, isTrue);
  });

  testWidgets('#3 编辑弹窗：保存返回正文', (tester) async {
    String? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (ctx) => Center(
            child: FilledButton(
              onPressed: () async {
                result = await showDescriptionEditDialog(ctx, initial: '旧正文');
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('编辑设定正文'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '  新正文内容  ');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(result, '新正文内容');
  });

  testWidgets('#4 编辑弹窗：取消返回 null', (tester) async {
    String? result = 'sentinel';
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (ctx) => Center(
            child: FilledButton(
              onPressed: () async {
                result = await showDescriptionEditDialog(ctx, initial: '旧');
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(result, isNull);
  });
}
