# 阶段 1 MVP 实施计划 — 聊天主页核心

> **目标**：实现最小可用的聊天主页（消息列表 + 输入框 + 流式回复渲染），让 App 能完成"用户发消息 → AI 流式回复"的核心闭环。

**架构**：在现有 chat_service.dart（已实现三层管线）+ llm_client.dart（已实现 streamChat）基础上，引入 Riverpod 做状态管理，实现 ChatPage 主页 + MessageList + ChatInput + 流式累加渲染。

**技术栈**：Flutter + Riverpod（状态管理）+ drift（DB）+ 现有 chat_service / llm_client

**范围限制（MVP 不实现）**：
- 诊断卡片 / 教学建议卡片 / 训练任务卡片（message_type 路由只处理 `chat`）
- ChatModals（诊断确认 / 症候详情 / 引用选择 / 文件上传 / SessionDrawer / SaveToFile）
- TaskPanel / QuickChips / AttitudeSuggestionBanner / ChatHeader 态度切换
- 长按删除 / 重试失败消息 / 采纳到章节 / 保存到文件
- 章节引用 `@W001/C003` 解析
- 呼吸动画（先做功能，动画后续打磨）

---

## 任务依赖图

```
T1 状态管理基建 → T2 ChatStore
                     ↓
T3 MessageBubble（基础） → T4 MessageList → T5 ChatInput
                                                ↓
T6 ChatPage 接线（T2 + T4 + T5 + 现有 chat_service）
                     ↓
T7 流式渲染联调 → T8 chat_service 关键路径测试
```

---

## Task 1: 引入 Riverpod 状态管理基建

**Files:**
- Modify: `pubspec.yaml`（添加 riverpod 依赖）
- Create: `lib/providers/app_providers.dart`

- [ ] **Step 1: 添加 riverpod 依赖**

修改 `pubspec.yaml` 的 `dependencies:` 段，在 flutter 后添加：

```yaml
dependencies:
  flutter:
    sdk: flutter
  flutter_riverpod: ^2.4.9
  riverpod_annotation: ^2.3.0
```

- [ ] **Step 2: 添加 build_runner + riverpod_generator 到 dev_dependencies**

```yaml
dev_dependencies:
  build_runner: ^2.4.7
  riverpod_generator: ^2.3.9
```

- [ ] **Step 3: 运行 flutter pub get**

Run: `flutter pub get`
Expected: 依赖安装成功，无版本冲突

- [ ] **Step 4: 创建 app_providers.dart 提供全局 AppDatabase**

```dart
// lib/providers/app_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/database/database.dart';

/// 全局 AppDatabase provider（单例）
/// 生产环境自动创建，测试时可 override
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});
```

- [ ] **Step 5: 在 main.dart 包裹 ProviderScope**

修改 `lib/main.dart`，用 `ProviderScope` 包裹 `runApp`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'widgets/chat_page.dart';

void main() {
  runApp(const ProviderScope(child: YueshengApp()));
}

class YueshengApp extends StatelessWidget {
  const YueshengApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '月笙写作教练',
      theme: ThemeData(
        primaryColor: const Color(0xFF2D5A52),
        scaffoldBackgroundColor: const Color(0xFFF7F8F6),
      ),
      home: const ChatPage(),
    );
  }
}
```

- [ ] **Step 6: 四闸验证 + commit**

Run: `flutter analyze && flutter test`
Expected: 0 errors / 150 tests pass

```bash
git add pubspec.yaml lib/main.dart lib/providers/app_providers.dart
git commit -m "feat: 引入 Riverpod 状态管理基建"
```

---

## Task 2: ChatStore + session bootstrap 迁移到 Provider（方案2 扩展）

**范围扩展背景**：原 T2 仅实现 ChatStore。用户授权方案 2，将 sessionId/bootstrap 状态从 ChatPage 的 setState 迁移到 Riverpod Provider，ChatPage 改为 ConsumerWidget。避免 T6 接线时出现 setState + Provider 混用的状态管理双轨制。

**Files:**
- Create: `lib/providers/chat_store.dart`（ChatState + ChatStore）
- Create: `lib/providers/session_providers.dart`（SessionBootstrapState + sessionBootstrapProvider + bootstrapServiceProvider）
- Modify: `lib/widgets/chat_page.dart`（StatefulWidget → ConsumerWidget，删除本地 _sessionId/_showOnboarding/_initialized/_initError）
- Test: `test/providers/chat_store_test.dart`
- Test: `test/providers/session_providers_test.dart`
- Modify: `test/widgets/chat_page_test.dart`（7 个测试迁移到 ProviderScope override 模式）

**关键技术决策**（用户确认）：
1. Provider 类型：`AsyncNotifierProvider`（支持 onboarding 完成后 `ref.invalidateSelf()` 刷新）
2. 状态结构：单个 record `SessionBootstrapState({String sessionId, bool shouldShowOnboarding})`
3. BootstrapService 暴露为独立 Provider（保留 #7 异常路径测试的 override 能力）

**对齐 RN `store/chat-store.ts`**：管理 messages / isStreaming / streamingContent / error / currentSessionId

- [x] **Step 1: 写 chat_store_test.dart 失败测试**

```dart
// test/providers/chat_store_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:writingcoach/providers/chat_store.dart';

