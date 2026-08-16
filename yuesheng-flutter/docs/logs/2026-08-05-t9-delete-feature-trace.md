# T9 #14 删除确认弹窗 — 完整链路日志

来源：`flutter test test/widgets/chat_page_test.dart` 全量通过输出
采集时间：2026-08-05
测试结果：12/12 通过

## 日志链路（按测试用例分组）

### #10 长按消息 → 弹出删除确认对话框

```
[MessageList] 长按消息 id=b8c696c4-8817-4523-a0b3-bee435617202 role=user
```

链路：`MessageBubble.GestureDetector.onLongPress` → `MessageList._showDeleteConfirm` → `setState(_pendingDelete = message)` → `_buildDeleteConfirmOverlay` 渲染弹窗

验证点：
- `确认删除` / `删除` / `取消` 三个文案均能找到（findsOneWidget）

### #11 点击删除 → 消息从 UI 和 DB 移除

```
[MessageList] 长按消息 id=e391419d-06e0-4af4-89d3-b0b3dc98f7cf role=user
[MessageList] 确认删除消息 id=e391419d-06e0-4af4-89d3-b0b3dc98f7cf
[ChatPage] 开始删除消息 sessionId=0325c889-6074-4c33-af26-098bcf6c320b messageId=e391419d-06e0-4af4-89d3-b0b3dc98f7cf
[ChatPage] DB 删除成功 messageId=e391419d-06e0-4af4-89d3-b0b3dc98f7cf
[ChatPage] 内存列表移除完成 messageId=e391419d-06e0-4af4-89d3-b0b3dc98f7cf
```

链路：
1. `MessageList._confirmDelete` → 调用 `widget.onDelete(messageId)` 回调
2. `ChatPage._handleDelete` → 读取 `sessionBootstrapProvider` 获取 sessionId
3. `SessionRepository.deleteMessage(sessionId, messageId)` → DB 删除
4. `chatStoreProvider.notifier.removeMessage(messageId)` → 内存列表移除

验证点：
- UI 中消息消失（findsNothing）
- `sessionRepo.listMessages(sessionId)` 返回空列表

### #12 点击取消 → 消息保留

```
[MessageList] 长按消息 id=643a3570-3595-4304-a8e8-645271f92ecc role=user
[MessageList] 用户取消删除
```

链路：`MessageList._cancelDelete` → `setState(_pendingDelete = null)` → 弹窗消失，不触发 `onDelete` 回调，不触碰 DB

验证点：
- 无 `[ChatPage]` 日志输出（DB 未被调用）
- UI 中消息仍存在（findsOneWidget）
- `sessionRepo.listMessages(sessionId)` 返回 1 条记录

## 节点覆盖说明

| 节点 | 日志标签 | 触发条件 |
|------|---------|---------|
| 长按入口 | `[MessageList] 长按消息` | 用户长按气泡 |
| 确认删除 | `[MessageList] 确认删除消息` | 点击「删除」按钮 |
| 取消删除 | `[MessageList] 用户取消删除` | 点击「取消」按钮 |
| 异常兜底 | `[MessageList] 删除取消：_pendingDelete=... onDelete=...` | _pendingDelete 或 onDelete 为空 |
| 删除前置 | `[ChatPage] 删除失败：bootstrap 为空` | sessionBootstrapProvider 未就绪 |
| 删除开始 | `[ChatPage] 开始删除消息` | 进入 _handleDelete |
| DB 成功 | `[ChatPage] DB 删除成功` | sessionRepo.deleteMessage 完成 |
| DB 失败 | `[ChatPage] DB 删除失败` | sessionRepo.deleteMessage 抛异常 |
| 内存同步 | `[ChatPage] 内存列表移除完成` | chatStore.removeMessage 完成 |

## 测试运行完整输出

```
00:00 +0: loading D:/teacher/yuesheng-flutter/test/widgets/chat_page_test.dart
00:00 +0: 新用户：空 DB → 弹问卷 #1 完成问卷 → 隐藏 + 状态迁移
00:00 +1: 新用户：空 DB → 弹问卷 #2 跳过问卷 → 隐藏 + 状态迁移
00:00 +2: 老用户：已有 questionnaire_completed → 不弹问卷 #3 老用户启动直接看到主页
00:00 +3: 初始化中 #4 显示 CircularProgressIndicator
00:01 +4: 完成问卷后状态持久化 #5 elementary → N1_ELEMENTS + onboarding_data 完整
00:01 +5: 复用已有 session（覆盖 sessions.first.id 分支） #6 DB 中已有 session → 复用而非新建
00:01 +6: bootstrap 异常路径 #7 bootstrapService 抛异常 → 显示错误 UI
00:01 +7: 发送消息集成（T6） #8 输入消息 + 点击发送 → 触发流式渲染
00:01 +8: 发送消息集成（T6） #9 发送空消息 → 按钮禁用
00:01 +9: 删除消息（T9 #14） #10 长按消息 → 弹出删除确认对话框
[MessageList] 长按消息 id=b8c696c4-8817-4523-a0b3-bee435617202 role=user
00:01 +10: 删除消息（T9 #14） #11 点击删除 → 消息从 UI 和 DB 移除
[MessageList] 长按消息 id=e391419d-06e0-4af4-89d3-b0b3dc98f7cf role=user
[MessageList] 确认删除消息 id=e391419d-06e0-4af4-89d3-b0b3dc98f7cf
[ChatPage] 开始删除消息 sessionId=0325c889-6074-4c33-af26-098bcf6c320b messageId=e391419d-06e0-4af4-89d3-b0b3dc98f7cf
[ChatPage] DB 删除成功 messageId=e391419d-06e0-4af4-89d3-b0b3dc98f7cf
[ChatPage] 内存列表移除完成 messageId=e391419d-06e0-4af4-89d3-b0b3dc98f7cf
00:01 +11: 删除消息（T9 #14） #12 点击取消 → 消息保留
[MessageList] 长按消息 id=643a3570-3595-4304-a8e8-645271f92ecc role=user
[MessageList] 用户取消删除
00:01 +12: All tests passed!
```
