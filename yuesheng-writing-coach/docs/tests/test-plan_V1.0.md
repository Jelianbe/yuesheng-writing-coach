# 月笙写作教练 — AI 问答交互测试方案 V1.0

**版本**: V1.0  
**创建日期**: 2026-06-04  
**关联**: MVP 审计报告、IPC 接口规范 V2.0、工程债修复规格  

---

## 1. 测试架构总览

```
┌─────────────────────────────────────────────────────────────┐
│                      Test Execution Engine                    │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌─────────────┐  │
│  │ 单元测试  │  │ 集成测试  │  │ 流程测试  │  │ 端到端测试  │  │
│  │ (Unit)   │  │ (Integ)  │  │ (Flow)   │  │ (E2E)      │  │
│  └─────┬────┘  └─────┬────┘  └─────┬────┘  └──────┬──────┘  │
│        └──────────────┴──────────────┴──────────────┘        │
│                            │                                 │
│                    ┌───────┴───────┐                         │
│                    │  Test Utils   │                         │
│                    │ (Mock Factory │                         │
│                    │  + Fixtures)  │                         │
│                    └───────────────┘                         │
└─────────────────────────────────────────────────────────────┘
```

### 测试分层

| 层级 | 范围 | 工具 | 覆盖目标 |
|------|------|------|---------|
| L1 单元测试 | 单个函数/Store/Service | vitest | 核心逻辑正确性 |
| L2 集成测试 | IPC Handler + Service 交互 | vitest + mock IPC | 模块间接口正确性 |
| L3 流程测试 | 完整链路端到端 | vitest + IPC mock | 业务流程完整性 |
| L4 E2E 测试 | 模拟用户操作 | Playwright + mock API | UI 交互正确性 |

---

## 2. 功能模块扫描

### 2.1 已实现模块清单

| 模块 ID | 模块名 | 核心功能 | 文件路径 | 实现状态 | 测试状态 |
|---------|--------|---------|---------|---------|---------|
| M-CONF | 配置管理 | API Key/URL/Model 配置读写 + 连接测试 | config.store.ts / config.handler.ts | ✅ 完整 | ⚠️ 部分 |
| M-CHAT | 聊天引擎 | 流式对话 + 消息存储 + 中断 | chat.handler.ts / api-proxy.ts | ✅ 完整 | ⚠️ 部分 |
| M-SESS | 会话管理 | 会话 CRUD + 自动标题 + 消息列表 | session.handler.ts / session.service.ts | ✅ 完整 | ⚠️ 部分 |
| M-DIAG | 诊断引擎 | AI 诊断解析 + 持久化 + IPC 推送 | diagnosis.handler.ts / diagnosis-parser.ts | ✅ 完整 | ⚠️ 部分 |
| M-TEACH | 教学状态机 | 阶段流转 + 子阶段管理 + 动作确认 | teaching-state.handler.ts / teaching-state.store.ts | ✅ 完整 | ⚠️ 部分 |
| M-EVID | 证据管理 | 证据 CRUD + 诊断关联 + 链式查询 | evidence.handler.ts / evidence.service.ts | ✅ 完整 | ❌ 未测 |
| M-PROF | 作者画像 | 能力评分 + 轨迹追踪 + 成长链 | author-profile-v2.handler.ts | ✅ 完整 | ❌ 未测 |
| M-INTENT | 意图一致性 | 意图提取 + 执行模式匹配 + 矛盾检测 | intent-consistency.service.ts | ✅ 完整 | ❌ 未测 |
| M-REWRITE | 修改原文 | 原文修改 + AI 评估 + 成长对比 | diagnosis.handler.ts / api-proxy.ts | ✅ 完整 | ❌ 未测 |
| M-UI | 前端 UI 组件 | Chat/诊断/教学/配置面板 | components/ | ⚠️ 核心完成 | ❌ 未测 |

### 2.2 模块依赖关系

```
M-CONF ────┬─── M-CHAT ──── M-SESS
           │
           ├─── M-DIAG ────┬─── M-EVID
           │               ├─── M-PROF
           │               └─── M-INTENT
           │
           ├─── M-REWRITE ──┬─── M-EVID
           │                └─── M-CHAT (消息存储)
           │
           └─── M-TEACH ──── M-DIAG (作为诊断输出消费者)
                           M-SESS (按 session 存储)
```

### 2.3 已实现与完整需求的差距

| 功能点 | 当前状态 | 完整目标 | 差距 |
|--------|---------|---------|------|
| 诊断面板简化 | M-5 待开发 | 单视图嵌入 Chat 流 | 需取消右面板三标签 |
| 训练任务 | V1.1-6 待开发 | 评估后推荐训练 | 未实现 |
| 能力画像文字版 | V1.1-7 待开发 | 数字评分→文字分级 | 未实现 |
| UI E2E 测试 | 未开始 | Playwright 全流程覆盖 | 需搭建 Playwright 环境 |

