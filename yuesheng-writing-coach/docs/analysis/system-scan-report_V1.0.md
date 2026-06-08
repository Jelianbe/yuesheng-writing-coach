# 月笙写作教练 - 系统全面扫描报告

> **生成日期**: 2026-06-06  
> **扫描范围**: 完整教学链路 + 诊断引擎 + 训练系统 + 文档资产  
> **状态**: 全部核心任务已完成（T-000 ~ T-021 + CS-001）

---

## 一、教学流程完整链路

### 1.1 从用户消息到教学回复的完整流程

```
用户发送消息
    │
    ├─ Step 1: 调用 DiagnosisAgent（diagnosis-agent-prompt-v1.md）
    │   ├─ AI 分析文本 → 输出 JSON 诊断表
    │   ├─ 提取：症候列表 + 关键片段 + 技法池 + 根因分析
    │   └─ 存入 SQLite（diagnosis_results 表）
    │
    ├─ Step 2: 构建教学上下文
    │   ├─ 加载 System Prompt（yuesheng-prompt-v3.md + 态度修饰词）
    │   ├─ 注入诊断历史（最近 5 次诊断）
    │   ├─ 注入教学策略指令（语气/模式决策）
    │   ├─ T-018: 反思门控（有 L2+ 症候时插入反思问题）
    │   └─ 辩驳追踪（T-016）
    │
    ├─ Step 3: AI 流式回复（Chat Agent）
    │   ├─ 基于诊断结果 + 教学策略生成回复
    │   └─ 流式推送给前端
    │
    └─ Step 4: 诊断表后处理
        ├─ processDiagnosisFromAI() 解析 AI 回复中的诊断表
        ├─ 合并到教学状态机（lockSyndromes）
        └─ 推送给前端（DIAGNOSIS_UPDATE 事件）
```

### 1.2 每次对话的诊断数量

| 项目 | 数值 | 说明 |
|------|------|------|
| DiagnosisAgent 调用 | **1 次 / 消息** | 每次用户消息触发一次诊断 |
| 症候返回数量 | **不限制** | 取决于文本质量和 AI 判断 |
| 前端展示 | **所有发现的症候** | 通过翻译层展示用户友好文本 |
| 诊断历史注入 | **MAX_DIAGNOSIS_HISTORY = 5** | 教学上下文注入最近 5 次诊断 |

---

## 二、诊断表填表机制

### 2.1 诊断数据流

```
AI Diagnosis Agent 输出
    │
    │  {
    │    syndromeRef: ["P001", "P003"],
    │    keyPassages: [
    │      { text: "原文片段", issue: "问题描述", syndromeRef: "P001" },
    │      ...
    │    ],
    │    techniquePool: [...],
    │    confidence: 0.8
    │  }
    │
    ▼
parseDiagnosisFromAIResponse() [diagnosis-parser.ts]
    │  ✅ 解析 JSON，提取症候列表
    │  ✅ 验证 syndromeRef 是否有效症候 ID
    │  ✅ 验证 severity 是否为 L1/L2/L3
    │
    ▼
processDiagnosisFromAI() [diagnosis.handler.ts]
    │  ✅ 持久化到 SQLite（diagnosis_results 表）
    │  ✅ 每个证据创建 Evidence 记录
    │     - evidenceId: EVD-{timestamp}{idx}
    │     - contentJson: { text: evText }
    │     - relatedDisease: syndrome.id
    │  ✅ 关联到诊断：linkToDiagnosis(diagnosisId, evidenceId, 'primary'|'supporting')
    │  ✅ 合并到教学状态机（lockSyndromes）
    │  ✅ 推送给前端（DIAGNOSIS_UPDATE 事件）
```

### 2.2 诊断表验证结果

| 项目 | 状态 | 说明 |
|------|:----:|------|
| SQLite 写入 | ✅ | `DiagnosisService.save()` 写入 `diagnosis_results` 表 |
| 解析验证 | ✅ | `parseDiagnosisFromAIResponse()` 验证症候 ID、严重度、证据 |
| 状态机合并 | ✅ | `lockSyndromes()` 将新症候锁定到教学状态 |
| 前端推送 | ✅ | `DIAGNOSIS_UPDATE` IPC 事件推送给渲染进程 |
| 翻译层 | ✅ | T-015 已完成，用户看到"你的故事设定很丰富"而非"P001" |

