# 教育型 AI 写作教练项目调研报告

---
type: "调研报告"
title: "教育型 AI 写作教练项目调研"
version: "V1.0"
author: "月笙团队"
date: "2026-06-04"
status: "published"
---

> 生成时间：2026-06-04  
> 性质：竞品调研 + 学术文献综述 + 月笙差异化定位分析  
> 依据：EDUCATION_INSIGHTS_2026-06-04.md, EDUCATION_FRAMEWORK_V2_2026-06-04.md

---

## 一、执行摘要

经过对 GitHub 开源项目、学术论文、商业平台三个维度的系统调研，发现当前 AI 写作教练领域呈现以下格局：

- **学术/开源项目**：在 ZPD 理论落地、学习者建模、多 Agent 架构方面有丰富探索，但**专注于创意写作（小说/虚构类）诊断与教学的开源项目极为稀缺**
- **商业产品**：Khan Academy Writing Coach、Quill、Grammarly for Education 等覆盖学术写作和语法训练，但**缺乏针对创意写作"症候诊断+针对性训练"的产品**
- **创意写作 AI 工具**：Sudowrite、NovelCrafter 等聚焦"辅助写作"而非"教学诊断"，没有学生模型和自适应教学

**核心结论：** "创意写作症候诊断+ZPD 自适应教学"是目前市场的空白区。月笙如果做成，就是品类开创者。

---

## 二、开源/学术项目（与月笙最相关的方向）

### 2.1 IntelliCode（EACL 2026 Demo）