---

## 3. 测试用例体系

### 3.1 功能验证用例（FC）

#### FC-01: API 配置全流程

```typescript
// 测试目标：配置读写 + 连接测试 + 持久化
test('配置管理 - 完整生命周期', async () => {
  // 1. 初始状态：未配置
  expect(store.isConfigured).toBe(false);
  
  // 2. 写入配置
  await store.setApiKey('sk-test-key');
  await store.setBaseUrl('https://api.test.com');
  await store.setModelName('gpt-4o');
  await store.setTemperature(0.7);
  
  // 3. 配置持久化
  expect(store.apiKey).toBe('sk-test-key');
  expect(store.isConfigured).toBe(true);
  
  // 4. 连接测试
  const result = await handler.testConnection({
    apiKey: 'sk-test-key',
    baseUrl: 'https://api.test.com',
  });
  expect(result.success).toBe(true);
  
  // 5. 重新加载
  await store.loadConfig();
  expect(store.apiKey).toBe('sk-test-key');
});
```

#### FC-02: 聊天基础交互

```typescript
// 测试目标：发送消息 → 流式接收 → 消息持久化
test('聊天 - 发送并接收回复', async () => {
  const sessionId = 'test-session-1';
  
  // 1. 发送消息
  const result = await handler.chatSend({
    message: '第一章 林凡出生在青云宗外门弟子院',
    sessionId,
  });
  expect(result.success).toBe(true);
  
  // 2. 验证消息保存
  const messages = sessionService.getMessages(sessionId);
  expect(messages).toHaveLength(2); // user + assistant
  expect(messages[0].role).toBe('user');
  expect(messages[1].role).toBe('assistant');
});
```

#### FC-03: 诊断生成与推送

```typescript
// 测试目标：可分析文本 → 诊断 Agent 调用 → DiagnosisEntry 推送
test('诊断 - 可分析文本触发诊断', async () => {
  const analysisText = '...500字小说文本...';
  const sessionId = 'test-session-2';
  const onDiagnosisUpdate = vi.fn();
  
  // 监听 diagnosis:update 事件
  mainWindow.webContents.on(IPC_CHANNELS.DIAGNOSIS_UPDATE, onDiagnosisUpdate);
  
  await handler.chatSend({ message: analysisText, sessionId });
  
  // 验证诊断事件推送
  expect(onDiagnosisUpdate).toHaveBeenCalledTimes(1);
  const entry = onDiagnosisUpdate.mock.calls[0][0];
  expect(entry.syndromes.length).toBeGreaterThan(0);
  expect(entry.sessionId).toBe(sessionId);
});
```

#### FC-04: 修改原文入口

```typescript
// 测试目标：编辑 → 提交 → 评估 → 成长对比
test('修改原文 - 完整流程', async () => {
  const sessionId = 'test-session-3';
  const originalText = '他资质平平，只是一个普通的散修';
  
  // 1. 提交修改
  const result = await handler.submitRewrite({
    sessionId,
    syndromeId: 'P004',
    originalText,
    rewrittenText: '他盘坐在硬板床上吐纳了三息便散去',
    syndromeName: '信息硬塞',
  });
  expect(result.success).toBe(true);
  expect(result.evaluation).toBeDefined();
  expect(['明显改善', '略有改善', '无明显改善']).toContain(result.evaluation!.improvement);
  
  // 2. 获取成长对比
  const comparison = await handler.getComparison({ sessionId });
  expect(comparison.hasHistory).toBe(false); // 首次诊断，无历史
});
```

#### FC-05: 教学状态流转

```typescript
test('教学状态 - 阶段推进', async () => {
  const sessionId = 'test-session-4';
  
  // 1. 初始状态
  let state = await handler.getState({ sessionId });
  expect(state.currentPhase).toBe('P0_INIT');
  
  // 2. 确认推进
  const confirmResult = await handler.confirmState({ sessionId });
  expect(confirmResult.oldState.currentPhase).toBe('P0_INIT');
  
  // 3. 验证新阶段
  state = await handler.getState({ sessionId });
  expect(['P1_WORLD', 'P2_PRACTICE_LOOP']).toContain(state.currentPhase);
});
```

### 3.2 边界条件用例（BC）

#### BC-01: 空文本处理

```typescript
test('边界 - 空文本不会触发诊断', async () => {
  const sessionId = 'test-session-5';
  const onDiagnosisUpdate = vi.fn();
  mainWindow.webContents.on(IPC_CHANNELS.DIAGNOSIS_UPDATE, onDiagnosisUpdate);
  
  await handler.chatSend({ message: '', sessionId });
  expect(onDiagnosisUpdate).not.toHaveBeenCalled();
});

test('边界 - 短文本不触发诊断', async () => {
  const sessionId = 'test-session-6';
  const onDiagnosisUpdate = vi.fn();
  mainWindow.webContents.on(IPC_CHANNELS.DIAGNOSIS_UPDATE, onDiagnosisUpdate);
  
  await handler.chatSend({ message: '你好', sessionId });
  expect(onDiagnosisUpdate).not.toHaveBeenCalled();
});
```

