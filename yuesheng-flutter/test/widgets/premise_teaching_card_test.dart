// T-20261110-13 · premise_teaching_card 测试（报批稿 R3/R4 判据 + U3 裁定自证）
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/widgets/premise_teaching_card.dart';

Message _msg(String id, String role, String content) => Message(
  id: id,
  sessionId: 's',
  role: role,
  content: content,
  timestamp: 0,
  messageType: 'chat',
  truncated: 0,
);

List<Map<String, dynamic>> _renderItems(List<Message> msgs) => [
  for (final m in msgs) {'type': 'message', 'data': m},
];

void main() {
  group('R4 · shouldAttachCard（每会话只渲染一张）', () {
    test('第一个触发轮的 assistant 回应 ⇒ 附卡', () {
      final items = _renderItems([
        _msg('u1', 'user', '你好'),
        _msg('a1', 'assistant', '你好呀'),
        _msg('u2', 'user', '我想聊聊这本书的题材定位'),
        _msg('a2', 'assistant', '好，我们聊聊'),
      ]);
      expect(PremiseTeachingCard.shouldAttachCard(items, 3), isTrue);
    });

    test('第二个触发轮的回应 ⇒ 不渲染第二张（R4）', () {
      final items = _renderItems([
        _msg('u1', 'user', '我想聊聊这本书的题材定位'),
        _msg('a1', 'assistant', '回应1'),
        _msg('u2', 'user', '再说说赛道的事'),
        _msg('a2', 'assistant', '回应2'),
      ]);
      expect(PremiseTeachingCard.shouldAttachCard(items, 1), isTrue);
      expect(PremiseTeachingCard.shouldAttachCard(items, 3), isFalse);
    });

    test('无触发轮 ⇒ 全部不附卡', () {
      final items = _renderItems([
        _msg('u1', 'user', '今天天气不错'),
        _msg('a1', 'assistant', '是呀'),
      ]);
      expect(PremiseTeachingCard.shouldAttachCard(items, 1), isFalse);
    });

    test('触发轮之后的第一条 assistant 才是目标（中间隔非命中轮不转移）', () {
      final items = _renderItems([
        _msg('u1', 'user', '说说题材'),
        _msg('a1', 'assistant', '回应1'),
        _msg('u2', 'user', '写完一章了'),
        _msg('a2', 'assistant', '回应2'),
      ]);
      expect(PremiseTeachingCard.shouldAttachCard(items, 1), isTrue);
      expect(PremiseTeachingCard.shouldAttachCard(items, 3), isFalse);
    });
  });

  group('R3 · 卡渲染（展开四段标题）', () {
    Future<void> pumpCard(WidgetTester tester, {bool expanded = false}) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: Scaffold(
            body: PremiseTeachingCard(initiallyExpanded: expanded),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('收起态：卡头单行，正文不渲染', (tester) async {
      await pumpCard(tester);
      expect(find.text(kPremiseCardTitle), findsOneWidget);
      // 四段正文未渲染（收起）
      expect(find.text('核心本质'), findsNothing);
    });

    testWidgets('R3：展开渲染四段标题（不含严重度判断参考——U3 裁定）', (tester) async {
      await pumpCard(tester, expanded: true);
      // R3 断言锚 = 四段标题齐
      expect(find.text('核心本质'), findsOneWidget);
      expect(find.text('教学要点'), findsOneWidget);
      expect(find.text('常见误区'), findsOneWidget);
      expect(find.text('教学素材库'), findsOneWidget);
      // U3 裁定自证：严重度判断参考段不渲染
      expect(find.text('严重度判断参考'), findsNothing);
      // 卡面不露症候编号（P031 标题是注入串锚，卡面标题无编号）
      expect(find.textContaining('P031'), findsNothing);
    });

    testWidgets('点卡头切换展开/收起', (tester) async {
      await pumpCard(tester);
      expect(find.text('核心本质'), findsNothing);
      await tester.tap(find.text(kPremiseCardTitle));
      await tester.pumpAndSettle();
      expect(find.text('核心本质'), findsOneWidget);
      await tester.tap(find.text(kPremiseCardTitle));
      await tester.pumpAndSettle();
      expect(find.text('核心本质'), findsNothing);
    });
  });
}
