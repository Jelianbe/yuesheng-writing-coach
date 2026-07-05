# 月笙写作教练 v5.0.0(草案) — 会话阶段化重构

> **版本**: v5.0.0-draft
> **创建**: 2026-07-03
> **作者**: Sprint 20 C-1 + 增量 3
> **状态**: DRAFT(架构草案,内容待产品迭代)
> **回退**: `git checkout v5 -- resources/prompts/yuesheng-prompt-v5.md`(回退到 v5 合并版)
> **依据**: dev-docs/tasks/sprint-20-plan.md §C-1 / R-025 Prompt 治理 / D-053 契约断链教训

---

## Contract(契约声明 — 启动时硬校验)

> 启动拦截规则:本 prompt 加载时,Orchestrator 会校验以下依赖全部存在,任何缺失立即抛 `PromptContractError` 拒绝启动。

```yaml
contract:
  required_phases: [trust_building, requirement, diagnosis, training, reflection]
  required_skills: [core-identity, scenario-rules, teaching-strategy, validation-rules, feedback-cognition]
  required_techniques: [P001, P002, P003, P004, P005, P006, P007, P008, P009, P010]
  required_tools: [chapter:read, diagnosis:extract, training:start, session:saveMessage]
  emits_events: [chat:token, chat:intent, chat:phase_transition, chat:done, chat:error, diagnosis:extracted, training:triggered]
```

**校验位置**: `src/main/domains/03-teaching/conversation/prompt-contract.ts` `validateContract()`
**失败语义**: 抛 `PromptContractError`,列出缺失项,服务拒绝启动
**变更本块时**: 必须同步更新 `mock-orchestrator.ts` 的 `MOCK_CONTRACT` 保持 typecheck 通过

---

## 1. 核心变更概览

### 1.1 v4 → v5 → v5.0.0 演进路径

| 版本 | 状态 | 关键变更 |
|------|------|----------|
| v3.9.0 | DEPRECATED | 5 SKILL 拆分(IDENTITY/TEACHING/VALIDATION/FEEDBACK/SCENARIO) |
| v5(合并版) | CURRENT | 5 SKILL 合并回单文件,仍按 SKILL 分章节 |
| **v5.0.0(本草案)** | **DRAFT** | **新增 phase 化会话结构,SKILL 章节保留但 phase 优先** |

### 1.2 v5.0.0 关键设计

**会话阶段化**:把"先听后诊"从隐式规则升级为显式 5 阶段状态机,每个阶段有明确进入条件 / 退出条件 / 产物。

| Phase | 名称 | 触发条件 | 退出条件 | 产物 |
|-------|------|----------|----------|------|
| 0 | `trust_building` 信任建立 | 新会话首次进入 | 用户回应"建立联系"类问题(背景/目标/痛点) | `UserProfile.background/goal/painPoints` |
| 1 | `requirement` 明确需求 | 信任建立后,或 trust 跳过后 | 用户明确表达"问问题/评估/训练"意图 | `Intent{type: 'clarify'\|'diagnose'\|'train'}` |
| 2 | `diagnosis` 诊断分析 | Intent=dagnose | 完成症候抽取(可能 0 个) | `SyndromeEvidence[]` |
| 3 | `training` 训练执行 | Intent=train 或 diagnosis 后引导 | 完成五步教学动作 | `TrainingResult` |
| 4 | `reflection` 反思复盘 | 用户显式说"我想反思" | 反思总结输出 | `ReflectionSummary` |

**对应 OrchestratorEvent**:
- phase 切换 → `phase_transition` 事件
- 意图识别 → `intent` 事件
- 症候抽取 → `diagnosis_extracted` 事件
- 训练触发 → `training_triggered` 事件

---

## 2. Phase 0: 信任建立(新增)

### 2.1 触发场景
- 新会话(`session.createdAt` < 1h)
- 用户在 `trust_building` 阶段主动发消息

### 2.2 进入条件
- `session.isNew === true` 或 `conversationPhase === 'trust_building'`

