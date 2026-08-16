// ─────────────────────────────────────────────────────────────
// ChatInput widget 测试 — 输入框 + 发送按钮
//
// 覆盖路径：
//   1. 输入文本 + 点击发送按钮 → 触发 onSend（带文本参数）
//   2. 空输入 → 发送按钮禁用
//   3. isStreaming=true → 发送按钮禁用 + TextField 不可编辑
//   4. onInputChange 在输入时触发
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/widgets/chat_input.dart';

void main() {
  group('ChatInput', () {
    testWidgets('输入文本 + 点击发送按钮 → 触发 onSend（带文本参数）', (tester) async {
      String? sentText;
      String inputText = '';
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) => Scaffold(
              body: ChatInput(
                input: inputText,
                isStreaming: false,
                onInputChange: (text) => setState(() => inputText = text),
                onSend: (text) => sentText = text,
              ),
            ),
          ),
        ),
      );

      // 输入文本（onInputChange → setState → input 更新 → _canSend=true）
      await tester.enterText(find.byType(TextField), '你好');
      await tester.pump();

      // 点击发送按钮
      await tester.tap(find.byType(FilledButton));
      await tester.pump();

      expect(sentText, '你好');
    });

    testWidgets('空输入 → 发送按钮禁用', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatInput(
              input: '',
              isStreaming: false,
              onInputChange: (_) {},
              onSend: (_) {},
            ),
          ),
        ),
      );

      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.enabled, false);
    });

    testWidgets('isStreaming=true → 发送按钮禁用 + TextField 不可编辑', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatInput(
              input: '有内容',
              isStreaming: true,
              onInputChange: (_) {},
              onSend: (_) {},
            ),
          ),
        ),
      );

      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.enabled, false);

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.enabled, false);
    });

    testWidgets('onInputChange 在输入时触发', (tester) async {
      String? changedText;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatInput(
              input: '',
              isStreaming: false,
              onInputChange: (text) => changedText = text,
              onSend: (_) {},
            ),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'test');
      expect(changedText, 'test');
    });

    // ════════════════════════════════════════════════════════
    // 批次3：+ 按钮 + 占位符切换
    // 批次70：@ 功能合并进输入框——移除独立 @ 按钮，改为输入 "@" 字符触发
    // ════════════════════════════════════════════════════════

    testWidgets('未传回调 → + 按钮不显示（保持 MVP 行为）', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatInput(
              input: '',
              isStreaming: false,
              onInputChange: (_) {},
              onSend: (_) {},
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.add), findsNothing);
      // 批次70：独立 @ 按钮已移除，永远不显示
      expect(find.byIcon(Icons.alternate_email), findsNothing);
    });

    testWidgets('传 onUploadFile → + 按钮显示，点击触发回调', (tester) async {
      var uploadTapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatInput(
              input: '',
              isStreaming: false,
              onInputChange: (_) {},
              onSend: (_) {},
              onUploadFile: () => uploadTapped = true,
            ),
          ),
        ),
      );

      final plus = find.byIcon(Icons.add);
      expect(plus, findsOneWidget);
      expect(find.byIcon(Icons.alternate_email), findsNothing);

      await tester.tap(plus);
      await tester.pump();
      expect(uploadTapped, isTrue);
    });

    testWidgets('批次70：输入 "@" 字符 → 触发 onMention 回调（字符级触发）', (tester) async {
      var mentionTapped = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatInput(
              input: '',
              isStreaming: false,
              onInputChange: (_) {},
              onSend: (_) {},
              onMention: () => mentionTapped++,
            ),
          ),
        ),
      );

      // 独立 @ 按钮不再显示（批次70）
      expect(find.byIcon(Icons.alternate_email), findsNothing);

      // 输入 "@" → 触发引用选择器
      await tester.enterText(find.byType(TextField), '@');
      await tester.pump();
      expect(mentionTapped, 1);

      // 输入普通字符 → 不触发
      await tester.enterText(find.byType(TextField), '你好');
      await tester.pump();
      expect(mentionTapped, 1);
    });

    testWidgets('批次70：双回调 + 上传按钮可点；@ 改字符触发', (tester) async {
      var uploadTapped = false;
      var mentionTapped = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatInput(
              input: '',
              isStreaming: false,
              onInputChange: (_) {},
              onSend: (_) {},
              onUploadFile: () => uploadTapped = true,
              onMention: () => mentionTapped++,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.add), findsOneWidget);
      expect(find.byIcon(Icons.alternate_email), findsNothing);

      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();
      expect(uploadTapped, isTrue);

      // @ 通过输入字符触发
      await tester.enterText(find.byType(TextField), '@');
      await tester.pump();
      expect(mentionTapped, 1);
    });

    testWidgets('批次70：isStreaming 时 TextField 禁用（无法输入 @）', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatInput(
              input: '有内容',
              isStreaming: true,
              onInputChange: (_) {},
              onSend: (_) {},
              onMention: () {},
            ),
          ),
        ),
      );

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.enabled, false);
    });

    testWidgets('entryPoint=manuscript → 占位符切换为诊断模式文案', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatInput(
              input: '',
              isStreaming: false,
              onInputChange: (_) {},
              onSend: (_) {},
              entryPoint: 'manuscript',
            ),
          ),
        ),
      );

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(
        textField.decoration?.hintText,
        '描述你遇到的写作问题…输入 @ 引用作品',
      );
    });

    testWidgets('默认 entryPoint → 全局占位符「和月笙聊聊…输入 @ 引用作品」', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatInput(
              input: '',
              isStreaming: false,
              onInputChange: (_) {},
              onSend: (_) {},
            ),
          ),
        ),
      );

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.decoration?.hintText, '和月笙聊聊…输入 @ 引用作品');
    });
  });
}
