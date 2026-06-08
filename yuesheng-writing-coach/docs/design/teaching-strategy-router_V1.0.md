# TeachingStrategyRouter — 教学策略路由层

> **版本**: V1.0-concept（概念草稿）  
> **创建日期**: 2026-06-06  
> **状态**: 概念阶段，Phase 3 启动  
> **设计依据**: [design-philosophy_V1.0.md](design-philosophy_V1.0.md) §第三章「降级规则」、§第五章「教学诊断体系」  
> **前置依赖**: T-024（训练效果评分，提供数据基础）、T-026（Prompt 蒸馏调研，提供素材）、T-028（教育学理论蒸馏，提供理论依据）

---

## 一、解决的问题

### 当前教学策略的局限

现有 `teaching-strategy.service.ts` 的决策逻辑是**简单的条件映射**：

```
diagnosis.syndrome → 查找 problem-tiering.json → 返回策略
```

但这种映射缺乏对以下因素的考量：

| 缺失的维度 | 问题 | 示例 |
|-----------|------|------|
| 用户水平 | 对 beginner 和 advanced 用户给同样的教学方式 | 一个需要案例模仿，一个需要自我诊断 |
| 历史反馈 | 用户对"分析型"练习完成度高 → 是否应该继续给分析型？ | 缺乏基于历史成功率的动态调整 |
| 教育学理论 | 为什么"先给案例再模仿"比"先解释再练习"更适合某些场景？ | 当前的教学方式选择缺乏理论支撑 |
| 多症候交叉 | 同时有 P001（世界观膨胀）+ P004（信息硬塞）时，先教哪一个？ | 当前只是按严重度排序，缺乏策略性 |

---

## 二、核心概念

TeachingStrategyRouter 不是取代现有教学框架的新引擎，而是在现有框架之上新增的**决策层**：

```
                          TeachingStrategyRouter
                                  │
                    ┌─────────────┴─────────────┐
                    │       决策输入              │
                    ├───────────────────────────┤
                    │ • userLevel (beginner /    │
                    │   intermediate / advanced) │
                    │ • syndrome 列表 + severity │
                    │ • trainingHistory (已完成   │
                    │   训练+评分)                │
                    │ • currentPhase (教学状态机  │
                    │   当前阶段)                 │
                    │ • userPreference (用户对     │
                    │   不同练习模式的偏好)        │
                    └─────────────┬─────────────┘
                                  │
                    ┌─────────────┴─────────────┐
                    │       决策引擎              │
                    │ 基于规则 + 权重 + 教育学     │
                    │ 蒸馏知识库                   │
                    └─────────────┬─────────────┘
                                  │
                    ┌─────────────┴─────────────┐
                    │       决策输出              │
                    ├───────────────────────────┤
                    │ • targetSyndrome (本次教学  │
                    │   聚焦的症候)               │
                    │ • teachingMode (案例驱动 /  │
                    │   反思驱动 / 分析驱动 /      │
                    │   练习驱动)                 │
                    │ • stepSequence (教学步骤     │
                    │   序列)                     │
                    │ • toneProfile (语气配置)    │
                    │ • practiceType (练习类型)    │
                    │ • theoryReference (教育学    │
                    │   理论依据，用于可解释性)     │
                    └─────────────┬─────────────┘
                                  │
                                  ▼
                    teaching-state-machine.ts
                    （消费决策输出，执行具体流程）
```

### Router 与现有框架的边界

| 职责 | 归属 |
|------|:----:|
| 决定"教什么"（聚焦哪个症候） | TeachingStrategyRouter |
| 决定"怎么教"（教学步骤序列） | TeachingStrategyRouter |
| 执行教学流程（状态流转） | teaching-state-machine.ts |
| 生成具体教学内容（Prompt 组装） | prompt-builder.ts |
| 记录教学效果（评分/反馈） | training-record.service.ts + T-024 |

---

## 三、决策输入详解

### 3.1 用户水平（userLevel）

| 来源 | 说明 |
|------|------|
| `student-classifier.ts` | 基于会话次数+历史诊断结果+训练完成率的分类 |
| 取值：beginner / intermediate / advanced |

### 3.2 症候信息（syndrome 列表）

| 来源 | 说明 |
|------|------|
| 当前诊断结果 | 含 syndromeId、severity（L1/L2/L3）、variant（T-027 后的变种） |
| 历史诊断统计 | 哪些症候反复出现、哪些症候已改善 |

