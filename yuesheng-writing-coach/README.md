# 月笙写作教练

> AI 驱动的中文小说写作辅导工具 · 不替写、不替决定、找根因

月笙写作教练是一个面向中文小说写作者的 **AI 辅导工具**。它不代替你写句子，也不替你做创作决策——而是通过诊断 → 教学 → 训练 → 复盘的闭环，帮你识别写作中的系统性问题，并提供针对性的训练。

**定位**：写作教练，不是写作助手。不生成内容，只提升能力。

---

## 项目状态

**当前版本**：`1.3.0`（2026-06-23）· 内部预览阶段 · 私有仓库

| 维度 | 评估 | 说明 |
|:----|:----:|:------|
| **功能成熟度** | 🟡 Alpha | 核心诊断与训练链路已贯通，UI/UX 仍处于迭代中 |
| **前端质量** | 🟢 Good | 审计评分 14.5/20（Accessibility 2.5 / Performance 3 / Theming 3.5 / Responsive 2 / Anti-Patterns 3.5） |
| **后端质量** | 🟢 Stable | typecheck 0 / 644+ tests pass / lint 0 errors |
| **安全** | 🟢 合规 | 零硬编码密钥，全部环境变量注入 |
| **UX 打磨** | 🟡 进行中 | Sprint 17 集中整改了 P0/P1 问题，剩余 P2 债务（~441 内联样式 / ~18 emoji 残留 / ~53 硬编码 hex） |

---

## 核心能力

### 已交付

| 能力 | 说明 | Sprint |
|:----|:-----|:------:|
| **诊断引擎** | 分析用户写作片段，识别症候（P001-P007）并排序 | S9 |
| **教学状态机** | 五阶段（初始→教学→训练→评估→复盘）驱动对话 | S9 |
| **五步训练流** | 解说→例证→确认→尝试→反馈，技法库动态填充 | S16 |
| **技法库** | ~100 条写作技法，按症候分类，支撑训练流 | S9+ |
| **Prompt 工程框架** | SkillDispatcher v2：依赖图 / 态度过滤 / 运行时条件 / 体积控制 | S14 |
| **三向 ID 映射** | 症候↔训练↔能力，打通诊断→教学→训练→画像全链路 | S15 |
| **能力图谱** | 8+ 能力节点，支撑训练推荐与进度追踪 | S15 |
| **训练推荐** | 基于诊断结果的针对性训练推荐列表 | S15 |
| **Workspace 注册表** | 右侧栏插件式扩展框架 | S13 |
| **学生模型（Phase 1）** | localStorage + Prompt 注入 | S12 |

### 开发中 / 待修复

| 问题 | 级别 | 说明 |
|:----|:----:|:------|
| **~441 内联样式 → CSS Modules** | P2 | `ChapterEditor` 等组件内 `style={{}}` 需迁移 |
| **~53 硬编码 hex → CSS 变量** | P2 | 部分组件仍用硬编码色值 |
| **~18 emoji 残留 → lucide-react** | P2 | 文本内 emoji 未全部替换 |
| **13 个 ARIA label 缺失** | P2 | a11y 待补全 |
| **Tailwind 包保留观察** | — | 代码已迁移完毕，包 1 sprint 后删除 |
| **BL-22 better-sqlite3 双版本** | P1 | Electron 与 Node.js 需分别 rebuild |

---

## 技术栈

| 层 | 技术 |
|:---|:-----|
| 前端框架 | Electron + React 18 + TypeScript (strict) |
| 状态管理 | Zustand + persist middleware |
| 样式 | **CSS Modules** + design tokens（金棕暖灰体系） |
| 持久化 | SQLite (better-sqlite3) + Knex migration |
| 构建 | Vite + tsc |
| 测试 | Vitest + @testing-library/react + user-event v14 |
| 质量门禁 | typecheck 0 / test pass / lint 0 / 安全 0 硬编码 |
| 包管理 | npm |

---

## 架构概览