void main() {
  group('ChatStore', () {
    test('初始状态：messages 空 / isStreaming=false / streamingContent 空', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final state = container.read(chatStoreProvider);
      expect(state.messages, isEmpty);
      expect(state.isStreaming, false);
      expect(state.streamingContent, isEmpty);
      expect(state.error, isNull);
      expect(state.currentSessionId, isNull);
    });

    test('setStreaming: 设置 isStreaming=true + 清空 streamingContent + 清空 error', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(chatStoreProvider.notifier).setStreaming(true);
      final state = container.read(chatStoreProvider);
      expect(state.isStreaming, true);
      expect(state.streamingContent, isEmpty);
      expect(state.error, isNull);
    });

    test('appendStreamingContent: 累加 delta', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(chatStoreProvider.notifier);
      notifier.setStreaming(true);
      notifier.appendStreamingContent('Hello');
      notifier.appendStreamingContent(' World');

      expect(container.read(chatStoreProvider).streamingContent, 'Hello World');
    });

    test('addMessage: 追加消息到列表', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final msg = Message(
        id: 'm1',
        sessionId: 's1',
        role: 'user',
        content: 'test',
        timestamp: 0,
        messageType: 'chat',
      );
      container.read(chatStoreProvider.notifier).addMessage(msg);

      expect(container.read(chatStoreProvider).messages.length, 1);
    });

    test('setError: 设置 error + 重置 isStreaming', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(chatStoreProvider.notifier);
      notifier.setStreaming(true);
      notifier.setError('网络错误');

      final state = container.read(chatStoreProvider);
      expect(state.error, '网络错误');
      expect(state.isStreaming, false);
    });

    test('completeStreaming: 追加 assistant 消息 + 重置流式状态', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(chatStoreProvider.notifier);
      notifier.setStreaming(true);
      notifier.appendStreamingContent('partial');

      final msg = Message(
        id: 'm1',
        sessionId: 's1',
        role: 'assistant',
        content: 'final content',
        timestamp: 0,
        messageType: 'chat',
      );
      notifier.completeStreaming(msg);

      final state = container.read(chatStoreProvider);
      expect(state.isStreaming, false);
      expect(state.streamingContent, isEmpty);
      expect(state.messages.length, 1);
      expect(state.messages.first.content, 'final content');
    });
  });
}
```

- [x] **Step 2: 运行测试确认失败**

Run: `flutter test test/providers/chat_store_test.dart`
Expected: FAIL — `chat_store.dart` 不存在

- [x] **Step 3: 实现 chat_store.dart**

```dart
// lib/providers/chat_store.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database/database.dart';

/// 聊天状态
class ChatState {
  final String? currentSessionId;
  final List<Message> messages;
  final bool isStreaming;
  final String streamingContent;
  final String? error;

  const ChatState({
    this.currentSessionId,
    this.messages = const [],
    this.isStreaming = false,
    this.streamingContent = '',
    this.error,
  });

