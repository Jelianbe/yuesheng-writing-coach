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

    test('#8 B14 切换会话清空流式状态（防止跨会话 stream 泄漏）', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(chatStoreProvider.notifier);

      // 会话 A 流式进行中
      notifier.setSessionId('session-A');
      notifier.setStreaming(true);
      notifier.appendStreamingContent('正在生成…');
      expect(container.read(chatStoreProvider).isStreaming, isTrue);
      expect(container.read(chatStoreProvider).streamingContent, isNotEmpty);

      // 切到会话 B：流式状态必须被清空，不得泄漏到 B
      notifier.setSessionId('session-B');
      final after = container.read(chatStoreProvider);
      expect(after.currentSessionId, 'session-B');
      expect(after.isStreaming, isFalse);
      expect(after.streamingContent, isEmpty);
      expect(after.streamStageLabel, isNull);
    });

    // ── 以下为第五批审查补充 ──────────────────────────────────
    // CR-37：这四个方法此前零覆盖，且都在「发送失败 → 重试」链路上

    test('#8 CR-37 removeMessage：从列表移除指定消息', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(chatStoreProvider.notifier);

      notifier.setMessages([
        _msg(id: 'u1', role: 'user', content: 'a'),
        _msg(id: 'a1', role: 'assistant', content: 'b'),
      ]);
      notifier.removeMessage('a1');

      final ids = container
          .read(chatStoreProvider)
          .messages
          .map((m) => m.id)
          .toList();
      expect(ids, ['u1'], reason: '只移除目标 id，其余保持原顺序');

      // 移除不存在的 id 不应抛，也不应影响列表
      notifier.removeMessage('not-exist');
      expect(container.read(chatStoreProvider).messages.length, 1);
    });

    test('#9 CR-37 cancelStreaming：清 error 与流式态，但不标消息失败', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(chatStoreProvider.notifier);

      notifier.setMessages([_msg(id: 'u1', role: 'user', content: 'hi')]);
      notifier.setStreaming(true);
      notifier.appendStreamingContent('半截内容');
      notifier.setError('网络错误');
      expect(container.read(chatStoreProvider).isFailed('u1'), isTrue);

      notifier.cancelStreaming();
      final s = container.read(chatStoreProvider);
      expect(s.isStreaming, isFalse);
      expect(s.streamingContent, isEmpty, reason: '取消后不再展示半截内容');
      expect(s.error, isNull);
      expect(
        s.isFailed('u1'),
        isTrue,
        reason: '「已标记失败」是既成状态，cancel 只负责干净退出本轮，不擦除历史',
      );
    });

    test('#10 CR-37 clearMessageFailed：重试前解除失败标记', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(chatStoreProvider.notifier);

      notifier.setMessages([_msg(id: 'u1', role: 'user', content: 'hi')]);
      notifier.setError('网络错误');
      expect(container.read(chatStoreProvider).isFailed('u1'), isTrue);

      notifier.clearMessageFailed('u1');
      final s = container.read(chatStoreProvider);
      expect(s.isFailed('u1'), isFalse);
      expect(s.error, isNull, reason: '解除失败标记时一并清掉错误横幅');
    });

    test('#11 CR-37 isFailed：仅对已标记 id 为真', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(chatStoreProvider.notifier);

      notifier.setMessages([
        _msg(id: 'u1', role: 'user', content: 'a'),
        _msg(id: 'a1', role: 'assistant', content: 'b'),
      ]);
      notifier.setError('出错了');

      final s = container.read(chatStoreProvider);
      expect(s.isFailed('u1'), isTrue, reason: 'setError 只标最后一条 user 消息');
      expect(s.isFailed('a1'), isFalse, reason: 'assistant 消息不该被标失败');
      expect(s.isFailed('nope'), isFalse);
    });

    // CR-34 回归：三处手写重建改为 copyWith 后，语义必须逐条等价。
    // 重点锁「重置为真」的字段——copyWith 无法用传 null 表达清空，
    // 若漏了 clear 标志，这里会静默沿用旧值。
    test('#12 CR-34 回归：setStreaming(true) 无 label 时重置阶段标签', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(chatStoreProvider.notifier);

      notifier.setStreaming(true, stageLabel: '正在诊断');
      expect(container.read(chatStoreProvider).streamStageLabel, '正在诊断');

      // 第二轮不带 label：不得沿用上一轮的「正在诊断」
      notifier.setStreaming(true);
      expect(
        container.read(chatStoreProvider).streamStageLabel,
        isNull,
        reason: '改造前靠重建隐式置 null，改造后靠 clear 标志，行为须一致',
      );

      notifier.setStreaming(false);
      expect(container.read(chatStoreProvider).streamStageLabel, isNull);
    });

    test('#13 CR-34 回归：completeStreaming 清空阶段标签', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(chatStoreProvider.notifier);

      notifier.setStreaming(true, stageLabel: '正在诊断');
      notifier.completeStreaming(
        _msg(id: 'a1', role: 'assistant', content: 'done'),
      );

      final s = container.read(chatStoreProvider);
      expect(s.streamStageLabel, isNull);
      expect(s.isStreaming, isFalse);
      expect(s.messages.length, 1);
      expect(s.error, isNull);
    });
  });
}
