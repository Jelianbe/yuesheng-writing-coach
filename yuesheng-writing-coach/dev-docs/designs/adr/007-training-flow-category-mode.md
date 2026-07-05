# ADR-007: 训练流 mapping 改用 CATEGORY 模式（偏离 sprint-16-plan 的 challengeId 模式）

> **编号**: ADR-007
> **状态**: 已接受（2026-06-23）
> **作者**: AI 架构师
> **关联**: Sprint 16 计划（PR #24 / D-046）/ Sprint 17 验收（T17-1）/ D-047

---

## 一、背景

Sprint 16 plan §BL-01a 写的是基于 challengeId 的映射：

```typescript
// plan 假设的形态
{
  challengeId: 'CH-P001-001',
  syndromeId: 'P001',
  techniqueName: '...',
  userLevel: 1,
  category: '开篇'
}
```

实际实现改成了「**5 个 CATEGORY + 5 步 FLOW_TEMPLATES**」的分离结构：

```typescript
// 实际 training-flow-mapping.json 形态
{
  categories: {
    '开篇': { name: '开篇', description: '...' },
    '人物': { ... },
    ...
  },
  flowTemplates: {
    default: [
      { step: 1, type: 'explain', name: '解说技法' },
      { step: 2, type: 'example', name: '例证展示' },
      { step: 3, type: 'confirm', name: '确认理解' },
      { step: 4, type: 'practice', name: '主动尝试' },
      { step: 5, type: 'feedback', name: '反馈评价' }
    ]
  }
}
```

Sprint 16 plan 的 DoD #2「fillTemplate() 覆盖 P001-P007 至少 5 个症候」**未在 PR #24 中兑现**。Sprint 17 验收时需 ADR 解释这个偏离，否则不算正式验收。

---

## 二、决策

### 2.1 选 CATEGORY 模式作为最终方案

**决议**: 保留实际实现的 CATEGORY 模式，**不退回** challengeId 模式。

### 2.2 修订 Sprint 16 DoD #2

原 plan DoD #2「fillTemplate() 覆盖 P001-P007 至少 5 个症候」修订为：

> **修订 DoD #2**: 5 个 CATEGORY 至少各覆盖 1 个 challengeId（开篇/人物/节奏/语言/结构 五大类各举 1 例）
>
> - 开篇 → CH-P001-001（开篇钩子）
> - 人物 → CH-P002-001（人物速写）
> - 节奏 → CH-P003-001（节奏控制）
> - 语言 → CH-P004-001（语言打磨）
> - 结构 → CH-P005-001（结构搭建）

### 2.3 训练流 mapping 的最终形态

```
challengeId (CH-PXXX-XXX)
   ↓ 路由
category (开篇/人物/节奏/语言/结构)
   ↓ 5 步模板
TrainingFlow (5 步通用流: 解说→例证→确认→尝试→反馈)
   ↓ 动态填充
ActiveTrainingSession (运行时实例)
```

---

## 三、理由

### 3.1 CATEGORY 模式的优势

#### 优势 1: 5 步教学动作与具体 challengeId 解耦后**可复用**

5 步教学动作（解说→例证→确认→尝试→反馈）是**通用教学协议**，与"开篇/人物/节奏/语言/结构"等具体写作领域无关。如果硬绑到 challengeId，就意味着每加一个 challenge 都要重写一份 5 步配置。

CATEGORY 模式让 5 步协议成为**横切关注点**：所有 category 共享同一份 5 步流程，差异仅在 step 1（解说）和 step 2（例证）的具体内容（由技法库动态取数）。

#### 优势 2: 避免 6 challengeId × 5 步笛卡尔积爆炸

6 个 challengeId × 5 步 = 30 个手写配置项。每加 1 个新 challenge 增加 5 个配置。

CATEGORY 模式下 5 个 category × 1 个 5 步模板 = 5 个配置 + 动态数据填充。新增 category 只需 1 个 JSON 条目。

#### 优势 3: 与"五步教学动作是正确解决方案"用户原话一致

D-046 记录的用户原话：

> 「技法库膨胀按当前缺口必定导致训练库膨胀，转为五步教学动作流程才是正确解决方案」

CATEGORY 模式正是把"5 步教学动作"作为**第一公民**的实现方式。

### 3.2 challengeId 模式的问题

#### 问题 1: 与 R-014 配置外置原则冲突