---

## 三、诊断匹配机制

### 3.1 AI 诊断 Agent 分析流程

```
用户文本
    │
    ▼
callDiagnosisAgent() [chat.handler.ts]
    │  调用 LLM，使用 diagnosis-agent-prompt-v1.md 作为 System Prompt
    │
    ▼
AI 按以下流程分析：
    │
    ├─ Step 0: 内容类型判断（narrative vs non-narrative）
    │     └─ non-narrative → 立即停止，不诊断
    │
    ├─ Step 1: 意图阶段判断（Phase 0/1/2）
    │
    ├─ Step 2: 症候检测（P001~P006，一句话触发条件）
    │
    ├─ Step 2.5: 开篇钩子检测（H001/H002）
    │
    ├─ Step 2.6: 情绪曲线分析（E001）
    │
    ├─ Step 2.7: 意图一致性检查（I001~I006）
    │     └─ 完全由 LLM 判断，无程序规则
    │
    ├─ Step 3: 技法匹配（根据症候选择 3-5 条技法）
    │
    └─ 输出: { syndromeRef, techniquePool, keyPassages, confidence }
```

### 3.2 匹配方式

**AI 全权判断，无程序规则引擎**。Prompt 提供了症候手册的识别标准作为 AI 的参考，但实际判断完全依赖 LLM 的理解能力。

---

## 四、初学者诊断生成机制

### 4.1 面对初学者的诊断流程

```
AI Diagnosis Agent（diagnosis-agent-prompt-v1.md）
    │
    ├─ 输入：用户文本 + System Prompt（含症候手册 + 动作库）
    ├─ 判断内容类型：narrative / non-narrative
    ├─ 匹配症候：P001~P010（L1/L2/L3 严重度）
    ├─ 匹配技法：techniquePool（最多 5 条）
    ├─ 提取关键片段：keyPassages（每个最多 50 字）
    └─ 输出 JSON 诊断表 → 解析 → 存入数据库
```

### 4.2 初学者场景

- AI 根据文本质量判断严重度（L1 轻度 / L2 中度 / L3 严重）
- 每个症候带证据片段（keyPassages）
- 置信度 `confidence` 0-1
- 推荐动作 `suggestedActions`（关联 A001~A010）

---

## 五、核心库现状分析

### 5.1 诊断库

| 维度 | 现状 | 评估 |
|------|------|------|
| 症候数量 | P001~P010（10 个），实际检测 P001~P006（6 个核心） | ⚠️ 偏少。覆盖世界观、角色、情绪、节奏、视角、信息六大维度，但缺乏"对话"、"结构"、"主题"维度 |
| 变种识别 | **无**。P001 就是 P001，无法区分不同变种 | ⚠️ 缺失。AI 的 trigger 条件过于简化，无法捕捉核心问题的不同表现形式 |
| 严重度 | L1/L2/L3 三级，由 AI 判断 | ✅ 基本够用 |
| 证据链 | keyPassages 带 syndromeRef，证据入库 | ✅ 链路完整 |

**症候手册覆盖维度**：

| 症候 | 名称 | 维度 |
|------|------|------|
| P001 | 世界观膨胀 | 设定管理 |
| P002 | 角色工具人化 | 角色塑造 |
| P003 | 情绪标签化 | 情绪展示 |
| P004 | 信息硬塞 | 信息传递 |
| P005 | 视角漂移 | 视角控制 |
| P006 | 节奏停滞 | 节奏推进 |
| P007 | 阅读结构单一 | 阅读拓展 |
| P008 | ⚠️ 已合并到 P004 | — |
| P009 | 角色动机缺失 | 角色塑造 |
| P010 | OC 平面化 | 角色塑造 |

### 5.2 技法库

