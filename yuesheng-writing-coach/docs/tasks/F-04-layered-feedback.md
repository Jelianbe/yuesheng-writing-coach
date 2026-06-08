# F-04: 分层反馈策略

> **优先级**: P0 | **状态**: done | **预估**: 0.5d
> **依赖**: 无（纯前端 UI 改造） | **后续**: F-02 AI味四维自查
> **来源**: docs/design/ai-tool-features-report_V1.0.md → F-04（InkoS 审计员分层思路）

## 目标

诊断面板区分"必须改"和"建议改"的症候，按严重度分层展示，降低用户认知负荷。

## 设计依据

- **F-04 定义**: docs/design/ai-tool-features-report_V1.0.md §F-04
  - 核心交互: 诊断结果分两区——"需要处理"（L2+症候）和"仅供参考"（L1症候）
  - 默认展开"需要处理"，折叠"仅供参考"
  - 折叠区顶部标注"还有 N 个轻微问题，点击展开查看"
- **理论基础**: Sweller 认知负荷理论——用户一次性看到所有症候可能不知所措，分层后先看到"必须处理的"再看到"建议了解的"
- **现有基础**: RightPanel.tsx 已有 `diagnosis-chip` 组件和 `severity: high/mid/low` 三级

## 改动方案

### 核心逻辑

```
buildRightPanelDiagnoses() 已有 severity 映射（L3→high, L2→mid, L1→low）
  ↓
RightPanel.tsx 内部按严重度拆分：
  - criticalDiagnoses (high/mid) → "需要处理"区（默认展开）
  - infoDiagnoses (low) → "仅供参考"区（默认折叠，显示计数）
```

### 修改文件

| # | 文件 | 说明 |
|---|------|------|
| 1 | src/renderer/components/panels/RightPanel.tsx | 添加两区分层展示 + 折叠逻辑 + 严重度标签 |
| 2 | src/renderer/styles/globals.css | 添加分层区样式 |
| 3 | docs/tasks/TASK-CHAIN.md | 更新 F-04 状态 |

### MVP 范围

- 只做两区（需要处理/仅供参考），不做三级（critical/warning/info）
- L2+/high/mid → "需要处理"，L1/low → "仅供参考"
- 每个症候 chip 增加严重度标签文字（严重/注意/轻微）

## DoD（完成标准）

- [x] D1. 诊断面板症候按严重度拆分为"需要处理"和"仅供参考"两区
- [x] D2. "需要处理"区默认展开，"仅供参考"区默认折叠
- [x] D3. 折叠区显示"还有 N 个轻微问题，点击展开查看"
- [x] D4. 每个症候 chip 显示严重度标签
- [x] D5. tsc 无错误，现有测试不破坏

## 回退方案

1. 回退 RightPanel.tsx 和 globals.css 到旧版本

## 执行记录

### 改动文件

| 文件 | 改动摘要 |
|------|---------|
| src/renderer/components/panels/RightPanel.tsx | 添加两区分层展示 + 折叠逻辑 + 严重度标签 |
| src/renderer/styles/globals.css | 添加分层区样式 |
| docs/tasks/TASK-CHAIN.md | 更新 F-04 状态 |

### 验证结果

- [x] tsc 无错误
- [x] 测试全部通过（39 文件 / 455 tests）
