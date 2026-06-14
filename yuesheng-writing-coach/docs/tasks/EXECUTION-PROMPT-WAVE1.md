# 月笙写作教练 — 教学节奏重构 · 项目交接与执行指令

> **本文件用途**：将完整项目上下文交接给新的 AI 会话，使其能独立推进全部重构任务。
> **方案文档**：`docs/tasks/TEACHING-RHYTHM-RESTRUCTURE-PLAN.md`（9 阶段 39 项任务详情）
> **最终命名**：创始人已确认此为"架构重构"而非"功能改造"
> **已完成的准备工作**：前端代码清理（12 死文件/16 死 Action 已删）、数据流向审计（5 项修复）、三块地基代码验证

---

## 一、项目全景

### 1.1 一句话描述

月笙写作教练是一个 **Electron 桌面应用**，使用 LLM 驱动的一对一写作教学系统——不替用户写，通过诊断→教学→训练循环帮用户自己发现问题并提升写作能力。

### 1.2 技术栈

| 层 | 技术 | 备注 |
|----|------|------|
| 框架 | Electron 34 + React 18 | 主进程 + 渲染进程架构 |
| 语言 | TypeScript (strict mode) | 禁用 `any`、`@ts-ignore` |
| 构建 | Vite 8 | renderer 构建 + main 编译 |
| 状态管理 | Zustand | 14 个 store 文件，位于 `src/renderer/stores/` |
| 持久化 | SQLite (better-sqlite3) + electron-store | 结构化数据用 DB，配置用 electron-store |
| IPC 通信 | Electron ipcMain/ipcRenderer | 50 个 invoke 通道 + 5 个 event 通道，通道名集中在 `src/shared/constants.ts` |
| 测试 | vitest | 单元测试 |
| 样式 | CSS Modules | 每个组件独立 .module.css |
| 打包 | electron-builder | |

### 1.3 目录结构（关键部分）

```
D:\ai-teacher\yuesheng-writing-coach\
├── src/
│   ├── main/                          # 主进程（Node.js 环境）
│   │   ├── core/                      # 核心初始化（DB、状态机、IPC 注册）
│   │   │   └── app-initializer.ts     # DB 表创建逻辑
│   │   ├── domains/                   # 领域层（6 个收敛领域）
│   │   │   ├── teaching/teaching-state/   # 教学状态机
│   │   │   ├── prompt/                # Prompt 组装（loader + builder + dynamic-context）
│   │   │   ├── training/              # 训练记录服务
│   │   │   ├── chat/                  # 对话编排服务
│   │   │   ├── diagnosis/             # 诊断相关
│   │   │   └── growth/                # 成长系统
│   │   ├── ipc/                       # IPC handler 注册（单个通道对应一个 .handler.ts）
│   │   │   ├── config.handler.ts
│   │   │   └── ...
│   │   ├── services/                  # 全局服务（output-validator.ts 将建于此）
│   │   └── db/                        # SQLite 迁移脚本
│   ├── renderer/                      # 渲染进程（浏览器环境）
│   │   ├── components/                # React 组件
│   │   │   ├── layout/                # 布局组件（Solosidebar, SessionList 等）
│   │   │   └── manuscript/            # 手稿面板
│   │   ├── stores/                    # Zustand store（14 个）
│   │   │   ├── panel-session.store.ts # 右栏面板状态（关键：currentPhase/currentMode）
│   │   │   ├── session.store.ts       # 会话状态
│   │   │   ├── config.store.ts        # 配置状态
│   │   │   └── training.actions.ts    # 训练操作
│   │   └── shared/                    # 渲染进程共享类型
│   │       ├── types-training.ts      # 训练/训练记录类型
│   │       ├── types-teaching.ts      # 教学状态类型
│   │       └── types-ipc.ts           # IPC 事件类型
│   └── shared/                        # 主/渲染进程共享
│       ├── constants.ts               # IPC_CHANNELS 集中定义
│       └── api-contracts/             # API 契约（部分与 Handler 实际实现不匹配）
├── resources/
│   ├── config/                        # JSON 配置（~20 个文件）
│   │   ├── syndrome-type-map.json     # 症候类型映射
│   │   ├── technique-library.json     # 技法库（89+ 技法）
│   │   ├── teaching-strategies.json   # 教学策略
│   │   ├── codex-config.json          # Codex 配置
│   │   └── ...                        # 其他配置
│   ├── prompts/                       # Prompt 文件
│   │   ├── yuesheng-prompt-v3.md      # 核心 Prompt（V3.8, ~7200字）← 本次重构重点
│   │   ├── teaching-agent-prompt-v1.md# 教学 Agent Prompt（66 行）
│   │   ├── diagnosis-agent-prompt-v1.md
│   │   └── ...
│   └── references/                    # 参考材料
```

