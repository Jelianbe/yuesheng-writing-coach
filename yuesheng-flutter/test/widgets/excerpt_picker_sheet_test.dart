// ─────────────────────────────────────────────────────────────
// ExcerptPickerSheet widget 测试 — A-3 方案 Y 手动选段弹层
//
// 覆盖：
//   1. 段落分行渲染（含空行占位）
//   2. 点击段落 → 单段选区 → 状态标签
//   3. 区间扩展（点右侧段 → 多段标签）
//   4. 区间内重锚
//   5. 确定 → pop ExcerptPickResult(anchor)
//   6. 清除选段 + 确定 → pop ExcerptPickResult(null)（清除语义）
//   7. 取消 → pop null（不写库语义）
//   8. 既有锚点预选回显 / 指向其它章节不预选（防串段）
//   9. 空内容章节占位
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/paragraph_selection.dart';
import 'package:writingcoach/widgets/excerpt_picker_sheet.dart';

const _p1 = '第一段：少年推开柴门。';
const _p2 = '第二段：风雪扑面而来。';
const _p4 = '第四段：他握紧了手中的剑。';
const _content = '$_p1\n$_p2\n\n$_p4';
final _paras = _content.split('\n');
/// 弹层内动作完成后，用返回的 getter 读取 pop 结果
Future<Object? Function()> pumpSheet(
  WidgetTester tester, {
  String? initialAnchorJson,
  String content = _content,
}) async {
  Object? popped;
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () async {
                popped = await Navigator.of(ctx).push<Object?>(
                  MaterialPageRoute<Object?>(
                    // 生产环境经 showYueModalBottomSheet 提供 Material 祖先，
                    // 这里等价补一层
                    builder: (_) => Scaffold(
                      body: Material(
                        child: ExcerptPickerSheet(
                          chapterId: 'ch-1',
                          chapterTitle: '第一章 风雪',
                          content: content,
                          initialAnchorJson: initialAnchorJson,
                        ),
                      ),
                    ),
                    fullscreenDialog: true,
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return () => popped;
}

void main() {
  testWidgets('#1 段落分行渲染（空行占位「（空行）」）', (tester) async {
    await pumpSheet(tester);
    expect(find.textContaining('少年推开柴门'), findsOneWidget);
    expect(find.textContaining('风雪扑面而来'), findsOneWidget);
    expect(find.text('（空行）'), findsOneWidget);
    expect(find.textContaining('握紧了手中的剑'), findsOneWidget);
    // 段号 1-4（0-based 段序的 1-based 展示）
    expect(find.text('1'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
  });

  testWidgets('#2 点击段落 → 单段选区 + 标签', (tester) async {
    await pumpSheet(tester);
    expect(find.textContaining('未选择'), findsOneWidget);

    await tester.tap(find.textContaining('风雪扑面而来'));
    await tester.pumpAndSettle();

    final chars = selectionCharCount(_paras, 1, 1);
    expect(find.text('已选第 2 段（$chars 字）'), findsOneWidget);
  });

  testWidgets('#3 点区间右侧 → 扩展为多段', (tester) async {
    await pumpSheet(tester);
    await tester.tap(find.textContaining('少年推开柴门'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('握紧了手中的剑'));
    await tester.pumpAndSettle();

    final chars = selectionCharCount(_paras, 0, 3);
    expect(find.text('已选第 1–4 段（$chars 字）'), findsOneWidget);
  });

  testWidgets('#4 点区间内 → 重锚为单段', (tester) async {
    await pumpSheet(tester);
    await tester.tap(find.textContaining('少年推开柴门'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('握紧了手中的剑'));
    await tester.pumpAndSettle();
    // 区间内点第 2 段 → 重锚
    await tester.tap(find.textContaining('风雪扑面而来'));
    await tester.pumpAndSettle();

    final chars = selectionCharCount(_paras, 1, 1);
    expect(find.text('已选第 2 段（$chars 字）'), findsOneWidget);
  });

  testWidgets('#5 确定 → pop 出锚点结果', (tester) async {
    final getPopped = await pumpSheet(tester);
    await tester.tap(find.textContaining('少年推开柴门'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    final popped = getPopped();
    expect(popped, isA<ExcerptPickResult>());
    final anchor = (popped as ExcerptPickResult).anchor!;
    expect(anchor.chapterId, 'ch-1');
    expect(anchor.startPara, 0);
    expect(anchor.endPara, 0);
  });

  testWidgets('#6 清除选段 + 确定 → pop anchor 为 null（清除语义）', (tester) async {
    final getPopped = await pumpSheet(
      tester,
      initialAnchorJson: '{"chapterId":"ch-1","startPara":0,"endPara":1}',
    );

    // 预选回显（第 1–2 段）
    final chars = selectionCharCount(_paras, 0, 1);
    expect(find.text('已选第 1–2 段（$chars 字）'), findsOneWidget);

    await tester.tap(find.text('清除选段'));
    await tester.pumpAndSettle();
    expect(find.textContaining('未选择'), findsOneWidget);

    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    final popped = getPopped();
    expect(popped, isA<ExcerptPickResult>());
    expect((popped as ExcerptPickResult).anchor, isNull); // 清除≠取消
  });

  testWidgets('#7 取消 → pop null（不写库语义）', (tester) async {
    final getPopped = await pumpSheet(tester);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(getPopped(), isNull);
  });

  testWidgets('#8 既有锚点预选回显（标签 + 区间）', (tester) async {
    await pumpSheet(
      tester,
      initialAnchorJson: '{"chapterId":"ch-1","startPara":1,"endPara":3}',
    );
    final chars = selectionCharCount(_paras, 1, 3);
    expect(find.text('已选第 2–4 段（$chars 字）'), findsOneWidget);
  });

  testWidgets('#8b 既有锚点指向其它章节 → 不预选（防串段）', (tester) async {
    await pumpSheet(
      tester,
      initialAnchorJson: '{"chapterId":"other-ch","startPara":1,"endPara":3}',
    );
    expect(find.textContaining('未选择'), findsOneWidget);
  });

  testWidgets('#9 空内容 → 占位提示且无段落行', (tester) async {
    await pumpSheet(tester, content: '');
    expect(find.text('本章暂无内容'), findsOneWidget);
    expect(find.textContaining('未选择'), findsOneWidget);
  });
}
