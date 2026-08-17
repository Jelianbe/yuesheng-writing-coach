// ─────────────────────────────────────────────────────────────
// chat_store — 聊天状态管理
// 复刻 yuesheng-android/src/store/chat-store.ts
//
// 管理状态：
//   - currentSessionId：当前会话 ID
//   - messages：消息列表（已持久化的）
//   - isStreaming：是否正在接收 LLM 流式回复
//   - streamingContent：流式累加的临时内容（完成后清空）
//   - error：最近一次错误（UI 显示用）
//   - failedMessageIds：发送失败的消息 ID 集合（纯内存状态，不持久化）
//
// 状态转换契约：
//   setStreaming(true)  → 清空 streamingContent + 清空 error
//   appendStreamingContent(delta) → 累加到 streamingContent
//   completeStreaming(msg) → 追加 msg 到 messages + 重置流式状态
//   setError(err) → 设置 error + 标记最后一条 user 消息为 failed + 重置 isStreaming
//   markMessageFailed(msgId) → 加入 failedMessageIds
//   clearMessageFailed(msgId) → 从 failedMessageIds 移除
// ─────────────────────────────────────────────────────────────

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database/database.dart';

/// 聊天状态（不可变）
class ChatState {
  final String? currentSessionId;
  final List<Message> messages;
  final bool isStreaming;
  final String streamingContent;

  /// 批次49：流式阶段标签（诊断/评估等场景显示阶段化「思考中」文案；
  /// null = 默认「正在思考…」）
  final String? streamStageLabel;
  final String? error;
  final Set<String> failedMessageIds;

  const ChatState({
    this.currentSessionId,
    this.messages = const [],
    this.isStreaming = false,
    this.streamingContent = '',
    this.streamStageLabel,
    this.error,
    this.failedMessageIds = const {},
  });

  /// 判断消息是否发送失败
  bool isFailed(String messageId) => failedMessageIds.contains(messageId);

  /// copyWith：error 字段通过 clearError 标志显式清空，避免与「设置 error」语义冲突
  ChatState copyWith({
    String? currentSessionId,
    List<Message>? messages,
    bool? isStreaming,
    String? streamingContent,
    String? streamStageLabel,
    String? error,
    bool clearError = false,
    Set<String>? failedMessageIds,
  }) {
    return ChatState(
      currentSessionId: currentSessionId ?? this.currentSessionId,
      messages: messages ?? this.messages,
      isStreaming: isStreaming ?? this.isStreaming,
      streamingContent: streamingContent ?? this.streamingContent,
      streamStageLabel: streamStageLabel ?? this.streamStageLabel,
      error: clearError ? null : (error ?? this.error),
      failedMessageIds: failedMessageIds ?? this.failedMessageIds,
    );
  }
}

/// 聊天状态管理器
///
/// 状态转换见文件顶部注释。setStreaming/completeStreaming/setError
/// 均会重置流式相关字段，保证流式状态不残留。
class ChatStore extends StateNotifier<ChatState> {
  ChatStore() : super(const ChatState());

  void setSessionId(String sessionId) {
    if (sessionId == state.currentSessionId) return;
    // B14：切换会话时重置流式状态，避免跨会话 stream 泄漏
    // （A 会话流式进行中切到 B，isStreaming/streamingContent 不应残留到 B）
    state = ChatState(
      currentSessionId: sessionId,
      messages: state.messages,
      failedMessageIds: state.failedMessageIds,
    );
  }

  void setMessages(List<Message> messages) {
    state = state.copyWith(messages: messages);
  }

  void addMessage(Message message) {
    state = state.copyWith(messages: [...state.messages, message]);
  }

  /// 从内存列表中移除消息（删除确认后调用）
  void removeMessage(String messageId) {
    state = state.copyWith(
      messages: state.messages.where((m) => m.id != messageId).toList(),
    );
  }

  /// 启动/停止流式：启动时清空 streamingContent + error
  ///
  /// 注意：仅用于启动（true）。停止流式应通过 completeStreaming 或 setError，
  /// 它们会同时处理消息追加或错误设置。直接 setStreaming(false) 也可用，
  /// 但会保留 streamingContent（需调用方手动清空）。
  ///
  /// [stageLabel] 批次49：流式阶段标签（诊断/评估等），null = 默认「正在思考…」。
  void setStreaming(bool streaming, {String? stageLabel}) {
    state = ChatState(
      currentSessionId: state.currentSessionId,
      messages: state.messages,
      isStreaming: streaming,
      streamingContent: '',
      streamStageLabel: streaming ? stageLabel : null,
      error: null,
      failedMessageIds: state.failedMessageIds,
    );
  }

  void appendStreamingContent(String delta) {
    state = state.copyWith(streamingContent: state.streamingContent + delta);
  }

  /// 完成流式：追加 assistant 消息 + 重置流式状态
  void completeStreaming(Message assistantMessage) {
    state = ChatState(
      currentSessionId: state.currentSessionId,
      messages: [...state.messages, assistantMessage],
      isStreaming: false,
      streamingContent: '',
      error: null,
      failedMessageIds: state.failedMessageIds,
    );
  }

  /// 主动取消生成：重置流式状态但不标记消息失败（区别于 setError）。
  /// 用户主动中止是预期行为，不应把最后一条 user 消息标红、也不弹错误横幅，
  /// 让发送/识别这条链路干净地退回可继续输入的状态。
  void cancelStreaming() {
    state = state.copyWith(
      isStreaming: false,
      streamingContent: '',
      clearError: true,
    );
  }

  /// 设置错误：标记最后一条 user 消息为 failed + 重置 isStreaming + 清空 streamingContent
  void setError(String error) {
    // 找到最后一条 user 消息，标记为 failed（复刻 RN chat-store.ts:147-152）
    final msgs = [...state.messages];
    String? failedId;
    for (var i = msgs.length - 1; i >= 0; i--) {
      if (msgs[i].role == 'user') {
        failedId = msgs[i].id;
        break;
      }
    }
    final newFailedIds = failedId != null
        ? {...state.failedMessageIds, failedId}
        : state.failedMessageIds;

    state = state.copyWith(
      isStreaming: false,
      streamingContent: '',
      error: error,
      failedMessageIds: newFailedIds,
    );
  }

  /// 从失败集合中移除消息（重试时调用）
  void clearMessageFailed(String messageId) {
    final newFailedIds = {...state.failedMessageIds}..remove(messageId);
    state = state.copyWith(failedMessageIds: newFailedIds, clearError: true);
  }

  void clearError() {
    state = state.copyWith(clearError: true);
  }
}

final chatStoreProvider = StateNotifierProvider<ChatStore, ChatState>((ref) {
  return ChatStore();
});

/// 批次 13：成长页「写作诊断」选章后传递的待诊断章节 ID
///
/// 成长页选章 → 设置该值并切到对话 Tab → ChatPage 监听非空时自动发起诊断，
/// 完成后置回 null（对齐 RN /chat?startDiagnosis=true 参数语义）。
final pendingDiagnosisChapterProvider = StateProvider<String?>((ref) => null);

/// 批次 30：作品详情页「相关对话」点击后传递的待打开会话 ID
///
/// 相关对话 Tab 点击会话 → 设置该值并切到对话 Tab（/）→ ChatPage
/// 监听非空时调用 _handleSwitchSession 打开目标会话，随后置回 null
/// （对齐 pendingDiagnosisChapterProvider 交接模式）。
final pendingOpenSessionProvider = StateProvider<String?>((ref) => null);
