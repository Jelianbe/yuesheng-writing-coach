# ADR-C89：教学主对话 prompt 子代理化拆分

- 状态：**待舰长裁决**（未实施，本文件为决策依据）
- 日期：2026-09-08
- 关联：ADR-C82（诊断协议 user 侧注入）、ADR-C80（分块诊断非流式）、ADR-C85/C88（快速观察）
- 提出背景：舰长反馈「单个 AI 承担写入、读取、诊断等过多操作 → 记忆/注意力分散 → 执行失真」，要求评估子代理模式

---

## 1. 实测证据（本 ADR 的全部数字均为实测，非估算）

### 1.1 单次调用规模

构造点：`lib/services/skill_dispatcher.dart:87`（`_buildL1Chunks` `:114` + `_buildL2Chunks` `:137` + 位置引导 `:94`，`join('\n\n---\n\n')` `:97`）。
唯一调用点：`lib/services/chat_service.dart:1000`。

| L2 模式 | prompt 总字符 | 块数 |
|---|---:|---:|
| **diagnosis** | **65 986** | 26 |
| training | 60 761 | 26 |
| beginner | 58 615 | 20 |
| advanced | 54 413 | 20 |
| outline | 50 363 | 20 |
| none（仅 L1+态度） | 27 098 | 11 |

交叉验证：`lib/config/shared_constants.dart:201-204` 记「systemPrompt 本体」实测（diagnosis 68010 等），与上表字符数基本吻合（ratio=1.0，`:209`）。
【2026-09-13 E 批更正】原引行号 `:171-173`/`:179` 为**行号漂移**，实际在 `:201-204`/`:209`；且该注释数值已于 2026-09-13 更新为 diagnosis 74,571 等（见该文件），上表 65,986 为本 ADR 立时（2026-09-08）快照，保留不改。

> **口径更正**：ADR-C82 记载的「30231 字符」是早期快照，现状为其 **2 倍**。后续引用请以上表为准。

### 1.2 单 prompt 内并存的 10 类职责

1. 产品身份与安全底线 — `skills_l1_core_p3.dart:122`、`skills_l1_core_p4.dart:24/43/57`
2. 阶段判定与推进 — `skills_l1_core_p1.dart:82/127`
3. 态度/人设/语气 — `skills_attitude.dart:21/86/147`、`skills_l1_core_p2.dart:207`
4. 诊断症候识别 — `skill_registry.dart:183-191`、`skills_diagnosis_p1.dart:7`
5. 训练/示范/改写 — `skills_training_p4.dart:7`、`skills_training_p5.dart:7`、`skills_training_p1.dart:216`
6. 协议化 JSON 输出 — `skills_l1_core_p2.dart:119`、`chat_service.dart:1104-1116`
7. 纪律重申 — `chat_service.dart:1085-1100`
8. 素材/画像/引用读取 — `chat_service.dart:1016-1049`（五类注入）
9. 冲突裁决元规则 — `skills_l1_core_p2.dart:284`
10. 回复节奏与长度 — `skills_l1_core_p3.dart:353`

### 1.3 四处自称「最高优先级」（执行失真的直接来源）

| 位置 | 自称 |
|---|---|
| `skills_l1_core_p2.dart:284` | 冲突裁决顺序「优先于其后所有条目」 |
| `skills_l1_core_p3.dart:161` | 「这是教学系统的**最高优先级**设计目标」 |
| `chat_service.dart:1090` | 回复纪律「**最后提醒**」 |
| `chat_service.dart:1105` | 「【输出要求·**最高优先级**】」 |

模型无从判断优先级，这是「执行失真」最直接的机制。

### 1.4 直接指令矛盾（实测原文）

- `chat_service.dart:1094` sensei「**零示范**只给方向」 ↔ `skills_training_p4.dart:7` demonstration「通过名家范例让学生'看见'好写法」
- `chat_service.dart:1092`「**不替用户写句子**」 ↔ `skills_training_p5.dart:7` model-rewrite「给学员一段'目标态'范文」
- `chat_service.dart:1093`「一次只抛一个点，删掉铺垫」 ↔ `chat_service.dart:1104-1113` 要求末尾附 7 字段完整 JSON
- `skill_dispatcher.dart:69`「不要输出任何类似的系统标记」 ↔ 同 prompt 要求结构化协议输出
- `skills_l1_core_p1.dart:102` 注释本身即为已存在冲突打的补丁

### 1.5 裁剪与检索机制失效

- **裁剪形同虚设**：`lib/services/token_budget_guard.dart:18` 自述「闸门不重建 systemPrompt（L2 内嵌其中），因此 **L2 组不参与运行时裁剪**」；阈值 `maxBudget = 128000-4096 = 123904`（`shared_constants.dart:175`），66k 远低于 → **闸门从不触发**。
- **L3 检索断链**：`injectL3`（`skill_dispatcher.dart:102/159`）在生产代码**零调用点**（`skills_advanced_outline_p7.dart:5` 自证）。症候详情/技法详情从不注入——索引 skill 承诺的「完整知识由 L3 注入」未兑现，模型持索引却需完成诊断。

