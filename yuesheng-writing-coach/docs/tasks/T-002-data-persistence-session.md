---
id: T-002
status: completed
follows: T-001
precedes:
started: 2026-06-01
completed: 2026-06-01
---

# T-002: 数据持久化与会话管理

## 目标
打通消息落库 → 诊断触发 → 会话管理全链路

## 阶段 A：数据库建表 + 消息持久化
- 创建 `004_create_chat.sql` 迁移（sessions + messages 表）
- 创建 `SessionService`（CRUD 封装，含 autoGenerateTitle）
- main/index.ts 注册 004 迁移 + 挂载 SessionService
- chat.handler.ts 流结束后自动持久化消息 + 自动生成标题
- shared/types.ts 补充 Session/MessageRow 类型 + IPC 映射

## 阶段 B：诊断链路接通
- chat.handler.ts 流结束后调用 `processDiagnosisFromAI()`
- 诊断数据自动解析 → 合并到 TeachingState → 推送到前端

## 阶段 C：会话管理 UI
- 创建 session.handler.ts（5 个 IPC 通道）
- 创建 session.store.ts（Zustand 状态管理）
- 创建 SessionSidebar.tsx（侧栏 UI，日期分组 + 新建/删除）
- App.tsx 集成侧栏布局 + 会话初始化
- chat.store.ts 对接 session store（sessionId 统一管理）
- Preload 白名单 + IPC_CHANNELS 常量全覆盖

## DoD（验收标准）
- [x] 消息发送后自动写入 SQLite，刷新后不丢失
- [x] AI 回复流结束后自动触发诊断解析
- [x] 左侧侧栏显示会话列表，按日期分组
- [x] 支持新建/切换/删除会话
- [x] 首条用户消息自动生成会话标题
- [x] 73 测试全部通过
- [x] 类型检查零错误

## 执行记录
### 改动文件
- 新建: `src/main/db/004_create_chat.sql`
- 新建: `src/main/services/session.service.ts`
- 新建: `src/main/ipc/session.handler.ts`
- 新建: `src/renderer/stores/session.store.ts`
- 新建: `src/renderer/components/SessionSidebar.tsx`
- 修改: `src/main/index.ts`
- 修改: `src/main/ipc/chat.handler.ts`
- 修改: `src/main/ipc/diagnosis.handler.ts`
- 修改: `src/preload/index.ts`
- 修改: `src/renderer/App.tsx`
- 修改: `src/renderer/stores/chat.store.ts`
- 修改: `src/renderer/shared/types.ts`
- 修改: `src/renderer/stores/__tests__/chat.store.test.ts`

### 测试结果
```
 Test Files  6 passed (6)
      Tests  73 passed (73)
 TypeScript: 0 errors
```