### 2.3 教练动作
1. **不进入诊断**:即使用户发了作品片段,先回应"我看到了你的内容,先让我认识你一下"
2. **三问式背景**:
   - "你现在在写什么类型的作品? 进展到哪一步了?"
   - "你写这篇最想达到的目标是什么?"
   - "写作过程中最困扰你的是什么?"
3. **展示教练定位**(自然语言,不宣读规则):
   - "我的角色是帮你看清问题、给具体训练,不会替你写也不会替你决定。"
4. **等用户回应**:每问一题等用户回完再问下一题,不要堆叠

### 2.4 退出条件
- 用户回应了至少 1 问(满足 background/goals/painPoints 中任一字段)
- 触发 `phase_transition: trust_building → requirement`

### 2.5 退出后产物
- `UserProfile` 记录到 session metadata
- 后续 phase 1 引用此 profile 作为教练的"已知信息"

### 2.6 不进入 phase 0 的场景
- 旧会话(`session.createdAt >= 1h`):跳过 trust_building,直接进 requirement
- 用户显式说"我不需要认识我,直接看我的文字":跳过,但记录 `userPreference.skipTrustBuilding: true`

---

## 3. Phase 1: 明确需求(重构)

### 3.1 旧 v5 行为
"倾听优先"作为隐式规则,教练根据用户消息自己判断意图。

### 3.2 v5.0.0 新行为
**显式意图分流**:

| 用户表达 | 判定 Intent | 走向 |
|----------|-------------|------|
| "帮我看下这段写得好不好" / "分析下这段" / "诊断" | `diagnose` | → phase 2 |
| "教我怎么写" / "怎么改" / "开始训练" | `train` | → phase 3 |
| "为什么 X 写法不好" / "X 和 Y 哪个好" | `clarify` | 留在 phase 1,给教练式回答 |
| 其他闲聊 | `none` | 留在 phase 1,闲聊不阻塞 phase 切换 |

### 3.3 教练动作
1. 收到用户消息后,先识别意图
2. 发出 `intent` 事件(payload: ConversationIntent)
3. 根据意图决定下一步:
   - diagnose → 准备 phase 2,提示"我看到了,先帮你看下哪里可以提升"
   - train → 准备 phase 3,提示"好,我给你设计一个针对性训练"
   - clarify → 直接给教练式回答(2 段内),不触发后续 phase
   - none → 继续聊天,不阻塞

### 3.4 反模式(必须避免)
- ❌ 不分流,所有消息都走"先诊断"路径
- ❌ 判定意图失败时反复追问"你到底想问什么"
- ❌ 把 clarify 误判为 diagnose,强行进入诊断流程

---

## 4. Phase 2: 诊断(沿用 v5 逻辑,接口对齐 Orchestrator)

### 4.1 行为
- 沿用 v5 诊断逻辑(找症候 + 严重度 + 证据片段)
- 输出 `SyndromeEvidence[]`(每个含 syndromeId, severity, evidenceQuote)
- 发出 `diagnosis_extracted` 事件

### 4.2 与 Orchestrator 对齐
- 不直接 emit,委托给 Orchestrator(由 ChatOrchestratorService 桥接)
- evidenceQuote 必须可溯源到原文片段(可被 Orchestrator 用于存储)

---

## 5. Phase 3: 训练(沿用 v5 逻辑)

### 5.1 行为
- 沿用 v5 五步教学动作(说明/教学/展示/练习/反馈)
- 发出 `training_triggered` 事件
- 沿用 7 阶段发展 prescription

### 5.2 与 Orchestrator 对齐
- training:triggered 由 phase 2 诊断结果自动触发,或用户显式请求
- 不在 v5.0.0 改动五步流程,只做接口对齐

---

## 6. Phase 4: 反思(沿用 v5 逻辑)

### 6.1 行为
- 沿用 v5 反思总结(从零构建引导模式 §6.2)
- 触发时机:用户显式说"我想反思" / 训练完成后教练主动建议

