// ─────────────────────────────────────────────────────────────
// block 编辑器测试 — ADR-0002 阶段1 懒加载 + 阶段2 块内编辑
//   - 阶段1：分块视图只构建视口块（BlockReadonlyView / BlockEditableView 同证）
//   - 阶段2：块内输入 → join() 整串同步；逐块智能标点生效；flag 关现网不变
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/features/writing/blocked_text/block_editable_view.dart';
import 'package:writingcoach/features/writing/blocked_text/block_readonly_view.dart';
import 'package:writingcoach/features/writing/writing_editor_view.dart';
import 'package:writingcoach/providers/writing_providers.dart';

/// 造数：确定性产出数千块。
String _buildLongText({int targetChars = 100000}) {
  const fragments = [
    '写作是一场与自己的对话',
    '窗外的雨声落在旧屋檐上',
    '他把台灯调亮了一格',
    '草稿纸上写满了又划掉',
    '故事的开头总要有点悬念',
    '夜色顺着江面慢慢铺开',
    '她想起去年的那场雪',
    '键盘的敲击声断断续续',
    '文字像水流一样自然涌出',
    '人总要学着和孤独相处',
  ];
  final buf = StringBuffer();
  int i = 0;
  while (buf.length < targetChars) {
    buf.write(fragments[i % fragments.length]);
    buf.write('\n');
    i++;
  }
  return buf.toString();
}