---

## 二、你需要理解的核心概念

### 2.1 当前架构瓶颈

**yuesheng-prompt-v3.md（7200 字）是一个单体巨人**，一个人承担 6 项职责：

| 职责 | 所在段落 | 字数占比 |
|------|---------|:--------:|
| 产品身份（4负4正） | §2.7 | ~15% |
| 教学策略（铁律/分层/自适应） | §三/§四 | ~25% |
| 态度档位 + 场景规则 | §五/§五附 | ~15% |
| 输出合规校验（V-01~V-09） | §八 | ~20% |
| 动作参考抽屉 | §九（按需提取） | ~10% |
| 从零构建引导 + 认知反馈 | §六/§七 | ~15% |

问题：**修改任何一项职责都需动整个文件**，风险波及全部 6 项。

### 2.2 重构核心方向：Prompt Skill化

不是"改 Prompt"，而是"解体 Prompt"——把规则变成配置，把角色变成 Skill，把知识变成引用。

```
当前（单体）                    未来（Skill化）
┌─────────────────────┐     ┌──────────────────┐
│ yuesheng-prompt-v3  │     │ Teacher Skill     │← 知识边界: 症候+技法+策略
│ (7200字, 6项职责)    │ ──→ ├──────────────────┤
│                     │     │ Assistant Skill   │← 知识边界: 训练库+概要症候
│ 改任何一项 → 动全文  │     ├──────────────────┤
└─────────────────────┘     │ Clown Skill       │← 知识边界: 仅激励话术
                             └──────────────────┘
                                   ↓ 共享同一套结构化配置
                             teaching-rules.json
                             attitude-rhythm.json
                             feedback-structure.json
                             role-schedules.json
```

**关键变化**：
- 规则从 Prompt 文本 → 结构化 JSON 配置（可独立修改、可测试）
- 角色从一段文字 → Skill 边界定义（各角色有自己的知识范围、Token 预算、上下文裁剪规则）
- Prompt 组装时从配置读取规则注入，不是从 v3.md 摘抄

### 2.3 教学状态机

状态位于 `src/main/domains/teaching/teaching-state/`，关键文件：

```
teaching-state-machine.constants.ts → PHASE_SUBPHASES 定义子阶段序列（数组）
teaching-state-machine.reflection.ts → reflection gate 使用 indexOf() 动态计算位置
```

子阶段序列（当前）：
```typescript
PRACTICE_LOOP: [
  PRACTICE_IDENTIFY,    // index 0
  PRACTICE_REFLECTION,  // index 1 ← reflection gate 用 indexOf() 定位
  PRACTICE_TEACHING,    // index 2
  PRACTICE_ASSIGN,      // index 3
  PRACTICE_REVIEW,      // index 4
]
```

重构后将插入 S2_GUIDE 子阶段，但 `indexOf()` 动态计算使其**无需硬编码修正**（已代码审计验证）。

### 2.4 IPC 模式