  ChatState copyWith({
    String? currentSessionId,
    List<Message>? messages,
    bool? isStreaming,
    String? streamingContent,
    String? error,
    bool clearError = false,
  }) {
    return ChatState(
      currentSessionId: currentSessionId ?? this.currentSessionId,
      messages: messages ?? this.messages,
      isStreaming: isStreaming ?? this.isStreaming,
      streamingContent: streamingContent ?? this.streamingContent,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// 聊天状态管理器
class ChatStore extends StateNotifier<ChatState> {
  ChatStore() : super(const ChatState());

  void setSessionId(String sessionId) {
    state = state.copyWith(currentSessionId: sessionId);
  }

  void setMessages(List<Message> messages) {
    state = state.copyWith(messages: messages);
  }

  void addMessage(Message message) {
    state = state.copyWith(messages: [...state.messages, message]);
  }

  void setStreaming(bool streaming) {
    state = ChatState(
      currentSessionId: state.currentSessionId,
      messages: state.messages,
      isStreaming: streaming,
      streamingContent: '',
      error: null,
    );
  }

  void appendStreamingContent(String delta) {
    state = state.copyWith(
      streamingContent: state.streamingContent + delta,
    );
  }

  void completeStreaming(Message assistantMessage) {
    state = ChatState(
      currentSessionId: state.currentSessionId,
      messages: [...state.messages, assistantMessage],
      isStreaming: false,
      streamingContent: '',
      error: null,
    );
  }

  void setError(String error) {
    state = state.copyWith(
      isStreaming: false,
      streamingContent: '',
      error: error,
    );
  }

  void clearError() {
    state = state.copyWith(clearError: true);
  }
}

final chatStoreProvider = StateNotifierProvider<ChatStore, ChatState>((ref) {
  return ChatStore();
});
```

- [x] **Step 4: 运行测试确认通过**

Run: `flutter test test/providers/chat_store_test.dart --reporter=expanded`
Expected: 6/6 PASS

- [x] **Step 5: 四闸验证 + commit**（方案2 扩展：含 session_providers + ChatPage 迁移）

```bash
git add lib/providers/chat_store.dart lib/providers/session_providers.dart \
  lib/widgets/chat_page.dart test/providers/chat_store_test.dart \
  test/providers/session_providers_test.dart test/widgets/chat_page_test.dart \
  test/router/app_router_test.dart test/widget_test.dart \
  docs/plans/2026-08-04-mvp-chat-phase1.md
git commit -m "feat: T2 ChatStore + session bootstrap 迁移到 Provider（方案2）"
```

---

## Task 3: 实现 MessageBubble 基础气泡

**Files:**
- Create: `lib/widgets/message_bubble.dart`
- Test: `test/widgets/message_bubble_test.dart`

**MVP 范围**：只渲染 user / assistant 两种 chat 类型气泡，不处理 message_type 卡片分支。

- [x] **Step 1: 写 message_bubble_test.dart 失败测试**

```dart
// test/widgets/message_bubble_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/widgets/message_bubble.dart';

Message _msg({
  required String role,
  required String content,
  String messageType = 'chat',
}) {
  return Message(
    id: 'm1',
    sessionId: 's1',
    role: role,
    content: content,
    timestamp: 1700000000,
    messageType: messageType,
  );
}

void main() {
  group('MessageBubble', () {
    testWidgets('user 消息：右对齐 + 竹青背景 + 内容显示', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MessageBubble(message: _msg(role: 'user', content: '你好')),
        ),
      ));

      expect(find.text('你好'), findsOneWidget);
      // user 消息应右对齐（通过 Align alignment 判断）
      final align = tester.widget<Align>(find.byType(Align));
      expect(align.alignment, Alignment.centerRight);
    });

    testWidgets('assistant 消息：左对齐 + 灰白背景 + 内容显示', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MessageBubble(
            message: _msg(role: 'assistant', content: '你好，我是月笙'),
          ),
        ),
      ));

      expect(find.text('你好，我是月笙'), findsOneWidget);
      final align = tester.widget<Align>(find.byType(Align));
      expect(align.alignment, Alignment.centerLeft);
    });

    testWidgets('streaming 气泡：应用半透明 + 左对齐', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MessageBubble(
            message: _msg(role: 'assistant', content: '正在输入...'),
            isStreaming: true,
          ),
        ),
      ));

      final align = tester.widget<Align>(find.byType(Align));
      expect(align.alignment, Alignment.centerLeft);
      // streaming 时 opacity 应该 < 1（通过 AnimatedOpacity 或 Opacity 判断）
      final opacity = tester.widget<Opacity>(find.byType(Opacity));
      expect(opacity.opacity, lessThan(1.0));
    });

    testWidgets('时间戳显示（非 streaming）', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MessageBubble(
            message: _msg(role: 'user', content: 'test'),
          ),
        ),
      ));

      // 应显示时间戳（具体格式不强制，只要存在 Text widget 显示时间）
      expect(find.byType(Text), findsNWidgets(2)); // 内容 + 时间戳
    });
  });
}
```

- [x] **Step 2: 运行测试确认失败**

Run: `flutter test test/widgets/message_bubble_test.dart`
Expected: FAIL — `message_bubble.dart` 不存在

- [x] **Step 3: 实现 message_bubble.dart**

```dart
// lib/widgets/message_bubble.dart
import 'package:flutter/material.dart';

import '../data/database/database.dart';

/// 单条消息气泡（MVP 版本）
///
/// MVP 范围：
/// - 只渲染 role='user' / 'assistant' 的 chat 类型
/// - 不处理 message_type 卡片分支（diagnosis_result / phase_upgrade 等）
/// - 不处理章节引用卡片 / 重试按钮 / 采纳到章节 / 保存到文件
class MessageBubble extends StatelessWidget {
  final Message message;
  final bool isStreaming;

  const MessageBubble({
    super.key,
    required this.message,
    this.isStreaming = false,
  });

