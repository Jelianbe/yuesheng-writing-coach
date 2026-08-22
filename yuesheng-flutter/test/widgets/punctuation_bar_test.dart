// ─────────────────────────────────────────────────────────────
// PunctuationBar widget 测试 — 中文标点符号栏
//
// 覆盖路径：
//   1. 渲染 15 个标点按钮（且均可点击）
//   2. 点击标点 → onTap 收到对应字符
//   3. 点击换行(↵) → onTap 收到 '\n'
//   4. 背景色为 #F7F8F6
//   5. visibleIds 过滤 + 按配置顺序渲染（批次86-2）
//   6. visibleIds 含未知 id → 忽略
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/widgets/punctuation_bar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpBar(
    WidgetTester tester, {
    required void Function(String) onTap,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: PunctuationBar(onTap: onTap)),
      ),
    );
  }

  group('PunctuationBar', () {
    testWidgets('渲染 15 个标点按钮 + 2 个撤销/重做操作项（可点击）', (tester) async {
      final calls = <String>[];
      await pumpBar(tester, onTap: calls.add);

      // 15 个标点 + 2 个操作项 = 17 个可点击区域（批次91-3）
      expect(find.byType(GestureDetector), findsNWidgets(17));
      // 15 个标点文本标签（操作项是图标，非文本）
      expect(find.byType(Text), findsNWidgets(15));
      // 批次91-3：撤销/重做图标常驻最前
      expect(find.byIcon(Icons.undo), findsOneWidget);
      expect(find.byIcon(Icons.redo), findsOneWidget);
    });

    testWidgets('批次91-3 点击撤销/重做 → onUndo/onRedo 回调', (tester) async {
      var undoCount = 0;
      var redoCount = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PunctuationBar(
              onTap: (_) {},
              onUndo: () => undoCount++,
              onRedo: () => redoCount++,
            ),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.undo));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.redo));
      await tester.pump();

      expect(undoCount, 1);
      expect(redoCount, 1);
    });

    testWidgets('点击标点 → onTap 收到对应字符', (tester) async {
      final calls = <String>[];
      await pumpBar(tester, onTap: calls.add);

      await tester.tap(find.text('，'));
      await tester.pump();

      expect(calls, ['，']);
    });

    testWidgets('点击换行(↵)按钮 → onTap 收到 "\\n"', (tester) async {
      final calls = <String>[];
      await pumpBar(tester, onTap: calls.add);

      await tester.tap(find.text('换行'));
      await tester.pump();

      expect(calls, ['\n']);
    });

    testWidgets('背景色为 #F7F8F6', (tester) async {
      final calls = <String>[];
      await pumpBar(tester, onTap: calls.add);

      final colored = find.byWidgetPredicate(
        (w) => w is Container && w.color == const Color(0xFFF7F8F6),
      );
      expect(colored, findsOneWidget);
    });

    testWidgets('批次86-2 visibleIds 过滤 + 按配置顺序渲染', (tester) async {
      final calls = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PunctuationBar(
              onTap: calls.add,
              visibleIds: const ['period', 'comma'],
            ),
          ),
        ),
      );

      // 2 个操作项常驻 + 配置的 2 项 = 4 个可点击区域（批次91-3）
      expect(find.byType(GestureDetector), findsNWidgets(4));
      expect(find.byIcon(Icons.undo), findsOneWidget);
      expect(find.byIcon(Icons.redo), findsOneWidget);
      expect(find.text('。'), findsOneWidget);
      expect(find.text('，'), findsOneWidget);
      expect(find.text('？'), findsNothing);

      // 顺序：操作项在前，period/comma 随后
      final order = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .toList();
      expect(order, ['。', '，']);
    });

    testWidgets('批次86-2 visibleIds 含未知 id → 忽略该 id', (tester) async {
      final calls = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PunctuationBar(
              onTap: calls.add,
              visibleIds: const ['comma', 'not-exist', 'period'],
            ),
          ),
        ),
      );

      // 操作项 2 + 有效标点 2
      expect(find.byType(GestureDetector), findsNWidgets(4));
      expect(find.text('，'), findsOneWidget);
      expect(find.text('。'), findsOneWidget);
    });

    testWidgets('批次86-2 visibleIds 为 null → 全部默认顺序', (tester) async {
      final calls = <String>[];
      await pumpBar(tester, onTap: calls.add);

      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .toList();
      expect(
        texts,
        defaultPunctuationIds
            .map(
              (id) => punctuationItems.firstWhere((it) => it.id == id).display,
            )
            .toList(),
      );
    });

    testWidgets('批次88-5 customItems 追加渲染（含在可见列表尾部）', (tester) async {
      final calls = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PunctuationBar(
              onTap: calls.add,
              visibleIds: const ['comma', 'custom_01'],
              customItems: const [
                PunctuationItem('custom_01', '『', '『'),
                PunctuationItem('custom_02', '』', '』'),
              ],
            ),
          ),
        ),
      );

      // 操作项 2 + 配置的 2 项（comma + custom_01）
      expect(find.byType(GestureDetector), findsNWidgets(4));
      expect(find.text('，'), findsOneWidget);
      expect(find.text('『'), findsOneWidget);
      expect(find.text('』'), findsNothing);

      // 点击自定义项 → 插入对应字符
      await tester.tap(find.text('『'));
      await tester.pump();
      expect(calls, ['『']);
    });

    testWidgets('批次88-5 visibleIds 为 null 时内置+自定义全部渲染', (tester) async {
      final calls = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PunctuationBar(
              onTap: calls.add,
              customItems: const [PunctuationItem('custom_01', '✎', '✎')],
            ),
          ),
        ),
      );

      expect(find.text('，'), findsOneWidget);
      expect(find.text('✎'), findsOneWidget);
      // 操作项 2 + 内置 15 + 自定义 1 = 18
      expect(find.byType(GestureDetector), findsNWidgets(18));
    });
  });
}
