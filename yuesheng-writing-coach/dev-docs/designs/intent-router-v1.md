# Intent Router v1 — 意图路由设计

> **目的**：在 ChatOrchestratorService 中插入意图路由层，使 AI 能根据用户消息自动选择教学行为，而非一刀切跑诊断。
> **前置**：Sprint 18 后端加固已完成（LLM 网关、SQLite 事务、技法库缓存等）。
> **产出**：Issue #34（sprint-2 / Phase B）。
> **更新**：2026-06-24 — 根据市场调研和参考项目分析确认设计决策。

---

## 问题

当前 `chat-orchestrator.service.ts` 的 `sendMessage()` 对每条消息都做三件事：

1. `diagnosisOrchestrator.analyze()` — 调用 LLM 做完整症候分析
2. `teachingContext.prepare()` — 加载完整教学上下文（历史诊断、技法池、反思门控）
3. `streamHandler.handleStream()` — 带完整 System Prompt 流式回复

**问题**：如果用户说"我想练一下对话描写"，系统实际上不需要先诊断——用户已经表达了训练意愿。目前的线性管道浪费 token、增加延迟，且无法支持对话驱动的三层架构。

---

## 设计

### 意图分类

| 意图 | 触发条件 | 路由目标 |
|:----|:---------|:---------|
| `diagnose` | 用户提交叙事文本要求分析/评价 | 诊断管道（analyze → 症候匹配 → 教学上下文 → 流式） |
| `learn` | 用户询问技法/知识点 | 教学管道（跳过诊断 → 技法匹配 → 教学上下文 → 流式） |
| `train` | 用户要求练习 | 训练管道（跳过诊断 → 推荐 → 生成训练流 → 返回结构） |
| `review` | 用户询问成长/进步 | 成长管道（跳过诊断 → 聚合画像 → 返回成长数据） |
| `general_chat` | 闲聊或未明确意图 | 轻量管道（跳过诊断 → 简化上下文 → 流式） |

### 分类方式

**混合策略：快速规则 + LLM 兜底 + 置信度阈值**

```
用户消息
    │
    ├─ 匹配规则关键词 → 直接分类（0 LLM 调用）
    │   "帮我看看" / "分析一下" / "你觉得这段" → diagnose
    │   "怎么" / "教教" / "什么是" / "……是什么" → learn
    │   "练" / "练习" / "写一个" / "试试" → train
    │   "进步" / "成长" / "最近" / "回顾" → review
    │
    └─ 规则未命中 → LLM 分类（1 次轻量调用，约 50 tokens）
        系统消息："判断用户意图，仅返回意图名称"
        模型：同配置（不额外消耗模型）
        超时：5 秒
        置信度：附带confidence分数(0-1)，< 0.6 回退到 general_chat
```

**参考依据**：
- [Grammarly](dev-docs/research/intent-routing-market-research.md)：四维目标配置（Intent/Audience/Formality/Domain），默认回退到基础服务
- [Writer.com](dev-docs/research/intent-routing-market-research.md)：Guardrails 层同时做安全过滤和路由拦截
- [InkOS](dev-docs/research/intent-router-reference-analysis.md)：22 个 Zod 枚举意图 + 分层 switch-case 分发
- [LangGraph](dev-docs/research/intent-router-reference-analysis.md)：Condition Edge + 置信度阈值 + 三级回退（生产环境路由错误率 21%→2.3%）

### 路由后管道

```
Intent Router
    │
    ├─ diagnose
    │   └─ diagnosisOrchestrator.analyze()
    │      └─ teachingContext.prepare(diagnosisAnalysis)
    │         └─ streamHandler.handleStream()  ← 当前完整管道
    │
    ├─ learn
    │   └─ teachingContext.prepareLight(noDiagnosis)
    │      └─ streamHandler.handleStream()     ← 轻量教学管道
    │
    ├─ train
    │   └─ trainingRecommendation.generate()
    │      └─ trainingFlow.generate()
    │         └─ 返回结构化训练流（非流式）
    │
    ├─ review
    │   └─ AbilityProfileService.computeProfile()
    │      └─ RetroService.generateRetroSummary()
    │         └─ 返回成长数据（非流式）
    │
    └─ general_chat
       └─ teachingContext.prepareMinimal()
          └─ streamHandler.handleStream()      ← 极简管道
```

### 关键设计决策

