# T9 UI 对齐修复清单

> 将 Flutter MVP 界面与 React Native 原产品的视觉/交互规范对齐
> 参考源：`yuesheng-android/src/components/chat/`

---

## 一、MessageBubble 差距（7 项）

### #1 气泡尖角

**现状**：全对称 12px 圆角
**目标**：user 右下 4px 小圆角 + assistant 左下 4px 小圆角

```dart
// 修改 message_bubble.dart 中 _buildBubble 方法的 borderRadius

BorderRadius.only(
  topLeft: const Radius.circular(12),
  topRight: const Radius.circular(12),
  bottomLeft: Radius.circular(_isUser ? 12 : 4),
  bottomRight: Radius.circular(_isUser ? 4 : 12),
),
```

---

### #2 AI 头像

**现状**：无头像
**目标**：圆形品牌色头像，显示"月"字

```dart
// 修改 _buildAssistantBubble 方法，在气泡左侧添加头像

Widget _buildAssistantBubble(Message message, DateTime time) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // 头像
      Container(
        width: 32,
        height: 32,
        margin: const EdgeInsets.only(right: 8, top: 4),
        decoration: const BoxDecoration(
          color: Color(0xFF2D5A52),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: const Text(
          '月',
          style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
        ),
      ),
      // 气泡内容
      Expanded(child: _buildBubble(message, time)),
    ],
  );
}
```

---

### #3 时间戳位置

**现状**：嵌在气泡内部底部
**目标**：AI 消息气泡下方独立一行，与操作按钮并排

```dart
// 修改 _buildAssistantBubble 方法，时间戳移到气泡外部

Widget _buildAssistantBubble(Message message, DateTime time) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 头像
            _buildAvatar(),
            // 气泡
            Expanded(child: _buildBubble(message)),
          ],
        ),
        // 时间戳（气泡外部）
        Padding(
          padding: const EdgeInsets.only(left: 40, top: 4),
          child: Text(
            _formatTime(message.timestamp),
            style: const TextStyle(fontSize: 11, color: Color(0xFF8A8D93)),
          ),
        ),
      ],
    ),
  );
}
```

---

### #4 最大宽度

**现状**：75% 屏幕宽
**目标**：80% 屏幕宽

```dart
// 修改 _buildBubble 方法中的 constraints

constraints: BoxConstraints(
  maxWidth: MediaQuery.of(context).size.width * 0.80, // 从 0.75 改为 0.80
),
```

---

### #5 发送中状态

**现状**：透明度 0.7
**目标**：透明度 0.6

```dart
// 修改 _buildBubble 方法中的 Opacity

opacity: _isStreaming ? 0.6 : 1.0, // 从 0.7 改为 0.6
```

---

### #6 操作按钮（功能增强）

**现状**：无
**目标**：AI 气泡下方显示"采纳到章节"和"保存到文件"按钮

> ⚠️ 此项涉及业务逻辑，需要配合 ChapterService 和文件导出功能实现

```dart
// 在 _buildAssistantBubble 方法中，时间戳右侧添加操作按钮

Row(
  mainAxisAlignment: MainAxisAlignment.spaceBetween,
  children: [
    Text(
      _formatTime(message.timestamp),
      style: const TextStyle(fontSize: 11, color: Color(0xFF8A8D93)),
    ),
    if (!isStreaming) ...[
      GestureDetector(
        onTap: () => onAdoptToChapter?.call(message),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFE8F5E9),
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.download, size: 12, color: Color(0xFF2E7D32)),
              SizedBox(width: 4),
              Text('采纳到章节', style: TextStyle(fontSize: 11, color: Color(0xFF2E7D32))),
            ],
          ),
        ),
      ),
      GestureDetector(
        onTap: () => onSaveToFile?.call(message),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFE3F2FD),
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.save, size: 12, color: Color(0xFF1565C0)),
              SizedBox(width: 4),
              Text('保存到文件', style: TextStyle(fontSize: 11, color: Color(0xFF1565C0))),
            ],
          ),
        ),
      ),
    ],
  ],
),
```

---

### #7 失败状态（功能增强）

**现状**：无
**目标**：红色边框 + "发送失败，点击重试"按钮

> ⚠️ 此项需要 Message 模型增加 `status` 字段和重试回调

```dart
// 修改 _buildUserBubble 方法，添加失败状态判断

Widget _buildUserBubble(Message message, DateTime time) {
  final isFailed = message.status == 'failed'; // 需要 Message 模型支持
  return Column(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.80),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isFailed ? const Color(0xFFFFEBEE) : const Color(0xFF2D5A52),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(12),
            topRight: Radius.circular(12),
            bottomLeft: Radius.circular(12),
            bottomRight: Radius.circular(4),
          ),
          border: isFailed ? Border.all(color: const Color(0xFFE57373), width: 1) : null,
        ),
        child: Text(message.content, style: const TextStyle(color: Colors.white, fontSize: 15)),
      ),
      if (isFailed) ...[
        GestureDetector(
          onTap: () => onRetry?.call(message),
          child: const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.warning, size: 14, color: Color(0xFFE53935)),
                SizedBox(width: 4),
                Text('发送失败，点击重试', style: TextStyle(fontSize: 12, color: Color(0xFFE53935))),
              ],
            ),
          ),
        ),
      ],
      if (!isFailed) _buildTimestamp(time),
    ],
  );
}
```

---

## 二、ChatInput 差距（5 项）

### #8 + 按钮（功能增强）

**现状**：无
**目标**：左侧 28px 圆角按钮，扩展功能入口

