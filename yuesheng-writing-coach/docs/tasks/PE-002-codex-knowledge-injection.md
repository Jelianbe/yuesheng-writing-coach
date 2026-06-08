# PE-002: Codex 结构化知识注入

> **优先级**: P1 | **状态**: done | **预估**: 1.5d
> **依赖**: 无（独立服务） | **后续**: PE-006 渐进策略
> **来源**: pro-writing-tools-report_V1.0.md → PE-002「Codex 结构化知识注入」（NovelCrafter）

## 目标

借鉴 NovelCrafter Codex 知识库系统的设计，构建月笙的 Codex 知识条目注入机制。将诊断历史、教学进度、学生画像等上下文信息格式化为带优先级的结构化条目，按规则自动注入 System Prompt，替代当前拼接式的文本注入。

## 设计依据

- **PE-002 模式定义**: docs/research/pro-writing-tools-report_V1.0.md → PE-002（NovelCrafter Codex 系统）
  - 核心结构: `知识条目 = {trigger_condition} + {content_block} + {injection_priority}`
  - 月笙最小版本: 将"最近 3 条诊断结果"格式化为结构化条目，按优先级注入回复 Prompt
- **现有实现**: `formatDiagnosisHistory()` in chat.handler.ts — 当前是纯文本拼接
- **现有注入点**: `PromptLoader.loadSystemPrompt()` — 三段式组装，Codex 注入应作为第三段（上下文层）的升级

## Codex 条目设计

```typescript
interface CodexEntry {
  /** 唯一标识（如 "diag-last-3", "teaching-progress", "student-profile"） */
  id: string;
  /** 条目类型 */
  type: 'diagnosis_history' | 'teaching_progress' | 'student_profile' | 'focus_area';
  /** 条目内容文本 */
  content: string;
  /** 注入优先级（1=最高，5=最低） */
  priority: number;
  /** 触发条件 */
  trigger: {
    /** 条件类型 */
    type: 'always' | 'on_session' | 'on_diagnosis' | 'on_phase';
    /** 条件值（如 phase id） */
    value?: string;
  };
  /** 元数据 */
  metadata?: {
    /** 是否可折叠（长内容设为 true） */
    collapsible?: boolean;
    /** 最大展示行数 */
    maxLines?: number;
  };
}
```

## 核心改动

| # | 文件 | 操作 | 说明 |
|---|------|:----:|------|
| 1 | src/main/services/codex.service.ts | 新增 | CodexService：聚合、过滤、排序、格式化知识条目 |
| 2 | resources/config/codex-config.json | 新增 | Codex 条目类型配置（优先级、上限、格式模板） |
| 3 | src/main/services/prompt-loader.ts | 修改 | 集成 CodexService，替换旧 diagnosisHistory 注入 |
| 4 | src/main/core/service-config.ts | 修改 | 注册 CodexService 到容器 |
| 5 | docs/tasks/TASK-CHAIN.md | 修改 | 更新 PE-002 状态 |

## 实施步骤

### 步骤1：codex-config.json

```json
{
  "version": "1.0",
  "entryTypes": {
    "diagnosis_history": {
      "priority": 1,
      "maxEntries": 3,
      "trigger": { "type": "on_session" },
      "format": "structured"
    },
    "teaching_progress": {
      "priority": 2,
      "maxEntries": 1,
      "trigger": { "type": "always" },
      "format": "structured"
    },
    "student_profile": {
      "priority": 3,
      "maxEntries": 1,
      "trigger": { "type": "on_session" },
      "format": "compact"
    },
    "focus_area": {
      "priority": 4,
      "maxEntries": 1,
      "trigger": { "type": "on_diagnosis" },
      "format": "compact"
    }
  }
}
```

### 步骤2：CodexService

- `collectEntries(sources)`: 从诊断服务、教学状态、学生模型收集原始数据
- `filterEntries(entries, context)`: 根据触发条件过滤
- `sortByPriority(entries)`: 按优先级排序
- `formatEntry(entry)`: 格式化为 Codex 文本块
- `buildCodexBlock(entries)`: 组合完整 Codex 块

### 步骤3：PromptLoader 集成

- 在 `loadSystemPrompt()` 第3段（上下文层）中，新增 Codex 注入
- Codex 块放在诊断历史和教学进度之前，作为上下文层的"头"

## DoD（完成标准）

- [x] D1. CodexService 能聚合来自 3 个来源（诊断历史、教学状态、学生画像）的条目
- [x] D2. 条目按优先级排序注入 Prompt，高优先级在前
- [x] D3. codex-config.json 可配置条目类型、优先级、上限
- [x] D4. tsc 无错误，现有测试不破坏（tsc 0 error, 439 tests pass）

## 回退方案

1. 回退 `prompt-loader.ts` 到旧版本
2. 删除 `codex.service.ts` 和 `codex-config.json`
3. `service-config.ts` 移除 CodexService 注册

## 执行记录

### 改动文件

| 文件 | 改动摘要 |
|------|---------|
| src/main/services/codex.service.ts | 新增 |
| resources/config/codex-config.json | 新增 |
| src/main/services/prompt-loader.ts | 修改 |
| src/main/core/service-config.ts | 修改 |
| docs/tasks/TASK-CHAIN.md | 更新 |

### 验证结果

- [x] tsc 无错误（0 errors）
- [x] 测试全部通过（38 files, 439 tests）

## 下个任务建议

PE-002 完成后，建议转向 PE-006「渐进式提需求策略」——优化训练入口的用户需求采集流程。