  bool get _isUser => message.role == 'user';

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: _isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Opacity(
        opacity: isStreaming ? 0.7 : 1.0,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75,
          ),
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: _isUser
                ? const Color(0xFF2D5A52) // 月色竹青
                : const Color(0xFFF2F4F2), // 灰白
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                message.content,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.4,
                  color: _isUser ? Colors.white : const Color(0xFF2D3142),
                ),
              ),
              if (!isStreaming) ...[
                const SizedBox(height: 4),
                Text(
                  _formatTime(message.timestamp),
                  style: TextStyle(
                    fontSize: 11,
                    color: _isUser
                        ? Colors.white.withValues(alpha: 0.6)
                        : const Color(0xFF8A8D93),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(int timestamp) {
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    return '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }
}
```

- [x] **Step 4: 运行测试确认通过**

Run: `flutter test test/widgets/message_bubble_test.dart --reporter=expanded`
Expected: 4/4 PASS

- [x] **Step 5: 四闸验证 + commit**

```bash
git add lib/widgets/message_bubble.dart test/widgets/message_bubble_test.dart
git commit -m "feat: 实现 MessageBubble 基础气泡（user/assistant）"
```

---

## Task 4: 实现 MessageList 消息列表

**Files:**
- Create: `lib/widgets/message_list.dart`
- Test: `test/widgets/message_list_test.dart`

**核心职责**：
1. 用 ListView.builder 渲染 messages 数组
2. 流式时把 streamingContent 包装为虚拟消息追加到末尾
3. isStreaming && streamingContent 为空时显示 ThinkingIndicator
4. 自动滚动到底部

- [x] **Step 1: 写 message_list_test.dart 失败测试**

```dart
// test/widgets/message_list.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/widgets/message_list.dart';

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
  group('MessageList', () {
    testWidgets('渲染多条消息', (tester) async {
      final messages = [
        _msg(id: 'm1', role: 'user', content: '你好'),
        _msg(id: 'm2', role: 'assistant', content: '你好，我是月笙'),
      ];

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MessageList(
            messages: messages,
            isStreaming: false,
            streamingContent: '',
          ),
        ),
      ));

      expect(find.text('你好'), findsOneWidget);
      expect(find.text('你好，我是月笙'), findsOneWidget);
    });

    testWidgets('空消息列表 + 非流式 → 显示空容器', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MessageList(
            messages: const [],
            isStreaming: false,
            streamingContent: '',
          ),
        ),
      ));

      // 空列表应显示占位（SizedBox.shrink 或空容器）
      expect(find.byType(MessageBubble), findsNothing);
    });

    testWidgets('流式中 + streamingContent 非空 → 追加虚拟气泡', (tester) async {
      final messages = [
        _msg(id: 'm1', role: 'user', content: '你好'),
      ];

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MessageList(
            messages: messages,
            isStreaming: true,
            streamingContent: '正在回复',
          ),
        ),
      ));

      // 应渲染 user 消息 + streaming 虚拟消息
      expect(find.text('你好'), findsOneWidget);
      expect(find.text('正在回复'), findsOneWidget);
    });

    testWidgets('流式中 + streamingContent 空 → 显示 ThinkingIndicator', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MessageList(
            messages: const [],
            isStreaming: true,
            streamingContent: '',
          ),
        ),
      ));

      expect(find.byType(ThinkingIndicator), findsOneWidget);
    });
  });
}
```

- [x] **Step 2: 运行测试确认失败**

Run: `flutter test test/widgets/message_list_test.dart`
Expected: FAIL — `message_list.dart` 不存在

- [x] **Step 3: 实现 message_list.dart**

```dart
// lib/widgets/message_list.dart
import 'package:flutter/material.dart';

import '../data/database/database.dart';
import 'message_bubble.dart';

/// 消息列表（MVP 版本）
///
/// 对齐 RN MessageList.tsx：
/// - 用 ListView.builder 渲染 messages
/// - 流式时把 streamingContent 包装为虚拟消息追加到末尾
/// - isStreaming && streamingContent 为空时显示 ThinkingIndicator
/// - 自动滚动到底部
class MessageList extends StatefulWidget {
  final List<Message> messages;
  final bool isStreaming;
  final String streamingContent;

  const MessageList({
    super.key,
    required this.messages,
    required this.isStreaming,
    required this.streamingContent,
  });

  @override
  State<MessageList> createState() => _MessageListState();
}

class _MessageListState extends State<MessageList> {
  final ScrollController _scrollController = ScrollController();

  @override
  void didUpdateWidget(MessageList oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 消息数变化或流式内容变化时，滚动到底部
    if (oldWidget.messages.length != widget.messages.length ||
        oldWidget.streamingContent != widget.streamingContent) {
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 构造渲染列表：真实消息 + 可选的流式虚拟消息
    final renderItems = <Map<String, dynamic>>[];

    for (final msg in widget.messages) {
      renderItems.add({'type': 'message', 'data': msg});
    }

    // 流式中：streamingContent 非空 → 追加虚拟消息
    if (widget.isStreaming && widget.streamingContent.isNotEmpty) {
      renderItems.add({
        'type': 'streaming',
        'data': Message(
          id: '__streaming__',
          sessionId: '',
          role: 'assistant',
          content: widget.streamingContent,
          timestamp: 0,
          messageType: 'chat',
        ),
      });
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 16),
      itemCount: renderItems.length + (widget.isStreaming && widget.streamingContent.isEmpty ? 1 : 0),
      itemBuilder: (context, index) {
        // 流式中 + streamingContent 空 → 末尾显示 ThinkingIndicator
        if (widget.isStreaming && widget.streamingContent.isEmpty &&
            index == renderItems.length) {
          return const ThinkingIndicator();
        }

        final item = renderItems[index];
        final msg = item['data'] as Message;
        final isStreamingBubble = item['type'] == 'streaming';

        return MessageBubble(
          message: msg,
          isStreaming: isStreamingBubble,
        );
      },
    );
  }
}