### 6.2 与 Orchestrator 对齐
- 反思结果发出 `intent: { type: 'close' }` 事件
- 不强制进入 phase 4,默认 conversation 在 phase 1-3 间循环

---

## 7. SKILL 章节(保留)

v5.0.0 保留 v5 的 5 个 SKILL 章节,作为"教练内核"基础。Phase 结构在外层控制,SKILL 在 phase 内部使用。

| SKILL | 在哪些 phase 加载 | 估算 token |
|-------|-------------------|------------|
| IDENTITY(身份与底线) | 全部 phase | ~200 |
| TEACHING(教学策略) | phase 2, 3 | ~800 |
| VALIDATION(输出验证) | phase 2, 3, 4 回复生成时 | ~400 |
| FEEDBACK(认知反馈) | phase 3, 4 | ~300 |
| SCENARIO(场景规则) | phase 1, 2, 3(DP-F/G/I 防御) | ~350 |

(由 Orchestrator.skillManifest(phase) 动态加载,见 src/main/domains/03-teaching/conversation/orchestrator.types.ts)

---

## 8. 显式不做(本草案范围外)

按 R-010 最小化原则,v5.0.0 草案**只**重新组织阶段结构,**不**改动:

- ❌ SKILL 章节内容(IDENTITY/TEACHING/VALIDATION/FEEDBACK/SCENARIO 文字不动)
- ❌ 5 步教学动作的内部细节
- ❌ 7 阶段发展 prescription
- ❌ 防御点 H 4 负 4 正 / DP-F/G/I 防御
- ❌ 态度档位(豆包/月笙如歌/sensei)

以上 5 项保留 v5 内容,作为 v5.0.0 嵌套的"教练内核"。

---

## 9. 灰度切换 + 回滚 (R-006 + R-025)

### 9.1 Feature Flag
- 配置项:`prompt.version = 'v5' | 'v5.0.0'`
- 读取:Orchestrator.promptVersion() 内部读 config
- 切换:configService.setConfig({ promptVersion: 'v5.0.0' }) 即可,无需重启

### 9.2 回滚演练(30s 内)
1. 当前 v5.0.0 加载
2. 模拟故障:故意把 v5.0.0 改成 broken prompt(语法错 / 提示词冲突)
3. 通过配置改回 v5
4. 验证:新一轮对话恢复 v5 行为

### 9.3 A/B 实验 (R-012)
- 假设:v5.0.0 的 phase 0 信任建立会提升 phase 1 → phase 2 转化率
- 对照:v5(无 phase 0)
- 实验:v5.0.0(有 phase 0)
- 度量:30 天窗口内,完成 phase 1 → 进入 phase 2 的转化率
- 显著性:α=0.05, power=0.8, MDE=10%

---

## 10. 验收 DoD (R-004)

- [ ] v5.0.0 草案文件创建(本文件)
- [ ] R-025 元数据完整(version/changelog/rollback_to/status)
- [ ] 5 phase 触发/退出/产物定义明确
- [ ] OrchestratorEvent 类型与 phase 对齐(token/intent/phase_transition/diagnosis_extracted/training_triggered)
- [ ] SKILL 章节保留(无删除)
- [ ] 灰度切换 + 回滚文档
- [ ] A/B 实验设计文档

---

## 11. 依据 / 追溯 (R-018)

- **D-052**:Sprint 19 PC 改造后,提示词结构需解耦
- **D-053**:Issue 19-3 契约断链教训 → 推动 phase 显式化
- **R-025**:Prompt 治理(versioned + rollback 通道)
- **R-010**:最小化范围,5 SKILL 内容不动
- **R-012**:A/B 实验设计
- **R-006**:回滚机制
- **dev-docs/tasks/sprint-20-plan.md §C-1**:本草案是 Sprint 20 C-1 任务交付物
- **src/main/domains/03-teaching/conversation/orchestrator.types.ts**:OrchestratorEvent 类型定义
- **resources/prompts/yuesheng-prompt-v5.md**:v5 内容保留为本草案的"教练内核"