### 1.6 关键反证：同项目已有的小 prompt 全部正常

| 调用 | prompt | 位置 | 规模 |
|---|---|---|---:|
| 教学主对话 | `buildSystemPromptV2` | `chat_service.dart:1000` | **65 986** |
| 快速观察 | `kEditorObservationSkillContent` | `editor_service.dart:86` | 2 142 |
| Teacher | `kTeacherSkillContent` | `teacher_service.dart:86` | 2 215 |
| Reviewer | `kReviewerSkillContent` | `agent_skills.dart:14` | 1 668 |
| 分块分析 | `kChunkSystemPrompt` | `progressive_diagnosis.dart:540` | ~1 300（估算） |

四条旁路调用均为 **1.7k–2.2k 独立小 prompt**，各自独立 service，运行稳定；唯一 66k 的巨型 prompt 即故障频发者。

---

## 2. 结论与决策建议

### 2.1 结论（事实）

1. 「单模块过大导致执行失真」假设**在教学主对话上成立**，有 1.1–1.5 全链条证据支撑。
2. 该假设**不适用于快速观察**——其 prompt 仅 2 142 字符（1.6）。快速观察真机失败属**链路健壮性**问题，见配套任务书 `docs/tasks/REALTIME-OBSERVE-HARDENING.md`，**不得混为一谈**。

### 2.2 建议决策

**将教学主对话按职责拆分为多个专职子代理，由调度器编排。** 理由：

- **非引入新范式，而是推广既有范式**——`agent_skills.dart` 的 Reviewer/Teacher/Editor 已是「一个能力 = 一个独立小 prompt + 一个独立 service」，且稳定。改造有可复用先例。
- 拆分后每子 prompt 降至 2k 量级，与已验证稳定的四条旁路同量级。
- 优先级冲突（1.3）在单 prompt 内无解——只能在调度层裁决。

### 2.3 建议拆分边界

| 子代理 | 职责 | 现状来源 |
|---|---|---|
| diagnose | 症候识别 + 协议化 JSON 输出 | `skills_diagnosis_*`、`chat_service.dart:1104-1116` |
| train | 训练 / 示范 / 改写 | `skills_training_*` |
| attitude | 语气与人设 | `skills_attitude.dart`、`skills_reply_voice.dart` |
| phase | 阶段判定与推进 | `skills_l1_core_p1.dart` |
| guard | 安全底线与冲突裁决（**唯一优先级裁决方**） | `skills_l1_core_p3.dart:122`、`skills_l1_core_p2.dart:284` |

> 边界为**建议**，需实施阶段实测校准。拆分须为**真分解**（独立类/显式接口/依赖注入），**禁止用 `part`/`extension` 机械拆分凑行数**——AGENTS.md 已定性为伪拆分（X-025-ARCH 回退 13 commit）。

### 2.4 顺带必修项（否则拆分收益打折）

- **修复 L3 断链**（1.5）：让 `injectL3` 真正被调用，或删除索引中「完整知识由 L3 注入」的虚假承诺。
- **收敛优先级声明**（1.3）：全项目只允许 **一处**「最高优先级」，其余降级为显式序号。

---

## 3. 影响面与风险

| 项 | 说明 |
|---|---|
| 涉及模块 | 诊断、Skill 注入、教学状态机 —— **AGENTS.md 明列的必写 ADR 范围，本 ADR 为前置** |
| 行为风险 | 拆分必然改变模型行为 → 属高风险，需**生产模型重采样**对照（参照 ADR-C80 验收口径） |
| 测试 | `test/snapshots/skill_prompt_anchor.json` 锚点快照会全量失效，需重生并逐项说明差异 |
| 回退 | 保留 `buildSystemPromptV2` 原路径，以开关切换；回退不需改代码只切开关 |

## 4. 验收标准（建议）

1. 任一子 prompt ≤ 5 000 字符，全链路合计 ≤ 现有 66k 的 **40%**。
2. 全项目「最高优先级」声明唯一。
3. 生产模型重采样：教学主对话各模式（diagnosis/training/beginner）行为不劣于拆分前，逐场景对拍。
4. 六道门禁全绿 + 锚点快照重生且差异逐条说明。

## 5. 未决事项（待舰长裁决）

1. 是否立项、何时启动（当前 UI-AUDIT-V1 在途，资源是否冲突）。
2. 拆分粒度取 2.3 的 5 子代理，还是更保守的「先拆 diagnose 一个」试点。
3. 是否同步修复 L3 断链与优先级收敛，或留作独立批次。
