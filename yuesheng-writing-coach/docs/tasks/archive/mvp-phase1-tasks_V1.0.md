# MVP 阶段一 - 任务清单

**版本**: V1.0  
**创建日期**: 2026-06-01  
**关联计划**: [api-config-plan_V1.0.md](../plans/api-config-plan_V1.0.md)  
**关联规范**: [api-config-spec_V1.0.md](../specs/api-config-spec_V1.0.md)  

## DoD 准出标准

1. 用户能够成功输入 API Key 并保存到本地存储
2. 用户能够点击"测试连接"并收到准确的成功/失败反馈
3. 配置界面加载时间 < 100ms，连接测试超时 < 10 秒

---

## 任务列表

### T-001: 类型定义与依赖安装
**优先级**: P0  
**状态**: ✅ 已完成  
**依赖**: 无

- [x] 安装 electron-store 和 zustand 依赖
- [x] 定义 `ApiConfig` 接口
- [x] 定义 `ConnectionTestResult` 接口
- [x] 定义 IPC 通道常量

### T-002: 配置服务实现
**优先级**: P0  
**状态**: ✅ 已完成  
**依赖**: T-001

- [x] 创建 `config.service.ts`
- [x] 实现 `getConfig()` / `setConfig()`
- [x] 实现 `validateConfig()`
- [x] 实现 `testConnection()`（10 秒超时）
- [x] 安全处理错误信息

### T-003: IPC Handler 注册
**优先级**: P0  
**状态**: ✅ 已完成  
**依赖**: T-002

- [x] 创建 `config.handler.ts`
- [x] 注册 `config:get` 通道
- [x] 注册 `config:set` 通道
- [x] 注册 `config:testConnection` 通道
- [x] 在主进程入口注册 handler

### T-004: Zustand Store 实现
**优先级**: P0  
**状态**: ✅ 已完成  
**依赖**: T-003

- [x] 创建 `config.store.ts`
- [x] 定义 `ConfigState` 接口
- [x] 实现 `setApiKey()` / `setBaseUrl()` 等方法
- [x] 实现 `testConnection()` 异步操作
- [x] 实现 `loadConfig()` 从主进程加载

### T-005: 配置界面组件
**优先级**: P0  
**状态**: ✅ 已完成  
**依赖**: T-004

- [x] 创建 `ApiConfig.tsx`
- [x] API Key 输入框（支持显示/隐藏）
- [x] 测试连接按钮和状态反馈
- [x] 校验错误提示
- [x] 加载状态展示

### T-006: Preload 脚本配置
**优先级**: P0  
**状态**: ✅ 已完成  
**依赖**: T-003

- [x] 在 preload/index.ts 暴露 `electronAPI`
- [x] 实现 IPC 通道白名单
- [x] TypeScript 类型声明

### T-007: App 集成
**优先级**: P0  
**状态**: ✅ 已完成  
**依赖**: T-005

- [x] 在 App.tsx 集成 ApiConfig 组件
- [x] 未配置时显示配置页
- [x] 已配置时显示主界面占位
- [x] 应用启动时自动加载配置

### T-008: 类型检查与验证
**优先级**: P0  
**状态**: ✅ 已完成  
**依赖**: T-007

- [x] `tsc --noEmit` 通过
- [x] 无 `any` 类型
- [x] 所有导入路径正确

---

## 下一步任务（Phase 1 剩余功能）

> **状态更新 (V1.1, 2026-06-04)**：以下任务 T-009 ~ T-014 已全部完成，标记保留供参考。

### T-009: 聊天界面 — 基础布局
**优先级**: P0  
**状态**: ✅ 已完成  
**依赖**: T-008

- [x] 创建 ChatPage 组件 → 实际使用 `App.tsx` 直接集成聊天布局
- [x] 消息列表组件 → [MessageList.tsx](../../src/renderer/components/chat/MessageList.tsx) 含自动滚动
- [x] 输入框组件 → [MessageInput.tsx](../../src/renderer/components/chat/MessageInput.tsx)
- [x] 发送按钮 → 内置于 MessageInput
- [x] 消息气泡 → [MessageBubble.tsx](../../src/renderer/components/chat/MessageBubble.tsx)
- [x] 打字指示器 → [TypingIndicator.tsx](../../src/renderer/components/chat/TypingIndicator.tsx)