#### BC-02: 超长文本

```typescript
test('边界 - 10000字长文本', async () => {
  const longText = '测试文本'.repeat(5000); // 10000 字
  const result = await handler.chatSend({
    message: longText,
    sessionId: 'test-session-7',
  });
  
  // 系统应能处理，不崩溃
  expect(result.success).toBe(true);
});
```

#### BC-03: 无效会话 ID

```typescript
test('边界 - 无效会话 ID', async () => {
  const result = await handler.getState({ sessionId: 'non-existent-id' });
  expect(result).toBeNull();
  
  const messages = await handler.getMessages({ sessionId: '' });
  expect(messages).toEqual([]);
});
```

#### BC-04: 配置边界值

```typescript
test('边界 - 温度参数边界', async () => {
  // 最小温度
  await store.setTemperature(0);
  expect(store.temperature).toBe(0);
  
  // 最大温度
  await store.setTemperature(2);
  expect(store.temperature).toBe(2);
  
  // 超出边界
  await store.setTemperature(-1);
  expect(store.temperature).toBe(0); // 应自动修正
  
  await store.setTemperature(3);
  expect(store.temperature).toBe(2); // 应自动修正
});
```

### 3.3 异常处理用例（EC）

#### EC-01: API 连接失败

```typescript
test('异常 - API 连接失败', async () => {
  const result = await handler.testConnection({
    apiKey: 'invalid-key',
    baseUrl: 'https://invalid-url.example.com',
  });
  expect(result.success).toBe(false);
  expect(result.error).toBeDefined();
});

test('异常 - 发送时网络断开', async () => {
  // 模拟网络断开
  mockApiProxy.mockReject(new Error('Network error'));
  
  const result = await handler.chatSend({
    message: '测试消息',
    sessionId: 'test-session-8',
  });
  expect(result.success).toBe(false);
  expect(result.error).toContain('Network error');
});
```

#### EC-02: 诊断解析失败

```typescript
test('异常 - AI 回复不含有效 JSON', () => {
  const invalidResponse = '这是一段普通的回复，不包含诊断JSON。';
  const result = parseDiagnosisFromAIResponse(invalidResponse, 'sid', 'mid');
  expect(result.diagnosis).toBeNull();
  expect(result.cleanResponse).toBe(invalidResponse);
});

test('异常 - 诊断 JSON 格式错误', () => {
  const malformedResponse = '一些前置文字\n```json\n{ invalid json }\n```';
  const result = parseDiagnosisFromAIResponse(malformedResponse, 'sid', 'mid');
  expect(result.diagnosis).toBeNull();
});
```

#### EC-03: 数据库异常

```typescript
test('异常 - 数据库写入失败', async () => {
  // 模拟数据库错误
  mockDb.mockReject(new Error('SQLITE_BUSY'));
  
  const result = await handler.chatSend({
    message: '测试消息',
    sessionId: 'test-session',
  });
  // 系统不应崩溃
  expect(result).toBeDefined();
});
```

### 3.4 性能测试用例（PC）

```typescript
test('性能 - 并发消息发送', async () => {
  const concurrency = 5;
  const promises = Array(concurrency).fill(null).map((_, i) =>
    handler.chatSend({
      message: `并行消息 ${i}`,
      sessionId: 'test-session-perf',
    })
  );
  
  const start = Date.now();
  const results = await Promise.all(promises);
  const duration = Date.now() - start;
  
  // 所有请求都应成功
  results.forEach(r => expect(r.success).toBe(true));
  // 总耗时应在可接受范围内（mock 场景 < 500ms）
  expect(duration).toBeLessThan(500);
});

test('性能 - 大量会话创建', async () => {
  const sessions = 50;
  const start = Date.now();
  
  for (let i = 0; i < sessions; i++) {
    const session = await handler.createSession();
    expect(session.id).toBeDefined();
  }
  
  const duration = Date.now() - start;
  // 50 个会话创建应在 2s 内完成
  expect(duration).toBeLessThan(2000);
});
```

---

## 4. 测试基础设施

### 4.1 Mock 体系

```
test/mocks/
├── ipc-mock.ts           # IPC 通道模拟（ipcMain.handle + webContents.send）
├── api-proxy-mock.ts     # API 代理模拟（流式/非流式）
├── db-mock.ts            # SQLite 模拟（better-sqlite3）
├── store-mock.ts         # electron-store 模拟
└── fixtures/
    ├── diagnosis.ts      # 诊断数据 fixture
    ├── messages.ts       # 聊天消息 fixture
    ├── analysis.ts       # DiagnosisAnalysis fixture
    └── sessions.ts       # 会话数据 fixture
```