void main() {
  testWidgets('编辑器懒加载已启用（0.5.1 发版状态）', (tester) async {
    expect(
      kBlockEditorEnabled,
      isTrue,
      reason: '0.5.1 已启用分块渲染；如需回退改回 false 并同步本测试',
    );
  });

  testWidgets('可编辑视图初始只构建视口内块（块 build 计数）', (tester) async {
    var built = 0;
    final text = _buildLongText();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlockEditableView(
            initialText: text,
            style: const TextStyle(fontSize: 16, height: 1.6),
            hintStyle: const TextStyle(fontSize: 16, height: 1.6),
            smartPunctOn: false,
            onChanged: (_) {},
            onBlockBuild: () => built++,
          ),
        ),
      ),
    );
    final total = text.split('\n').length;
    debugPrint('>>> BLOCKS total=$total builtAtFirstFrame=$built');
    expect(built, lessThan(40), reason: '首帧只应构建视口+缓存区内的块');
    expect(built, lessThan(total ~/ 10), reason: '绝不能整章构建');
  });

  testWidgets('滚动 20 屏后累计构建仍远小于总块数', (tester) async {
    var built = 0;
    final text = _buildLongText();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlockEditableView(
            initialText: text,
            style: const TextStyle(fontSize: 16, height: 1.6),
            hintStyle: const TextStyle(fontSize: 16, height: 1.6),
            smartPunctOn: false,
            onChanged: (_) {},
            onBlockBuild: () => built++,
          ),
        ),
      ),
    );
    final builtAtStart = built;
    // 可编辑块的 TextField 内部会引入额外 Scrollable，不能用
    // find.byType(Scrollable).single；从首块 TextField 向上找最近外层
    // Scrollable（即 ListView 自身的滚动体）。
    final listScrollable = find.ancestor(
      of: find.byType(TextField).first,
      matching: find.byType(Scrollable),
    );
    final position = tester.state<ScrollableState>(listScrollable).position;
    final viewportH = position.viewportDimension;
    for (var i = 1; i <= 20; i++) {
      position.jumpTo(viewportH * i);
      await tester.pump();
    }
    final total = text.split('\n').length;
    debugPrint(
      '>>> SCROLL20 builtStart=$builtAtStart builtNow=$built total=$total',
    );
    expect(built, lessThan(total ~/ 3), reason: '20 屏滚动后视口外块仍不应被构建');
  });

  testWidgets('正文始终解析到 chapterContentField（flag 开=分块首块 / 关=单 TextField）', (
    tester,
  ) async {
    final controller = TextEditingController(text: '\u3000\u3000第一段正文。');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WritingEditorView(
            state: const WritingState(),
            titleController: TextEditingController(),
            contentController: controller,
            focusNode: FocusNode(),
            editorStackKey: GlobalKey(),
            punctBarIds: null,
            punctCustomItems: const [],
            showSelectionMenu: false,
            selectionMenuPos: null,
            onTitleChanged: (_) {},
            onContentChanged: (_) {},
            onDiagnoseSelection: () {},
            onSaveToLibrary: () {},
            onUndo: () {},
            onRedo: () {},
            onPunctuationTap: (_) {},
          ),
        ),
      ),
    );
    expect(
      find.byKey(const Key('chapterContentField')),
      findsOneWidget,
      reason: '无论 flag 开关，正文容器都解析到 chapterContentField',
    );
  });

  testWidgets('块内输入 → join() 整串同步（定制：扁平串唯一真源）', (tester) async {
    String? emitted;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlockEditableView(
            initialText: '甲\n乙',
            style: const TextStyle(fontSize: 16),
            hintStyle: const TextStyle(fontSize: 16),
            smartPunctOn: false,
            onChanged: (s) => emitted = s,
          ),
        ),
      ),
    );
    await tester.enterText(find.byKey(const ValueKey('contentBlock_0')), '甲乙丙');
    expect(emitted, '甲乙丙\n乙', reason: r'块0 改动后应与块1 以 \n 拼回整串');
  });

  testWidgets('空章节首块显示原占位提示', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlockEditableView(
            initialText: '',
            style: const TextStyle(fontSize: 16),
            hintStyle: const TextStyle(fontSize: 16),
            smartPunctOn: false,
            onChanged: (_) {},
          ),
        ),
      ),
    );
    expect(find.text('请输入正文内容'), findsOneWidget);
  });

  testWidgets('智能标点逐块生效（定制1：左配对符自动补右符）', (tester) async {
    String? emitted;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlockEditableView(
            initialText: '',
            style: const TextStyle(fontSize: 16),
            hintStyle: const TextStyle(fontSize: 16),
            smartPunctOn: true,
            onChanged: (s) => emitted = s,
          ),
        ),
      ),
    );
    await tester.enterText(find.byKey(const ValueKey('contentBlock_0')), '「');
    expect(emitted, '「」', reason: '块内输入「 应被 SmartPunctuationFormatter 补成 「」');
  });

  testWidgets('智能标点关闭时逐块不挂格式化器', (tester) async {
    String? emitted;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlockEditableView(
            initialText: '',
            style: const TextStyle(fontSize: 16),
            hintStyle: const TextStyle(fontSize: 16),
            smartPunctOn: false,
            onChanged: (s) => emitted = s,
          ),
        ),
      ),
    );
    await tester.enterText(find.byKey(const ValueKey('contentBlock_0')), '「');
    expect(emitted, '「', reason: 'smartPunctOn=false 时不应自动补右符');
  });

  // 阶段1 只读视图仍可独立单测（未删除，懒加载机制本体保留）。
  testWidgets('BlockReadonlyView 仍只渲染文本', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlockReadonlyView(
            text: '只读行1\n只读行2',
            style: const TextStyle(fontSize: 16),
          ),
        ),
      ),
    );
    expect(find.text('只读行1'), findsOneWidget);
    expect(find.text('只读行2'), findsOneWidget);
  });

  // ── 阶段3：回车拆块 / 退格合并 / FocusAware 淡化 ──────────────────────────

  testWidgets('回车拆块 + 自动补缩进（定制2 钩子）', (tester) async {
    String? emitted;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlockEditableView(
            initialText: '',
            style: const TextStyle(fontSize: 16),
            hintStyle: const TextStyle(fontSize: 16),
            smartPunctOn: false,
            indentParagraph: true,
            onChanged: (s) => emitted = s,
          ),
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey('contentBlock_0')),
      '甲\n乙',
    );
    await tester.pump();
    expect(emitted, '甲\n\u3000\u3000乙', reason: '拆块后新块首应补两个全角空格');
    expect(find.byKey(const ValueKey('contentBlock_1')), findsOneWidget);
  });

  testWidgets('回车拆块 + 段间空行（blankLineBetween）', (tester) async {
    String? emitted;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlockEditableView(
            initialText: '',
            style: const TextStyle(fontSize: 16),
            hintStyle: const TextStyle(fontSize: 16),
            smartPunctOn: false,
            blankLineBetween: true,
            onChanged: (s) => emitted = s,
          ),
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey('contentBlock_0')),
      '甲\n乙',
    );
    await tester.pump();
    expect(emitted, '甲\n\n乙', reason: '段间应插入一个空行块');
  });

  testWidgets('空块块首退格 → 拼回上一块', (tester) async {
    String? emitted;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlockEditableView(
            initialText: '甲\n',
            style: const TextStyle(fontSize: 16),
            hintStyle: const TextStyle(fontSize: 16),
            smartPunctOn: false,
            onChanged: (s) => emitted = s,
          ),
        ),
      ),
    );
    // 聚焦末尾空块（块首偏移 0），退格应合并进上一块。
    await tester.tap(find.byKey(const ValueKey('contentBlock_1')));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();
    expect(emitted, '甲', reason: '空块退格后应拼回上一块末尾');
    expect(find.byKey(const ValueKey('contentBlock_1')), findsNothing);
  });

  testWidgets('FocusAware：focusMode 下非当前块淡化 alpha 0.32', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlockEditableView(
            initialText: '甲\n乙',
            style: const TextStyle(fontSize: 16, color: Color(0xFF000000)),
            hintStyle: const TextStyle(fontSize: 16),
            smartPunctOn: false,
            focusMode: true,
            onChanged: (_) {},
          ),
        ),
      ),
    );
    // 初始无聚焦块 → 两块都淡化。
    var t0 = tester.widget<TextField>(
      find.byKey(const ValueKey('contentBlock_0')),
    );
    expect(t0.style!.color!.a, closeTo(0.32, 0.01));
    // 聚焦块0 → 块0 恢复正常不透明。
    await tester.tap(find.byKey(const ValueKey('contentBlock_0')));
    await tester.pump();
    t0 = tester.widget<TextField>(find.byKey(const ValueKey('contentBlock_0')));
    expect(t0.style!.color!.a, closeTo(1.0, 0.01));
  });

  // ── 阶段4：Key 兼容 / 外部整串回灌 / locateCaret ─────────────────────────

  testWidgets('Key 兼容：flag 开时 chapterContentField 解析到首块', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlockEditableView(
            initialText: '甲乙',
            style: const TextStyle(fontSize: 16),
            hintStyle: const TextStyle(fontSize: 16),
            smartPunctOn: false,
            onChanged: (_) {},
          ),
        ),
      ),
    );
    expect(
      find.byKey(const ValueKey('chapterContentField')),
      findsOneWidget,
      reason: '无聚焦块时首块应挂现网 chapterContentField Key',
    );
  });

  testWidgets('外部整串回灌：applyExternalText 重建块并恢复光标', (tester) async {
    final viewKey = GlobalKey<BlockEditableViewState>();
    String? emitted;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlockEditableView(
            key: viewKey,
            initialText: '甲',
            style: const TextStyle(fontSize: 16),
            hintStyle: const TextStyle(fontSize: 16),
            smartPunctOn: false,
            onChanged: (s) => emitted = s,
          ),
        ),
      ),
    );
    // 模拟 undo/redo 后回灌：新整串含两段。
    viewKey.currentState?.applyExternalText('甲乙\n丙丁', caretOffset: 5);
    await tester.pump();
    expect(emitted, '甲乙\n丙丁', reason: '回灌后整串应同步宿主');
    expect(find.byKey(const ValueKey('contentBlock_1')), findsOneWidget);
    // caretOffset 5 = 块0(2)+\n(1)=3 起，块1 局部偏移 2（= 块尾）。
    expect(FocusManager.instance.primaryFocus, isNotNull);
  });

  testWidgets('locateCaret：绝对偏移定位到对应块', (tester) async {
    final viewKey = GlobalKey<BlockEditableViewState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlockEditableView(
            key: viewKey,
            initialText: '甲\n乙乙',
            style: const TextStyle(fontSize: 16),
            hintStyle: const TextStyle(fontSize: 16),
            smartPunctOn: false,
            onChanged: (_) {},
          ),
        ),
      ),
    );
    // 绝对偏移 3 = 块1（块0 '甲' 长度1 + '\n'1 = 2）。定位后块1 应获焦。
    viewKey.currentState?.locateCaret(3);
    await tester.pump();
    final block1 = tester.widget<TextField>(
      find.byKey(const ValueKey('contentBlock_1')),
    );
    expect(block1.focusNode?.hasFocus, isTrue, reason: '偏移 3 应聚焦块1');
  });
}
