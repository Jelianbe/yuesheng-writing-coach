// 追加 D-059 决策日志到 docs/decision-log.md
const fs = require('fs');
const path = require('path');

const FILE = 'd:/ai-teacher/yuesheng-writing-coach/docs/decision-log.md';

const content = `
## 2026-07-03

### D-059: A-4 ChatPage 订阅模式落地 — IPC 事件流推送 + Mock 桥接
- **类型**: 架构桥接 / DoD 验证
- **背景**:
  - Sprint 20 A-4 DoD: ChatPage 不直接调 chat:sendMessage,无 raw stream 消费
  - Sprint 20 plan 描述"for await (const ev of orchestrator.handleTurn(...))" — 但 Electron 跨进程模型下 AsyncIterable 不能直接 IPC 序列化
- **决策**:
  1. 引入两条新 IPC 通道:
     - \`chat:handleTurn\`(invoke 模式): 接收 HandleTurnInput,返回 streamId
     - \`chat:event\`(事件推送): 推送 OrchestratorEvent 标准化事件流
  2. 新建 \`ChatHandleTurnBridge\`(主进程)包装 \`MockConversationOrchestrator\`(A-4 试点,Sprint 21 切真实):
     - 异步消费 handleTurn() 事件流
     - 通过 webContents.send 推 \`chat:event\`
     - 支持 stopAll() 中断活跃流
  3. 新建 \`useOrchestrator\` Hook(renderer):
     - send(input) → invoke 触发,返回 streamId
     - subscribe(handler) → 订阅 \`chat:event\`,按 streamId 过滤本轮 turn
     - 单例订阅(避免 on() 重复触发)
  4. ChatPage 改造:
     - 立即插入 user + ai 占位消息
     - send() 拿 streamId,订阅事件
     - token → 累积到 ai 消息 content
     - done → 完成,解锁输入
     - error → 错误条提示
     - phase_transition/intent/training/diagnosis → console 留痕(Sprint 21 接状态机)
- **交付物**:
  1. \`src/shared/constants.ts\`: CHAT_HANDLE_TURN + CHAT_EVENT
  2. \`src/shared/api-contracts/chat.contract.ts\`: ChatHandleTurnRequest/Response + ChatEventPayload
  3. \`src/preload/index.ts\`: 白名单新增 2 频道
  4. \`src/main/domains/03-teaching/conversation/chat-handle-turn.bridge.ts\` (NEW)
  5. \`src/main/ipc/chat.handler.ts\`: 注册 chat:handleTurn handler
  6. \`src/renderer/hooks/useOrchestrator.ts\` (NEW)
  7. \`src/renderer/pages/ChatPage.tsx\`: 改造 handleSend + 订阅事件
  8. \`src/main/domains/03-teaching/conversation/__tests__/chat-handle-turn-bridge.test.ts\` (NEW, 7 个用例)
- **门禁**:
  - typecheck: ✅ 0 errors
  - vitest: ✅ 749/749(新增 7 个 bridge 测试)
  - lint: ✅ 0 errors, 257 warnings(无新增)
- **教训**:
  1. **for-await 在跨进程 IPC 边界不可行**: Electron 序列化层不识别 AsyncIterable,必须用 invoke + event-push 双通道实现"等效语义"。Sprint 21 切真实 orchestrator 时,只需替换 Bridge 内部持有的 orchestrator 实例,IPC 契约不变
  2. **renderer 不应跨域引用 main/domains 类型** (R-020): \`ChatEventPayload.event\` 用 unknown,renderer 端用轻量类型守卫 narrow。避免 shared → main 循环依赖
  3. **Edit 工具增量修改可能"假成功"**: 第一次编辑 constants.ts 时,Edit 工具声称成功但文件未实际变更(磁盘缓存未刷新)。验证方式:typecheck 仍报 CHAT_HANDLE_TURN 不存在。修复:重读确认 + 重新 Edit。教训:重要字段插入后必须 Read 验证
  4. **Mock 桥接先于真实桥接**: Sprint 20 范围控制(R-010),A-4 用 MockConversationOrchestrator 验证架构方向,真实 ChatOrchestratorService → ConversationOrchestrator 适配器留给 Sprint 21
  5. **WebContents vs BrowserWindow 区分**: ipcMain.handle 的 event.sender 是 WebContents,不是 BrowserWindow。Bridge 接口收 WebContents 更精确;提供 startTurnToWindow 包装 BrowserWindow 入口
- **依据**:
  - dev-docs/tasks/sprint-20-plan.md §A-4
  - D-058(试点 → A-3 状态机迁移)
  - R-010 最小化范围(用 mock 而非真实)
  - R-018 变更溯源(本决策追溯到 plan §A-4)
  - R-020 循环依赖零容忍(shared 边界用 unknown)
  - R-028 防御性编码(emit/webContents=null/destroyed 异常隔离)
- **后续**:
  - Sprint 21: ChatOrchestratorService → ConversationOrchestrator 适配器,替换 Bridge 内部 mock 为真实 orchestrator
  - Sprint 21: phase_transition/intent/training_triggered 事件接入真实状态机
  - Sprint 21: 多 streamId 并发管理(当前 activeStreamId 串行处理)
`;

fs.appendFileSync(FILE, content, 'utf8');
console.log('[D-059] Appended to decision-log.md');
console.log('[D-059] Total file size now:', fs.statSync(FILE).size, 'bytes');