| 项目 | 状态 |
|------|------|
| 技法数量 | 34 条（TQ-001 ~ TQ-024 + TC-001 ~ TC-010） |
| 文档位置 | `docs/teaching/technique-library/` |
| 系统接入 | ❌ **仅文档存在，未被系统使用** |
| 配置外置 | ❌ 技法在 diagnosis-agent-prompt-v1.md 中被硬编码为字符串列表 |
| 推荐引擎引用 | ❌ `recommendTasks()` 返回空数组 |

**技法分类**：

| 类别 | 文档 | 技法数 |
|------|------|--------|
| 开篇 | technique-kaiqiao_V1.md | 12 |
| 节奏 | technique-jiezou_V1.md | 9 |
| 对话 | technique-duihua_V1.md | 0 |
| 世界观 | technique-shijieguan_V1.md | 2 |
| 人物 | technique-renwu_V1.md | 11 |

### 5.3 训练方案

| 项目 | 状态 |
|------|------|
| 框架 | ✅ T-021 已实现 TrainingWorkshop 组件和逐步练习交互 |
| 推荐算法 | ❌ `recommendation-engine.ts` 的 `recommendTasks()` 返回空数组 |
| 训练效果评分 | ❌ 未实现 |
| 训练任务库 | ❌ 未建立 |

---

## 六、证据引用机制

### 6.1 完整数据流

```
AI Diagnosis Agent 输出
    │
    │  keyPassages: [
    │    { text: "原文片段", issue: "问题描述", syndromeRef: "P001" },
    │    ...
    │  ]
    │
    ▼
parseDiagnosisFromAIResponse()
    │  ✅ 解析 JSON，提取 keyPassages
    │  ✅ 验证 syndromeRef 是否有效症候ID
    │
    ▼
processDiagnosisFromAI()
    │  ✅ 每个 keyPassage 创建 Evidence 记录
    │     - evidenceId: EVD-{timestamp}{idx}
    │     - contentJson: { text: evText }
    │     - relatedDisease: syndrome.id
    │  ✅ 关联到诊断：linkToDiagnosis(diagnosisId, evidenceId, 'primary'|'supporting')
    │
    ▼
SQLite 证据表 (evidence_records)
    │  字段: evidenceId, type, level, novelId, contentJson,
    │        relatedDisease, relatedAbility, extractedBy, createdAt
    │
    └─ diagnosis_evidence 关联表
         字段: diagnosisId, evidenceId, linkType (primary/supporting)
```

### 6.2 关键发现

**引用链路完整，但前端未消费**。证据被存入 SQLite 并关联到诊断，但 RightPanel 的诊断芯片只展示 `syndrome.evidence` 字符串数组，不展示 keyPassages 的原文引用。用户看不到"为什么这样诊断"。

---

## 七、系统回答长度问题

### 7.1 当前存在的问题

| 问题 | 原因 | 建议 |
|------|------|------|
| AI 回复偏长 | System Prompt 未限制回复长度 | 在 Prompt 中加入"每次回复不超过 3 段"的指令 |
| 诊断即给建议 | 缺乏反思门控的实际执行 | T-018 已接入但 `isReflectionGate` 尚未在教学状态机中实际使用 |
| 一次输出太多信息 | `MAX_DIAGNOSIS_HISTORY = 5` 全部注入 | 改为按需注入：首次只显示最严重的 1-2 个症候 |
| 缺乏"只说一个问题"的约束 | Prompt 未限制 | 在 System Prompt 中加入"一次只聚焦一个问题"的原则 |

---

## 八、只存在于文档中未被任务标记的内容

### 8.1 设计规格文档