```
┌─────────────────────────────────────────────────┐
│  Renderer Process (Electron)                     │
│  ┌─────────────┐  ┌──────────────────────────┐  │
│  │  Left Panel  │  │  Center Panel             │  │
│  │  (工具网格)    │  │  ├─ ChatView (诊断会话)    │  │
│  │              │  │  └─ TrainingWorkshop      │  │
│  │  技法目录     │  │     ├─ 推荐列表           │  │
│  │  教学进度     │  │     ├─ FiveStepFlow      │  │
│  │  学习日志     │  │     └─ 历史记录           │  │
│  │  作品管理     │  └──────────────────────────┘  │
│  │  教学笔记     │                               │
│  │  设置        │                               │
│  │  发展路径     │                               │
│  └─────────────┘                               │
│         │ IPC (typed channels)                  │
├─────────┼───────────────────────────────────────┤
│  Main Process (Electron)                        │
│  ┌───────────────┐  ┌─────────────────────────┐ │
│  │ IPC Handlers   │  │  Services               │ │
│  │  training:*    │  │  ├─ TrainingFlowService │ │
│  │  session:*     │  │  ├─ DiagnosisService    │ │
│  │  diagnosis:*   │  │  ├─ TeachingStateMachine│ │
│  │  prescription:*│  │  └─ EvaluatorAgent      │ │
│  └───────────────┘  └─────────────────────────┘ │
│                           │                      │
│                    ┌──────┴──────┐               │
│                    │   SQLite    │               │
│                    └─────────────┘               │
└─────────────────────────────────────────────────┘
         │
         │ LLM API (DeepSeek Chat)
         ▼
   ┌──────────┐
   │  AI 模型  │
   └──────────┘
```

### 关键设计原则

- **IPC 隔离**：Renderer 通过 typed IPC channels 访问 main process，不直连数据库或 LLM
- **Prompt 工程**：所有 AI 提示词用四段式结构（Identity/Context/Tasks/Output），SkillDispatcher v2 管理依赖
- **设计 token 体系**：金棕暖灰 + 暖纸美学，全部样式通过 CSS 变量控制
- **五步教学协议**：解说→例证→确认→尝试→反馈，与具体写作领域解耦

---

## 快速开始

### 前置依赖

- Node.js 18+
- Electron 相关系统库（Windows 下通常无需额外安装）

### 安装与运行

```bash
# 克隆
git clone https://github.com/Jelianbe/yuesheng-writing-coach.git
cd yuesheng-writing-coach

# 安装依赖
npm install

# 开发模式（Vite HMR + Electron 并行）
npm run dev

# 浏览器预览（仅 UI，无 Electron IPC）
npm run dev:vite
# 然后访问 http://localhost:5173
```

> **注意**：浏览器预览模式下，技法目录详情等依赖 Electron IPC 的功能不可用。完整体验需使用 Electron 窗口。

### 构建

```bash
npm run build
```

### 质量门禁

```bash
npm run typecheck   # TypeScript 严格检查
npm run test        # 单元测试（644+）
npm run lint        # ESLint 检查
```

---

## 版本历史

| 版本 | 日期 | 主要内容 |
|:----:|:----:|:---------|
| 1.3.0 | 2026-06-23 | Tailwind 全量迁移 + 审计 14/20 + Catalog IPC 包裹层修复 + ToolGrid 重构 + Catalog 类名适配 |
| 1.2.0 | 2026-06-23 | P0/P1 前端整改：CSS 模块化 / Zustand 选择子 / emoji → lucide / rAF 节流 / 测试启用 |
| 1.1.0 | 2026-06-23 | 五步训练流贯通 + 技法库填充 + 22 单元测试 |
| 1.0.0 | 2026-06-22 | 首版：诊断引擎 + 教学状态机 + 基础 Chat |
| <1.0 | 2026-05~06 | 原型阶段，14 个 Sprint 迭代 |

---

## 项目路线图

### Sprint 18（计划）

| 优先级 | 任务 | 类型 | 估时 |
|:-----:|:----|:----:|:----:|
| P1 | attitude 透传改造（T15-1） | 新功能 | 1d |
| P1 | SKILL 文件补充 conditions（T15-2） | 改进 | 0.5d |
| P1 | 7 个 workspace 组件化（BL-19） | 功能 | 1d |
| P1 | 内联样式迁移（分批） | 债务 | ~2d |
| P2 | ~53 硬编码 hex → CSS 变量 | 债务 | 0.5d |
| P2 | 13 ARIA label 补全 | a11y | 0.3d |
| P2 | ~18 emoji → lucide | 样式 | 0.2d |
| - | Tailwind 包确认无回归后删除 | 清理 | 0.1d |

### 后续

- P008/T016 症候补全（D-DEBT-19）
- v5 vs dispatcher v2 A/B 灰度
- 训练推荐边界测试（D-DEBT-21）
- IPC 调用全面审计（createHandler 包裹层一致性）
- ActiveProblem 字段统一（D-DEBT-20）
- 61 条 heuristic 二次精标（D-DEBT-18）

---

## 贡献与反馈

本项目目前为**内部预览阶段**，未开放公开贡献。如果你受邀审查，欢迎：

1. 在 GitHub Issues 提交 bug 或建议
2. 直接 PR 到 `main` 分支做代码审查
3. 关注项目的 DEV.md 和决策日志了解设计上下文

---

## 协议

MIT License

---

*月笙写作教练 · AI 不替你写，但帮你会写*