```typescript
// 通道名集中定义（src/shared/constants.ts）
IPC_CHANNELS.CHAT_SEND    = 'chat:send'
IPC_CHANNELS.DIAGNOSIS_GET = 'diagnosis:get'
IPC_CHANNELS.CONFIG_GET    = 'config:get'

// Handler 统一使用 createHandler 包裹，返回 { success, data } 或 { success: false, error, message }
// 注意：ConfigApi Contract 与 Handler 实际实现不匹配（Contract 设计新，Handler 实现旧）
// 使用 IPC_CHANNELS.CONFIG_GET + { key: 'xxx' } payload 格式（Handler 期望的格式）
```

### 2.5 状态管理（Zustand）

```typescript
// panel-session.store.ts — 右栏面板状态
// 注意：当前没有 sidebarPhase / sidebarMode 字段（从零创建）
interface PanelSessionState {
  currentPanel: 'chat' | 'diagnosis' | 'training' | 'growth';
  // F-01 将新增 sidebarPhase（引导/教学/训练/完成）
  // I-03 将新增 sidebarMode（日常/比对/模板）
}
```

### 2.6 训练记录

```typescript
// types-training.ts TrainingRecord
interface TrainingRecord {
  id: string;
  sessionId: string;
  taskId: string;
  syndromeId: string;
  status: string;           // 'assigned' | 'completed' | 'skipped'
  effectiveness: number;    // 0-1
  score?: number | null;    // 1-10（非 0-100）
  // G-01 将新增:
  taskType?: 'writing' | 'reading' | 'reflection' | 'technique';
}
```

### 2.7 工程约束（必须遵守）

| 维度 | 上限 | 说明 |
|------|:----:|------|
| 单文件 | ≤ 300 行 | 超限需拆分子组件 |
| 单函数 | ≤ 50 行 | 超限需提取子函数 |
| 超 500 行 | 🔴 **错误** | 必须拆分 |
| IPC channel | `domain:verb` 格式 | 如 `chat:send`，在 constants.ts 定义 |
| Handler | 入参必须校验 | 使用 validatePayload<T>() |
| 密钥 | **禁止硬编码** | 使用 process.env（R-029） |
| 导出 | **禁用** `export default` | 使用具名导出 |
| 命名 | `camelCase` / `UPPER_SNAKE` / `PascalCase` | 对应的三种场景 |

---

## 三、已经完成的工作（当前 Git 状态）

这些是提交到 main 分支的，新 AI **不需要**重复做：

### 3.1 已完成的健康修复

- ✅ 数据流审计：5 项差距（teachingState 数据形状、IPC 调用方式、diagnosis-dedup、unknown 类型、文档标注）
- ✅ 前端代码清理：删除 12 个死文件、移除 16 个死 Action、移除 1 个死函数
- ✅ 修复 diagnosis:update IPC 数据格式不匹配
- ✅ 修复对话列表 mount 时不加载
- ✅ 修复编辑器设置弹出层定位异常
- ✅ 补充 16 处 aria-label

### 3.2 已完成的三块地基验证

| 验证项 | 结论 | 对重构的影响 |
|--------|------|-------------|
| panelStore 是否有 sidebarPhase/sidebarMode | **无** → 从零创建 | F-01 / I-03 从零实现 |
| training_records.score 范围 | **1-10**（非 0-100） | MasteryGate 需映射：>9.0 = >90%，<4.0 = <40% |
| PHASE_SUBPHASES 子阶段定位 | **indexOf() 动态计算** | **G-06 不需要**（已移除） |

### 3.3 已完成的关键决策

- ✅ 方案名称从"改造"改"重构"（风险级别锚定）
- ✅ E-08（三 store 协调协议 + IPC 契约统一）从第四波**提前到第一波**
- ✅ G-06（反思门控 index 偏移）**标记为已移除**
- ✅ 删除全部"最后一次""终极"叙事
- ✅ A 阶段从"Prompt 约束收紧"改为**"Prompt Skill化 规则提取与配置化"**
- ✅ A-04 从"拆成三份 Prompt"改为**"三 Skill 边界定义"**

