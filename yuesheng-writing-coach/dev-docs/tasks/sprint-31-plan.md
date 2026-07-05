# Sprint 31 — Android 端最小可用：配置持久化 + 聊天激活

> **范围**: 让 Android 端至少能完成「保存 API 配置 → 与 AI 对话」这一核心链路
> **依据**: Sprint 30 就绪检查结论（Sessions 可用，Chat/Diagnosis/Training 全部 noop）
> **前置**: Sprint 26-29 全部完成（StorageAdapter + 双轨架构 + ServiceBridge + 测试补强）

---

## 0. 当前 Android 端可用性现状

| 模块 | 当前状态 | 是否为核心依赖 |
|:-----|:---------|:--------------|
| 会话管理 | ✅ 真实实现（CapacitorSqliteAdapter） | — |
| ActiveTraining 草稿 | ✅ 真实实现 | — |
| 教学状态读写 | ⚠️ 部分实现 | — |
| **配置持久化** | ❌ **Noop（依赖 Electron main process）** | ⭐ **AI 对话的前提** |
| **聊天（Chat）** | ❌ **Noop（依赖 main process ChatOrchestrator）** | ⭐ **核心功能** |
| 诊断（Diagnosis） | ❌ Noop | 次优先 |
| 训练（Training） | ❌ Noop | 次优先 |

> **核心障碍链**: 配置不能存 → API Key 拿不到 → LLM 调不了 → Chat 发不出 → 诊断/训练全卡住

---

## 1. 阶段拆解

### 阶段 1: Android 端配置持久化

**目标**: 在 Android/Capacitor 端实现 API 配置的存取

**现状**: 
- Electron 端配置存在 `config.json`（文件系统），由 `ConfigService` 管理
- Android/Capacitor 端没有文件系统级别的配置存储

**方案**: 用 Capacitor 的 Preferences API（键值存储）封装配置

**实施**:
1. 创建 `src/renderer/services/android-config.service.ts`
   - 基于 `@capacitor/preferences` 存取 `apiKey`/`baseUrl`/`modelName` 等
   - get/set 接口
2. 在 Android/Capacitor 端替换 `configService` 调用
   - renderer 端检测 `isCapacitor()` 时走 Android 配置

**DoD**:
- 配置可读写（apiKey/baseUrl/modelName/temperature）
- 重启后配置持久保留
- Capacitor 端 typecheck 0 error

### 阶段 2: Android 端 LLM 直调

**目标**: 在 Android/Capacitor 端直接调用 DeepSeek API（绕过 Electron main process）

**现状**:
- Electron 端 ChatOrchestratorService → LLMService → HTTP (main process)
- Capacitor 端 noop

**方案**: 创建 `src/shared/llm/llm-client.ts` — 跨平台的 LLM HTTP 客户端
- 使用 `fetch` API（WebView 原生支持）
- 支持流式（SSE）和非流式调用
- 不依赖 Electron 的 `net` 模块

**实施**:
1. 封装 LLM HTTP 调用（`llm-client.ts`）
   - 支持 `fetch` 流式读取
   - 请求重试（参考 main process 的 retry middleware）
   - 错误标准化
2. 创建轻量 `ChatService` for Android
   - 接收消息列表 → 调用 LLM → 返回流式响应
   - 不含 full orchestrator 的业务逻辑（诊断/教学编排等暂不包含）
3. `src/renderer/services/chat.service.ts` 的 Capacitor 分支从 noop 改为 `/shared` 直调

**DoD**:
- Android 端可发送消息并接收 AI 回复
- 流式响应支持（SSE → 逐字显示）
- 非流式 fallback
- 错误处理（网络异常/API Key 无效等）

### 阶段 3: 最小链路验证

**目标**: 端到端跑通「启动 App → 配置 API Key → 新建会话 → 发消息 → 收回复」

**实施**:
1. 配置页面在 Android 端可用（已有 UI 组件，只需确保配置存取通）
2. 会话列表 → 会话详情 → 输入框 → 发送 → 显示 AI 回复

**DoD**:
- 最小链路端到端跑通
- `console.log` 链路关键节点
- 写测试覆盖核心路径

### 阶段 4: 门禁 + 收尾

- typecheck 0 error
- test 全部通过
- lint 0 warning
- 写入决策日志 D-081

---

## 2. 总 DoD

1. ✅ Android 端配置持久化（Preferences API）
2. ✅ Android 端 LLM 直调（fetch + SSE）
3. ✅ Chat 从 noop 升级为可用
4. ✅ 最小链路端到端跑通（配置 → 新建会话 → 发消息 → 收回复）
5. ✅ typecheck 0 error
6. ✅ test 全部通过
7. ✅ lint 0 warning
8. ✅ 决策日志 D-081

---

## 3. 时间盒

| 子阶段 | 工时 |
|:-------|:----:|
| 阶段 1: 配置持久化 | 0.5 天 |
| 阶段 2: LLM 直调 + Chat 激活 | 1.5 天 |
| 阶段 3: 最小链路验证 | 0.5 天 |
| 阶段 4: 门禁收尾 | 0.25 天 |
| **总计** | **~3 工作日** |

---

## 4. 后续候选（S32+）

| 候选 | 说明 |
|:-----|:------|
| Diagnosis 移植 | Android 端诊断激活 |
| Training 移植 | Android 端训练激活 |
| 教学状态机移植 | TeachingStateMachine Android 端激活 |
| 日志基础设施 | Android 端结构化日志 + 错误采集 |