/// 思考指示器（流式启动但尚未收到 token 时显示）
class ThinkingIndicator extends StatelessWidget {
  const ThinkingIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Color(0xFF8A8D93),
            ),
          ),
          SizedBox(width: 8),
          Text(
            '正在思考…',
            style: TextStyle(
              fontSize: 13,
              color: Color(0xFF8A8D93),
            ),
          ),
        ],
      ),
    );
  }
}
```

- [x] **Step 4: 运行测试确认通过**

Run: `flutter test test/widgets/message_list_test.dart --reporter=expanded`
Expected: 4/4 PASS

- [x] **Step 5: 四闸验证 + commit**

```bash
git add lib/widgets/message_list.dart test/widgets/message_list_test.dart
git commit -m "feat: 实现 MessageList 消息列表 + ThinkingIndicator"
```

---

## Task 5: 实现 ChatInput 输入框

**Files:**
- Create: `lib/widgets/chat_input.dart`
- Test: `test/widgets/chat_input_test.dart`

**对齐 RN ChatInput.tsx**：多行 TextInput + 发送按钮，streaming 时禁用。

- [x] **Step 1: 写 chat_input_test.dart 失败测试**

```dart
// test/widgets/chat_input_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/widgets/chat_input.dart';

void main() {
  group('ChatInput', () {
    testWidgets('输入文本 + 点击发送按钮 → 触发 onSend', (tester) async {
      String? sentText;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ChatInput(
            input: '',
            isStreaming: false,
            onInputChange: (_) {},
            onSend: () => sentText = 'triggered',
          ),
        ),
      ));

      // 输入文本
      await tester.enterText(find.byType(TextField), '你好');
      expect(find.text('你好'), findsOneWidget);

      // 点击发送按钮
      await tester.tap(find.byType(FilledButton));
      await tester.pump();

      expect(sentText, 'triggered');
    });

    testWidgets('空输入 → 发送按钮禁用', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ChatInput(
            input: '',
            isStreaming: false,
            onInputChange: (_) {},
            onSend: () {},
          ),
        ),
      ));

      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.enabled, false);
    });

    testWidgets('isStreaming=true → 发送按钮禁用 + TextField 不可编辑', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ChatInput(
            input: '有内容',
            isStreaming: true,
            onInputChange: (_) {},
            onSend: () {},
          ),
        ),
      ));

      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.enabled, false);

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.enabled, false);
    });

    testWidgets('onInputChange 在输入时触发', (tester) async {
      String? changedText;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ChatInput(
            input: '',
            isStreaming: false,
            onInputChange: (text) => changedText = text,
            onSend: () {},
          ),
        ),
      ));

      await tester.enterText(find.byType(TextField), 'test');
      expect(changedText, 'test');
    });
  });
}
```

- [x] **Step 2: 运行测试确认失败**

Run: `flutter test test/widgets/chat_input_test.dart`
Expected: FAIL — `chat_input.dart` 不存在

- [x] **Step 3: 实现 chat_input.dart**

```dart
// lib/widgets/chat_input.dart
import 'package:flutter/material.dart';

/// 聊天输入框（MVP 版本）
///
/// 对齐 RN ChatInput.tsx：
/// - 多行 TextInput
/// - 圆形发送按钮
/// - isStreaming 时禁用
///
/// MVP 不实现：+ 按钮（文件上传）/ @ 按钮（引用）
class ChatInput extends StatelessWidget {
  final String input;
  final bool isStreaming;
  final void Function(String text) onInputChange;
  final VoidCallback onSend;

  const ChatInput({
    super.key,
    required this.input,
    required this.isStreaming,
    required this.onInputChange,
    required this.onSend,
  });