1. **诊断不再无条件执行**。只有 `diagnose` 意图才跑完整诊断分析。
2. **学习/训练/成长意图跳过诊断**。节省 token + 降低延迟。
3. **训练/成长返回结构化数据**（非流式文本）。前端可解析渲染。
4. **意图路由对用户透明**。无"请选择模式"的 UI。
5. **LLM 分类附带置信度**。`confidence < 0.6` → 降级到 `general_chat`（参考 LangGraph 实践）。
6. **每条消息独立路由**。不缓存路由结果，用户意图可能在对话中变化。

---

## 实现步骤

### Step 1: 创建 Intent Router

```
src/main/domains/03-teaching/chat/
  ├── intent-router.ts              # IntentRouter 类实现
  ├── intent-router.types.ts        # Intent 枚举 + 路由结果类型
  └── __tests__/
       └── intent-router.test.ts    # 单元测试
```

#### IntentRouter 类接口

```typescript
class IntentRouter {
  route(message: string, _sessionId: string): Promise<RouteResult>
  // 内部方法：
  // - classifyByKeywords(message): IntentType | null
  // - classifyByLLM(message): Promise<{intent: IntentType, confidence: number}>
}
```

#### RouteResult 类型

```typescript
interface RouteResult {
  intent: IntentType;
  confidence: number;
  source: 'keyword' | 'llm';  // 分类来源，便于调试和指标收集
}
```

### Step 2: 修改 ChatOrchestratorService

```typescript
async sendMessage(args) {
  // 1. 解析章节引用（不变）
  // 2. 保存消息（不变）
  // 3. 意图路由 ← 新增
  const routeResult = await this.intentRouter.route(message, activeSessionId);
  // 4. 按意图路由
  switch (routeResult.intent) {
    case 'diagnose':  return this.handleDiagnose(...);   // 完整诊断管道
    case 'learn':     return this.handleLearn(...);       // 轻量教学管道
    case 'train':     return this.handleTrain(...);        // 训练管道
    case 'review':    return this.handleReview(...);       // 成长管道
    default:          return this.handleChat(...);         // 极简管道
  }
}
```

#### handleDiagnose → 当前完整流程（诊断+教学+流式）
#### handleLearn → 跳过诊断，prepareLight + 流式
#### handleTrain → 训练推荐 + 训练流生成（非流式）
#### handleReview → 能力画像 + 复盘总结（非流式）
#### handleChat → prepareMinimal + 流式

### Step 3: 定义轻量/极简教学上下文

在 `TeachingContextService` 中新增：

- **`prepareLight()`** — 无诊断结果时的教学上下文
  - 含技法池（从 `TechniqueLibraryLoader` 加载）
  - 不含症候分析
  - 不含反思门控
  - System Prompt 更轻量（角色定义 + 技法上下文 + 安全规则）

- **`prepareMinimal()`** — 纯聊天上下文
  - 仅角色定义（"你是一个专业的写作教练月笙"）
  - 安全规则（不替写、不替决定）
  - 不含诊断历史、技法、反思等

### Step 4: 测试

| 测试 | 覆盖 |
|:----|:-----|
| 规则命中 | 每个意图 3 条规则关键词命中测试 |
| LLM 兜底 | mock LLM 返回各意图名称 + 置信度 |
| 未命中 fallback | 空字符串/非常用词 → general_chat |
| 低置信度降级 | confidence < 0.6 → general_chat |
| 端到端 | sendMessage 按意图路由到不同管道 |

---

## 研究参考

- [市场调研报告](dev-docs/research/intent-routing-market-research.md)：Grammarly/Writer.com 意图路由模式分析
- [参考项目分析](dev-docs/research/intent-router-reference-analysis.md)：Rasa/InkOS/LangGraph/Parlant 开源方案对比
- [INKOS 外部参考](dev-docs/external-references/inkos-source/)：22 种 InteractionIntent Zod 枚举

---

## 未解决问题

| 问题 | 决策 |
|:-----|:-----|
| 用户已说"我想练"但消息中包含叙事文本 | 当前方案忽略诊断，直接进入训练管道 |
| 意图切换 | 用户问了一个问题后说"算了，还是先帮我看看这段" → 按新消息重新路由 |
| 路由结果缓存 | 不缓存，每条消息独立路由 |
| 训练/成长管道的非流式响应 | 先返回结构化数据，后续可扩展为流式 |
| 路由指标收集 | v1 不实现，留待 v2 |

---

*本设计基于三层架构 PRD v1、backend-audit-report-2026-06-24.md 和研究参考文件*