| 维度 | 信息 |
|------|------|
| 论文 | [IntelliCode: A Multi-Agent LLM Tutoring System with Centralized Learner Modeling](https://aclanthology.org/2026.eacl-demo.10.pdf) |
| 团队 | VIT-AP University, IIT Bhubaneswar, India |
| 核心架构 | 6 个专业 Agent 围绕**中心化、版本化的学习者状态**运行：技能评估、学习者画像、渐进式提示、课程选择、间隔重复、参与度监控 |
| 关键技术 | StateGraph Orchestrator + 单写者策略 + 统一学习者状态 Schema |
| 与月笙的相关性 | **极高**——中心化学习者模型架构可直接参考。IntelliCode 的学习者状态包含掌握度估计、误解记录、复习计划、行为信号，与月笙的学生画像高度对应 |
| 在线演示 | https://intellicode.redomic.in |
| 局限性 | 面向编程教学（DSA），非写作领域 |

**可借鉴的关键设计：**
```
LearnerState Schema:
  - skillMastery: Map<skillId, confidence: 0-1>
  - misconceptions: Array<{skillId, description, detectedAt}>
  - reviewSchedule: Map<skillId, nextReviewDate>
  - behavioralSignals: {engagement, frustration, confidence}
```

### 2.2 Claw-STU（开源自适应学习 Agent）

| 维度 | 信息 |
|------|------|
| 项目 | [Claw-STU](https://pypi.org/project/clawstu/) / GitHub: sirhanmacx/Claw-STU |
| 开发者 | SirhanMacx（教师背景） |
| 核心特性 | **ZPD 优先**——3-5 道诊断题建立 ZPD 基线，自适应选择教学方式（苏格拉底对话/一手资料分析等），夜间巩固学习者记忆 |
| 技术栈 | Python >= 3.11, FastAPI, MIT License |
| 与月笙的相关性 | **高**——ZPD 校准流程、学习者画像持久化、模态自适应是月笙可借鉴的。项目包含 `SOUL.md` 定义教学法原则，与月笙的 design-philosophy 思路一致 |
| 局限性 | 通用学习领域，非写作专用；无创意写作诊断功能 |

**可借鉴的关键设计：**
- ZPD 校准流程：先做诊断 → 建立基线 → 匹配教学方式
- `SOUL.md` 教学法原则文档化（与月笙 design-philosophy 同源思路）

### 2.3 Prober.ai（议论文写作反馈系统，arXiv 2026）

| 维度 | 信息 |
|------|------|
| 论文 | [Prober.ai: Gated Inquiry-Based Feedback via LLM-Constrained Personas](https://arxiv.org/html/2605.05598v1) |
| 团队 | Florida State University, New York University |
| 核心架构 | **约束 LLM 只生成探究式提问**（不直接修改文本），通过 persona 系统（"逻辑刺客审稿人"+"困惑的 novice 读者"）提供多维度反馈 |
| 关键技术 | Persona-specific system prompts + 结构化 JSON 输出 Schema + Challenge-Unlock 两阶段交互 |
| 理论基础 | Toulmin 论证理论 + 同伴前馈提问机制 |
| 与月笙的相关性 | **极高**——"AI 不替学生写，只提问引导"的理念与月笙完全一致。Challenge-Unlock 机制（学生必须先反思才能解锁修改建议）是月笙"教学摩擦"设计的优秀参考 |
| 局限性 | 仅覆盖议论文，不涉及创意写作/虚构写作；尚无 GitHub 仓库公开 |

**可借鉴的关键设计：**
- Challenge-Unlock：学生必须回答问题 → 才能看到下一步建议
- Persona 约束：LLM 被严格限制只提问，不生成内容

### 2.4 GenMentor（目标导向多 Agent 辅导框架）

| 维度 | 信息 |
|------|------|
| 论文 | [LLM-powered Multi-agent Framework for Goal-oriented Learning in ITS](https://arxiv.org/abs/2501.15749) |
| 团队 | HKUST(GZ), Microsoft Research Asia |
| 核心架构 | 目标→技能映射（fine-tuned LLM）+ 进化优化学习路径 + 探索-草稿-整合内容适配机制 |
| GitHub | https://github.com/GeminiLight/gen-mentor |
| 与月笙的相关性 | **中高**——目标导向学习路径和动态学习者画像可参考，但面向专业技能学习而非写作 |

### 2.5 PETITE（导师-学生双 Agent 编程框架，2026）

| 维度 | 信息 |
|------|------|
| 论文 | [Enhancing LLM Problem Solving via Tutor-Student Multi-Agent Interaction](https://arxiv.org/abs/2604.08931) |
| 团队 | Ozyegin University, University of Osaka |
| 核心思路 | 同一 LLM 实例扮演**不对称角色**（学生 vs 导师），利用生成/评估的认知不对称性进行迭代改进 |
| 与月笙的相关性 | **中**——证明了角色分化的 Agent 架构优于单 Agent，为月笙的诊断 Agent/教学 Agent 分离提供学术支撑 |

### 2.6 GAMER PAT（学术写作严肃游戏，arXiv 2025）

| 维度 | 信息 |
|------|------|
| 论文 | [GAMER PAT: Research as a Serious Game](https://arxiv.org/html/2510.21719v1) |
| 团队 | Waseda University |
| 核心思路 | 将学术论文写作重构为严肃游戏，用户与 co-author NPC 和审稿人 NPC 互动，反馈变成"任务" |
| 四阶段支架模式 | (1) 提问 → (2) 元视角 → (3) 结构化 → (4) 递归反思 |
| 与月笙的相关性 | **中**——四阶段支架模式与月笙"引导→指导→挑战"的教学模式有相通之处 |

---

## 三、商业产品平台

### 3.1 Khan Academy Writing Coach（Khanmigo）

| 维度 | 信息 |
|------|------|
| 网站 | https://www.khanmigo.ai/writingcoach |
| 定位 | 面向 7-12 年级学生的 AI 写作教练，**免费** |
| 核心流程 | 理解任务 → 列大纲 → 起草 → 反馈与修订 |
| 技术 | Google Gemini AI 驱动 |
| 教师端 | 分析面板：步骤完成数、时间、字数、建议采纳情况、原创性预警 |
| 与月笙对比 | 覆盖学术写作全流程，但**无诊断系统、无学生能力画像、无自适应训练** |

### 3.2 Quill.org（免费写作素养平台）

| 维度 | 信息 |
|------|------|
| 网站 | https://www.quill.org/ |
| 规模 | 1100 万+学生，21 万+教师，50 州覆盖 |
| 工具 | 诊断测试、语法练习、句子连接、段落校对、证据阅读 |
| 核心能力 | 实时分析学生写作 → 具体技能反馈 → 多次修订机会 → **自适应学习路径**（诊断后推荐针对性练习） |
| 与月笙对比 | 有诊断→自适应路径机制，但**仅覆盖语法和句子层面**，无创意写作诊断 |

### 3.3 Clara AI（Google Docs 写作教练）

| 维度 | 信息 |
|------|------|
| 网站 | https://inviteclara.org/ |
| 定位 | 嵌入 Google Docs 的对话式写作教练 |
| 核心特性 | **苏格拉底提问**（不给答案）、个性化反馈、随时间适应学生水平、教师可指导 Clara 的反馈方向 |
| 与月笙对比 | 教学理念高度一致（不替学生写、提问引导），但无症候诊断系统 |

### 3.4 Stylus Education（英国 KS2-3 写作评估）

| 维度 | 信息 |
|------|------|
| 网站 | https://stylus.education/ |
| 定位 | AI 写作评估系统，**BESA 2025 年度最佳创业公司** |
| 核心能力 | **超细粒度诊断**（近 100 个评估标准）、教师仪表盘、干预分组建议、学生个性化反馈（WWW/EBI/Next Steps） |
| 工作流 | 纸笔写作 → 扫描 → AI 批改 → 反馈报告 |
| 与月笙对比 | **最接近月笙诊断理念的商业产品**——多维度细粒度诊断+教师洞察。但覆盖的是英国课程标准作文评估，非创意写作 |

### 3.5 Sudowrite / NovelCrafter（创意写作 AI 工具）

| 维度 | 信息 |
|------|------|
| Sudowrite | https://sudowrite.com/ —— 基于自有 Muse 模型的虚构写作 AI，Story Bible 管理角色/世界观/大纲 |
| NovelCrafter | 长篇小说 AI 工作台，支持多 LLM 选择，管理书籍/系列/角色/时间线 |
| 与月笙对比 | 这些是**写作辅助工具**（帮作家写得更快），不是**教学工具**（帮写作者提升能力）。没有诊断、没有学生模型、没有训练系统 |

---

## 四、关键研究发现

### 4.1 什么有效（Best Practices）

| 实践 | 证据来源 | 说明 |
|------|----------|------|
| **中心化学者状态** | IntelliCode, Claw-STU | 版本化学习者模型（掌握度、误解、复习计划）是所有自适应系统的基础 |
| **约束 LLM 不直接生成答案** | Prober.ai, Clara, Khanmigo | 通过 prompt 约束 + JSON Schema 限制 LLM 输出为提问/引导，防止认知外包 |
| **渐进式支架** | GAMER PAT, EduGenius | 低难度给提示，高难度给元认知问题，根据掌握度调节反馈粒度 |
| **多 Agent 角色分化** | IntelliCode, PETITE, GenMentor | 诊断 Agent / 教学 Agent / 课程 Agent 分离优于单 Agent 架构 |
| **教师可见性** | Khanmigo, Stylus, Clara | 教师需要看到学生的互动过程和诊断结果，才能进行针对性干预 |
| **诊断→自适应路径** | Quill, Claw-STU | 先做诊断建立基线，再推荐针对性练习，形成闭环 |
| **教学摩擦机制** | Prober.ai Challenge-Unlock | 学生必须先完成反思/回答问题，才能解锁下一步提示，防止跳过思考 |

### 4.2 什么不够好（What's Missing）

| 缺失领域 | 说明 |
|----------|------|
| **创意写作症候诊断** | 所有产品覆盖语法、结构、论证，**没有产品诊断"世界观说明书症""对话木偶症"等创意写作特有症候** |
| **ZPD 理论在写作中的落地** | Claw-STU 在通用学习领域实现了 ZPD，但**写作教学领域没有 ZPD 自适应产品** |
| **引导/指导/挑战三种教学模式切换** | 现有产品要么全程引导（Grammarly），要么全程提问（Clara），**缺乏根据学生水平动态切换教学模式** |
| **持久学习者画像在写作领域** | IntelliCode 展示了完整的 Learner State Schema，但仅用于编程教学 |
| **中文创意写作 AI 教学** | 小花狮覆盖中文作文但偏语言规范，**没有中文创意写作教学产品** |

### 4.3 月笙的差异化定位

基于调研，月笙写作教练的独特价值定位：

```
市场空白：创意写作（小说/虚构类）的 AI 教学诊断 + ZPD 自适应训练

月笙的独特组合：
1. 症候诊断引擎（P001-P00X 创意写作症候识别） ← 无同类产品
2. 学生能力画像（基于诊断结果的持久化掌握度模型） ← 参考 IntelliCode
3. ZPD 自适应教学（引导→指导→挑战模式动态切换） ← 参考 Claw-STU
4. 训练推荐系统（症候→训练映射） ← 参考 Quill 的自适应路径
5. 教学摩擦（不替学生写，只提问引导） ← 参考 Prober.ai / Clara
```

---

## 五、推荐进一步阅读的学术文献

| 论文 | 核心价值 |
|------|----------|
| [Help Me Write a Story: Evaluating LLMs' Ability to Generate Writing Feedback](https://arxiv.org/html/2507.16007v1/) (Google DeepMind, 2025) | 评估 LLM 对**创意写作**反馈的能力，发现当前模型难以识别故事的最大问题 |
| [Creativeable: Leveraging AI for Personalized Creativity Enhancement](https://mdpi.com/2673-2688/6/10/247) (Technion, 2025) | AI 自适应创意写作训练的实证研究，反馈+自适应难度的效果分析 |
| [From errors to excellence: AI-driven scaffolding for advancing L2 writing skills](https://www.tandfonline.com/doi/pdf/10.1080/2331186X.2025.2588512) (2025) | ZPD + AI 支架在二语写作中的应用 |
| [A Technology-Enhanced Learning Framework for College English Writing](https://dl.acm.org/doi/10.1145/3802133.3802283) (IECA 2026) | 多 Agent 在工作流程驱动的写作教学中的编排 |
| [GPT is all you need](https://www.frontiersin.org/journals/psychology/articles/10.3389/fpsyg.2025.1549755/full) (Frontiers in Psychology, 2025) | GPT 作为认知支架的理论框架（ZPD + 认知负荷理论） |

---

## 六、对月笙项目的直接影响

### 6.1 确认了教育文档方向的正确性

调研结果与 EDUCATION_INSIGHTS_2026-06-04.md 和 EDUCATION_FRAMEWORK_V2_2026-06-04.md 的核心洞察高度一致：
- "从陪伴型 AI 到教练型 AI"——Prober.ai、Clara 都证明了这一点
- "中心化学者状态"——IntelliCode 的 LearnerState 验证了学生模型的必要性
- "诊断→自适应路径"——Quill、Claw-STU 都采用了这一模式

### 6.2 提供了可参考的技术方案

| 月笙需求 | 参考项目 | 参考内容 |
|----------|----------|----------|
| 学生模型设计 | IntelliCode | LearnerState Schema |
| ZPD 自适应 | Claw-STU | ZPD 校准流程 |
| 教学摩擦 | Prober.ai | Challenge-Unlock 机制 |
| 多 Agent 架构 | IntelliCode, PETITE | 角色分化的 Agent 设计 |
| 支架模式切换 | GAMER PAT | 四阶段支架模式 |

### 6.3 确认了市场空白

没有任何产品同时覆盖"创意写作症候诊断"和"ZPD 自适应教学"。月笙的核心竞争力不是诊断能力本身（大模型都能做到），而是**基于有限核心错误模式的个性化教学决策系统**。

---

## 变更记录

| 版本 | 日期 | 变更内容 | 变更人 |
|------|------|---------|--------|
| V1.0 | 2026-06-04 | 初始版本，覆盖 GitHub 开源、学术论文、商业平台三个维度 | 月笙团队 |
