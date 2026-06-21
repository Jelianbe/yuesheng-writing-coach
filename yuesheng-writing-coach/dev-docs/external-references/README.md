# 外部参考索引

> 本目录存放项目开发过程中收集的外部参考材料，作为 X-01 外部项目研究的补充输入。
> 每份材料标注了来源、用途和与月笙项目相关度。

---

## INKOS + OpenWrite 外部项目源码（2026-06-20 收录）

**来源**: GitHub 开源项目（AGPL-3.0 许可）

**相关度**: 高 — 与月笙项目的多 Agent 架构、Codex UI、BYOK AI 助手、编辑器设计高度相关

| 材料 | 类型 | 说明 | 对应报告 |
|:-----|:-----|:------|:---------|
| `inkos-core-extracted/` | 目录 | INKOS 核心包解压（完整 dist + .d.ts 类型定义） | [FB20260620-001 报告](../../docs/reports/FB20260620-001-外部项目研究报告.md) |
| `inkos-cli-extracted/` | 目录 | INKOS CLI 包解压（25+ 命令 + TUI） | 同上 |
| `inkos-cli-source/` | 目录 | INKOS CLI 源码（package.json + LICENSE） | 同上 |
| `actalk-inkos-1.5.0.tgz` | 归档 | INKOS CLI npm 包原始 tgz | 同上 |
| `actalk-inkos-core-1.5.0.tgz` | 归档 | INKOS Core npm 包原始 tgz | 同上 |
| `inkos-source/` | 预留 | INKOS 完整 git clone 目标位置 | 第二阶段 |
| `openwrite-source/` | 预留 | OpenWrite 完整 git clone 目标位置 | 第二阶段 |

**相关链接**:
- [INKOS GitHub](https://github.com/Narcooo/inkos) — 1.9k stars
- [OpenWrite GitHub](https://github.com/ilrein/openwrite) — ~10 stars
- [研究报告](../../docs/reports/FB20260620-001-外部项目研究报告.md)

---

## CYS 同学总结（2026-06-19 收录）

**来源**: CYS 同学整理的 AI IDE 工程规范总结

**相关度**: 高 — 与月笙项目的 R-XXX 规则体系、Phase J 前端迁移、IPC 安全防线高度吻合

| 文件 | 主题 | 对应月笙模块 | 建议用途 |
|:-----|:-----|:-------------|:---------|
| `1.宪法规则.txt` | Agent 协作宪法 | AGENTS.md + R-XXX 体系 | 借鉴"完成标准"12 条补充 R-027 门禁 |
| `2.SKILL纲要.txt` | 场景→Skill 映射 | 可用 Skill 列表 | X-03 Skill 集成时参考场景映射方法 |
| `3.立项.txt` | 立项流程与标准 | `.specify/` + `dev-docs/designs/` | 流程参考 |
| `4.技术栈选择与确立流程.txt` | 技术选型决策 | 通用参考 | 以后新项目参考 |
| `5.Git的使用方式与流程.txt` | Git 操作规范 | R-016 Git 提交规范 | 补充参考 |
| `6.前端框架搭建规则与流程.txt` | **前端骨架 6 步法** | **Phase J React 迁移** | **核心参考 — J 阶段执行前阅读** |
| `7.数据库设计规范与搭建流程.txt` | 数据库设计 | 后续构建参考 | 通用参考 |
| `8.后端业务边界界定与规则梳理流程.txt` | 后端模块划分 | Phase I 后端集成 | 参考 |
| `9.后端框架搭建规则与流程.txt` | 后端骨架搭建 | 通用参考 | 参考 |
| `10.验收规则与标准及流程.txt` | **验收 7 步法** | **Phase K 打磨收尾** | **核心参考 — 验收阶段引入** |
| `11.后端安全规范及流程.txt` | **安全 7 道防线** | **Phase I 安全加固** | **核心参考 — SEC-DEBT 修复后校验** |