  bool get _canSend => input.trim().isNotEmpty && !isStreaming;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        8,
        16,
        16 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFFF7F8F6),
        border: Border(
          top: BorderSide(color: Color(0xFFE8EAED), width: 0.5),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: TextEditingController(text: input),
              enabled: !isStreaming,
              maxLines: 5,
              minLines: 1,
              textInputAction: TextInputAction.newline,
              onChanged: onInputChange,
              decoration: const InputDecoration(
                hintText: '和月笙聊聊…',
                hintStyle: TextStyle(color: Color(0xFFB8BCC0)),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 10),
              ),
              style: const TextStyle(
                fontSize: 15,
                color: Color(0xFF2D3142),
              ),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: _canSend ? onSend : null,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF2D5A52),
              disabledBackgroundColor: const Color(0xFFE8EAED),
              shape: const CircleBorder(),
              padding: const EdgeInsets.all(12),
              minimumSize: const Size(44, 44),
            ),
            child: const Icon(
              Icons.arrow_upward,
              color: Colors.white,
              size: 20,
            ),
          ),
        ],
      ),
    );
  }
}
```

- [x] **Step 4: 运行测试确认通过**

Run: `flutter test test/widgets/chat_input_test.dart --reporter=expanded`
Expected: 4/4 PASS

- [x] **Step 5: 四闸验证 + commit**

```bash
git add lib/widgets/chat_input.dart test/widgets/chat_input_test.dart
git commit -m "feat: 实现 ChatInput 输入框"
```

---

## Task 6: 接线 ChatPage（串联 ChatStore + MessageList + ChatInput + chat_service）

**Files:**
- Modify: `lib/widgets/chat_page.dart`（重写为聊天主页）
- Test: `test/widgets/chat_page_test.dart`（补充发送消息测试）

**核心改动**：
1. ChatPage 改为 ConsumerStatefulWidget
2. 初始化时加载现有消息
3. handleSend 调用 chat_service.sendMessage，传入 onStream/onComplete/onError 回调
4. 回调中更新 ChatStore 状态

- [ ] **Step 1: 补充 chat_page_test.dart 发送消息集成测试**

在现有 `test/widgets/chat_page_test.dart` 末尾追加：

```dart
group('发送消息集成', () {
  testWidgets('#8 输入消息 + 点击发送 → 触发 sendMessage + 流式渲染', (tester) async {
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: ChatPage()),
    ));
    await tester.pumpAndSettle();

    // 输入消息
    await tester.enterText(find.byType(TextField), '测试消息');
    await tester.pump();

    // 点击发送
    await tester.tap(find.byType(FilledButton));
    await tester.pump();

    // 应立即显示 user 消息（streaming 启动前）
    expect(find.text('测试消息'), findsOneWidget);

    // 应显示 ThinkingIndicator（streaming 启动但内容为空）
    expect(find.byType(ThinkingIndicator), findsOneWidget);
  });
});
```

- [ ] **Step 2: 重写 chat_page.dart 为聊天主页**

将 `lib/widgets/chat_page.dart` 改为：

```dart
// lib/widgets/chat_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database/database.dart';
import '../data/repositories/app_state_repository.dart';
import '../data/repositories/session_repository.dart';
import '../data/repositories/student_model_repository.dart';
import '../data/repositories/teaching_state_repository.dart';
import '../providers/app_providers.dart';
import '../providers/chat_store.dart';
import '../services/bootstrap_service.dart';
import '../services/chat_service.dart';
import '../services/llm_client.dart';
import '../services/onboarding_service.dart';
import '../types/teaching_types.dart';
import 'message_list.dart';
import 'chat_input.dart';
import 'onboarding_questionnaire.dart';

