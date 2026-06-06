# MVP 砍掉设计回收方案 V1.0

> **背景**：MVP 阶段使用第一性原理审计砍掉了大量设计。本文档从被砍设计中挖掘"有意思的内容"，评估复活价值，制定分阶段实施路线图。

**来源文档**：
- `docs/reports/FIRST_PRINCIPLES_AUDIT_V1.1.md` — 审计报告（砍掉决策记录）
- `docs/specs/SPEC_Evidence_V1.md` — 四级证据体系
- `docs/specs/SPEC_Novel-Profile_V1.0.md` — 小说画像三层架构
- `docs/specs/SPEC_AuthorProfile_V1.md` — 作者能力画像
- `docs/design/agent-architecture-reuse_V1.0.md` — Agent 架构复用

---

## 一、Evidence 四级体系（来源：SPEC_Evidence_V1.md）

### 原始设计

| 层级 | 内容 | 被砍理由（审计 V1.1） |
|------|------|------------------------|
| **Level 1 文本证据** | 从用户原文抽取具体段落，带 `source.novelId/chapterId/paragraphIndex`，精确回溯原文 | "保留，展示原文引用"——但 MVP 未实现 |
| **Level 2 模式证据** | 跨段落/跨章节的模式聚合（"连续8次出现情绪标签"） | "后台运行，不强制展示" |
| **Level 3 统计证据** | 量化基准线（情绪标签占比18% vs 行业6%） | "默认不展示" |
| **Level 4 对比证据** | "过去自己 vs 现在自己"的对比快照 | "融入成长层，不单独展示" |

### 有意思的点

**Level 1**：审计明确说"保留"，但代码里完全没实现。当前 `SyndromeResult.evidence` 字段注释写的是"用户原文证据片段"，实际填的是 AI 描述（如"情绪标签过多"），**语义不一致，是 bug 不是 feature**。

**Level 4**：这是"成长可视化"的核心素材——用户看到"三个月前：他很愤怒 → 现在：指节收紧"，会 wow。当前完全缺失。

### 复活决策

| 层级 | 决策 | 理由 |
|------|------|------|
| **Level 1** | ✅ **立即复活（MVP 补丁）** | 修复 `evidence` 字段语义 bug；直接解决"诊断无来源"问题；训练入口需要原文引用 |
| **Level 4** | ✅ **V1.5 复活** | 成长可视化的核心；需要先有 Level 1 数据才能做对比；TrainingLayer 的基础 |
| **Level 2** | 🟡 **V2 后台跑，不展示** | 聚合逻辑有价值（让用户理解"这不是偶然，是习惯"），但不需要前端展示 |
| **Level 3** | 🟡 **V2 可选展示** | 统计基准线说服力很强，但优先级低于 Level 1/4 |

### 实施建议

**Step 1（MVP 补丁）**：`DiagnosisEntry` 新增 `sourceSnippets: string[]`，与 `SyndromeResult.evidence` 一一对应。后端诊断时从触发诊断的用户消息中提取对应原文片段填入。

**Step 2（V1.5）**：建立 `EvidenceSnapshot` 机制——每次诊断+训练完成保存一次快照（原文+改写+评估），用于 Level 4 对比。

**Step 3（V2）**：Level 2 模式聚合后台跑，存入 `AuthorProfile.patternHistory`，不展示在前端。

---

## 二、NovelProfile 三层架构（来源：SPEC_Novel-Profile_V1.0.md）

### 原始设计

```
NovelProfile（小说数字孪生）
├── Meta（用户声明）        ← 用户主动填写的小说信息
├── Projection（AI 抽取）  ← 从文本抽取的规范化特征
└── Evolution（演化追踪）   ← 小说随写作进度的变化
```

**被砍理由（审计 V1.1）**：NovelProfile 偏向系统架构完整性，而非教学有效性。V1 用户价值不大。

### 有意思的点

| 概念 | 有意思的点 | 备注 |
|------|-------------|------|
| **Projection 增量更新** | 只分析新章节，不重新分析全书——长篇用户必踩的性能坑 | 当前 DeepSeek 1M 上下文可能不需要，但增量更新是正确架构 |
| **Projection 结构化特征** | 诊断 Agent 只读 Projection 不读全文——减少噪声，提高诊断准确性 | 当前诊断直接读全文，Projection 可以提供结构化索引 |
| **Evolution 追踪** | 记录"第3章人物动机清晰 → 第8章又模糊了"——定位能力回退 | 成长性追踪的高级功能 |

### 复活决策

| 部分 | 决策 | 理由 |
|------|------|------|
| **Projection（极简版）** | 🟡 **V2 实施** | 只存诊断需要的几个数值字段（情绪标签密度、对话占比等），不搞完整数字孪生 |
| **Projection 增量更新** | ✅ **V2 实施（性能优化）** | 长篇用户的真实需求，不属于"架构过度设计" |
| **Meta（用户声明）** | ❌ **暂不复活** | 用户填小说信息对教学帮助有限，属于"锦上添花" |
| **Evolution（演化追踪）** | ❌ **V3 再议** | 需要先有长期用户数据和成熟的成长追踪体系 |

