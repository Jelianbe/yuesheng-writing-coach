---
name: "R-024-AGENTS.md机制"
description: "定义项目级 AI 规则入口文件（AGENTS.md）的创建、维护和触发机制。确保 AI 开发工具每次会话都能自动感知项目核心约束。"
alwaysApply: false
priority: "high"
trigger:
  - "AI 工具首次接入项目时"
  - "项目核心规则变更后"
  - "技术栈或构建命令变更后"
checkLogic:
  - "AGENTS.md 是否存在于项目根目录？"
  - "内容是否与 .trae/rules/ 核心规则一致？"
  - "技术栈与构建/测试命令是否仍有效？（本项目已迁至 Flutter）"
enforcement: "缺少 AGENTS.md 或内容过时时，AI 工具可能因无法感知项目约束而产生违规操作"
---

# R-024: AGENTS.md 机制

## 原则

**AI 工具不会读心。** 规则分散在 `.trae/rules/`、Skill 注册表、设计文档等
多个位置，AI 工具启动时不会自动扫描全部。需要一个统一入口文件——
**AGENTS.md**（跨工具通用名），让任何 AI 工具第一轮就能读到项目核心约束。

> ⚠️ **2026-08-29 重大修正**：本规则原附的 AGENTS.md 模板为 Electron/TS 版
> （Electron + React + Zustand + Vite/vitest + IPC 规范），与当前真源
> **完全不符**。技术栈迁移后入口文件未同步，导致 AI 首轮即读到错误约束。
> 现已更新为 Flutter 版模板，并同步刷新了根目录 `AGENTS.md`。

## 文件规范

### 位置
项目根目录：`d:\ai-teacher\AGENTS.md`

### 内容结构（不超过 200 行）

```markdown
# 月笙写作教练 — AI 协作规则入口

## 技术栈（当前真源）
- **Flutter + Dart** — 唯一活跃真源：`yuesheng-flutter/`
- 状态管理：Riverpod
- 持久化：drift（SQLite），生成文件 `database.g.dart` 勿手改
- 测试：flutter test（基线 2035 用例）
- 归档/维护模式：`yuesheng-writing-coach/`（Electron+React+TS，已不再开发）

## 核心禁止事项
1. 不替用户写句子或做决定（R-009 用户主权）
2. 不顺手格式化/重构任务范围外的文件（R-010）
3. 不新增 A→B 静态映射表
4. 不硬编码 API Key 或敏感配置（R-029）
5. 不引入当前未使用的新框架或第三方库

## 代码硬上限（R-019）
- **函数 ≤ 50 行（硬上限）**
- 文件 ≤ 300 行；服务层超限需 ADR 决策
- **禁止用 part/extension 机械拆分服务层凑行数**（X-025-ARCH 已定性为
  伪拆分并回退 13 个 commit）；真分解 = 独立类 / 显式接口 / 依赖注入
- UI 样式走 AppTextStyles 等设计令牌，不写裸字面量

## 边界防御（R-028）
- 边界层：Repository / LLM Client / 平台通道 / 表单
- 空 catch 禁止；确需静默降级必须留痕（decode_guard / ErrorHandler）

## 构建与测试（四道门禁，R-027）
- 格式：dart format --set-exit-if-changed -o none <改动文件>
- 静态分析：flutter analyze lib --no-pub
- 循环依赖：python scripts/check_circular.py
- 测试：flutter test --exclude-tags live,external --no-pub

## Prompt 入口规则
- 教练定位：不替写、不替决定、找根因
- 态度档位：豆包(默认) / 月笙如歌 / sensei
- 安全词："轻一点"无条件降档

## 不确定时的默认行为
- 风格冲突 → 沿用目标文件已有风格
- 多种实现方式 → 选最简单的那一个
- 改动范围有争议 → 只改最小必要范围
- 未验证的功能 → 必须明确声明"未验证"
```

### 维护义务

| 触发场景 | 维护动作 |
|---------|---------|
| 新增/修改 L1 核心规则 | 同步更新 AGENTS.md 对应章节 |
| **技术栈迁移 / 真源切换** | **必须重写技术栈与构建命令段**（本批次即因此触发） |
| 新增核心禁止事项 | 追加到禁止事项列表 |
| Prompt 行为规则变更 | 更新 Prompt 入口规则段 |
| 门禁命令变更（如新增检查项） | 同步四道门禁段 |

> 技术栈段是**最易腐化**的部分：它不随代码报错而暴露，只会静默误导。
> 每次规则复核都应优先核对这一段。

## 与 .trae/rules/ 的关系

```
AGENTS.md（入口摘要，≤200行）
    ↓ "详细规则见 .trae/rules/R-XXX"
.trae/rules/（完整规则集，每条可独立引用）
    ↓ 具体执行标准
代码/文档/Prompt（实际产出）
```

AGENTS.md 是**索引和摘要**，不是完整规则的替代。它解决的是"AI 第一眼能看到什么"的问题。

## 检查清单

```
□ AGENTS.md 是否存在于项目根目录？
□ 文件大小是否 ≤ 200 行？
□ 技术栈段是否描述的是当前真源（Flutter，非 Electron）？
□ 是否包含禁止事项/代码上限/边界防御/门禁命令四个核心段落？
□ 构建与测试命令是否可实际执行？（过期命令等于没有）
□ 内容是否与当前 .trae/rules/ 核心规则一致？
□ 最后更新日期是否在最近 30 天内？
```

## 与其他规则的协作

| 规则 | 关系 | 协作方式 |
|------|------|----------|
| R-028 防御性编码 | 依赖 | AGENTS.md 须摘要边界防御要求，作为 AI 第一眼可见的约束 |
| R-021 AI行为边界 | 被依赖 | AGENTS.md 的「核心禁止事项」段落来自 R-021 的边界定义 |
| R-029 安全与隐私 | 依赖 | AGENTS.md 须包含 R-029 核心安全规则（禁止硬编码 Key） |
| R-027 质量门禁 | 依赖 | AGENTS.md 的四道门禁命令须与 R-027 保持一致 |

## 优先级

高优先级 — AI 协作的第一道栅栏，降低误操作概率的基础设施
