# 工程债修复 + MVP 后续开发规格

**版本**: V1.0  
**创建日期**: 2026-06-04  
**关联文档**:  
- MVP 审计报告: `docs/tasks/MVP-audit-report_V1.0.md`  
- 任务序列: `docs/tasks/TASK-SEQUENCE_V1.0.md`  
- 前端设计: `docs/design/FRONTEND_REDESIGN_V1.md`

---

## 一、当前状态快照

### 已完成（15/15 MVP 阶段一）

核心教学链路完整跑通：

| 模块 | 状态 | 说明 |
|------|------|------|
| API 配置 | ✅ | 含自动升级迁移 |
| 聊天系统 | ✅ | 流式输出 + 中断 + 消息持久化 |
| 会话管理 | ✅ | SQLite CRUD + 自动标题 |
| 诊断系统 | ✅ | AI 解析 + IPC 推送 + 卡片展示 |
| 教学状态机 | ✅ | 状态流转 + 持久化 + IPC |
| 态度档位 | ✅ | Header 三态 → Store → IPC → Prompt |

### 审计发现必须处理的工程债

| # | 事项 | 优先级 | 说明 |
|---|------|--------|------|
| 1 | MVP 任务文档过期 | P0 | T-009~T-014 实际已完成但文档标记"待开发" |
| 2 | IPC 接口文档过期 | P0 | 文档仅 14 通道，实际 34 通道 |
| 3 | Preload 白名单验证 | P1 | 新增 17 通道需验证，但**已完成**——preload/index.ts 已包含全部 29 个 invoke 通道和 4 个 event 通道 |
| 4 | Handler 缺口 | P0 | `diagnosis:submitRewrite` 和 `diagnosis:getComparison` 在 constants.js 定义了常量，但审计报告中错误标注为"无后端实现"——实际已在 [diagnosis.handler.ts](file:///D:/ai-teacher/yuesheng-writing-coach/src/main/ipc/diagnosis.handler.ts#L90-L143)（getComparison）和 [diagnosis.handler.ts](file:///D:/ai-teacher/yuesheng-writing-coach/src/main/ipc/diagnosis.handler.ts#L236-L275)（submitRewrite）中实现 |
| 5 | design-specification 配色对齐 | P1 | 现有 CSS 需要与 FRONTEND_REDESIGN_V1.md 的 V2.0 配色对齐 |

**重要修正**：审计报告第 4.3 节标注 `diagnosis:submitRewrite` 和 `diagnosis:getComparison` 为"通道定义但无 handler"，这是**错误**的。实际代码已检查：
- `DIAGNOSIS_SUBMIT_REWRITE` handler 在 diagnosis.handler.ts 第 236-275 行
- `DIAGNOSIS_GET_COMPARISON` handler 在 diagnosis.handler.ts 第 90-143 行
- 两者都已在 Preload 白名单中注册（constants.js + preload/index.ts 均包含）

---

## 二、开发规划

### 阶段 A：工程债修复（当前阶段）

| 任务 | 操作 | 产出 |
|------|------|------|
| A-1 更新 MVP 任务文档 | 标记 T-009~T-014 为已完成，补充实际实现描述 | `mvp-phase1-tasks_V1.1.md` |
| A-2 更新 IPC 接口文档 | 从 14 通道扩展到 34 通道，按模块分类 | `ipc-interface-spec_V2.0.md` |
| A-3 更新审计报告 | 修正 Handler 缺口的错误标注 | `MVP-audit-report_V1.1.md` |

### 阶段 B：MVP 后续开发（核心治疗闭环）

这是本阶段的核心目标。M-1（症候修正）已完成，后续按依赖顺序执行：

```
M-1 ✅（已完成）
  ↓
M-2 修改原文入口（6h）
  ↓
M-3 AI 修改评估（3.5h）
  ↓
M-4 一句话成长记录（2h）
  ↓
M-5 诊断面板简化（4h）
```

#### 整体体验目标

```
用户发送文本
    ↓
月笙回复（包含诊断）
    ↓
诊断卡片嵌入 Chat 流中（默认折叠）
    ↓
用户点击"尝试修改"
    ↓
EditPanel 在 Chat 流中内联展开
    ↓
用户修改后点击"提交评估"
    ↓
EvaluationCard 作为新消息出现
    ↓
GrowthCard 自动展示一句话成长对比
```

#### M-2：修改原文入口

**设计目标**：在诊断卡片中增加"尝试修改"按钮，点击后在 Chat 流中展开内联编辑区。

**前端设计**：

```
┌─── 修改这段 ──────────────────────────┐
│                                        │
│  ┌── 原文（灰色底，不可编辑）───┐     │
│  │ "筑基中期。普通散修资质..."  │     │
│  └──────────────────────────────┘     │
│                                        │
│  ┌── 你的修改 ─────────────────────┐  │
│  │ (placeholder: 试着把这段... )   │  │
│  │                                  │  │
│  └──────────────────────────────────┘  │
│                                        │
│  [取消]                    [提交评估 →]│
└────────────────────────────────────────┘
```

**交互流程**：
1. 诊断卡片中点击"尝试修改"按钮
2. EditPanel 内联展开（高度动画 300ms）
3. 原文区灰色显示（不可编辑），编辑区聚焦
4. 用户修改后点击"提交评估"
5. 调用 `diagnosis:submitRewrite` IPC
6. 等待 AI 评估期间显示 loading
7. 评估结果作为 EvaluationCard 插入 Chat 流
8. EditPanel 自动收起

**涉及变更**：
| 文件 | 变更内容 |
|------|---------|
| `src/renderer/components/diagnosis/EditPanel.tsx` | 重构为 M-2 规范（双栏：原文 + 编辑区 + 提交按钮） |
| `src/renderer/components/chat/MessageBubble.tsx` | 支持在消息流中嵌入 EditPanel |
| `src/renderer/stores/diag.store.ts` | 新增 `setRewriteTarget`、`clearRewriteTarget` 状态 |
| `src/renderer/App.tsx` | 处理 submitRewrite 的 IPC 调用 + loading 状态 |
| `src/renderer/shared/types.ts` | 新增 `RewriteEvaluation` 类型定义 |
| `src/main/api-proxy.ts` | 新增 `evaluateRewrite()` 方法 |

**DoD**：
- [ ] 每条诊断的原文引用旁都有"尝试修改"按钮
- [ ] 点击后在 Chat 流中内联展开编辑区（不跳转页面）
- [ ] 原文区只读，编辑区可编辑
- [ ] 提交后能收到 AI 评估结果
- [ ] TypeScript 编译零错误

---

#### M-3：AI 修改评估

**设计目标**：用户提交修改后，AI 评估修改效果并返回结构化的评估结果。

**前端设计**：

```
┌─── 修改评估 ─────────────────────────┐
│  ✅ 这个改法有效                      │
│                                        │
│  你的修改用"摸符箓"替代了"资源稀缺"    │
│  的旁白说明——这个小场景让读者自己       │
│  感受到主角的处境。                    │
│                                        │
│  建议再试一步：如果在这个动作之后       │
│  加一个环境细节（比如阴冷的风吹过他     │
│  后颈），氛围会更完整。                │
│                                        │
│  ───                                  │
│  对比之前：                           │
│  ❌ "筑基中期。普通散修资质..."        │
│  ✅ "他摸了摸腰间仅剩的两张匿气符"     │
└────────────────────────────────────────┘
```

**后端 API 调用**：

提交修改时，后端调用 AI 接口获取评估。评估 Prompt 结构：
```
你是一位写作教练。用户刚刚尝试修改一段文字。
- 原文：[originalText]
- 修改后：[rewrittenText]
- 症候：[syndromeName] - [syndromeDesc]

请评估用户的修改是否有效改善了这个症候，输出：
1. 总体评价（✅有效 / ⚠️部分有效 / ❌需要调整）
2. 具体评语（月笙风格：先肯定再建议）
3. 对比展示（原文 vs 修改后的关键差异点）
```

**后端评估返回结构**（`RewriteEvaluation`）：
```typescript
interface RewriteEvaluation {
  /** 评估结果：有效 / 部分有效 / 需要调整 */
  improvement: 'improved' | 'partial' | 'needs_work';
  /** 评语文本 */
  comment: string;
  /** 对比展示：原文和修改后的关键差异 */
  beforeAfter: { before: string; after: string }[];
  /** 下一步建议 */
  nextStep?: string;
}
```

**涉及变更**：
| 文件 | 变更内容 |
|------|---------|
| `src/main/api-proxy.ts` | 新增 `evaluateRewrite()` 方法，调用 AI 评估接口 |
| `src/main/ipc/diagnosis.handler.ts` | submitRewrite handler 已存在，需确保返回 `RewriteEvaluation` |
| `src/renderer/shared/types.ts` | 新增 `RewriteEvaluation` 接口 |
| `src/renderer/components/diagnosis/EvaluationCard.tsx` | 评估结果展示组件 |
| `src/renderer/App.tsx` | 接收评估结果后插入 Chat 流 |

**DoD**：
- [ ] 提交修改后 5 秒内返回评估
- [ ] 评估结果包含总体评价 + 具体评语
- [ ] EvaluationCard 在 Chat 流中作为新消息展示
- [ ] 评估内容可读（非系统语言）

---

#### M-4：一句话成长记录

**设计目标**：对比上次诊断和本次诊断，生成一句话进步总结。

**前端设计**：

```
┌─── 成长记录 ─────────────────────────┐
│  📈 这次你试了"用动作替代设定旁白"      │
│  上次还在直接讲设定，今天已经能通过     │
│  角色的手的动作传达"资源稀缺"了。       │
│  继续——下一步是"环境也在说话"。        │
└────────────────────────────────────────┘
```

**数据来源**：调用 `diagnosis:getComparison` IPC，获取历史诊断对比结果。

**后端已实现**：`diagnosis.handler.ts` 的 `DIAGNOSIS_GET_COMPARISON` handler 已在第 90-143 行实现。返回结构：
```typescript
{
  hasHistory: boolean;  // 是否有历史对比数据
  comparison?: string;  // 对比文本，如 "P001 从 3 次减少到 1 次"
}
```

**展示规则**：
- 有历史数据时显示 GrowthCard
- 首次诊断（`hasHistory === false`）不显示
- GrowthCard 出现在 EvaluationCard 之后，作为聊天的自然收尾

**涉及变更**：
| 文件 | 变更内容 |
|------|---------|
| `src/renderer/components/diagnosis/GrowthCard.tsx` | 重构为一句话摘要风格（去掉复杂图表） |
| `src/renderer/App.tsx` | 在评估完成后自动调用 getComparison 并展示 GrowthCard |

**DoD**：
- [ ] 有历史诊断时展示对比
- [ ] 首次诊断不展示
- [ ] 对比语言自然（非系统语言）

---

#### M-5：诊断面板简化

**设计目标**：取消右面板三标签（诊断/能力画像/成长记录），改为单视图诊断卡片嵌入 Chat 流。

**变更概述**：

| 当前 | 改为 |
|------|------|
| 右面板三标签页切换 | 单视图，诊断卡片直接嵌入 Chat 流 |
| 诊断、画像、成长独立面板 | 全部作为 Chat 流中的嵌入式组件 |
| Evidence、置信度分数等内部概念 | 全部隐藏，改为"为什么这样判断" |
| 数字评分展示 | 文字分级（🟢良好 / 🟡一般 / 🔴薄弱） |

**交互流程**：
```
用户收到月笙回复
    ↓
诊断卡片自动嵌入（默认折叠，显示摘要）
    ↓
用户点击"定位根因"
    ↓
展开显示 rootCause + 技法推荐
    ↓
用户点击"尝试修改"
    ↓
EditPanel 展开
    ↓
提交后 EvaluationCard 出现
    ↓
GrowthCard 自动出现
```

**涉及变更**：
| 文件 | 变更内容 |
|------|---------|
| `src/renderer/App.tsx` | 大幅重构：移除右面板三标签架构 |
| `src/renderer/components/panels/RightPanel.tsx` | 降级或移除 |
| `src/renderer/components/panels/DiagnosisPanel.tsx` | 改为轻量嵌入模式 |
| `src/renderer/components/panels/TeachingProgressPanel.tsx` | 保留但简化 |
| `src/renderer/stores/teaching-state.store.ts` | 清理未使用的状态 |

**DoD**：
- [ ] 诊断面板默认展示单视图
- [ ] 前端找不到"证据"这个词（改为"诊断依据"）
- [ ] 前端找不到"能力评分"数字
- [ ] 三标签页不再出现

---

### 阶段 C：V1.1 扩展（MVP 完成后）

| 任务 | 工时 | 说明 |
|------|------|------|
| V1.1-6 训练任务补充 | 8h | 修改评估后推荐训练任务 |
| V1.1-7 能力画像文字版 | 2h | 数字评分改为文字分级 |
| V1.1-8 聚焦方向后置 | 2h | 先全量诊断，再建议聚焦 |
| V1.1-9 意图-执行一致性集成 | 7h | 新增诊断维度 |

详细规格见 `docs/tasks/TASK-SEQUENCE_V1.0.md` 第四节。

---

## 三、技术约束

### 3.1 IPC 通道验证状态

| 通道 | Preload | Handler | 前端调用 | 状态 |
|------|---------|---------|---------|------|
| `diagnosis:submitRewrite` | ✅ 已注册 | ✅ 已实现 | ⬜ M-2 开发后接入 | 就绪 |
| `diagnosis:getComparison` | ✅ 已注册 | ✅ 已实现 | ⬜ M-4 开发后接入 | 就绪 |
| 其他新增通道 | ✅ 已注册 | ✅ 已实现 | ❌ 未接入 | V1.1+ |

**结论**：MVP 后续开发依赖的 2 个 IPC 通道均已就绪，无需额外后端开发。

### 3.2 API 评估接口

M-3 需要 `api-proxy.ts` 新增 `evaluateRewrite()` 方法。复用现有 `ApiProxy` 类，调用相同 API 端点，仅 messages 不同。

### 3.3 Store 状态管理

现有 7 个 Store 需扩展：
- `diag.store.ts`：新增 `rewriteTarget`（当前修改目标）、`evaluation`（评估结果）、`comparison`（成长对比）
- 其余 Store 不变，复用现有能力

### 3.4 配色系统

前端配色需遵循 `docs/design/FRONTEND_REDESIGN_V1.md` 的 V1.0 规范：
- 主背景：`#FAFAF8`
- 品牌色：`#C0776E`（暖陶土色）
- 语义色：成功 `#7AB87A`、警告 `#D4A84B`、错误 `#C4736B`

---

## 四、风险评估

| 风险 | 可能性 | 影响 | 缓解措施 |
|------|--------|------|---------|
| API 评估返回超时 | 中 | 高 | 设置 10 秒超时，超时显示"评估中，请稍候" |
| EditPanel 展开后输入区被挤出 | 中 | 中 | 使用 `flex-shrink: 0` 固定输入区（已修复过的 bug） |
| 诊断卡片过多导致页面过长 | 低 | 中 | 限制最多展示 3 个，旧的折叠 |
| 成长记录首次无历史 | 高 | 低 | 正常处理，不展示 GrowthCard |

---

## 五、实施顺序建议

```
阶段 A（工程债修复）
  A-1 更新任务文档
  A-2 更新 IPC 文档
  A-3 修正审计报告
    ↓
阶段 B（MVP 后续开发）
  M-2 修改原文入口
  M-3 AI 修改评估
  M-4 一句话成长记录
  M-5 诊断面板简化
    ↓
阶段 C（V1.1 扩展）
  V1.1-6 ~ V1.1-9
```

---

## 变更记录

| 版本 | 日期 | 变更内容 |
|------|------|---------|
| V1.0 | 2026-06-04 | 初始规格，基于审计报告 + TASK-SEQUENCE + 前端设计规格整合 |