### 实施建议

**V2 极简版 Projection**：

```typescript
// 不建完整 NovelProfile，只在 DiagnosisEntry 里加结构化特征
interface DiagnosisEntry {
  // ...现有字段
  projections?: {
    emotionTagDensity: number;    // 情绪标签密度
    dialogueRatio: number;         // 对话占比
    perspective: 'first' | 'third' | 'mixed';
    avgSentenceLength: number;     // 平均句长
    // 仅诊断需要的特征，不存全文
  };
}
```

---

## 三、AuthorProfile 能力画像（来源：SPEC_AuthorProfile_V1.md）

### 原始设计

```
AuthorProfile（作者能力画像）
├── 能力维度评分（show_dont_tell: 0.7, perspective_control: 0.4, ...）
├── 成长证据链（问题 → 训练 → 改善的完整周期）
├── 能力轨迹（每次诊断/评估打点，连成曲线）
└── 作品对比展示（改前 vs 改后的直观对比）
```

**被砍理由（审计 V1.1）**：前端展示偏重数据可视化而非训练转化。V1 用户价值不大。

### 有意思的点

| 内容 | 有意思的点 | 备注 |
|------|-------------|------|
| **成长证据链** | 记录"问题→训练→改善"完整周期，每个症候一条链 | 当前完全缺失，训练完了没记录，用户不知道自己进步了没有 |
| **能力轨迹** | 每次诊断/评估打一个点，连起来就是成长曲线 | 需要先有数据才能画，当前完全没有数据点 |
| **作品对比展示** | "三个月前：他很愤怒 → 现在：指节收紧" | 最直观的成长证明，用户看到会 wow |

### 复活决策

| 部分 | 决策 | 理由 |
|------|------|------|
| **成长证据链（GrowthChain）** | ✅ **V1.5 实施** | 训练层的基础数据结构；当前训练完了没记录，用户不知道自己进步了没有 |
| **作品对比展示** | ✅ **V1.5 实施** | 复用 Evidence Level 4 的快照机制；最直观的成长证明 |
| **能力轨迹打点** | 🟡 **V2 实施** | 需要先有 GrowthChain 数据才能打点；V2 再做可视化 |
| **能力维度评分算法** | 🟡 **V2 实施** | `AuthorProfile` 更新算法（学习率α=0.3，抗噪声）——当前完全没实现分数更新 |

### 实施建议

**V1.5 GrowthChain 数据模型**：

```typescript
interface GrowthChainEntry {
  syndromeId: string;           // 关联的症候
  detectedAt: number;            // 首次发现时间
  trainingRecords: string[];     // 训练记录 ID 列表
  snapshots: {                  // 对比快照（Evidence Level 4）
    before: string;             // 改前原文
    after: string;              // 改后文本
    evaluatedAt: number;         // 评估时间
  }[];
  status: 'active' | 'resolved' | 'recurring';
}
```

---

## 四、Agent 架构复用（来源：agent-architecture-reuse_V1.0.md）

### 原始设计

| 内容 | 原始设计 | 被砍理由（审计 V1.1） |
|------|---------|------------------------|
| **图结构状态机** | 非线性的教学流程（跳步/回退/卡壳） | "V1 线性推进足够" |
| **断点续传** | 聊到一半离开，回来继续 | "V1 会话通常一次性完成" |
| **RAG 案例库** | 教学不再凭空生成，有历史案例参考 | "V1 不需要案例库" |
| **三层记忆系统** | 短期（本轮对话）+ 长期（用户画像）+ 垂类（方法论库） | "V1 只用对话历史足够" |

### 有意思的点

| 内容 | 有意思的点 | 备注 |
|------|-------------|------|
| **断点续传** | 聊到一半离开，回来继续——当前完全不支撑，是用户体验硬伤 | 不是"架构过度设计"，是基本用户体验 |
| **RAG 案例库** | 教练给的例子不再凭空生成，而是从历史诊断/训练记录里检索相关案例 | 效果提升明显，但工程量较大 |
| **图结构状态机** | 真实创作是跳步/回退/卡壳的，线性推进不够自然 | V2 再考虑，V1 线性可以接受 |

### 复活决策

| 部分 | 决策 | 理由 |
|------|------|------|
| **断点续传** | ✅ **V1.5 实施** | 用户体验硬伤；当前完全不支撑；属于"修 bug"而非"加功能" |
| **RAG 案例库** | 🟡 **V2 实施** | 效果提升明显，但工程量大；需要先有成长证据链数据才能检索 |
| **图结构状态机** | ❌ **V2 再议** | V1 线性推进可以接受；真实创作的跳步/回退需要 V2 的成熟教学状态机 |
| **三层记忆系统** | ❌ **V2 再议** | V1 只用对话历史足够；V2 当用户画像数据丰富后再加 |