---

## 四、重构总览（9 阶段 39 项任务）

### 阶段 A：Prompt Skill化 — 规则提取与配置化（第一波）
| ID | 任务 | 核心动作 |
|:--:|------|---------|
| A-01 | teaching-rules.json 规则提取 | 将 V-01~V-09 从 v3.md 提取为结构化 JSON |
| A-02 | attitude-rhythm.json 规则提取 | 态度↔节奏映射从 v3.md 提取为配置 |
| A-03 | feedback-structure.json 规则提取 | 三明治反馈话术结构提取为配置 |
| A-04 | 角色 Skill 拆分 | 三分 Prompt → 三 Skill 边界定义（knowledgeBoundary / tokenBudget / contextRetention） |
| A-05 | 配置驱动输出验证器 | 读取上述配置做验证，新增规则只需改配置 |

### 阶段 B：教学状态机改造（第二波，依赖 A 完成）
| ID | 任务 | 依赖 |
|:--:|------|:----:|
| B-01 | S2_GUIDE 子阶段 + MasteryGate | G-03 常量层就绪 |
| B-02 | 阅读前置决策点 | B-01 就绪 |

### 阶段 C：训练/阅读库扩充
| ID | 任务 | 核心动作 |
|:--:|------|---------|
| C-01a | 通用训练库结构骨架 | 独立 |
| C-01b | 训练库内容填充 | 等待 D 产出 |
| C-02a | 阅读任务库结构骨架 | 独立，含 READING_STEPS 常量 |
| C-02b | 阅读库内容填充 | 等待 D 产出 |

### 阶段 D：第三次蒸馏（核心前置）
| ID | 任务 |
|:--:|------|
| D-01 | 蒸馏先导探测（网络搜索 100 条素材） |
| D-02~D-07 | 症候/技法/教学库交叉验证（6 项） |

### 阶段 E：遗留问题（穿插执行）
| ID | 任务 | 优先级 |
|:--:|------|:------:|
| E-01~E-03 | 独立遗留问题 | P2 |
| E-04 | WCAG AA 对比度修复 + CI a11y 检测 | P1 |
| E-05~E-06 | 独立遗留问题 | P2 |
| E-07 | 阅读推荐闭环 | P1（依赖 B-02）|
| **E-08** | **三 store 协调协议 + IPC 契约统一 + feature-flags** | **P0（已提前）** |

### 阶段 F：右边栏渐进式披露（依赖 B 阶段事件）
| ID | 任务 |
|:--:|------|
| F-01 | 侧边栏阶段管理（sidebarPhase） |
| F-02 | "常见问题"渐进披露 |
| F-03 | 训练卡延期 + 阅读提醒 |
| F-04 | 分级提示 + 战争迷雾 |

### 阶段 G：数据层改造
| ID | 任务 |
|:--:|------|
| G-01 | **DB Migration（task_type 列）** |
| G-02 | 训练记录契约/类型同步 |
| G-03 | TeachingState 常量层扩展（B-01 前置） |
| G-04 | 症候配置 discoverable 字段 |
| G-05 | 技法库 discoverable 字段 |
| ~~G-06~~ | ~~反思门控 index 偏移~~ 🔴 已移除 |
| G-07 | 操作审计日志 |

### 阶段 H：右边栏标签页重构（第一波可做）
| ID | 任务 |
|:--:|------|
| H-01 | **删除空标签页**（零依赖）|
| H-02 | 重命名成长记录 |
| H-03 | 诊断对比视图 |

### 阶段 I：对话栏按钮精简 + 模板辅助
| ID | 任务 |
|:--:|------|
| I-01 | 对话栏按钮精简 |
| I-02 | 快速模板选择器 |
| I-03 | 辅助模式切换（sidebarMode） |
| I-04 | 模板管理系统 |

---

## 五、第一波执行（可全并行，5+1 项）

