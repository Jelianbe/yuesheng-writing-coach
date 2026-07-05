# Intent Router — 任务清单

> 关联：Issue #34 | Sprint-2 / Phase B | 设计文档：`dev-docs/designs/intent-router-v1.md`
> 创建：2026-06-24

---

## 总览

| 步骤 | 任务 | 文件 | 依赖 | 预计 |
|:----:|:-----|:-----|:-----|:-----|
| T-01 | 创建 IntentRouter types | `intent-router.types.ts` | — | 小 |
| T-02 | 创建 IntentRouter 类 | `intent-router.ts` | T-01 | 中 |
| T-03 | 单元测试 | `__tests__/intent-router.test.ts` | T-02 | 中 |
| T-04 | DI 注册 IntentRouter | `di-container.ts` + `chat-orchestrator.deps.ts` | T-02 | 小 |
| T-05 | ChatOrchestrator 拆分 handler | `chat-orchestrator.service.ts` | T-04 | 大 |
| T-06 | TeachingContext 新增方法 | `teaching-context.service.ts` | — | 小 |
| T-07 | 四道门禁 + 全链路验证 | 终端 | T-05~T-06 | 中 |
| T-08 | 更新 documentation | 设计文档 + decision-log | T-07 | 小 |

---

## 详细任务

### T-01: 创建 IntentRouter types

**文件**：`src/main/domains/03-teaching/chat/intent-router.types.ts`

```typescript
// Intent Router 类型定义

export type IntentType = 'diagnose' | 'learn' | 'train' | 'review' | 'general_chat';

export interface RouteResult {
  intent: IntentType;
  confidence: number;       // 0-1
  source: 'keyword' | 'llm';
}

/** 关键词规则映射 */
export interface KeywordRule {
  keywords: string[];
  intent: IntentType;
}

/** LLM 分类响应格式 */
export interface LLMClassification {
  intent: IntentType;
  confidence: number;
}
```

**DoD**：
- [ ] 类型定义完整，使用 `src/shared/types/index.ts` barrel 导出
- [ ] 无 `any`、`as` 断言、`@ts-ignore`

### T-02: 创建 IntentRouter 类

**文件**：`src/main/domains/03-teaching/chat/intent-router.ts`

```
class IntentRouter {
  private keywordRules: KeywordRule[]
  private llmProvider: LLMProvider
  private CONFIDENCE_THRESHOLD = 0.6

  async route(message: string, _sessionId: string): Promise<RouteResult>
  private classifyByKeywords(message: string): { intent: IntentType; source: 'keyword' } | null
  private async classifyByLLM(message: string): Promise<RouteResult>
}
```

**分类逻辑**：
1. `classifyByKeywords()` 遍历关键词规则，优先匹配最长关键词
2. 若命中 → 返回 `{ intent, confidence: 1.0, source: 'keyword' }`
3. 未命中 → `classifyByLLM()` 调用 LLM 网关做单轮分类
4. LLM 返回的 `confidence < 0.6` → 降级到 `general_chat`

**DoD**：
- [ ] 规则匹配覆盖 5 种意图
- [ ] LLM 兜底调用通过 `LLMProvider` 接口
- [ ] 低置信度降级实现
- [ ] 单文件 ≤ 300 行，单函数 ≤ 50 行

### T-03: 单元测试

**文件**：`src/main/domains/03-teaching/chat/__tests__/intent-router.test.ts`

| 测试用例 | 覆盖率 |
|:---------|:--------|
| `关键词 diagnose 命中` | "帮我看看这段怎么样" → diagnose |
| `关键词 learn 命中` | "怎么才能写好对话" → learn |
| `关键词 train 命中` | "我想练习描写" → train |
| `关键词 review 命中` | "我最近有进步吗" → review |
| `无关键词 → LLM 返回 learn` | mock LLM → learn |
| `LLM 低置信度` | mock LLM confidence 0.4 → general_chat |
| `空字符串` | "" → general_chat |
| `非常用词闲聊` | "今天天气真好" → general_chat |

**DoD**：
- [ ] ≥ 8 个测试用例
- [ ] mock LLMProvider 覆盖 LLM 分类场景
- [ ] 所有测试通过

### T-04: DI 注册

- 在 DI 容器中注册 `IntentRouter`（参考 `chat-orchestrator.service.ts` 已有 DI 模式）
- 注入到 `ChatOrchestratorService`

### T-05: 修改 ChatOrchestratorService.sendMessage()

**重构方案**：
1. `sendMessage()` 中插入 `intentRouter.route()` 调用
2. 提取 5 个 handler 方法：`handleDiagnose`, `handleLearn`, `handleTrain`, `handleReview`, `handleChat`
3. `handleDiagnose` = 当前完整流程
4. `handleLearn` = 跳过诊断 → `teachingContext.prepareLight()` → 流式
5. `handleTrain` = 训练推荐 → 返回训练流
6. `handleReview` = 能力画像 → 返回成长数据
7. `handleChat` = `teachingContext.prepareMinimal()` → 流式

**注意**：train/review handler 在当前 Sprint 中可以先返回简单占位响应，完整的训练流/成长管道留给后续任务。

### T-06: TeachingContext 新增 prepareLight / prepareMinimal

- `prepareLight()`: 加载技法池，不含诊断历史/反思门控
- `prepareMinimal()`: 仅角色定义 + 安全规则

### T-07: 四道门禁

```bash
npm run typecheck   # 零错误
npm run test         # 全绿
npm run lint         # 零 error, warnings ≤ 300
# 安全审查（R-029 零硬编码密钥）
```

### T-08: 文档更新

- 本 checklist 标记完成状态
- `docs/decision-log.md` 记录决策
- Issue #34 更新状态

---

## 文件清单

| 文件 | 行数 | 说明 |
|:-----|:-----:|:------|
| `intent-router.types.ts` | 32 | Intent 枚举 + 路由结果类型 |
| `intent-router.ts` | 190 | IntentRouter 类（规则匹配 + LLM 兜底 + 降级） |
| `__tests__/intent-router.test.ts` | 236 | 22 个单元测试 |

---

## 进度追踪
|:-----|:-----|:---------|:------|
| T-01 | ✅ | 2026-06-24 | Intent types (intent-router.types.ts) |
| T-02 | ✅ | 2026-06-24 | IntentRouter 类 (190行，< 300) |
| T-03 | ✅ | 2026-06-24 | 22 tests, 全部通过 |
| T-04 | ✅ | 2026-06-24 | DI 注册 intentRouter |
| T-05 | ✅ | 2026-06-24 | sendMessage → 5 handler 方法 |
| T-06 | ✅ | 2026-06-24 | prepareLight + prepareMinimal |
| T-07 | ✅ | 2026-06-24 | typecheck ✅ test 683 ✅ lint ✅ |
| T-08 | ✅ | 2026-06-24 | decision-log D-051 + Issue #34 |