### 3.3 训练历史（trainingHistory）

| 来源 | 说明 |
|------|------|
| T-024 评分数据 | 每个已完成训练的 score、feedback、improved 标记 |
| 训练完成率 | 用户是否倾向于完成训练，还是跳过 |

### 3.4 教学阶段（currentPhase）

| 来源 | 说明 |
|------|------|
| teaching-state-machine | 当前所在 Phase 和子阶段（S1_ANALYSIS / S2_REFLECTION / S3_TEACHING / S4_PRACTICE） |

### 3.5 用户偏好（userPreference）

| 来源 | 说明 |
|------|------|
| 隐式学习（历史行为推断） | 用户对"分析型"练习的完成率更高？对"改写型"更积极？ |
| 显式反馈（可选） | 未来可考虑让用户选择偏好模式 |

---

## 四、决策引擎设计原则

### 4.1 分层决策

```
第一层：聚焦症候选择
如果用户有多个活跃症候（L2+）：
  - 优先选择历史训练评分最低的（最需要改进）
  - 如果所有症候都未训练过，选择 severity 最高的
  - 如果有教育学理论建议优先级，遵循理论

第二层：教学方式选择
基于 userLevel + syndrome.type + teachingMode 的矩阵匹配：
  - beginner + 展示力不足 → 案例驱动（先看好的例子再模仿）
  - intermediate + 结构失序 → 分析驱动（先复盘再重构）
  - advanced + 任何症候 → 反思驱动（先自我诊断再针对性练习）

第三层：参数细化
基于 trainingHistory 和 userPreference 微调具体参数：
  - 步骤数量（用户耐心值高 → 更多步骤）
  - 反馈频率（用户完成率高 → 减少中间反馈）
  - 难度递进速度
```

### 4.2 教育学蒸馏知识库接口

TeachingStrategyRouter 依赖一个外置的**教育学蒸馏知识库**（由 T-028 产出），格式示例：

```json
{
  "theoryFragments": [
    {
      "id": "VYG-001",
      "theory": "最近发展区（ZPD）",
      "source": "Vygotsky, 1978",
      "principle": "教学应该在学习者当前水平和潜在水平之间进行",
      "application": {
        "condition": { "userLevel": "beginner" },
        "recommendedMode": "案例驱动（scaffolding）",
        "rationale": "初学者需要案例作为脚手架，逐步过渡到独立练习"
      }
    },
    {
      "id": "SCH-001",
      "theory": "反思性实践",
      "source": "Schön, 1983",
      "principle": "专业能力的提升来自对实践过程的反思而非外部指导",
      "application": {
        "condition": { "userLevel": "advanced", "syndromeType": "structural" },
        "recommendedMode": "反思驱动",
        "rationale": "高级用户需要的是自我诊断能力而非外部答案"
      }
    }
  ]
}
```

路由器不一定直接引用知识库做实时决策（性能考虑），而是在决策规则定义时引用理论依据，使规则有可追溯的教育学来源。

---

## 五、与相关模块的关系

| 模块 | 与 Router 的关系 |
|------|----------------|
| `teaching-strategy.service.ts` | Router 将取代它的决策职责。但 teaching-strategy.service 中的策略执行逻辑（如问题优先级排序）可能被复用 |
| `problem-tiering.json` | 继续作为症候的静态优先级参考，Router 在此基础上做动态决策 |
| `tone-modifiers.json` | Router 的 toneProfile 输出将直接引用此配置 |
| `teaching-state-machine.ts` | 无变化。仍负责流程执行，Router 的输出作为其 stepSequence 输入 |
| `prompt-builder.ts` | 可能需要微调以接收 Router 输出的 teachingMode 参数 |

---

## 六、Phase 3 启动条件

TeachingStrategyRouter 的启动依赖以下条件全部满足：

```
□ T-024 训练效果评分已上线（至少 50+ 条评分数据）
□ T-026 Prompt 蒸馏调研报告已完成
□ T-028 教育学理论蒸馏已完成
□ 教学状态机稳定运行（无 P0/P1 级别的 bug）
□ T-022 技法库已接入系统（技法库作为练习资源）
```

建议在 Phase 2 任务全部完成后，基于 T-024 积累的数据和 T-026/T-028 的知识输入开启 Phase 3。

---

## 变更记录

| 日期 | 变更内容 | 版本 |
|------|---------|:----:|
| 2026-06-06 | 初始概念草稿，基于 Phase 2 评估结果创建 | V1.0-concept |
