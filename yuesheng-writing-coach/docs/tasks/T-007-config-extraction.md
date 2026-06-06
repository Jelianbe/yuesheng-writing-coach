# T-007: Config 配置层提取

## 基本信息
- **优先级**: P0（阻塞链 — 无此基础，Strategy Service 无法实现）
- **状态**: ready
- **预估工时**: 1-2 天
- **依赖**: 无（首个任务）

## 目标
将散落在 md 文档中的教学知识提取为结构化 JSON 配置文件，为后续所有 Service 提供数据基础。

## 前后端分工
| 层 | 工作内容 | 涉及文件 |
|---|---------|---------|
| 数据 | 从 md 提取教学知识为结构化 JSON | `resources/config/*.json` |
| 前端 | 无 | — |

## 设计依据
- **技术规格**: [teaching-knowledge-bridge_V1.0.md](../design/teaching-knowledge-bridge_V1.0.md) §三（数据配置层）、§七 Phase A
- **来源任务**: T-006（独立新链的起点）

## 涉及文件

| 文件路径 | 改动类型 | 来源文档 |
|---------|---------|---------|
| `resources/config/teaching-strategies.json` | 新增 | SPEC_adaptive-teaching_V1.0.md（三模式触发条件） |
| `resources/config/user-type-matrix.json` | 新增 | teaching-strategy-notes.md（用户类型→教学方式映射） |
| `resources/config/problem-tiering.json` | 新增 | syndrome-manual.md（问题分级：致命/结构/皮肤） |
| `resources/config/challenge-templates.json` | 新增 | action-library.md（Challenge-Unlock 模板，T-013 用） |

## Json Schema 规范

每个 JSON 文件必须附带一段 JSDoc 注释说明来源，结构示例：

```json
// resources/config/problem-tiering.json
{
  "$schema": "problem-tiering-schema.json",
  "$source": "synrome-manual.md §2 '问题分级'",
  "tiers": [
    { "level": "fatal", "syndromes": ["P002", "P009"], "action": "must_fix", "description": "致命伤 — 优先处理" },
    { "level": "structural", "syndromes": ["P001", "P004", "P005", "P006"], "action": "priority", "description": "结构病 — 次优先" },
    { "level": "surface", "syndromes": ["P003", "P007", "P010"], "action": "deferrable", "description": "皮肤症 — 可推迟" }
  ],
  "maxPerTurn": 1,
  "principle": "一次只说一个问题 — design-philosophy_V1.0.md"
}
```

## 涉及来源文档

提取前需完整阅读以下文档：

| 文档路径 | 提取内容 | 章节 |
|---------|---------|------|
| `docs/specs/SPEC_adaptive-teaching_V1.0.md` | 三模式触发条件 | §4.1-4.3 |
| `docs/notes/teaching-strategy-notes.md` | 用户类型映射 | 全文 |
| `resources/prompts/syndrome-manual.md` | 问题分级 | §2 |
| `resources/prompts/action-library.md` | Challenge-Unlock 模板 | §3 |

## DoD（完成标准）

- [ ] 4 个 JSON 文件创建在 `resources/config/` 目录下
- [ ] 每个文件包含 `$source` 字段，标注原始文档引用
- [ ] JSON 格式正确，可通过 `JSON.parse()` 验证
- [ ] 文件路径与后续 T-009/T-013 的计划引用路径一致

## 回退方案
无需回退 — 纯文件新增，不影响现有代码。

## 下个任务建议
T-008 学生模型桥接：在 Config 配置就绪后，修复 `{student_context}` 为空的问题，并为 Strategy Service 提供学生模型输入。
