// ─────────────────────────────────────────────────────────────
// 流式渲染联调测试（T7）
//
// 验证目标：
//   1. ChatStore 流式状态转换（setStreaming → append → complete）
//   2. MessageList 流式状态切换（ThinkingIndicator → 流式气泡 → 完成）
//   3. 模拟 LLM 分块流式数据的完整渲染链路
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/providers/chat_store.dart';
import 'package:writingcoach/widgets/message_list.dart';

void main() {
  group('流式渲染联调', () {
    test('ChatStore 流式状态转换', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(chatStoreProvider.notifier);

      // 1. 启动流式
      notifier.setStreaming(true);
      expect(container.read(chatStoreProvider).isStreaming, true);
      expect(container.read(chatStoreProvider).streamingContent, '');

      // 2. 累加 token
      notifier.appendStreamingContent('Hello');
      notifier.appendStreamingContent(' World');
      expect(container.read(chatStoreProvider).streamingContent, 'Hello World');

      // 3. 完成
      final msg = Message(
        id: 'm1',
        sessionId: 's1',
        role: 'assistant',
        content: 'Hello World',
        timestamp: 0,
        messageType: 'chat',
      );
      notifier.completeStreaming(msg);
      expect(container.read(chatStoreProvider).isStreaming, false);
      expect(container.read(chatStoreProvider).streamingContent, '');
      expect(container.read(chatStoreProvider).messages.length, 1);
    });

    testWidgets('MessageList 流式状态切换', (tester) async {
      // 阶段 1：流式启动 + 内容空 → ThinkingIndicator
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageList(
              messages: const [],
              isStreaming: true,
              streamingContent: '',
            ),
          ),
        ),
      );
      expect(find.byType(ThinkingIndicator), findsOneWidget);

      // 阶段 2：收到 token → 显示流式气泡
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageList(
              messages: const [],
              isStreaming: true,
              streamingContent: '正在回复',
            ),
          ),
        ),
      );
      expect(find.byType(ThinkingIndicator), findsNothing);
      expect(find.text('正在回复'), findsOneWidget);

      // 阶段 3：完成 → 消息持久化
      final msg = Message(
        id: 'm1',
        sessionId: 's1',
        role: 'assistant',
        content: '最终回复',
        timestamp: 1700000000,
        messageType: 'chat',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageList(
              messages: [msg],
              isStreaming: false,
              streamingContent: '',
            ),
          ),
        ),
      );
      expect(find.text('最终回复'), findsOneWidget);
      expect(find.byType(ThinkingIndicator), findsNothing);
    });

    testWidgets('批次51 诊断阶段流式（已有流式内容）→ 显示诊断占位而非流式文本', (tester) async {
      // 诊断阶段：即使 streamingContent 非空（协议块拦截后的前导文本），
      // 也应隐藏文本统一走占位，避免「先长文本后变卡片」跳变
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageList(
              messages: const [],
              isStreaming: true,
              streamingContent: '本章结构清晰，节奏明快。',
              streamStageLabel: '正在诊断本章…',
            ),
          ),
        ),
      );

      expect(find.byType(ThinkingIndicator), findsOneWidget);
      expect(find.text('正在诊断本章…'), findsOneWidget);
      expect(find.textContaining('本章结构清晰'), findsNothing);
    });

    testWidgets('批次51 评估阶段流式 → 保留流式文本（仅诊断隐藏）', (tester) async {
      // 评估/快速观察等阶段最终交付物是文本，不应隐藏流式内容
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageList(
              messages: const [],
              isStreaming: true,
              streamingContent: '你这段改得很到位，冲突更自然了。',
              streamStageLabel: '正在评估你的改写…',
            ),
          ),
        ),
      );

      expect(find.byType(ThinkingIndicator), findsNothing);
      expect(find.text('你这段改得很到位，冲突更自然了。'), findsOneWidget);
    });

    testWidgets('批次53 消息 item 被 RepaintBoundary 隔离（每 token 重绘不扩散）', (
      tester,
    ) async {
      // 历史消息 2 条 + 流式气泡：每个 item 都应独立于 RepaintBoundary，
      // 使 appendStreamingContent 触发全列表 rebuild 时绘制/动画不扩散
      final msgs = [
        Message(
          id: 'm1',
          sessionId: 's1',
          role: 'user',
          content: '历史消息1',
          timestamp: 0,
          messageType: 'chat',
        ),
        Message(
          id: 'm2',
          sessionId: 's1',
          role: 'assistant',
          content: '历史消息2',
          timestamp: 1,
          messageType: 'chat',
        ),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageList(
              messages: msgs,
              isStreaming: true,
              streamingContent: '流式中的回复内容',
            ),
          ),
        ),
      );

      // 历史消息 + 流式气泡均被带消息级 key 的 RepaintBoundary 包裹
      expect(find.byKey(const ValueKey('msg-item-m1')), findsOneWidget);
      expect(find.byKey(const ValueKey('msg-item-m2')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('msg-item-__streaming__')),
        findsOneWidget,
      );
      // 包裹层是 RepaintBoundary（非普通容器）
      expect(
        tester.widget<RepaintBoundary>(
          find.byKey(const ValueKey('msg-item-__streaming__')),
        ),
        isA<RepaintBoundary>(),
      );
      // 渲染未被破坏：历史消息 + 流式文本都可见
      expect(find.text('历史消息1'), findsOneWidget);
      expect(find.text('流式中的回复内容'), findsOneWidget);
    });

    testWidgets('模拟 LLM 分块流式 → 逐块渲染 → 最终持久化', (tester) async {
      // 模拟 LLM 分块推送的完整链路
      final chunks = ['你好，', '我是月笙。', '今天我们来聊聊', '写作吧。'];
      final fullContent = chunks.join();

      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(chatStoreProvider.notifier);

      // 1. 启动流式
      notifier.setStreaming(true);

      // 2. 逐块推送
      for (final chunk in chunks) {
        notifier.appendStreamingContent(chunk);
      }

      // 验证累加正确
      expect(container.read(chatStoreProvider).streamingContent, fullContent);

      // 3. 渲染验证：流式气泡应显示完整内容
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageList(
              messages: const [],
              isStreaming: true,
              streamingContent: container
                  .read(chatStoreProvider)
                  .streamingContent,
            ),
          ),
        ),
      );
      expect(find.text(fullContent), findsOneWidget);

      // 4. 完成 → 持久化消息
      final msg = Message(
        id: 'm_final',
        sessionId: 's1',
        role: 'assistant',
        content: fullContent,
        timestamp: 1700000001,
        messageType: 'chat',
      );
      notifier.completeStreaming(msg);
      expect(container.read(chatStoreProvider).isStreaming, false);
      expect(container.read(chatStoreProvider).messages.length, 1);
      expect(
        container.read(chatStoreProvider).messages.first.content,
        fullContent,
      );
    });

    testWidgets('流式中错误恢复 → setError 后可重新发送', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(chatStoreProvider.notifier);

      // 1. 启动流式
      notifier.setStreaming(true);
      expect(container.read(chatStoreProvider).isStreaming, true);

      // 2. 收到部分内容后出错
      notifier.appendStreamingContent('部分内容');
      notifier.setError('网络断开');

      // 验证错误状态
      final errorState = container.read(chatStoreProvider);
      expect(errorState.isStreaming, false);
      expect(errorState.streamingContent, '');
      expect(errorState.error, '网络断开');

      // 3. 渲染错误 UI
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                Expanded(
                  child: MessageList(
                    messages: const [],
                    isStreaming: errorState.isStreaming,
                    streamingContent: errorState.streamingContent,
                  ),
                ),
                if (errorState.error != null)
                  Container(
                    padding: const EdgeInsets.all(8),
                    color: const Color(0xFFFEE2E2),
                    child: Text(errorState.error!),
                  ),
              ],
            ),
          ),
        ),
      );
      expect(find.text('网络断开'), findsOneWidget);
      expect(find.byType(ThinkingIndicator), findsNothing);

      // 4. 清除错误后可重新启动
      notifier.clearError();
      notifier.setStreaming(true);
      expect(container.read(chatStoreProvider).error, isNull);
      expect(container.read(chatStoreProvider).isStreaming, true);
    });
  });
}
