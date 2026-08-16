// ─────────────────────────────────────────────────────────────
// MessageBubble widget 测试 — 基础气泡
//
// 覆盖路径：
//   1. user 消息：右对齐 + 竹青背景 + 内容显示
//   2. assistant 消息：左对齐 + 灰白背景 + 内容显示
//   3. streaming 气泡：半透明 + 左对齐
//   4. 时间戳显示（非 streaming）
//   5. 批次71：@ 引用徽章（渲染 + 点击跳转 + 非法 JSON 降级）
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/widgets/message_bubble.dart';

Message _msg({
  required String role,
  required String content,
  String messageType = 'chat',
  String? referencesJson,
}) {
  return Message(
    id: 'm1',
    sessionId: 's1',
    role: role,
    content: content,
    timestamp: 1700000000,
    messageType: messageType,
    referencesJson: referencesJson,
  );
}

void main() {
  group('MessageBubble', () {
    testWidgets('user 消息：右对齐 + 竹青背景 + 内容显示', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageBubble(
              message: _msg(role: 'user', content: '你好'),
            ),
          ),
        ),
      );

      expect(find.text('你好'), findsOneWidget);
      // user 消息应右对齐（通过 Align alignment 判断）
      final align = tester.widget<Align>(find.byType(Align));
      expect(align.alignment, Alignment.centerRight);
    });

    testWidgets('assistant 消息：显示头像 + 灰白背景 + 内容显示', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageBubble(
              message: _msg(role: 'assistant', content: '你好，我是月笙'),
            ),
          ),
        ),
      );

      expect(find.text('你好，我是月笙'), findsOneWidget);
      // 应显示"月"字头像
      expect(find.text('月'), findsOneWidget);
      // assistant 气泡使用 Row 布局（头像 + 内容行 + 元信息行）
      expect(find.byType(Row), findsNWidgets(2));
    });

    testWidgets('streaming 气泡：应用半透明', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageBubble(
              message: _msg(role: 'assistant', content: '正在输入...'),
              isStreaming: true,
            ),
          ),
        ),
      );

      // streaming 时 opacity 应该 < 1
      final opacity = tester.widget<Opacity>(find.byType(Opacity));
      expect(opacity.opacity, lessThan(1.0));
    });

    testWidgets('时间戳显示（非 streaming）', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageBubble(
              message: _msg(role: 'user', content: 'test'),
            ),
          ),
        ),
      );

      // 应显示时间戳（具体格式不强制，只要存在 Text widget 显示时间）
      expect(find.byType(Text), findsNWidgets(2)); // 内容 + 时间戳
    });

    testWidgets('assistant 时间戳在气泡外部', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageBubble(
              message: _msg(role: 'assistant', content: '你好'),
            ),
          ),
        ),
      );

      // assistant 消息应有 3 个 Text：头像"月" + 内容 + 时间戳
      expect(find.byType(Text), findsNWidgets(3));
    });

    testWidgets('streaming 时不显示时间戳', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageBubble(
              message: _msg(role: 'assistant', content: '正在输入...'),
              isStreaming: true,
            ),
          ),
        ),
      );

      // streaming 时只有 2 个 Text：头像"月" + 内容（无时间戳）
      expect(find.byType(Text), findsNWidgets(2));
    });

    testWidgets('批次14：assistant 非 streaming + onSaveToFile → 显示保存到文件按钮并可点击', (
      tester,
    ) async {
      Message? savedMessage;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageBubble(
              message: _msg(role: 'assistant', content: '教练回复内容'),
              onSaveToFile: (m) => savedMessage = m,
            ),
          ),
        ),
      );

      expect(find.text('保存到文件'), findsOneWidget);
      await tester.tap(find.text('保存到文件'));
      expect(savedMessage?.content, '教练回复内容');
    });

    testWidgets('批次14：未传 onSaveToFile → 不显示保存到文件按钮', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageBubble(
              message: _msg(role: 'assistant', content: '教练回复内容'),
            ),
          ),
        ),
      );

      expect(find.text('保存到文件'), findsNothing);
    });

    testWidgets('批次14：streaming 时即使提供 onSaveToFile 也不显示按钮', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageBubble(
              message: _msg(role: 'assistant', content: '正在输入...'),
              isStreaming: true,
              onSaveToFile: (m) {},
            ),
          ),
        ),
      );

      expect(find.text('保存到文件'), findsNothing);
    });

    group('批次71：@ 引用徽章', () {
      testWidgets('user 消息带引用快照 → 显示徽章标题', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MessageBubble(
                message: _msg(
                  role: 'user',
                  content: '帮我看看',
                  referencesJson: jsonEncode([
                    {
                      'refType': 'chapter',
                      'refId': 'c1',
                      'manuscriptId': 'm1',
                      'title': '我的小说 · 第三章',
                    },
                  ]),
                ),
              ),
            ),
          ),
        );

        expect(find.text('我的小说 · 第三章'), findsOneWidget);
        // 章节徽章应显示描述图标
        expect(find.byIcon(Icons.description_outlined), findsOneWidget);
      });

      testWidgets('作品/素材徽章使用对应图标', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MessageBubble(
                message: _msg(
                  role: 'user',
                  content: '结合这些材料',
                  referencesJson: jsonEncode([
                    {
                      'refType': 'manuscript',
                      'refId': 'm1',
                      'manuscriptId': 'm1',
                      'title': '我的小说',
                    },
                    {
                      'refType': 'file',
                      'refId': 'f1',
                      'manuscriptId': 'm1',
                      'title': '【素材】大纲.txt',
                    },
                  ]),
                ),
              ),
            ),
          ),
        );

        expect(find.text('我的小说'), findsOneWidget);
        expect(find.text('【素材】大纲.txt'), findsOneWidget);
        expect(find.byIcon(Icons.menu_book_outlined), findsOneWidget);
        expect(find.byIcon(Icons.attach_file), findsOneWidget);
      });

      testWidgets('点击徽章触发 onMentionTap（回传 refType/refId/manuscriptId）', (
        tester,
      ) async {
        String? tappedRefType;
        String? tappedRefId;
        String? tappedManuscriptId;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MessageBubble(
                message: _msg(
                  role: 'user',
                  content: '帮我看看',
                  referencesJson: jsonEncode([
                    {
                      'refType': 'chapter',
                      'refId': 'c1',
                      'manuscriptId': 'm1',
                      'title': '我的小说 · 第三章',
                    },
                  ]),
                ),
                onMentionTap: (refType, refId, manuscriptId) {
                  tappedRefType = refType;
                  tappedRefId = refId;
                  tappedManuscriptId = manuscriptId;
                },
              ),
            ),
          ),
        );

        await tester.tap(find.text('我的小说 · 第三章'));
        expect(tappedRefType, 'chapter');
        expect(tappedRefId, 'c1');
        expect(tappedManuscriptId, 'm1');
      });

      testWidgets('非法 referencesJson → 降级不显示徽章', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MessageBubble(
                message: _msg(
                  role: 'user',
                  content: 'hi',
                  referencesJson: 'not-a-json',
                ),
              ),
            ),
          ),
        );

        expect(find.byIcon(Icons.menu_book_outlined), findsNothing);
        expect(find.byIcon(Icons.description_outlined), findsNothing);
      });
    });
  });
}
