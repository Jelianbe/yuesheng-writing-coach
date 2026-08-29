# yuesheng-flutter 文档索引

> 本文件是 **Flutter 真源侧**的文档入口（对应仓库根 `AGENTS.md` 的第 2 层）。
> 上层入口：[`../../AGENTS.md`](../../AGENTS.md)（AI 协作规则入口，R-024）
> 规则全集：[`../../.trae/rules/`](../../.trae/rules/)

---

## 一、先确认你在对的项目里

| 目录 | 状态 |
|:--|:--|
| **`yuesheng-flutter/`** | ✅ **唯一活跃真源** — Flutter + Dart，所有开发在此 |
| `yuesheng-writing-coach/` | 归档维护 — Electron + React + TS，**已不再开发** |
| `yuesheng-android/` | 已废弃 |

> 历史文档（含旧版 README）多指向 Electron 目录，其技术栈与路径对本项目
> **均不适用**。遇到冲突以本文件与根目录 `AGENTS.md` 为准。

## 二、技术栈与门禁

- Flutter + Dart / Riverpod（状态管理）/ drift（SQLite 持久化）
- 测试：`flutter test --exclude-tags live,external --no-pub`（基线 **2035 用例**）
- Prompt 真源：`lib/services/skill_registry.dart` + 各 `skills_*.dart`

**四道门禁**（声称完成前必须全绿，详见 R-027）：

```bash
dart format --set-exit-if-changed -o none <改动文件>
flutter analyze lib --no-pub
python scripts/check_circular.py
flutter test --exclude-tags live,external --no-pub
```

## 三、文档地图

### 常读（入口级）

| 文档 | 用途 |
|:--|:--|
| [`待办执行清单.md`](待办执行清单.md) | **任务台账 / 批次记录 / 决策留痕**，改动前先查重 |
| [`启动提示词.md`](启动提示词.md) | 会话启动上下文 |
| [`yuesheng-flutter-宪法草案.md`](yuesheng-flutter-宪法草案.md) | 项目级约束与布防现状 |

### ADR（架构决策）

| 文档 | 主题 |
|:--|:--|
| [`ADR-skill-orthogonal-model.md`](ADR-skill-orthogonal-model.md) | Skill 正交模型 |
| [`ADR-knowledge-injection-driver-model.md`](ADR-knowledge-injection-driver-model.md) | 知识注入驱动模型 |
| [`ADR-capability-contracts.md`](ADR-capability-contracts.md) | 能力契约与依赖倒置 |
| [`ADR-P0-receipt-state.md`](ADR-P0-receipt-state.md) | 回执状态 |
| [`ADR-A2-stable-mention-id.md`](ADR-A2-stable-mention-id.md) | 稳定 mention id |
| [`ADR-A3-paragraph-anchor.md`](ADR-A3-paragraph-anchor.md) | 段落锚点 |

### 设计与审计

| 目录 | 内容 |
|:--|:--|
| [`designs/`](designs/) | 设计方案、拆分清单、溯源记录（含日期前缀的历史设计 27 份） |
| [`audits/`](audits/) | 体检 / 审计报告 |
| [`plans/`](plans/)、[`research/`](research/)、[`logs/`](logs/) | 计划、调研、日志 |

### 专项

| 文档 | 用途 |
|:--|:--|
| [`教学机制审查包.md`](教学机制审查包.md) | 教学机制审查 |
| [`内容层修正-执行提示词包.md`](内容层修正-执行提示词包.md) | 内容层修正 |
| [`txt-import-logic.md`](txt-import-logic.md) | 文本导入逻辑 |

## 四、Skill 体系

- **29 个已注册 Skill**，按 `group` 分 7 组：core / teaching / coaching /
  diagnosis / training / attitude / advanced
- 注册与调度：`lib/services/skill_registry.dart`、`skill_dispatcher.dart`
- 内容分片：`lib/services/skills_*.dart`（A 类纯常量，part 拆分豁免 R-019）
- **场景速查表**：[`tasks/SKILLS-QUICKREF.md`](tasks/SKILLS-QUICKREF.md)

## 五、流程模板（R-030）

| 文件 | 用途 |
|:--|:--|
| [`tasks/FEEDBACK-REPORT-TEMPLATE.md`](tasks/FEEDBACK-REPORT-TEMPLATE.md) | 反馈溯源报告模板（Step 1） |
| [`standards/CODE_REVIEW_CHECKLIST_V1.0.md`](standards/CODE_REVIEW_CHECKLIST_V1.0.md) | 代码审查清单（Step 4.5） |

## 六、规则索引（仓库根）

`.trae/rules/` 共 30 条。高频引用：

| 规则 | 主题 |
|:--|:--|
| R-009 / R-029 | 用户主权（L1）、安全与隐私（L1） |
| R-019 | 代码规范（**函数 ≤50 行**为硬上限；禁止 part/extension 伪拆分） |
| R-027 | AI 代码质量门禁（四道） |
| R-013 | 测试覆盖率 |
| R-028 | 防御性编码 |
| R-020 | 循环依赖零容忍 |
| R-010 / R-006 | 最小化范围、回退机制 |

## 七、已知债务与缺口

| 项 | 状态 |
|:--|:--|
| 76 个文件超 R-019 的 300 行 | 已登记；`chat_service.dart`（3004 行）为回退后的有意单体，真分解待 ADR |
| 12 个函数超 50 行（最长 293 行） | 已登记，见 [`audits/2026-08-29-app-health-check.md`](audits/2026-08-29-app-health-check.md) |
| UI 样式字面量：`fontSize` 485 / `fontWeight` 318 处 | 颜色层已 100% 令牌化；字号按 R-010 顺手迁移 |
| `feedback-cognition` 与 `coaching-rhythm §五` 内容重叠 | 未决，会导致重复注入 |

---

*建立：2026-08-29（原缺口：Flutter 侧长期无 README 索引，Electron 版的
`yuesheng-writing-coach/dev-docs/README.md` 不适用于本真源）。*