### T-010: 聊天界面 — API 通信
**优先级**: P0  
**状态**: ✅ 已完成  
**依赖**: T-009

- [x] 创建 `api-proxy.ts` 主进程服务 → [api-proxy.ts](../../src/main/api-proxy.ts)
- [x] 实现流式输出 → `chatStream()` 异步生成器
- [x] 注册 `chat:send` IPC 通道 → [chat.handler.ts](../../src/main/ipc/chat.handler.ts)
- [x] 实现 AbortController 中断 → `AbortController` + signal

### T-011: System Prompt 注入
**优先级**: P0  
**状态**: ✅ 已完成  
**依赖**: T-010

- [x] 读取 `yuesheng-prompt-v3.md` → `loadSystemPrompt()` 动态加载
- [x] 构建 messages 数组 → system + history + user
- [x] 注入 system prompt → 三态分支（yuesheng / doubao / direct）
- [x] 豆包模式修饰符 → `DOUBAO_TONE_MODIFIER`
- [x] 直接模式修饰符 → `DIRECT_TONE_MODIFIER`
- [x] 诊断分析注入 → 有诊断结果时加载 Teaching Agent Prompt 并注入

### T-012: 会话管理
**优先级**: P0  
**状态**: ✅ 已完成  
**依赖**: T-011

- [x] 创建 SQLite 数据库 schema → `migrations/002_sessions.sql`
- [x] 实现 `session.service.ts` → [session.service.ts](../../src/main/services/session.service.ts)
- [x] 注册 `session:list` / `session:create` IPC 通道 → [session.handler.ts](../../src/main/ipc/session.handler.ts)（5 通道：list/create/delete/rename/getMessages）
- [x] 会话列表 UI → [AppSidebar.tsx](../../src/renderer/components/layout/AppSidebar.tsx)
- [x] 自动标题生成 → `autoGenerateTitle()` 异步

### T-013: 诊断书展示
**优先级**: P0  
**状态**: ✅ 已完成  
**依赖**: T-012

- [x] 创建 DiagnosisPanel 组件 → [DiagnosisCard.tsx](../../src/renderer/components/diagnosis/DiagnosisCard.tsx) + [DiagnosisPanel.tsx](../../src/renderer/components/panels/DiagnosisPanel.tsx)
- [x] 注册 `diagnosis:query` IPC 通道 → [diagnosis.handler.ts](../../src/main/ipc/diagnosis.handler.ts)
- [x] 流结束后自动触发诊断 → `processDiagnosisFromAI()` 在 chat.handler 中调用
- [x] 侧边栏展示诊断结果 → `diagnosis:update` Event 推送 + App.tsx 监听
- [x] 诊断持久化 → [diagnosis.service.ts](../../src/main/services/diagnosis.service.ts) 存入 SQLite
- [x] AI 响应解析 → [diagnosis-parser.ts](../../src/main/services/diagnosis-parser.ts)

### T-014: 态度档位控制
**优先级**: P1  
**状态**: ✅ 已完成  
**依赖**: T-013

- [x] 在 Header 添加档位切换 → 三态 UI（月笙 / 豆包 / 直接）
- [x] 保存到配置 → `attitudeLevel` → IPC → electron-store
- [x] Prompt 中动态切换档位 → `loadSystemPrompt(attitudeLevel)` 动态拼接 Tone Modifier
- [x] 完整链路验证 → Header → Store → IPC → chat.handler → System Prompt

---

## 任务进度

| 阶段 | 总任务 | 已完成 | 进行中 | 待开发 |
|------|--------|--------|--------|--------|
| API 配置 | 8 | 8 | 0 | 0 |
| 聊天界面 | 3 | 3 | 0 | 0 |
| Prompt 注入 | 1 | 1 | 0 | 0 |
| 会话管理 | 1 | 1 | 0 | 0 |
| 诊断展示 | 1 | 1 | 0 | 0 |
| 档位控制 | 1 | 1 | 0 | 0 |
| **合计** | **15** | **15** | **0** | **0** |

---

## 变更记录

| 版本 | 日期 | 变更内容 |
|------|------|---------|
| V1.0 | 2026-06-01 | 初始任务清单，T-001~T-008 已完成 |
| V1.1 | 2026-06-04 | T-009~T-014 全部标记为已完成，补充实际实现文件路径和功能描述 |
