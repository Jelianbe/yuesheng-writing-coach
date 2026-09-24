// ─────────────────────────────────────────────────────────────
// ChatInput widget 测试 — 输入胶囊 + 发送按钮 + 「+」面板
//
// 覆盖路径：
//   1. 输入文本 + 点击发送按钮 → 触发 onSend（带文本参数）
//   2. 空输入 → 发送按钮禁用
//   3. isStreaming=true → 发送按钮禁用 + TextField 不可编辑
//   4. onInputChange 在输入时触发
//   5. 「+」面板（2026-09-15 版式）：开合、点外部收起、上传项、思考开关
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/features/chat/chat_input.dart';
import 'package:writingcoach/features/chat/chat_plus_panel.dart';

/// 统一装配：默认传齐两个面板能力，「+」才会出现。
Widget buildInput({
  String input = '',
  bool isStreaming = false,
  ValueChanged<String>? onInputChange,
  ValueChanged<String>? onSend,
  VoidCallback? onUploadFile,
  bool thinkingEnabled = true,
  String reasoningTierLabel = '标准',
  void Function(bool)? onThinkingToggle,
}) {
  return MaterialApp(
    home: Scaffold(
      // 真实布局里输入栏贴在页面底部，面板向上展开依赖这个位置
      body: Column(
        children: [
          const Spacer(),
          ChatInput(
            input: input,
            isStreaming: isStreaming,
            onInputChange: onInputChange ?? (_) {},
            onSend: onSend ?? (_) {},
            onUploadFile: onUploadFile,
            thinkingEnabled: thinkingEnabled,
            reasoningTierLabel: reasoningTierLabel,
            onThinkingToggle: onThinkingToggle,
          ),
        ],
      ),
    ),
  );
}

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
      await tester.pumpWidget(buildInput());

      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.enabled, false);
    });

    testWidgets('isStreaming=true → 发送按钮禁用 + TextField 不可编辑', (tester) async {
      await tester.pumpWidget(buildInput(input: '有内容', isStreaming: true));

      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.enabled, false);

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.enabled, false);
    });

    testWidgets('onInputChange 在输入时触发', (tester) async {
      String? changedText;
      await tester.pumpWidget(
        buildInput(onInputChange: (text) => changedText = text),
      );

      await tester.enterText(find.byType(TextField), 'test');
      expect(changedText, 'test');
    });

    // ════════════════════════════════════════════════════════
    // 批次3：+ 按钮
    // 批次70：@ 功能合并进输入框——移除独立 @ 按钮，改为输入 "@" 字符触发
    // 2026-09-15：+ 回到胶囊左侧，点击不再直弹覆盖层，改为上方浮层面板
    // ════════════════════════════════════════════════════════

    testWidgets('未传任何面板能力 → + 按钮不显示（保持 MVP 行为）', (tester) async {
      await tester.pumpWidget(buildInput());

      expect(find.byIcon(Icons.add), findsNothing);
      // 批次70：独立 @ 按钮已移除，永远不显示
      expect(find.byIcon(Icons.alternate_email), findsNothing);
    });

    testWidgets('仅传 onThinkingToggle → + 仍显示（否则开关不可达）', (tester) async {
      await tester.pumpWidget(buildInput(onThinkingToggle: (_) {}));

      expect(find.byIcon(Icons.add), findsOneWidget);
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

    testWidgets('批次70：@ 与「+」面板可共存', (tester) async {
      var mentionTapped = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatInput(
              input: '',
              isStreaming: false,
              onInputChange: (_) {},
              onSend: (_) {},
              onUploadFile: () {},
              onMention: () => mentionTapped++,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.add), findsOneWidget);
      expect(find.byIcon(Icons.alternate_email), findsNothing);

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
      expect(textField.decoration?.hintText, '描述你遇到的写作问题…输入 @ 引用作品');
    });

    testWidgets('默认 entryPoint → 全局占位符「输入 @ 引用作品」', (tester) async {
      await tester.pumpWidget(buildInput());

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.decoration?.hintText, '输入 @ 引用作品');
    });

    group('空态一行 + 纵向滑块（2026-09-08 回归）', () {
      testWidgets('空输入框高度 = 一行（不占两行）', (tester) async {
        await tester.pumpWidget(buildInput());
        await tester.pump();

        final size = tester.getSize(find.byType(TextField));
        // 空态一行：isDense + vertical 10 → 约 36-42px；两行会 ≥ 55
        expect(
          size.height,
          lessThan(45),
          reason: '空态输入框应保持一行，实际高度 ${size.height}',
        );
        expect(size.height, greaterThan(20));
      });

      testWidgets('长文本超 5 行 → 高度封顶 + 纵向滑块出现', (tester) async {
        await tester.pumpWidget(buildInput());
        await tester.pump();
        final emptyHeight = tester.getSize(find.byType(TextField)).height;

        // 输入 200 字（超过 5 行显示容量）
        await tester.enterText(find.byType(TextField), '这是测试文字。' * 40);
        await tester.pump();

        final filledHeight = tester.getSize(find.byType(TextField)).height;
        // 多行增高但封顶（≤ 6 行高），不无限撑高
        expect(filledHeight, greaterThan(emptyHeight));
        expect(
          filledHeight,
          lessThan(emptyHeight * 6 + 60),
          reason: '输入框应封顶（maxLines 5），实际 $filledHeight',
        );

        // 纵向滑块存在（Scrollbar 已挂 controller）
        final scrollbar = find.descendant(
          of: find.byType(ChatInput),
          matching: find.byType(Scrollbar),
        );
        expect(scrollbar, findsOneWidget);
      });
    });

    // ════════════════════════════════════════════════════════
    // 2026-09-15：「+」上方面板（取代原「+ 直弹覆盖层」）
    // ════════════════════════════════════════════════════════

    group('「+」上方面板', () {
      testWidgets('点击 + → 面板出现（含「上传作品」），不再直开覆盖层', (tester) async {
        await tester.pumpWidget(buildInput(onUploadFile: () {}));

        expect(find.byType(ChatPlusPanel), findsNothing);

        await tester.tap(find.byIcon(Icons.add));
        await tester.pump();

        expect(find.byType(ChatPlusPanel), findsOneWidget);
        expect(find.text('上传作品'), findsOneWidget);
      });

      testWidgets('点面板内「上传作品」→ 触发回调且面板收起', (tester) async {
        var uploadTapped = false;
        await tester.pumpWidget(
          buildInput(onUploadFile: () => uploadTapped = true),
        );

        await tester.tap(find.byIcon(Icons.add));
        await tester.pump();
        await tester.tap(find.text('上传作品'));
        await tester.pump();

        expect(uploadTapped, isTrue);
        expect(find.byType(ChatPlusPanel), findsNothing);
      });

      testWidgets('再点一次 + → 面板收起（开合切换）', (tester) async {
        await tester.pumpWidget(buildInput(onUploadFile: () {}));

        await tester.tap(find.byIcon(Icons.add));
        await tester.pump();
        expect(find.byType(ChatPlusPanel), findsOneWidget);

        await tester.tap(find.byIcon(Icons.add));
        await tester.pump();
        expect(find.byType(ChatPlusPanel), findsNothing);
      });

      testWidgets('点面板外 → 面板收起', (tester) async {
        await tester.pumpWidget(buildInput(onUploadFile: () {}));

        await tester.tap(find.byIcon(Icons.add));
        await tester.pump();
        expect(find.byType(ChatPlusPanel), findsOneWidget);

        // 点远处空白处（TapRegion 组外）
        await tester.tapAt(const Offset(400, 10));
        await tester.pump();
        expect(find.byType(ChatPlusPanel), findsNothing);
      });

      testWidgets('只传 onUploadFile → 面板内不渲染思考开关', (tester) async {
        await tester.pumpWidget(buildInput(onUploadFile: () {}));

        await tester.tap(find.byIcon(Icons.add));
        await tester.pump();

        expect(find.byType(ChatPlusPanel), findsOneWidget);
        expect(find.byType(Switch), findsNothing);
        expect(find.text('思考'), findsNothing);
      });
    });

    // ════════════════════════════════════════════════════════
    // 批次 TH 三：思考开关（二值快捷入口）
    // 2026-09-15：从「输入框上方常驻行」迁入「+」面板
    // 完整四档仍在设置页「模型行为」/ 头部「更多」菜单，本处只负责快关/快开。
    // ════════════════════════════════════════════════════════

    group('思考开关（面板内）', () {
      /// 打开「+」面板后返回，便于逐条断言面板内容。
      Future<void> openPanel(WidgetTester tester) async {
        await tester.tap(find.byIcon(Icons.add));
        await tester.pump();
      }

      testWidgets('未传回调 → 不渲染开关（既有调用点零改动）', (tester) async {
        await tester.pumpWidget(buildInput(onUploadFile: () {}));
        await openPanel(tester);

        expect(find.byType(Switch), findsNothing);
        expect(find.text('思考'), findsNothing);
      });

      testWidgets('打开面板 → 显示「思考」+ 当前档位副文案 + 开关为开', (tester) async {
        await tester.pumpWidget(
          buildInput(reasoningTierLabel: '深度', onThinkingToggle: (_) {}),
        );
        await openPanel(tester);

        expect(find.text('思考'), findsOneWidget);
        expect(find.text('深度'), findsOneWidget);
        expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
      });

      testWidgets('点击开关 → onThinkingToggle(false)（关掉思考）', (tester) async {
        bool? toggled;
        await tester.pumpWidget(
          buildInput(onThinkingToggle: (v) => toggled = v),
        );
        await openPanel(tester);

        await tester.tap(find.byType(Switch));
        await tester.pump();

        expect(toggled, isFalse);
      });

      testWidgets('关闭态 → 副文案改为「已关闭」（不再显示档位名）', (tester) async {
        await tester.pumpWidget(
          buildInput(
            thinkingEnabled: false,
            reasoningTierLabel: '深度',
            onThinkingToggle: (_) {},
          ),
        );
        await openPanel(tester);

        expect(find.text('已关闭'), findsOneWidget);
        expect(find.text('深度'), findsNothing);
        expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
      });

      testWidgets('关闭态再点 → onThinkingToggle(true)（恢复上次档位由上层负责）', (
        tester,
      ) async {
        bool? toggled;
        await tester.pumpWidget(
          buildInput(
            thinkingEnabled: false,
            onThinkingToggle: (v) => toggled = v,
          ),
        );
        await openPanel(tester);

        await tester.tap(find.byType(Switch));
        await tester.pump();

        expect(toggled, isTrue);
      });

      testWidgets('isStreaming → 开关禁用（防中途换档与已发请求不一致）', (tester) async {
        await tester.pumpWidget(
          buildInput(isStreaming: true, onThinkingToggle: (_) {}),
        );
        await openPanel(tester);

        final sw = tester.widget<Switch>(find.byType(Switch));
        expect(sw.onChanged, isNull);
      });
    });
  });

  // 2026-09-15 真机回归：原实现「打开面板时算一次绝对坐标」⇒ 落点被冻结，
  // 键盘收起后面板飘到屏幕上方 937 物理像素。此组锁死「面板紧贴「+」上方」。
  group('ChatInput 面板落点（LayerLink 锚定）', () {
    /// 「+」按钮框（取 InkWell 本体，不是其中的图标）。
    Rect plusRect(WidgetTester tester) => tester.getRect(
      find
          .ancestor(of: find.byIcon(Icons.add), matching: find.byType(InkWell))
          .first,
    );

    /// 面板底边 →「+」顶边的间距（应恒为 AppSpacing.sm = 8）。
    double gap(WidgetTester tester) =>
        plusRect(tester).top -
        tester.getRect(find.byType(ChatPlusPanel)).bottom;

    /// 面板左边缘 →「+」左边缘的水平偏差（应对齐）。
    double leftDelta(WidgetTester tester) =>
        tester.getRect(find.byType(ChatPlusPanel)).left - plusRect(tester).left;

    Future<void> tapPlus(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
    }

    testWidgets('键盘开合 / 面板保持打开时，落点始终跟随「+」', (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        buildInput(onUploadFile: () {}, onThinkingToggle: (_) {}),
      );

      // A 键盘未弹出时打开
      await tapPlus(tester);
      expect(gap(tester), closeTo(8, 0.5), reason: 'A 无键盘');
      expect(leftDelta(tester), closeTo(0, 0.5), reason: 'A 左边缘应与「+」对齐');

      // 关面板 → 键盘弹出后再打开
      await tapPlus(tester); // 再点一次 = 收起
      tester.view.viewInsets = const FakeViewPadding(bottom: 888);
      await tester.pumpAndSettle();
      await tapPlus(tester);
      expect(gap(tester), closeTo(8, 0.5), reason: 'B 键盘已弹出');

      // ★ 关键回归：面板保持打开，键盘收起 ⇒ 落点必须跟着「+」回来
      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.pumpAndSettle();
      expect(gap(tester), closeTo(8, 0.5), reason: 'C 键盘收起后落点不得冻结');
      expect(leftDelta(tester), closeTo(0, 0.5), reason: 'C 左边缘仍对齐');
    });
  });
}