| 文档 | 内容 | 状态 |
|------|------|------|
| `SPEC_adaptive-teaching_V1.0.md` | 自适应教学完整规格 | ❌ 无对应任务 |
| `SPEC_Technique_Invocation_V1.md` | 技法调用规格 | ❌ 无对应任务 |
| `SPEC_Teaching_Summary_Technique_Distillation_V1.md` | 教学总结技法提炼 | ❌ 无对应任务 |
| `SPEC_novel-profile_V1.0.md` | 小说画像规格 | ❌ 无对应任务（项目记忆标记为"过度工程"） |
| `SPEC_Dual_Agent_V1.md` | 双 Agent 架构 | ❌ 无对应任务（部分已实现） |
| `SPEC_focus-area-transition_V1.0.md` | 聚焦方向迁移 | ⚠️ 有 T-006 但可能不完整 |
| `training-effectiveness-scoring_V1.0.md` | 训练效果评分 | ❌ 无对应任务 |
| `dynamic-context-service_V1.0.md` | 动态上下文服务 | ❌ 无对应任务 |
| `mvp-cut-recovery_V1.0.md` | MVP 裁剪恢复方案 | ❌ 无对应任务 |
| `teaching-knowledge-bridge_V1.0.md` | 教学知识桥梁 | ❌ 无对应任务 |

### 8.2 技法库文档

| 文件 | 状态 |
|------|------|
| `technique-library/index_V1.md` | 索引文档，34 条技法 |
| `technique-library/technique-kaiqiao_V1.md` | 12 条开篇技法 |
| `technique-library/technique-jiezou_V1.md` | 9 条节奏技法 |
| `technique-library/technique-duihua_V1.md` | 0 条（空） |
| `technique-library/technique-shijieguan_V1.md` | 2 条世界观技法 |
| `technique-library/technique-renwu_V1.md` | 11 条人物技法 |

**仅文档存在，未被系统使用**。

---

## 九、规划但未实现的核心目标

| 目标 | 文档依据 | 优先级 | 说明 |
|------|---------|:------:|------|
| **诊断库重构** | design-philosophy_V1.0.md | **P0** | 转为"核心问题 + 变种"架构，提升诊断精度 |
| **技法库接入系统** | technique-library/ | **P0** | 技法库目前只是文档，需要转换为 JSON 配置并接入诊断/训练流程 |
| **训练推荐算法实现** | recommendation-engine.ts | **P0** | `recommendTasks()` 返回空数组，需要实现完整的推荐逻辑 |
| **训练效果评分** | training-effectiveness-scoring_V1.0.md | P2 | 训练完成后如何评分和反馈 |
| **自适应教学** | SPEC_adaptive-teaching_V1.0.md | P2 | 根据用户水平动态调整教学策略 |
| **AI 写作工具 Prompt 蒸馏** | design-philosophy_V1.0.md 第四章 | P1 | 逆向工程提取其他工具的教学策略 |
| **前端证据引用展示** | 证据系统设计 | P1 | 用户需要看到"为什么这样诊断" |
| **小说画像（NovelProfile）** | SPEC_novel-profile_V1.0.md | P3 | 被项目记忆标记为"过度工程" |
| **双 Agent 架构完善** | SPEC_Dual_Agent_V1.md | P3 | DiagnosisAgent + ChatAgent 分离（部分已实现） |

---

## 十、核心教学链路完成度

```
核心教学链路：用户作品 → 发现问题 → 解释原因 → 制定训练 → 执行训练 → 验证进步 → 形成能力
                    ✅           ✅         ✅         ⚠️         ✅         ❓         ❓
```

| 环节 | 状态 | 说明 |
|------|:----:|------|
| 用户作品 → 发现问题 | ✅ | DiagnosisAgent + 解析器 + SQLite |
| 发现问题 → 解释原因 | ⚠️ | 翻译层+右侧栏展示存在，但 AI 回复中不一定包含清晰解释 |
| 解释原因 → 制定训练 | ⚠️ | T-021 框架完成，但推荐算法未实现 |
| 制定训练 → 执行训练 | ✅ | TrainingWorkshop 组件 + 逐步练习 |
| 执行训练 → 验证进步 | ⚠️ | 训练评估器存在但未接入主流程 |
| 验证进步 → 形成能力 | ❓ | 能力成长可视化框架存在但数据为空 |
| 新用户引导 | ✅ | T-019 OnboardingFlow 完成 |

---

## 十一、核心建议：诊断库重构方向

### 11.1 当前问题

症候定义过于扁平，"P001 世界观膨胀"只是一个标签，无法区分不同变种：