以下 6 个任务**无依赖关系**，可同时执行：

### │ 任务 A-01：创建 teaching-rules.json

**改动文件**（新建/修改）：
- `resources/config/teaching-rules.json`（新建）
- `resources/prompts/yuesheng-prompt-v3.md`（§八 精简）
- `src/main/domains/prompt/prompt-loader.ts`（新增 injectRulesConfig 方法）

**配置结构**（每条规则）：
```typescript
{
  id: 'V-01',          // V-01 ~ V-09
  level: 'fatal' | 'warning' | 'suggestion',
  description: '规则中文描述',
  detectPattern: { type: 'regex' | 'keyword' | 'llm', patterns: string[] },
  applicableRoles: ['teacher', 'assistant', 'clown'],
  examples: { bad: string[], good: string[] },
  testCases: [{ input: string, expected: 'pass'|'fail', matchedRules?: string[] }]
}
```

**V-01 ~ V-09 内容来源**（从 v3.md §八 行 342-389 提取）：

| ID | 级别 | 内容 | 检测方式 |
|:--:|:----:|------|:--------:|
| V-01 | fatal | 禁止替用户写完整句子/段落（>50字连续改写） | regex: `.{51,}` |
| V-02 | fatal | 禁止替用户做决定（"你应该/务必/一定/最好/肯定"） | keyword |
| V-03 | warning | 禁止暴露内部编号（P001~P010 / A001~A012 等） | keyword |
| V-04 | warning | 语气档位一致性（sensei 禁"哈哈/呢~" 等） | regex |
| V-05 | suggestion | 单次回复不超过 4 段 | regex: 段落计数 |
| V-06 | suggestion | 单次回复不超过 3 个具体建议 | llm: 建议数量判定 |
| V-07 | warning | 安全词降档确认（"轻一点"后必须更温和） | keyword |
| V-08 | suggestion | 引用格式规范（`[[chapter:标题]]`） | regex |
| V-09 | fatal | 产品身份合规（不得 AI 写/续写/描写/润色） | keyword |

**v3.md §八 操作**：从 ~1500 字精简为 ~200 字引用段 + `{teaching_rules_ref}` 占位符

**prompt-loader.ts 操作**：新增 `injectRulesConfig()` → 读取 JSON → 按角色过滤 → 替换占位符

---

### │ 任务 A-02：创建 attitude-rhythm.json

**改动文件**：
- `resources/config/attitude-rhythm.json`（新建）
- `resources/prompts/yuesheng-prompt-v3.md`（§五 精简）
- `src/main/domains/prompt/prompt-builder.ts`（新增方法）

**节奏参数表**（新设计）：

| 参数 | 豆包 🟢 | 月笙 🟡 | sensei 🔴 |
|------|:-------:|:--------:|:---------:|
| 教学节奏 | slow | medium | fast |
| 引导强度 | 0.85 | 0.55 | 0.25 |
| 阅读前置 | must | recommend | skip |
| 每轮最大提问数 | 3 | 2 | 1 |
| 反思门控轮次上限 | 4 | 3 | 2 |

**v3.md §五 操作**：从 ~400 字精简为 ~100 字表格 + `{attitude_rhythm_ref}`

**prompt-builder.ts 操作**：新增 `buildAttitudeRhythmSection(attitude)` → 读 JSON → 格式化文本注入

---

### │ 任务 A-03：创建 feedback-structure.json

**改动文件**：
- `resources/config/feedback-structure.json`（新建）
- `resources/prompts/yuesheng-prompt-v3.md`（三明治规则 → 占位符）
- `resources/prompts/teaching-agent-prompt.md`（同步引用）
- `src/main/domains/prompt/prompt-builder.ts`（新增方法）

**三段式结构**：

