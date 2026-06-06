# 月笙写作教练 — 整合任务序列 V2.0

> **编制日期**：2026-06-04  
> **依据文档**：TASK-SEQUENCE_V1.0.md / teaching-knowledge-bridge_V1.0.md / student-model-redesign_V1.0.md / integrated-resource-report_V1.0.md / resource-detail-report_V1.0_part1+2.md  
> **核心原则**：治疗优先，不建不需要的 Service，增量对齐而非重写

---

## 一、现状快照（源码审查结论）

### 已存在且正常工作的组件

| 组件 | 位置 | 状态 | 来源 |
|------|------|------|------|
| 聊天链路 | `chat.handler.ts` | ✅ 正常工作 | — |
| 诊断解析 | `diagnosis-parser.ts` | ✅ 正常工作 | — |
| 教学状态机 | `teaching-state-machine.ts` | ✅ 4 阶段 + 10 子阶段 + 聚焦方向 | — |
| Prompt 构建 | `prompt-builder.ts` | ✅ 消费教学状态，生成注入文本 | — |
| 能力画像 | `ability-profile.service.ts` (主进程) | ✅ 实时聚合，趋势计算 | — |
| 学生上下文 | `student-context.store.ts` (渲染进程) | ✅ Zustand + localStorage，维护用户类型/信心/错误 | — |
| 聚焦方向 | 状态机 + DB migration 006 | ✅ 已集成 | — |
| 症候体系 | P001-P010（P008 已合并到 P004）| ✅ M-1 已完成 | — |
| 推荐引擎骨架 | `recommendation-engine.ts` | 🟡 Phase 2 骨架，类型已定义 | — |

### 源码审查发现的 5 个关键问题

