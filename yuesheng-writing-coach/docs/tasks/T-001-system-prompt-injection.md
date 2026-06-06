---
id: T-001
status: completed
follows: T-000
precedes: T-002
started: 2026-06-01
completed: 2026-06-01
---

# T-001: System Prompt 注入 + 态度档位控制

## 目标
将聊天链路中当前使用的 fallback prompt 替换为完整的 V3.0 System Prompt，并实现豆包/月笙如歌两种态度档位的切换控制，使用户能通过 UI 选择 AI 的教学风格。

## 前置条件
- [x] T-000 基线建设完成（聊天链路已可收发消息）
- [x] `resources/prompts/yuesheng-prompt-v3.md` 已就绪

## DoD（验收标准）
- [x] System Prompt 从 `resources/prompts/yuesheng-prompt-v3.md` 加载，注入到每次 API 调用的 messages 首位
- [x] 态度档位类型（`doubao` | `yuesheng`）在 TypeScript 中正确定义
- [x] 态度档位通过 chat.handler.ts IPC 动态注入（不硬编码）
- [x] 态度档位选择器 UI 在聊天界面头部展示（两颗并排胶囊按钮）
- [x] 切换档位后后续消息的语气风格跟随变化
- [x] 档位选择持久化到 electron-store 配置
- [x] 73 测试全部通过
- [x] 类型检查零错误

## 执行记录
### 改动文件
- `src/renderer/shared/types.ts` — 新增 `AttitudeLevel` 类型，`ApiConfig.attitudeLevel` 字段
- `src/renderer/stores/config.store.ts` — 新增 `attitudeLevel` 状态 + `setAttitudeLevel` 动作 + loadConfig 加载
- `src/main/services/config.service.ts` — 新增 `ATTITUDE_LEVEL` 配置键 + `getConfig()` 返回
- `src/main/ipc/chat.handler.ts` — 新增 `DOUBAO_TONE_MODIFIER` 常量 + `loadSystemPrompt(attitude)` 参数化
- `src/renderer/stores/chat.store.ts` — `sendMessage` 读取 configStore.attitudeLevel 并传递到 IPC
- `src/renderer/components/ChatPage.tsx` — 新增 `AttitudeToggle` 组件（两颗胶囊按钮）
- `src/renderer/stores/__tests__/chat.store.test.ts` — 新增 2 个态度传递测试
- `src/renderer/stores/__tests__/config.store.test.ts` — 新增文件，3 个态度切换 + 持久化测试
- `src/main/services/__tests__/api-proxy.test.ts` — TEST_CONFIG 补全 `attitudeLevel`

### 测试结果
```
 Test Files  6 passed (6)
      Tests  73 passed (73)
   Duration  804ms
 TypeScript: 0 errors
```

## 输出产物
- System Prompt 从 V3.0 文件加载 + 豆包语气修饰符拼接机制
- 态度档位持久化配置（electron-store：`attitudeLevel` 键）
- 聊天头部态度切换 UI 组件（`AttitudeToggle`）
- 5 个新测试覆盖态度传递和持久化

## 下一步建议
- T-002: 会话管理（SQLite 持久化 + 会话列表） — 消息持久化和多会话管理，使聊天体验完整