```
核心问题：主角锚点缺失
  ├── 变种A：世界观设定过多（当前 P001）
  ├── 变种B：支线太多分散注意力（无对应症候）
  └── 变种C：配角抢戏（无对应症候）
```

### 11.2 建议架构

```
核心问题层（Root Cause）
    ├── RC-001 主角锚点缺失
    │   ├── 变种: 世界观膨胀、支线泛滥、配角抢戏
    │   └── 训练: 回归主角练习
    │
    ├── RC-002 角色空心化
    │   ├── 变种: 工具人化、动机缺失、OC平面化
    │   └── 训练: 角色动机构建
    │
    ├── RC-003 展示力不足
    │   ├── 变种: 情绪标签化、信息硬塞
    │   └── 训练: Show Don't Tell 练习
    │
    └── RC-004 结构失序
        ├── 变种: 节奏停滞、视角漂移
        └── 训练: 结构重构练习
```

诊断时先识别**核心问题**，再标注**变种类型**，后续训练直接针对核心问题而非变种。

---

## 十二、两个蒸馏的处理建议

### 12.1 蒸馏1：优秀小说技法蒸馏

**现状**：
- ✅ 34 条技法已入库（technique-library/）
- ✅ 每条技法标注了来源小说、难度、对应症候
- ❌ 仅文档存在，未被系统使用
- ❌ 技法在 diagnosis-agent-prompt-v1.md 中被硬编码为字符串列表

**正确处理方式**：
1. 转换为 JSON 配置（遵循 R-014 配置外置）
2. 建立技法 ID 体系（TQ-001~TQ-034 已有编号）
3. 在推荐引擎中使用技法库而非硬编码
4. 训练方案直接引用技法 ID，形成"诊断→技法→训练"的完整链路

### 12.2 蒸馏2：成熟 AI 写作程序提示词蒸馏

**现状**：
- ❌ **完全没有**。未在任何文档中找到相关蒸馏内容
- ⚠️ 这是设计哲学 V1.0 第四章"Prompt逆向工程"要求的方向，但未落地

**正确处理方式**：
1. 收集其他 AI 写作工具的系统提示词（如 NovelAI, Sudowrite 等）
2. 逆向工程提取其教学策略：
   - 它如何处理用户输入？
   - 它的反馈模式是什么？（鼓励式/批判式/引导式）
   - 它的结构化输出有哪些？
3. 提炼为月笙的教学策略，不是照搬，而是提取可教学的认知模式
4. 融入 diagnosis-agent-prompt 和 chat system prompt

### 12.3 蒸馏结果使用原则

| 蒸馏来源 | 如何使用 | 不怎么做 |
|---------|---------|---------|
| 优秀小说技法 | 作为训练方案的参考库，给用户"可执行的练习" | ❌ 不直接把技法当答案告诉用户 |
| AI 工具提示词 | 提取教学策略和反馈模式，融入系统 Prompt | ❌ 不直接复制其他工具的 Prompt |
| 核心原则 | **提炼认知能力，而非模仿表面形式** | ❌ 不做技法搬运工 |

---

## 十三、待实现核心缺口汇总

| 优先级 | 缺口 | 影响 | 预估工作量 |
|:------:|------|------|:---------:|
| **P0** | 诊断库转为"核心问题 + 变种"架构 | 诊断精度不够，无法针对性教学 | 大 |
| **P0** | 技法库从文档转为系统可用的 JSON 配置 | 训练方案没有技法支撑 | 中 |
| **P0** | 训练推荐算法实现 | 诊断后无训练方案 | 中 |
| **P1** | AI 写作工具 Prompt 蒸馏 | 教学策略来源单一 | 中 |
| **P1** | 前端消费 Evidence 原文引用 | 用户看不到"为什么诊断" | 小 |
| **P2** | 训练效果评分 | 无法验证进步 | 中 |

---

## 变更记录

| 日期 | 变更内容 | 版本 |
|------|---------|:----:|
| 2026-06-06 | 初始版本，系统全面扫描报告 | V1.0 |
| 2026-06-06 | 新增 7.2 教学节奏问题；修正第十章"解释原因"环节状态；更新第十三章缺口汇总 | V1.1 |
