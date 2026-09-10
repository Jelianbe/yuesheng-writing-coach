# 月笙写作教练（Electron 原型 · 已归档）

> ⚠️ **归档状态（2026-08 起）**：本目录为早期 Electron + React 原型，**已停止开发**。
> 产品真源已迁移至 [`yuesheng-flutter/`](../yuesheng-flutter/)（Flutter + Dart），所有开发与维护均在新目录进行。
> 本 README 仅作历史参考，不再更新。

---

## 历史简介（2026-06 时代）

早期原型：AI 驱动的中文小说写作辅导工具，定位「写作教练，不是写作助手」——不替用户写句子，通过诊断 → 教学 → 训练 → 复盘的闭环识别写作系统性问题并提供训练。

当时实现的核心链路：

- 五阶段教学状态机（初始→教学→训练→评估→复盘）
- 诊断引擎（症候识别 P001–P007 并排序）
- 五步训练流（解说→例证→确认→尝试→反馈）+ 技法库
- 能力图谱与训练推荐
- 学生模型（localStorage + Prompt 注入）

## 历史技术栈

| 层 | 技术 |
|:---|:-----|
| 前端框架 | Electron + React 18 + TypeScript (strict) |
| 状态管理 | Zustand + persist middleware |
| 样式 | CSS Modules + 设计 token（金棕暖灰体系） |
| 持久化 | SQLite (better-sqlite3) + Knex migration |
| 构建/测试 | Vite + tsc / Vitest + @testing-library/react |
| LLM | DeepSeek Chat API |

架构：Renderer Process（左中右三栏）+ Main Process（IPC Handlers + Services），Renderer 不直连数据库或 LLM（IPC 隔离）。

---

## 为什么迁移到 Flutter

主力工程已迁移至 `yuesheng-flutter/`，原因包括：

- 移动端发布与跨平台一致性需求（Electron 仅限桌面）
- 技术栈统一为 Dart（状态管理 Riverpod + 本地持久化 drift/SQLite）
- 工程纪律升级：六道质量门禁、函数行数硬上限等规范

> **注意**：本目录中代码涉及的症候编号体系（P001–P007）与当前真源（P001–P041）已不一致，一切以 `yuesheng-flutter/` 为准。