| 阶段 | 目标 | 禁止 | 示例好 |
|:----:|------|------|--------|
| ① Praise | 具体肯定亮点（引用户文本+技法） | "写得不错"泛泛而谈 | "你这段比喻很精准" |
| ② Question | 用提问指出问题，2-3个方向 | 断言批评"你这样写不对" | "视角切换是困惑还是有意？" |
| ③ Direction | 给方法方向，不给成品 | >50 字改写示例 | "可以试试用对比手法" |

**配置结构**：
```typescript
{ structure: [{ phase, order, mandatory, goal, forbiddenBehaviors, allowedPatterns, maxTokens, applicableRoles, examples }], generalRules: { ... } }
```

---

### │ 任务 A-04：创建角色 Skill 配置

**改动文件**（新建 7 个文件 + 修改 2 个文件）：
- `resources/config/role-skills/teacher.skill.json`（新建）
- `resources/config/role-skills/assistant.skill.json`（新建）
- `resources/config/role-skills/clown.skill.json`（新建）
- `resources/config/role-schedules.json`（新建）
- `resources/prompts/teacher-prompt.md`（新建）
- `resources/prompts/assistant-prompt.md`（新建）
- `resources/prompts/clown-prompt.md`（新建）
- `src/shared/types.ts`（新增 TeachingRole 类型 + RoleSkillConfig 接口）
- `src/main/domains/prompt/prompt-loader.ts`（新增 selectRoleSkill 方法）
- `resources/prompts/teaching-agent-prompt.md` 保留为索引/降级入口

**三个 Skill 的角色边界**：

| 维度 | Teacher | Assistant | Clown |
|:----:|:-------:|:---------:|:-----:|
| 风格 | 严肃准确 | 亲和引导 | 幽默温暖 |
| 知识源 | 症候+技法+策略 | 训练库+症候概要 | 仅激励话术 |
| Token 预算 | 高（6轮） | 中（4轮） | 低（2轮） |
| 上下文保留 | 全部症候段落 | 训练相关段落 | 破冰段，裁诊断/教学历史 |

**role-schedules.json**：状态机阶段→角色映射，如 `S2_GUIDE → assistant`、`S2_TEACHING → teacher`、`S2_REVIEW → clown`

**SelectRoleSkill 方法**：读 schedule → 匹配当前 subphase → 获取 roleId → 读 skill.json → 只注入该角色允许的知识

**上下文裁剪规则**：角色切换时只保留目标角色允许的对话历史，删除其他角色的知识污染（Teacher 的严肃不被 Clown 历史污染）。

---

### │ 任务 G-01：DB Migration（task_type 列）

**改动文件**：
- `src/main/core/app-initializer.ts`（表定义加列）
- `src/main/db/020_db_add_task_type.sql`（新建迁移脚本）
- `src/renderer/shared/types-training.ts`（TrainingRecord 加 taskType 字段）

**SQL 改动**：
```sql
-- app-initializer.ts 中 CREATE TABLE 加列（新表用）
task_type TEXT NOT NULL DEFAULT 'writing' CHECK(task_type IN ('writing','reading','reflection','technique'))

-- 迁移脚本（旧库升级用）
ALTER TABLE user_training_records ADD COLUMN task_type TEXT NOT NULL DEFAULT 'writing';
```

**TaskType 枚举**：`'writing'`（写作训练，默认）/ `'reading'`（阅读任务）/ `'reflection'`（反思自评）/ `'technique'`（技法练习）

**类型同步**：TrainingRecord 接口新增 `taskType?: 'writing' | 'reading' | 'reflection' | 'technique'`

---

### │ 任务 H-01：删除空标签页（零依赖）

**目标**：删除右边栏中已确认空的标签页组件，只保留有实际内容的标签。

**动作**：检查 `src/renderer/components/` 下右边栏标签页组件，删除无内容的标签页及其路由/按钮引用。确认哪些标签页有内容、哪些是空壳。

---

### ▶ 执行顺序建议