### 4.2 测试数据生成器

```
test/generators/
├── text-generator.ts     # 小说文本生成器（长度/风格可控）
├── diagnosis-generator.ts # 诊断结果生成器
└── flow-generator.ts     # 流程场景生成器
```

### 4.3 断言辅助

```
test/assertions/
├── diagnosis-assert.ts   # 诊断结果断言
├── state-assert.ts       # 教学状态断言
└── chat-assert.ts        # 聊天交互断言
```

---

## 5. 测试覆盖率目标

| 覆盖维度 | 当前基线 | 目标 |
|---------|---------|------|
| 函数覆盖率 | - | ≥ 80% |
| 分支覆盖率 | - | ≥ 70% |
| IPC Handler 覆盖率 | - | 100% |
| Service 覆盖率 | - | ≥ 90% |
| Store 覆盖率 | - | ≥ 90% |
| UI 组件覆盖率 | - | ≥ 60% |
| E2E 流程覆盖率 | - | 核心链路 100% |

### 核心链路必须覆盖

```
API 配置 → 聊天发送 → 诊断 Agent → 诊断展示
  → 教学状态更新 → 修改原文 → AI 评估 → 成长记录
```

---

## 6. 测试报告系统

### 6.1 测试通过/失败判定规则

| 等级 | 定义 | 阈值 |
|------|------|------|
| 🟢 通过 | 全部功能用例通过 | 100% |
| 🟡 警告 | 功能用例通过，边界/异常用例 < 20% 失败 | > 80% |
| 🔴 失败 | 功能用例失败或边界/异常用例 > 20% 失败 | < 80% |
| ⚫ 阻塞 | 编译错误或核心模块测试失败 | 0% |

### 6.2 报告格式

```json
{
  "timestamp": "2026-06-04T12:00:00Z",
  "summary": {
    "total": 120,
    "passed": 115,
    "failed": 3,
    "skipped": 2,
    "passRate": 95.8,
    "duration": "45.2s"
  },
  "modules": {
    "M-CONF": { "total": 10, "passed": 10, "failed": 0, "coverage": 92 },
    "M-CHAT": { "total": 25, "passed": 24, "failed": 1, "coverage": 88 },
    "M-DIAG": { "total": 30, "passed": 29, "failed": 0, "coverage": 85 },
    "M-TEACH": { "total": 20, "passed": 20, "failed": 0, "coverage": 90 },
    "M-SESS": { "total": 15, "passed": 15, "failed": 0, "coverage": 91 },
    "M-REWRITE": { "total": 10, "passed": 9, "failed": 1, "coverage": 80 },
    "M-EVID": { "total": 10, "passed": 8, "failed": 1, "coverage": 0 },
  },
  "failedTests": [
    {
      "name": "证据管理 - 创建并查询",
      "error": "evidence.service is not initialized",
      "module": "M-EVID"
    }
  ]
}
```

---

## 7. 执行策略

### 7.1 分阶段执行

| 阶段 | 内容 | 优先度 | 预计工时 |
|------|------|--------|---------|
| P1 | 测试基础设施搭建（mock + config + utils） | 最高 | 2h |
| P2 | 已有测试文件的补充完善 | 高 | 1h |
| P3 | IPC Handler 集成测试 | 高 | 2h |
| P4 | Store 单元测试 | 高 | 1.5h |
| P5 | Service 单元测试（证据、画像、意图） | 高 | 2h |
| P6 | E2E 流程集成测试 | 中 | 2h |
| P7 | 报告系统 + CI 配置 | 中 | 1h |

### 7.2 运行命令

```bash
# 完整测试套件
npm test

# 仅单元测试（快速）
npx vitest run --reporter=verbose

# 带覆盖率报告
npm run test:coverage

# 指定模块测试
npx vitest run src/main/services/__tests__/

# 持续监视模式（开发用）
npm run test:watch
```

---

## 8. 系统行为监控验证

| 监控点 | 验证方法 | 验证标准 |
|--------|---------|---------|
| 数据流向 | 追踪 IPC 调用链 | 每一环都有输入输出记录 |
| 状态一致性 | 读回数据库验证 | UI 状态 === 数据库状态 |
| 错误传播 | 注入异常后验证 | 错误被正确捕获并返回友好消息 |
| 资源释放 | 长时间运行后验证 | 无内存泄露、连接未释放 |

---

## 变更记录

| 版本 | 日期 | 变更内容 |
|------|------|---------|
| V1.0 | 2026-06-04 | 初始测试方案，含模块扫描、用例体系、基础设施、覆盖率目标 |