原 plan §BL-01a 的 challengeId 模式需要为每个 challenge 写完整 5 步配置。这会导致：
- 配置条目数爆炸（6 起步，扩展到 31 条 = 155 步配置）
- 与"配置外置是为了减少硬编码"的初衷背道而驰（硬编码 = 把所有 5 步内容写死到 JSON）

#### 问题 2: 复用率低

同一个"开篇钩子"教学技法，可能适用于 CH-P001-001（开篇钩子）、CH-P001-002（开篇共鸣）、CH-P001-003（开篇悬念）三个不同 challenge。如果按 challengeId 硬绑，会出现：
- 同一技法被描述 3 次
- 调整教学法时需同步 3 处

#### 问题 3: 与"技法库动态取数"理念冲突

D-046 的核心决策 1「不新增 per-症候训练任务，从技法库动态取数据」要求训练流是**通用容器**。challengeId 模式会把容器与具体内容混在一起，破坏通用性。

---

## 四、影响

### 4.1 验证影响

| 原 plan DoD | 实际验收标准 |
|:---|:---|
| DoD #2: fillTemplate() 覆盖 P001-P007 至少 5 个症候 | 修订：5 个 CATEGORY 各覆盖 1 个 challengeId（共 5 个示例） |
| DoD #1: 用户可走完五步流 | **未验收**（BL-22 阻塞 Electron E2E，Sprint 17 T17-3 处理） |
| DoD #3-#6 | 保持不变（已通过） |

### 4.2 技术债

- **D-DEBT-2026-06-23-28**（新）：CATEGORY 与 challengeId 路由映射未在外置 JSON 中明确化。当前 `getFlowCategory()` 函数内部 hardcode 了 categoryKey → challengeId 的隐式映射（通过 challengeId 字符串前缀 P001/P002/P003 推断 category）。**Sprint 17+ 安排**：在 training-flow-mapping.json 增加 `challengeRouting` 字段，显式声明 P001 → 开篇
- Sprint 16 plan §BL-01a 与实际实现偏离 = **流程债务**：Sprint 计划文档与实现脱节。**改进**：Sprint 17 起严格执行 plan → code 偏差必须 24 小时内 ADR 登记

### 4.3 数据流

```
用户在 ChatPanel 触发训练 (challengeId=CH-P001-001)
  ↓
training.actions.ts: startTraining(challengeId)
  ↓ IPC: training:generateFlow
TrainingFlowService
  ↓ 调 training.flow.ts: getFlowCategory('开篇')  // 硬编码前缀
  ↓ 调 training-flow-mapping.json: flowTemplates.default
  ↓ 返回 TrainingFlow (5 步模板 + category 元数据)
  ↓ 返回给 renderer
ActiveTrainingView: if (activeTraining.flowType === 'flow5')
  ↓ 渲染
<FiveStepFlow flow={trainingFlow} ... />
```

---

## 五、备选方案（已否决）

### 备选 A: 退回原 plan 的 challengeId 模式

- 缺点 1: 与用户原话"5 步教学动作是正确解决方案"冲突
- 缺点 2: 6 challengeId × 5 步笛卡尔积爆炸
- 缺点 3: 实现已完成 CATEGORY 模式，退回成本高（要重写 training.actions.ts / training.flow.ts / 5 步容器）
- 决策: 否决

### 备选 B: 双轨模式（同时保留 challengeId + CATEGORY）

- 缺点 1: 复杂度翻倍，文档/测试/调试全翻倍
- 缺点 2: 用户实际只看到一种模式（UI 层只渲染 flow5），双轨无意义
- 决策: 否决

### 备选 C: 纯 challengeId 模式但简化（每 challenge 只配 1 个 step 类型标识符）

- 缺点 1: "5 步教学动作"被弱化为可选
- 缺点 2: 失去"通用 5 步协议"的一致性
- 决策: 否决

---

## 六、依据

- D-046 Sprint 16 Reflect（5 决策 + 用户原话「5 步教学动作是正确解决方案」）
- D-047 Sprint 17 启动（验收闭环）
- Sprint 16 plan §BL-01a
- `resources/config/training-flow-mapping.json` 实际实现
- `src/renderer/flow/training.flow.ts` getFlowCategory 函数
- R-010 最小化范围 / R-014 配置外置 / R-018 变更溯源
- 用户原话（保留在 D-046 Context）

---

## 七、状态

✅ **已接受**（2026-06-23）— 与实际实现对齐；Sprint 16 DoD #2 修订为"5 个 CATEGORY 各覆盖 1 个 challengeId"；Sprint 17 T17-3 E2E 验证时一并验收