class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({super.key});

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> {
  final TextEditingController _inputController = TextEditingController();

  bool _initialized = false;
  bool _showOnboarding = false;
  String? _sessionId;
  String? _initError;
  late final ChatService _chatService;
  late final LlmClient _llmClient;
  late final BootstrapService _bootstrapService;
  late final OnboardingService _onboardingService;
  late final SessionRepository _sessionRepo;

  @override
  void initState() {
    super.initState();
    // 从 Provider 拿 db，方便测试 override
    final db = ref.read(appDatabaseProvider);
    _sessionRepo = SessionRepository(db);
    _llmClient = LlmClient();
    _chatService = ChatService(
      db: db,
      llmClient: _llmClient,
      sessionRepo: _sessionRepo,
      stateRepo: TeachingStateRepository(db),
      studentModelRepo: StudentModelRepository(db),
      appStateRepo: AppStateRepository(db),
    );
    _bootstrapService = BootstrapService(
      appStateRepo: AppStateRepository(db),
      studentModelRepo: StudentModelRepository(db),
    );
    _onboardingService = OnboardingService(
      studentModelRepo: StudentModelRepository(db),
      stateRepo: TeachingStateRepository(db),
      appStateRepo: AppStateRepository(db),
    );
    _runBootstrap();
  }

  Future<void> _runBootstrap() async {
    try {
      final sessions = await _sessionRepo.listSessions();
      final sessionId = sessions.isNotEmpty
          ? sessions.first.id
          : await _sessionRepo.createBlankSession();

      final shouldShow = await _bootstrapService.shouldShowQuestionnaire(sessionId);

      // 加载现有消息
      final messages = await _sessionRepo.listMessages(sessionId);

      ref.read(chatStoreProvider.notifier).setSessionId(sessionId);
      ref.read(chatStoreProvider.notifier).setMessages(messages);

      setState(() {
        _sessionId = sessionId;
        _showOnboarding = shouldShow;
        _initialized = true;
      });
    } catch (e, stack) {
      setState(() {
        _initError = '$e\n\n$stack';
        _initialized = true;
      });
    }
  }

  Future<void> _handleSend() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _sessionId == null) return;

    _inputController.clear();
    ref.read(chatStoreProvider.notifier).setStreaming(true);

    try {
      await _chatService.sendMessage(
        _sessionId!,
        text,
        SendMessageCallbacks(
          onStream: (delta) {
            ref.read(chatStoreProvider.notifier).appendStreamingContent(delta);
          },
          onComplete: (fullContent, messageId) async {
            // 从 DB 重新加载消息列表（确保拿到完整 message 对象）
            final messages = await _sessionRepo.listMessages(_sessionId!);
            ref.read(chatStoreProvider.notifier).setMessages(messages);
            ref.read(chatStoreProvider.notifier).setStreaming(false);
          },
          onError: (error) {
            ref.read(chatStoreProvider.notifier).setError(error);
          },
        ),
        const SendMessageOptions(),
      );
    } catch (e) {
      ref.read(chatStoreProvider.notifier).setError(e.toString());
    }
  }

  Future<void> _handleOnboardingComplete(OnboardingData data) async {
    if (_sessionId == null) return;
    await _onboardingService.submitOnboarding(_sessionId!, data);
    setState(() => _showOnboarding = false);
  }

  Future<void> _handleOnboardingSkip() async {
    if (_sessionId == null) return;
    await _onboardingService.skipOnboarding(_sessionId!);
    setState(() => _showOnboarding = false);
  }

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(chatStoreProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('月笙写作教练'),
        backgroundColor: const Color(0xFF2D5A52),
        foregroundColor: Colors.white,
      ),
      body: _buildBody(chatState),
    );
  }

  Widget _buildBody(ChatState chatState) {
    if (!_initialized) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_initError != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Text(
            '初始化失败：\n\n$_initError',
            style: const TextStyle(fontSize: 14, fontFamily: 'monospace'),
          ),
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: MessageList(
            messages: chatState.messages,
            isStreaming: chatState.isStreaming,
            streamingContent: chatState.streamingContent,
          ),
        ),
        if (chatState.error != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: const Color(0xFFFEE2E2),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    chatState.error!,
                    style: const TextStyle(fontSize: 13, color: Color(0xFFB91C1C)),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: () => ref.read(chatStoreProvider.notifier).clearError(),
                ),
              ],
            ),
          ),
        ChatInput(
          input: _inputController.text,
          isStreaming: chatState.isStreaming,
          onInputChange: (text) {
            _inputController.value = _inputController.value.copyWith(
              text: text,
              selection: TextSelection.collapsed(offset: text.length),
            );
          },
          onSend: _handleSend,
        ),
        // onboarding 问卷（Stack 顶层）
        OnboardingQuestionnaire(
          visible: _showOnboarding,
          onComplete: _handleOnboardingComplete,
          onSkip: _handleOnboardingSkip,
        ),
      ],
    );
  }
}
```

- [ ] **Step 3: 运行测试确认通过**

Run: `flutter test test/widgets/chat_page_test.dart --reporter=expanded`
Expected: 全部 PASS

- [ ] **Step 4: 四闸验证 + commit**

```bash
git add lib/widgets/chat_page.dart test/widgets/chat_page_test.dart
git commit -m "feat: 接线 ChatPage 串联 ChatStore + MessageList + ChatInput + chat_service"
```

---

## Task 7: 流式渲染联调

**Files:**
- Test: `test/widgets/chat_page_streaming_test.dart`

**验证目标**：模拟 LLM 流式 token 回调，验证 MessageList 正确累加 + ThinkingIndicator 切换 + 完成后消息持久化。

- [ ] **Step 1: 写 streaming 集成测试**

```dart
// test/widgets/chat_page_streaming_test.dart
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/providers/app_providers.dart';
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
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MessageList(
            messages: const [],
            isStreaming: true,
            streamingContent: '',
          ),
        ),
      ));
      expect(find.byType(ThinkingIndicator), findsOneWidget);

      // 阶段 2：收到 token → 显示流式气泡
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MessageList(
            messages: const [],
            isStreaming: true,
            streamingContent: '正在回复',
          ),
        ),
      ));
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
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MessageList(
            messages: [msg],
            isStreaming: false,
            streamingContent: '',
          ),
        ),
      ));
      expect(find.text('最终回复'), findsOneWidget);
      expect(find.byType(ThinkingIndicator), findsNothing);
    });
  });
}
```

- [ ] **Step 2: 运行测试确认通过**

Run: `flutter test test/widgets/chat_page_streaming_test.dart --reporter=expanded`
Expected: 2/2 PASS

- [ ] **Step 3: 四闸验证 + commit**

```bash
git add test/widgets/chat_page_streaming_test.dart
git commit -m "test: 流式渲染联调测试"
```

---

## Task 8: 补 chat_service.dart 关键路径测试

**Files:**
- Test: `test/services/chat_service_send_message_test.dart`

**目标**：用 FakeLlmClient 覆盖 sendMessage 的核心路径，验证无假完成。

- [ ] **Step 1: 写 chat_service_send_message_test.dart**

```dart
// test/services/chat_service_send_message_test.dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/app_state_repository.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/data/repositories/student_model_repository.dart';
import 'package:writingcoach/data/repositories/teaching_state_repository.dart';
import 'package:writingcoach/services/chat_service.dart';
import 'package:writingcoach/services/llm_client.dart';

// 复用 editor_service_test.dart 的 FakeLlmClient
class FakeLlmClient extends LlmClient {
  final String _response;
  final Exception? _error;

