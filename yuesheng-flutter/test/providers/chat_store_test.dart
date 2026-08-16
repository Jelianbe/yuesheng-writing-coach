// ─────────────────────────────────────────────────────────────
// chat_store_test — ChatStore 状态管理单元测试
//
// 覆盖路径：
//   1. 初始状态
//   2. setStreaming：启动流式 + 清空 streamingContent + 清空 error
//   3. appendStreamingContent：累加 delta
//   4. addMessage：追加消息到列表
//   5. setError：设置 error + 重置 isStreaming
//   6. completeStreaming：追加 assistant 消息 + 重置流式状态
//   7. setSessionId / setMessages / clearError
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/providers/chat_store.dart';

Message _msg({
  required String id,
  required String role,
  required String content,
}) {
  return Message(
    id: id,
    sessionId: 's1',
    role: role,
    content: content,
    timestamp: 1700000000,
    messageType: 'chat',
  );
}

void main() {
  group('ChatStore', () {
    test(
      '#1 初始状态：messages 空 / isStreaming=false / streamingContent 空 / error null / sessionId null',
      () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final state = container.read(chatStoreProvider);
        expect(state.messages, isEmpty);
        expect(state.isStreaming, false);
        expect(state.streamingContent, isEmpty);
        expect(state.error, isNull);
        expect(state.currentSessionId, isNull);
      },
    );

    test(
      '#2 setStreaming(true)：isStreaming=true + 清空 streamingContent + 清空 error',
      () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final notifier = container.read(chatStoreProvider.notifier);
        // 先设置非初始状态，验证 setStreaming 会清空
        notifier.setError('残留错误');
        notifier.setStreaming(true);

        final state = container.read(chatStoreProvider);
        expect(state.isStreaming, true);
        expect(state.streamingContent, isEmpty);
        expect(state.error, isNull);
      },
    );

    test('#3 appendStreamingContent：累加 delta', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(chatStoreProvider.notifier);
      notifier.setStreaming(true);
      notifier.appendStreamingContent('Hello');
      notifier.appendStreamingContent(' World');

      expect(container.read(chatStoreProvider).streamingContent, 'Hello World');
    });

    test('#4 addMessage：追加消息到列表末尾', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(chatStoreProvider.notifier);
      final m1 = _msg(id: 'm1', role: 'user', content: '你好');
      final m2 = _msg(id: 'm2', role: 'assistant', content: '你好，我是月笙');

      notifier.addMessage(m1);
      notifier.addMessage(m2);

      final state = container.read(chatStoreProvider);
      expect(state.messages.length, 2);
      expect(state.messages[0].id, 'm1');
      expect(state.messages[1].id, 'm2');
    });

    test(
      '#5 setError：设置 error + 重置 isStreaming=false + 清空 streamingContent',
      () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final notifier = container.read(chatStoreProvider.notifier);
        notifier.setStreaming(true);
        notifier.appendStreamingContent('partial');
        notifier.setError('网络错误');

        final state = container.read(chatStoreProvider);
        expect(state.error, '网络错误');
        expect(state.isStreaming, false);
        expect(state.streamingContent, isEmpty);
      },
    );

    test('#6 completeStreaming：追加 assistant 消息 + 重置流式状态', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(chatStoreProvider.notifier);
      notifier.setStreaming(true);
      notifier.appendStreamingContent('partial');

      final msg = _msg(id: 'm1', role: 'assistant', content: 'final content');
      notifier.completeStreaming(msg);

      final state = container.read(chatStoreProvider);
      expect(state.isStreaming, false);
      expect(state.streamingContent, isEmpty);
      expect(state.error, isNull);
      expect(state.messages.length, 1);
      expect(state.messages.first.content, 'final content');
    });

    test('#7 setSessionId / setMessages / clearError', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(chatStoreProvider.notifier);

      notifier.setSessionId('session-xyz');
      expect(container.read(chatStoreProvider).currentSessionId, 'session-xyz');

      final msgs = [_msg(id: 'm1', role: 'user', content: 'a')];
      notifier.setMessages(msgs);
      expect(container.read(chatStoreProvider).messages.length, 1);

      notifier.setError('err');
      expect(container.read(chatStoreProvider).error, 'err');
      notifier.clearError();
      expect(container.read(chatStoreProvider).error, isNull);
    });
  });
}