### 实施建议

**V1.5 断点续传极简版**：

```typescript
// 不建完整的状态快照机制，只存"最后一个未完成的诊断/训练"
interface SessionResumeState {
  lastDiagnosisEntryId: string | null;   // 最后一个未完成的诊断
  lastTrainingSessionId: string | null;   // 最后一个未完成的训练
  lastMessageAt: number;                  // 最后一条消息时间
}
// 用户重新打开应用时，检查 lastMessageAt < 24h → 提示"上次聊到一半，继续吗？"
```

---

## 五、优先级总览

### ✅ 高优先级（V1.5 实施）

| 编号 | 内容 | 来源 | 实施难度 | 用户价值 |
|------|------|------|---------|---------|
| 1 | Evidence Level 1（文本证据） | SPEC_Evidence_V1.md | 低（MVP 补丁） | 🔴 高——修复 bug |
| 2 | 成长证据链（GrowthChain） | SPEC_AuthorProfile_V1.md | 中 | 🔴 高——训练层基础 |
| 3 | 作品对比展示（Level 4 Evidence） | SPEC_Evidence_V1.md | 中 | 🔴 高——wow 效果 |
| 4 | 断点续传（极简版） | agent-architecture-reuse_V1.0.md | 低 | 🔴 高——修复体验硬伤 |

### 🟡 中优先级（V2 实施）

| 编号 | 内容 | 来源 | 实施难度 | 用户价值 |
|------|------|------|---------|---------|
| 5 | Evidence Level 2/3（模式+统计） | SPEC_Evidence_V1.md | 中 | 🟡 中——后台跑不展示 |
| 6 | Projection 极简版 | SPEC_Novel-Profile_V1.0.md | 中 | 🟡 中——提高诊断准确性 |
| 7 | Projection 增量更新 | SPEC_Novel-Profile_V1.0.md | 高 | 🟡 中——性能优化 |
| 8 | AuthorProfile 更新算法 | SPEC_AuthorProfile_V1.md | 中 | 🟡 中——需要先有数据 |
| 9 | 能力轨迹可视化 | SPEC_AuthorProfile_V1.md | 中 | 🟡 中——需要先有数据 |
| 10 | RAG 案例库 | agent-architecture-reuse_V1.0.md | 高 | 🟡 中——效果提升但工程量大 |

### ❌ 低优先级（V3 或暂不实施）

| 编号 | 内容 | 来源 | 理由 |
|------|------|------|------|
| 11 | NovelProfile 完整架构 | SPEC_Novel-Profile_V1.0.md | 过度工程化，V1/V2 不需要完整数字孪生 |
| 12 | Agent 架构正式化 | agent-architecture-reuse_V1.0.md | "为了 Agent 而 Agent"，V1/V2 不需要 |
| 13 | Evolution 演化追踪 | SPEC_Novel-Profile_V1.0.md | 需要先有长期用户数据和成熟的成长追踪体系 |

---

## 六、与现有任务链的关联

| 复活内容 | 关联任务 | 关联性 |
|---------|---------|-------|
| Evidence Level 1 | T-021（训练入口与工坊） | Level 1 是"错误卡片最近引用"的数据基础 |
| 成长证据链 | T-013（能力成长可视化） | GrowthChain 是能力成长可视化的数据结构基础 |
| 作品对比展示 | T-013（能力成长可视化） | Level 4 Evidence 直接服务于成长展示 |
| 断点续传 | T-XXX（待创建） | 独立任务，不阻塞其他任务 |
| Projection 极简版 | T-014（动态上下文装载） | Projection 可以提供结构化特征，减少上下文长度 |

---

## 七、下一步行动

### 立即行动（本次会话）

- [x] 创建本文档（MVP 砍掉设计回收方案 V1.0）
- [ ] 更新 `T-021-training-entry.md`——Evidence Level 1 纳入 DoD
- [ ] 创建 `T-023-onboarding-flow-design.md`——新用户引导流程（开放问题 #6 拆出）

### V1.5 实施计划（下次会话）

1. **Evidence Level 1 实施**（1d）
   - `DiagnosisEntry` 新增 `sourceSnippets: string[]`
   - 后端诊断时填入原文片段
   - 修复 `evidence` 字段语义不一致

2. **成长证据链数据模型**（1d）
   - 创建 `GrowthChainEntry` 接口
   - 接入训练完成流程（TrainingLayer）
   - 存储到 SQLite

3. **作品对比展示**（1d）
   - 复用 Evidence Level 4 快照机制
   - GrowthCard 展示改前 vs 改后对比
   - 前端组件：`ComparisonViewer.tsx`

4. **断点续传极简版**（0.5d）
   - `SessionResumeState` 接口
   - 应用启动时检查未完成任务
   - 提示用户继续

---

**文档版本**：V1.0（2026-06-05）  
**作者**：月笙如歌 + AI 协作  
**状态**：待评审