  FakeLlmClient(this._response, [this._error]);

  @override
  Future<void> streamChat(
    List<ChatMessage> messages,
    void Function(LlmStreamResponse response) callback, {
    CancelToken? cancelToken,
  }) async {
    if (_error != null) throw _error;
    // 模拟流式分块
    for (int i = 0; i < _response.length; i += 10) {
      final end = i + 10 < _response.length ? i + 10 : _response.length;
      callback(LlmStreamResponse(
        content: _response.substring(i, end),
        isDone: false,
      ));
    }
    callback(const LlmStreamResponse(content: '', isDone: true));
  }
}

void main() {
  late AppDatabase db;
  late ChatService chatService;
  late SessionRepository sessionRepo;
  late String sessionId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    sessionRepo = SessionRepository(db);
    sessionId = await sessionRepo.createBlankSession();
    chatService = ChatService(
      db: db,
      llmClient: FakeLlmClient('你好，我是月笙。'),
      sessionRepo: sessionRepo,
      stateRepo: TeachingStateRepository(db),
      studentModelRepo: StudentModelRepository(db),
      appStateRepo: AppStateRepository(db),
    );
  });

  tearDown(() => db.close());

  test('#1 sendMessage 成功：user 消息写入 + assistant 消息写入 + onComplete 触发', () async {
    String? completeContent;
    String? completeMessageId;

    await chatService.sendMessage(
      sessionId,
      '你好',
      SendMessageCallbacks(
        onStream: (_) {},
        onComplete: (content, messageId) {
          completeContent = content;
          completeMessageId = messageId;
        },
        onError: (_) {},
      ),
      const SendMessageOptions(),
    );

    // user 消息应已写入
    final messages = await sessionRepo.listMessages(sessionId);
    expect(messages.length, 2); // user + assistant
    expect(messages[0].role, 'user');
    expect(messages[0].content, '你好');
    expect(messages[1].role, 'assistant');
    expect(messages[1].content, contains('月笙'));

    // onComplete 应被触发
    expect(completeContent, isNotNull);
    expect(completeMessageId, isNotNull);
  });

  test('#2 sendMessage 流式：onStream 收到 delta', () async {
    final deltas = <String>[];

    await chatService.sendMessage(
      sessionId,
      '测试',
      SendMessageCallbacks(
        onStream: (delta) => deltas.add(delta),
        onComplete: (_, __) {},
        onError: (_) {},
      ),
      const SendMessageOptions(),
    );

    // 应收到至少一个 delta
    expect(deltas, isNotEmpty);
    // deltas 拼接应包含完整内容
    expect(deltas.join(), contains('月笙'));
  });

  test('#3 sendMessage LLM 异常 → onError 触发', () async {
    final errorService = ChatService(
      db: db,
      llmClient: FakeLlmClient('', Exception('网络错误')),
      sessionRepo: sessionRepo,
      stateRepo: TeachingStateRepository(db),
      studentModelRepo: StudentModelRepository(db),
      appStateRepo: AppStateRepository(db),
    );

    String? errorMsg;

    await errorService.sendMessage(
      sessionId,
      '测试',
      SendMessageCallbacks(
        onStream: (_) {},
        onComplete: (_, __) {},
        onError: (err) => errorMsg = err,
      ),
      const SendMessageOptions(),
    );

    expect(errorMsg, isNotNull);
    expect(errorMsg, contains('网络错误'));
  });
}
```

- [ ] **Step 2: 运行测试确认通过**

Run: `flutter test test/services/chat_service_send_message_test.dart --reporter=expanded`
Expected: 3/3 PASS

- [ ] **Step 3: 四闸验证 + commit + tag**

```bash
flutter analyze
flutter test
git add test/services/chat_service_send_message_test.dart
git commit -m "test: 补 chat_service.dart 关键路径测试（无假完成验证）"
git tag batch1-9_mvp_chat
```

---

## 总结

8 个任务，按依赖顺序执行：

| Task | 内容 | 工作量 |
|------|------|--------|
| T1 | Riverpod 基建 | S |
| T2 | ChatStore 状态管理 | S |
| T3 | MessageBubble 基础气泡 | S |
| T4 | MessageList 消息列表 | M |
| T5 | ChatInput 输入框 | S |
| T6 | ChatPage 接线 | M |
| T7 | 流式渲染联调 | S |
| T8 | chat_service 测试 | M |

**MVP 完成后可达成的状态**：
- 用户可输入消息并发送
- LLM 流式回复实时渲染
- 消息持久化到 DB
- onboarding 问卷正常触发
- chat_service 关键路径有测试覆盖（无假完成）

**MVP 不包含**（后续迭代）：
- 诊断卡片 / 教学建议卡片 / 训练任务卡片
- ChatModals（诊断确认 / 症候详情 / 引用选择等）
- TaskPanel / QuickChips / ChatHeader 态度切换
- 长按删除 / 重试失败消息
- 章节引用 `@W001/C003` 解析