```
第一阶段（全并行，6 项）
  A-01 teaching-rules.json  ← 先于此阶段其他任务的代码改动
  A-02 attitude-rhythm.json
  A-03 feedback-structure.json
  A-04 角色 Skill 拆分
  G-01 DB Migration + 类型同步
  H-01 删除空标签页

第二阶段（A-01~A-04 就绪后）
  A-05 配置驱动输出验证器 ─ 纯函数，单元测试可脱机
  E-08 三 store 协调协议 + IPC 契约统一 + feature-flags ─ P0 任务
  G-03 TeachingState 常量层扩展 ─ B-01 前置条件

第三阶段（G-03 就绪后）
  B-01 S2_GUIDE 状态机改造 + MasteryGate ─ 核心状态机改动
  C-01a 通用训练库结构骨架 ─ 独立
  C-02a 阅读任务库结构骨架 ─ 独立
  D-01 蒸馏先导探测 ─ 网络搜索

后续阶段按方案文档依赖图推进
```

---

## 六、关键文件索引（快速参考）

| 你要找什么 | 在哪里 |
|-----------|--------|
| 方案文档（完整版） | `docs/tasks/TEACHING-RHYTHM-RESTRUCTURE-PLAN.md` |
| IPC 通道名 | `src/shared/constants.ts` |
| 状态机常量 | `src/main/domains/teaching/teaching-state/teaching-state-machine.constants.ts` |
| 状态机反射门控 | `src/main/domains/teaching/teaching-state/teaching-state-machine.reflection.ts` |
| 训练记录服务 | `src/main/domains/training/training-record.service.ts` |
| DB 初始化 | `src/main/core/app-initializer.ts`（行 138-154 训练记录表） |
| DB 迁移脚本 | `src/main/db/` |
| 核心 Prompt | `resources/prompts/yuesheng-prompt-v3.md` |
| 教学 Agent Prompt | `resources/prompts/teaching-agent-prompt-v1.md` |
| Prompt 组装 | `src/main/domains/prompt/prompt-loader.ts` |
| Prompt 构建 | `src/main/domains/prompt/prompt-builder.ts` |
| 动态上下文 | `src/main/domains/prompt/dynamic-context.service.ts` |
| 症候配置 | `resources/config/syndrome-type-map.json` |
| 技法库 | `resources/config/technique-library.json` |
| 训练记录类型 | `src/renderer/shared/types-training.ts` |
| 教学状态类型 | `src/renderer/shared/types-teaching.ts` |
| IPC 事件类型 | `src/renderer/shared/types-ipc.ts` |
| 面板状态 Store | `src/renderer/stores/panel-session.store.ts` |
| 会话 Store | `src/renderer/stores/session.store.ts` |
| 训练 Action | `src/renderer/stores/training.actions.ts` |
| 类型检查 | 运行 `npx tsc --noEmit` |
| 单元测试 | 运行 `npx vitest run` |
| 行数检查 | 运行 `npm run check:size` |

---

## 七、每次提交前的确检查清

```
□ tsc --noEmit 0 错误？
□ 没有修改任务范围外的文件？
□ 没有硬编码 API Key / Token？
□ 没有使用 any 或 @ts-ignore？
□ 没有 export default（用具名导出）？
□ 新 JSON 配置文件在 resources/config/ 下？
□ DB 迁移脚本在 src/main/db/ 下？
□ commit 信息格式正确（feat/refactor/fix + scope + subject）？
```

---

> **本项目命名约定**
> - 变量/函数：`camelCase`
> - 常量：`UPPER_SNAKE_CASE`
> - 类/接口/类型：`PascalCase`
> - 文件/目录：`kebab-case`
> - CSS 类名：`camelCase`
>
> **特别提醒**
> - 不要重构 yuesheng-prompt-v3.md 中未在任务列表中的段落
> - IPC channel 必须使用 `src/shared/constants.ts` 中定义的常量，不要硬编码字符串
> - 任何新配置必须添加 discoverable 字段时参考现有的 syndrome-type-map.json 格式