```dart
// 修改 _buildInputBar 方法，在输入框前添加 + 按钮

Widget _buildInputBar() {
  return Padding(
    padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + MediaQuery.of(context).padding.bottom),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // + 按钮
        GestureDetector(
          onTap: onUploadFile,
          child: Container(
            width: 28,
            height: 28,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF2F4F2),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE8EAED)),
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.add, size: 18, color: Color(0xFF2D3142)),
          ),
        ),
        // 原有输入框和发送按钮
        Expanded(child: _buildTextField()),
        const SizedBox(width: 8),
        _buildSendButton(),
      ],
    ),
  );
}
```

---

### #9 @ 按钮（功能增强）

**现状**：无
**目标**：左侧 28px ghost 按钮，引用选择入口

```dart
// 在 + 按钮后添加 @ 按钮

GestureDetector(
  onTap: onMention,
  child: Container(
    width: 28,
    height: 28,
    margin: const EdgeInsets.only(right: 8),
    alignment: Alignment.center,
    child: const Icon(Icons.alternate_email, size: 18, color: Color(0xFF8A8D93)),
  ),
),
```

---

### #10 发送按钮尺寸

**现状**：44px
**目标**：36px

```dart
// 修改 _buildSendButton 方法

Widget _buildSendButton() {
  return SizedBox(
    width: 36, // 从 44 改为 36
    height: 36, // 从 44 改为 36
    child: FilledButton(
      onPressed: canSend ? handleSend : null,
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFF2D5A52),
        disabledBackgroundColor: const Color(0xFFE8EAED),
        shape: const CircleBorder(),
        padding: const EdgeInsets.all(8), // 从 12 改为 8
      ),
      child: const Icon(Icons.arrow_upward, color: Colors.white, size: 18),
    ),
  );
}
```

---

### #11 输入框形状

**现状**：矩形
**目标**：完全圆角（pill shape）

```dart
// 修改 _buildTextField 方法中的 InputDecoration

InputDecoration(
  hintText: '和月笙聊聊…',
  hintStyle: const TextStyle(color: Color(0xFFB8BCC0)),
  border: OutlineInputBorder(
    borderRadius: BorderRadius.circular(24), // 完全圆角
    borderSide: BorderSide.none,
  ),
  filled: true,
  fillColor: const Color(0xFFF2F4F2),
  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
),
```

---

### #12 输入框背景

**现状**：白色
**目标**：浅灰 `#F2F4F2`

```dart
// 配合 #11，在 InputDecoration 中设置 fillColor

fillColor: const Color(0xFFF2F4F2), // 从 Colors.white 改为浅灰
filled: true,
```

---

## 三、MessageList 差距（2 项）

### #13 列表内边距

**现状**：无 padding
**目标**：16px 四周 padding

```dart
// 修改 _buildList 方法

Widget _buildList() {
  return ListView.builder(
    padding: const EdgeInsets.all(16), // 添加四周 16px padding
    itemCount: messages.length,
    itemBuilder: (context, index) => _buildMessageItem(messages[index]),
  );
}
```

---

### #14 删除确认弹窗（功能增强）

**现状**：无
**目标**：长按消息后弹出确认对话框

> ⚠️ 此项需要配合 onLongPress 回调和状态管理

```dart
// 在 MessageList 中添加删除确认弹窗

class MessageListState extends State<MessageList> {
  String? _deletingMessageId;

  void _showDeleteConfirm(Message message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('确认删除', textAlign: TextAlign.center),
        content: const Text('确定要删除这条消息吗？此操作不可撤销。', textAlign: TextAlign.center),
        actions: [
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                    backgroundColor: const Color(0xFFF2F4F2),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('取消', style: TextStyle(color: Color(0xFF2D3142))),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _deletingMessageId != null ? null : () {
                    setState(() => _deletingMessageId = message.id);
                    onDelete(message.id);
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE53935),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(_deletingMessageId != null ? '删除中...' : '删除'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // 在 MessageBubble 的 onLongPress 中调用
  // onLongPress: () => _showDeleteConfirm(message),
}
```

---

## 四、实施优先级

### 纯视觉对齐（无逻辑依赖，可立即实施）

| 优先级 | 差距编号 | 描述 |
|--------|---------|------|
| P0 | #1 | 气泡尖角 |
| P0 | #2 | AI 头像 |
| P0 | #3 | 时间戳位置 |
| P0 | #4 | 最大宽度 |
| P0 | #5 | 发送中状态 |
| P0 | #10 | 发送按钮尺寸 |
| P0 | #11 | 输入框形状 |
| P0 | #12 | 输入框背景 |
| P1 | #13 | 列表内边距 |

### 功能增强（需要额外开发）

| 优先级 | 差距编号 | 描述 | 前置依赖 |
|--------|---------|------|---------|
| P2 | #6 | 操作按钮（采纳/保存） | ChapterService、文件导出 |
| P2 | #7 | 失败状态 + 重试 | Message.status 字段、重试 API |
| P2 | #8 | + 按钮（文件上传） | 文件选择器、上传 API |
| P2 | #9 | @ 按钮（引用选择） | 引用选择器组件 |
| P2 | #14 | 删除确认弹窗 | 消息删除 API |

---

## 五、验证清单

完成每项修改后需验证：

- [ ] 视觉效果与 RN 版一致（截图对比）
- [ ] `flutter analyze` 0 errors
- [ ] `flutter test` 全绿
- [ ] 不影响现有功能（发送消息、流式渲染）
- [ ] 响应式正常（不同屏幕尺寸适配）