来源：[student-model-redesign_V1.0.md](file:///d:/ai-teacher/yuesheng-writing-coach/docs/design/student-model-redesign_V1.0.md) §一

| # | 问题 | 严重度 | 来源文档 |
|---|------|--------|---------|
| 1 | `{student_context}` 永远为空 — `chat.handler.ts` 的 `studentContext` 参数从渲染进程传入，但从未有效填充 | 🔴 P0 | student-model-redesign §1.1 |
| 2 | `student-context.store.ts` 的 `updateFromDiagnosis()` / `updateFromInteraction()` 从未被调用 — 代码存在，但无调用者 | 🔴 P0 | student-model-redesign §1.1 |
| 3 | `ability-profile.service.ts` 只查单会话 — `computeProfile(sessionId)` 用 `getBySession(sessionId)`，跨会话的反复问题无法识别 | 🟡 P1 | student-model-redesign §1.2 |
| 4 | 三套用户类型互相冲突 — store 用 beginner/intermediate/advanced，classifier 用 thinking/technical/mixed，方案文档用 newbie/experienced/analytical/emotional | 🟡 P1 | student-model-redesign §1.2 |
| 5 | 诊断数据在 SQLite 但无人做跨会话聚合 — `diagnosis_results` 表有数据，但没有 Service 跨会话读取 | 🟡 P1 | student-model-redesign §1.2 |

**注意**：这些问题与外部资源研究报告的断言一致。但解决方案选择 **增量对齐** 而非新建 Service（详见 T-1.2）。

---

## 二、任务切割原则

```
治疗优先                  基础设施                 自适应                 数据驱动
（用户痛点）              （教学知识结构化）        （个性化体验）          （有条件实施）
────────                  ─────────               ─────────               ─────────
诊断→改原文→评估          Config 外置              Challenge-Unlock        BKT（50+会话后）
一句话成长记录             Service 对齐             训练推荐                子维度诊断
面板简化                  Strategy 决策             ZPD 校准                能力图表

每个任务标注了来源文档引用，方便追溯依据链。
```

---

## 三、执行计划总览

```
Phase 0: 治疗闭环 (1周)            Phase 1: 教学知识结构化 (2周)          Phase 2: 自适应 (2-3周)
────────────────────              ──────────────────────                  ──────────────────────
M-2 修改原文入口 ██████           T-1.1 Config 提取 ████                  T-2.1 Challenge-Unlock ██████
M-3 AI 评估 ████                  T-1.2 学生模型对齐 ████                 T-2.2 训练推荐 ██████
M-4 一句话记录 ██                  T-1.3 Strategy Service ██████          T-2.3 ZPD 校准 ████
M-5 面板简化 ████                 T-1.4 PromptBuilder 改造 ████          T-2.4 内容创作 ████████
                                  └── teaching-knowledge-bridge 落地       └── 参考 OATutor + Prober.ai
```

---

## Phase 0：治疗闭环（保留现有 MVP，约 15.5h）

**依据**：[TASK-SEQUENCE_V1.0.md](file:///d:/ai-teacher/yuesheng-writing-coach/docs/tasks/TASK-SEQUENCE_V1.0.md) §三 MVP 任务  
**来源**：V2 审计 + Kimi 审计，确认"修改原文路径缺失"是 P0 问题

| ID | 任务 | 工时 | 依赖 | 来源 | 说明 |
|----|------|------|------|------|------|
| **M-2** | 修改原文入口 | 6h | 无 | TASK-SEQUENCE_V1.0 §三 M-2 | 诊断结果下方"尝试修改"→ 内联编辑 |
| **M-3** | AI 修改评估 | 3.5h | M-2 | TASK-SEQUENCE_V1.0 §三 M-3 | 用户提交修改后 AI 评估反馈 |
| **M-4** | 一句话成长记录 | 2h | 无 | TASK-SEQUENCE_V1.0 §三 M-4 | 对比上次诊断，一句话展示进步 |
| **M-5** | 诊断面板简化 | 4h | M-2, M-3, M-4 | TASK-SEQUENCE_V1.0 §三 M-5 | 取消三标签，改为单视图 |

**里程碑 W1**：用户能走通"诊断 → 修改原文 → AI 评估 → 看到进步"的完整闭环。

---

## Phase 1：教学知识结构化（2 周，新增）

### T-1.1：Config 配置层提取（1-2 天）

**依据**：[teaching-knowledge-bridge_V1.0.md](file:///d:/ai-teacher/yuesheng-writing-coach/docs/design/teaching-knowledge-bridge_V1.0.md) §三（数据配置层）、§七 Phase A  
**来源**：SPEC_adaptive-teaching_V1.0.md / teaching-strategy-notes.md / syndrome-manual.md / action-library.md

**做什么**：从现有 md 文档提取结构化 JSON，不改代码。

| 配置 | 来源文档 | 对应 teaching-knowledge-bridge 章节 |
|------|---------|-----------------------------------|
| `teaching-strategies.json` | SPEC_adaptive-teaching_V1.0.md | §3.1 三模式触发条件 |
| `user-type-matrix.json` | teaching-strategy-notes.md | §3.2 用户类型→教学方式映射 |
| `problem-tiering.json` | syndrome-manual.md | §3.3 问题分级（致命/结构/皮肤） |
| `challenge-templates.json` | action-library.md | §3.4 Challenge-Unlock 模板 |

```json
// resources/config/problem-tiering.json（示例）
{
  "tiers": [
    { "level": "fatal", "syndromes": ["P002", "P009"], "action": "must_fix" },
    { "level": "structural", "syndromes": ["P001", "P004", "P005", "P006"], "action": "priority" },
    { "level": "surface", "syndromes": ["P003", "P007", "P010"], "action": "deferrable" }
  ],
  "maxPerTurn": 1
}
```

**DoD**：
- [ ] 4 个 JSON 文件创建完成
- [ ] 每个字段标注了来源文档引用
- [ ] JSON Schema 验证通过

**为什么先做这个**：零代码风险，但为后续所有 Service 提供数据基础。

---

### T-1.2：学生模型对齐（2 天）

**依据**：
- [student-model-redesign_V1.0.md](file:///d:/ai-teacher/yuesheng-writing-coach/docs/design/student-model-redesign_V1.0.md) §一（问题 1-5 确认）
- [integrated-resource-report_V1.0.md](file:///d:/ai-teacher/yuesheng-writing-coach/docs/research/integrated-resource-report_V1.0.md) §二（IntelliCode 中心化学者状态）
- [resource-detail-report_part1.md](file:///d:/ai-teacher/yuesheng-writing-coach/docs/research/resource-detail-report_V1.0_part1.md) §2（IntelliCode LearnerState Schema）

**做什么**：对齐现有 `ability-profile.service.ts`（主进程）和 `student-context.store.ts`（渲染进程），不新建 Service。

**当前断裂（来源：student-model-redesign §1.1）**：

```
ability-profile.service.ts (主进程)          student-context.store.ts (渲染进程)
  ┌─────────────────────┐                     ┌─────────────────────────┐
  │ 能力评分 (L1=85...) │                     │ userType (beginner...)  │
  │ 弱点标签            │                     │ confidenceLevel         │
  │ 训练统计            │                     │ lastErrors              │
  │ 诊断趋势            │ ← 无 IPC 桥接 →    │ thinkingStyle           │
  │                     │                     │ frustrationCount        │
  │ SQLite 持久化       │                     │ localStorage 持久化     │
  └─────────────────────┘                     └─────────────────────────┘
```

**改造方案**：

```
Step 1: ability-profile.service.ts 新增跨会话聚合方法
  - computeCrossSessionProfile() — SQL 查询去掉 WHERE session_id = ?
  - 同时聚合 userType + confidenceLevel（从诊断历史推断）
  - 来源：student-model-redesign §三 核心算法

Step 2: 在 ability-profile.handler.ts 中新增能力画像注入
  - 新增 toPromptText() 方法，输出 200-300 字的 Prompt 注入文本
  - 来源：student-model-redesign §3.3.4

Step 3: 修复 chat.handler.ts 的 {student_context} 生成
  - 由主进程调用 abilityProfileService.computeCrossSessionProfile() 生成
  - 替代从渲染进程传入的 studentContext 参数
  - 来源：student-model-redesign §4.3
```

**涉及文件**：

| 文件 | 改动 | 依据文档 |
|------|------|---------|
| `src/main/services/ability-profile.service.ts` | 新增 `computeCrossSessionProfile()` | student-model-redesign §3.3 |
| 同上 | 新增 `toPromptText()` | student-model-redesign §3.3.4 |
| `src/main/ipc/chat.handler.ts` | 修 `{student_context}` 生成方式 | student-model-redesign §4.3 |
| `src/main/services/prompt-builder.ts` | 新增学生模型输入参数 | — |

**不做的**（和 student-model-redesign 方案的区别）：

| student-model-redesign 提议 | 本方案选择 | 理由 |
|---------------------------|-----------|------|
| 新建 `StudentModelService` 类 | 在 ability-profile.service.ts 加方法 | 功能重叠，不增加新类 |
| 新增 `student-model.types.ts` | 复用 `renderer/shared/types.ts` | 不增加类型文件 |
| 新增 IPC 通道 + hooks | 主进程内部调用 | 当前无前端 UI 展示需求 |
| `cognitiveStyle` 关键词推断 | 不做 | 写作场景用户提问少，keyword match 不可靠 |
| 标记废弃 `student-context.store.ts` | 保留不动 | 兼容已有逻辑，V2 再清理 |

**DoD**：
- [ ] `computeCrossSessionProfile()` 跨会话聚合诊断数据
- [ ] `toPromptText()` 输出格式符合 Prompt 注入要求（≤300 字）
- [ ] `{student_context}` 在 V3 Prompt 中被正确替换（不再显示"暂无学生状态数据"）
- [ ] 类型检查通过

---

### T-1.3：Strategy Service（3 天）

**依据**：[teaching-knowledge-bridge_V1.0.md](file:///d:/ai-teacher/yuesheng-writing-coach/docs/design/teaching-knowledge-bridge_V1.0.md) §四（策略服务层）、§七 Phase C  
**来源**：SPEC_adaptive-teaching_V1.0.md（三模式切换条件）、syndrome-manual.md（问题分级）

**做什么**：实现 teaching-knowledge-bridge 的核心策略服务层。

#### 1.3.1 TeachingStrategyService

```typescript
// 读取 Config + 学生模型 → 输出教学策略
class TeachingStrategyService {
  decide(config: StrategyConfig, student: StudentContext): StrategyDecision {
    // 规则 1：连续失败 ≥ 2 → 支架模式（高支持度）
    // 规则 2：掌握度 > 0.7 → 挑战模式（低支持度）
    // 规则 3：confidence low → 鼓励语气
    // 规则从 JSON 加载，不在代码里硬编码
  }
}
```

#### 1.3.2 ProblemPrioritizer

```typescript
// 读取 problem-tiering.json → 排序症候
class ProblemPrioritizer {
  prioritize(syndromes: SyndromeResult[]): PrioritizedProblem[] {
    // 致命伤 > 结构病 > 皮肤症
    // 每次只说一个最高优先级的问题
    // 依据："一次只说一个问题" — design-philosophy_V1.0.md
  }
}
```

**涉及文件**：

| 文件 | 操作 | 依据 |
|------|------|------|
| `src/main/services/teaching-strategy.service.ts` | 新增 | teaching-knowledge-bridge §4.2 |
| `src/main/services/problem-prioritizer.service.ts` | 新增 | teaching-knowledge-bridge §4.3 |
| `src/main/index.ts` | 注册服务 | — |
| `src/main/ipc/chat.handler.ts` | 在 `sendMessage` 中调用策略服务 | teaching-knowledge-bridge §六 |

**DoD**：
- [ ] `TeachingStrategyService.decide()` 输入学生模型 → 输出教学模式/语气
- [ ] `ProblemPrioritizer.prioritize()` 输入症候列表 → 输出排序后的列表
- [ ] 决策规则从 JSON 加载，不硬编码
- [ ] 单元测试覆盖（mock 学生模型）

---

### T-1.4：PromptBuilder 改造（2 天）

**依据**：[teaching-knowledge-bridge_V1.0.md](file:///d:/ai-teacher/yuesheng-writing-coach/docs/design/teaching-knowledge-bridge_V1.0.md) §五（PromptBuilder 改造）、§七 Phase D  
**来源**：Phase D "集成到现有流程"

**做什么**：PromptBuilder 消费 Service 输出，不再只读原始教学状态。

```typescript
// 改造前
buildSystemPrompt(state: TeachingState, ...): string;

// 改造后
buildSystemPrompt(
  strategy: StrategyDecision,          // 策略服务输出
  prioritized: PrioritizedProblem[],   // 排序后的问题
  studentContext: string,              // 学生模型文本（来自 toPromptText()）
  state: TeachingState,                // 原有（仅用于阶段信息）
): string;
```

**涉及文件**：

| 文件 | 改动 | 依据 |
|------|------|------|
| `src/main/services/prompt-builder.ts` | 新增策略决策参数 | teaching-knowledge-bridge §五 |
| `src/main/ipc/chat.handler.ts` | 调用策略服务后传给 PromptBuilder | teaching-knowledge-bridge §六 |

**DoD**：
- [ ] Prompt 注入内容反映策略决策（语气、模式）
- [ ] 只展示最高优先级问题（其余折叠）
- [ ] 现有测试不破坏

---

### Phase 1 依赖图

```
T-1.1 Config 提取 ────────── T-1.3 Strategy Service
    │                          （依赖 Config）
    │
    └── T-1.2 学生模型对齐 ── T-1.4 PromptBuilder 改造
         （独立）                （依赖 T-1.2 + T-1.3）
```

---

## Phase 2：自适应体验（2-3 周）

### T-2.1：Challenge-Unlock（Prober.ai，3 天）

**依据**：
- [resource-detail-report_part1.md](file:///d:/ai-teacher/yuesheng-writing-coach/docs/research/resource-detail-report_V1.0_part1.md) §1（Prober.ai Challenge-Unlock 机制）
- [integrated-resource-report_V1.0.md](file:///d:/ai-teacher/yuesheng-writing-coach/docs/research/integrated-resource-report_V1.0.md) §4.1（"立即可用，0 改造成本"）

**做什么**：诊断完成后不直接给建议，先生成反思问题让学生先思考。

```
当前流程：
  诊断完成 → 直接给教学建议

加入 Challenge-Unlock 后：
  诊断完成 → 生成 1-2 个反思问题 → 学生回答 → 评估质量
                                                    ↓
                                              [不够好] → 追问
                                              [够好] → 解锁建议
```

**代码改动**：

```typescript
// teaching-state-machine.ts 新增子阶段
const PHASE_SUBPHASES = {
  [TeachingPhase.PRACTICE_LOOP]: [
    TeachingSubphase.PRACTICE_IDENTIFY,
    // 新增 ↓（来源：resource-detail-report_part1 §1.4）
    'S2_REFLECTION',        // 挑战-反思
    'S2_REFLECTION_ASSESS', // 反思评估
    // 原有 ↓
    TeachingSubphase.PRACTICE_TEACHING,
    TeachingSubphase.PRACTICE_ASSIGN,
    TeachingSubphase.PRACTICE_REVIEW,
  ],
};
```

**涉及文件**：

| 文件 | 改动 | 依据 |
|------|------|------|
| `src/shared/constants.ts` | 新增 `S2_REFLECTION` / `S2_REFLECTION_ASSESS` | resource-detail-report_part1 §1.4 |
| `src/main/services/teaching-state-machine.ts` | 新增子阶段 + 流转逻辑 | 同上 |
| `src/main/services/teaching-state.types.ts` | 更新类型 | 同上 |
| `src/main/ipc/chat.handler.ts` | 诊断完成后→发反思→等待→评估→解锁 | 同上 |
| `src/renderer/components/chat/MessageBubble.tsx` | 新增"请先思考"UI 提示 | — |
| `resources/config/challenge-templates.json` | 使用 T-1.1 产出的模板 | — |

**DoD**：
- [ ] 诊断完成后不直接给建议，先发 1-2 个反思问题
- [ ] 学生回答后评估通过才解锁教学建议
- [ ] 前端能看到"请先思考再查看建议"的提示
- [ ] 可使用 challenge-templates.json 中的模板

**为什么放在 Phase 2 而不是 Phase 0**：
- 需要 T-1.1 的 `challenge-templates.json` 作为问题模板
- MVP（Phase 0）优先保证"诊断→修改→评估"闭环可用
- Challenge-Unlock 是体验增强，不是核心闭环

---

### T-2.2：训练推荐引擎（3 天）

**依据**：
- [resource-detail-report_part1.md](file:///d:/ai-teacher/yuesheng-writing-coach/docs/research/resource-detail-report_V1.0_part1.md) §4（OATutor 自适应推荐）
- [integrated-resource-report_V1.0.md](file:///d:/ai-teacher/yuesheng-writing-coach/docs/research/integrated-resource-report_V1.0.md) §4.2（"需适配后可用"）

**做什么**：完善 `recommendation-engine.ts` 骨架，实现"选最弱技能"推荐。

```typescript
class TrainingRecommender {
  recommend(studentModel: StudentContext): TaskRecommendation[] {
    // 策略 1：选掌握度最低的症候（来源：OATutor ProblemSelector）
    // 策略 2：如果最弱症候 < 0.3，先练它
    // 策略 3：如果 0.3-0.7，混合练习
    // 从 training-tasks.json 读取任务
  }
}
```

**涉及文件**：

| 文件 | 改动 | 依据 |
|------|------|------|
| `src/main/services/recommendation-engine.ts` | 实现推荐算法 | resource-detail-report_part1 §4.4 |
| `resources/config/training-tasks.json` | 新增（训练题目配置） | — |
| `src/main/ipc/chat.handler.ts` | 诊断完成后触发推荐 | — |
| `src/renderer/components/diagnosis/DiagnosisCard.tsx` | 展示推荐训练入口 | — |

**DoD**：
- [ ] 推荐算法基于学生模型（掌握度最低优先）
- [ ] 推荐结果可展示在前端
- [ ] 训练任务配置外置

---

### T-2.3：ZPD 校准（2 天，Claw-STU 理念）

**依据**：
- [resource-detail-report_part1.md](file:///d:/ai-teacher/yuesheng-writing-coach/docs/research/resource-detail-report_V1.0_part1.md) §5（Claw-STU ZPD 校准流程）
- [integrated-resource-report_V1.0.md](file:///d:/ai-teacher/yuesheng-writing-coach/docs/research/integrated-resource-report_V1.0.md) §4.1（"立即可用，0 改造成本"）

**做什么**：新用户首次使用时，通过 2-3 个快速问题建立能力基线。

**不是独立向导**，而是增强 `P0_INIT` 阶段的对话流程。

```
当前 P0_INIT：
  「你好，请粘贴你的文字」

增强后 P0_INIT：
  「你好！在开始前，我想了解一下你的写作经验」
  → 问题 1：「你写网文多久了？」（新手/几个月/一年以上）
  → 问题 2：「下面这段文本有什么问题？」（简单诊断题）
  → 根据回答初始化 userType + confidence
```

**涉及文件**：

| 文件 | 改动 | 依据 |
|------|------|------|
| `src/main/services/teaching-state-machine.ts` | 增强 `P0_INIT` 阶段处理 | resource-detail-report_part1 §5.4 |
| `src/main/ipc/chat.handler.ts` | 检测新用户，触发校准问题 | 同上 |
| `src/renderer/stores/student-context.store.ts` | 校准结果写入 | — |
| `resources/config/calibration-questions.json` | 新增（校准题配置） | — |

**DoD**：
- [ ] 新用户首次对话触发校准
- [ ] 校准结果正确初始化学生模型
- [ ] 老用户跳过校准

---

### T-2.4：训练内容创作（持续，4-8h/批）

**依据**：
- [TASK-SEQUENCE_V1.0.md](file:///d:/ai-teacher/yuesheng-writing-coach/docs/tasks/TASK-SEQUENCE_V1.0.md) §四 V1.1-6 训练任务补充
- [resource-detail-report_part2.md](file:///d:/ai-teacher/yuesheng-writing-coach/docs/research/resource-detail-report_V1.0_part2.md) §10.2 Phase 3 路线图

**做什么**：为每个症候创作微型练习题目。

| 症候 | 题目类型 | 示例 |
|------|---------|------|
| P001 视角混乱 | 识别问题 | "这段文本的视角哪里有问题？" |
| P004 信息堆积 | 改写约束 | "删掉这段话中的说明性文字，用角色的动作暗示" |
| P009 动机缺失 | 填空 | "写一句角色内心真正的恐惧——不是剧情需要他做什么，而是他害怕什么" |

**不需要一次性完成**，可以在 Phase 2 持续迭代。

---

## Phase 3：数据驱动（条件触发，不设固定时间）

| 任务 | 触发条件 | 来源 | 说明 |
|------|---------|------|------|
| **BKT 知识追踪** | 积累 > 50 次诊断记录 | resource-detail-report_part1 §3（pyBKT）| 用真实数据验证 BKT 是否优于现有规则系统 |
| **子维度诊断** | 基础症候诊断准确率 > 80% | resource-detail-report_part2 §8（Stylus）| 参照 Stylus 细粒度设计 |
| **能力雷达图** | 至少 3 轮诊断数据 | TASK-SEQUENCE_V1.0 §五 | 已有组件，仅需数据触发 |
| **成长时间线** | 至少 5 轮诊断数据 | TASK-SEQUENCE_V1.0 §五 | 已有组件，仅需数据触发 |

**BKT 实施前提验证**（接入前必须先验证）：

```
1. 收集 50+ 次诊断记录（现有数据）
2. 用历史数据训练 BKT 模型
3. 对比 BKT 预测 vs 现有规则（L1=85/L2=55/L3=20）的准确率
4. 仅当 BKT 准确率 > 规则系统 10% 时才实施
   来源：resource-detail-report_part2 §10.3 风险控制
```

---

## 四、完整依赖图

```
Phase 0（治疗闭环）
  M-2 修改原文入口 ─→ M-3 AI 评估 ─→ M-5 面板简化
  M-4 一句话记录 ───────────────────→ ↑

Phase 1（教学结构化）
  T-1.1 Config 提取 ──────→ T-1.3 Strategy Service
                                 │
  T-1.2 学生模型对齐 ──────→ T-1.4 PromptBuilder 改造
                                 │
Phase 2（自适应）                │
  T-1.1 → T-2.1 Challenge-Unlock (需 challenge-templates.json)
                                 │
  T-1.2 → T-2.2 训练推荐 (需学生模型)
                                 │
  T-2.3 ZPD 校准（独立，不阻塞）
                                 │
  T-2.4 内容创作（持续，不阻塞）
                                 ↓
                          V1.0 Release
```

---

## 五、三阶段路线图

```
Week 1（治疗闭环）              Week 2-3（教学结构）              Week 4-6（自适应）
────────────────              ──────────────────                ──────────────────
M-2 修改原文 ██████████        T-1.1 Config ████████            T-2.1 Challenge-Unlock ██████████
M-3 AI 评估 ██████████         T-1.2 学生模型 ████████          T-2.2 训练推荐 ██████████
M-4 一句话记录 ██████████      T-1.3 Strategy ██████████████    T-2.3 ZPD 校准 ████████
M-5 面板简化 ██████████        T-1.4 PromptBuilder ████████     T-2.4 内容创作 ████████████████
```

---

## 六、与外部资源研究报告的对应关系

| 外部资源 | 落地任务 | 实施方式 | 来源文档 |
|---------|---------|---------|---------|
| **Prober.ai** | T-2.1 Challenge-Unlock | 新增反思子阶段 + 模板驱动 | resource-detail-report_part1 §1 |
| **IntelliCode** | T-1.2 学生模型对齐 | IPC 桥接现有服务，不新建 | resource-detail-report_part1 §2 |
| **teaching-knowledge-bridge** | T-1.1 + T-1.3 + T-1.4 | Config 提取 → Service → PromptBuilder | teaching-knowledge-bridge_V1.0 |
| **student-model-redesign** | T-1.2（问题依据） | 跨会话聚合 + Prompt 注入 | student-model-redesign_V1.0 |
| **Claw-STU** | T-2.3 ZPD 校准 | 增强 P0_INIT 阶段 | resource-detail-report_part1 §5 |
| **OATutor** | T-2.2 训练推荐 | 参考"选最弱技能"启发式 | resource-detail-report_part1 §4 |
| **pyBKT** | ⏸️ 暂缓 | Phase 3 条件触发 | resource-detail-report_part1 §3 |
| **Stylus / OpenMAIC / GenMentor** | ⏸️ 仅概念参考 | 不纳入当前计划 | resource-detail-report_part2 |

---

## 七、风险与缓解

| 风险 | 概率 | 缓解 |
|------|------|------|
| Phase 0 改动影响现有诊断准确率 | 中 | 每次改动独立分支，充分测试 |
| T-1.3 Strategy 决策规则过于简单 | 中 | V1 用确定性规则，不追求 ML 决策 |
| Challenge-Unlock 增加用户操作成本 | 低 | A/B 测试：允许用户跳过反思 |
| ZPD 校准问题质量不够 | 中 | 先出 2 题 MVP，后续迭代补充 |
| BKT 数据不足 | 高 | Phase 3 条件触发，不强上 |
| 跨会话聚合查询性能 | 低 | 单用户几百条记录，毫秒级 |

---

## 八、文档引用索引

每个任务对应的来源文档，方便追溯依据链：

| 文档 | 位置 | 被引用的任务 |
|------|------|-------------|
| [TASK-SEQUENCE_V1.0.md](file:///d:/ai-teacher/yuesheng-writing-coach/docs/tasks/TASK-SEQUENCE_V1.0.md) | §三 MVP | M-2, M-3, M-4, M-5 |
| [TASK-SEQUENCE_V1.0.md](file:///d:/ai-teacher/yuesheng-writing-coach/docs/tasks/TASK-SEQUENCE_V1.0.md) | §四 V1.1-6 | T-2.4 |
| [TASK-SEQUENCE_V1.0.md](file:///d:/ai-teacher/yuesheng-writing-coach/docs/tasks/TASK-SEQUENCE_V1.0.md) | §五 V2 | Phase 3 雷达图/时间线 |
| [teaching-knowledge-bridge_V1.0.md](file:///d:/ai-teacher/yuesheng-writing-coach/docs/design/teaching-knowledge-bridge_V1.0.md) | §三 数据配置层 | T-1.1 |
| [teaching-knowledge-bridge_V1.0.md](file:///d:/ai-teacher/yuesheng-writing-coach/docs/design/teaching-knowledge-bridge_V1.0.md) | §四 策略服务层 | T-1.3 |
| [teaching-knowledge-bridge_V1.0.md](file:///d:/ai-teacher/yuesheng-writing-coach/docs/design/teaching-knowledge-bridge_V1.0.md) | §五 PromptBuilder | T-1.4 |
| [teaching-knowledge-bridge_V1.0.md](file:///d:/ai-teacher/yuesheng-writing-coach/docs/design/teaching-knowledge-bridge_V1.0.md) | §七 执行顺序 | T-1.1 ~ T-1.4 |
| [student-model-redesign_V1.0.md](file:///d:/ai-teacher/yuesheng-writing-coach/docs/design/student-model-redesign_V1.0.md) | §一 问题分析 | T-1.2（问题依据） |
| [student-model-redesign_V1.0.md](file:///d:/ai-teacher/yuesheng-writing-coach/docs/design/student-model-redesign_V1.0.md) | §3.3 核心算法 | T-1.2（方案参考）|
| [student-model-redesign_V1.0.md](file:///d:/ai-teacher/yuesheng-writing-coach/docs/design/student-model-redesign_V1.0.md) | §3.3.4 Prompt 注入 | T-1.2（toPromptText）|
| [integrated-resource-report_V1.0.md](file:///d:/ai-teacher/yuesheng-writing-coach/docs/research/integrated-resource-report_V1.0.md) | §二 问题↔资源 | T-1.2（IntelliCode）|
| [integrated-resource-report_V1.0.md](file:///d:/ai-teacher/yuesheng-writing-coach/docs/research/integrated-resource-report_V1.0.md) | §4.1 立即可用 | T-2.1, T-2.3 |
| [resource-detail-report_part1.md](file:///d:/ai-teacher/yuesheng-writing-coach/docs/research/resource-detail-report_V1.0_part1.md) | §1 Prober.ai | T-2.1 |
| [resource-detail-report_part1.md](file:///d:/ai-teacher/yuesheng-writing-coach/docs/research/resource-detail-report_V1.0_part1.md) | §2 IntelliCode | T-1.2 |
| [resource-detail-report_part1.md](file:///d:/ai-teacher/yuesheng-writing-coach/docs/research/resource-detail-report_V1.0_part1.md) | §3 pyBKT | Phase 3 |
| [resource-detail-report_part1.md](file:///d:/ai-teacher/yuesheng-writing-coach/docs/research/resource-detail-report_V1.0_part1.md) | §4 OATutor | T-2.2 |
| [resource-detail-report_part1.md](file:///d:/ai-teacher/yuesheng-writing-coach/docs/research/resource-detail-report_V1.0_part1.md) | §5 Claw-STU | T-2.3 |
| [resource-detail-report_part2.md](file:///d:/ai-teacher/yuesheng-writing-coach/docs/research/resource-detail-report_V1.0_part2.md) | §8 Stylus | Phase 3 子维度 |
| [resource-detail-report_part2.md](file:///d:/ai-teacher/yuesheng-writing-coach/docs/research/resource-detail-report_V1.0_part2.md) | §10.3 风险控制 | Phase 3 BKT 验证 |

---

## 九、变更记录

| 版本 | 日期 | 变更内容 | 变更人 |
|------|------|---------|--------|
| V2.0 | 2026-06-04 | 基于 TASK-SEQUENCE_V1.0 + 外部资源研究 + teaching-knowledge-bridge + student-model-redesign 的重新设计 | AI |
| V2.1 | 2026-06-04 | 补充各任务来源文档引用 + 文档引用索引 | AI |
