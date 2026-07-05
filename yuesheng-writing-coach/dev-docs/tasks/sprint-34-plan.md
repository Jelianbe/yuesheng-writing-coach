# Sprint 34: 基础设施债务清理

> 依据: Sprint 34-38 Roadmap, D-DEBT-30/31/33
> GStack 阶段: Plan → Build

## 背景

C-2/C-3 暴露了基础设施缺口: `ability:getProfile` IPC 合约类型与实际返回值不匹配（缺少 `trainingStats`/`diagnosisTrend`/`abilities` 字段），导致统计卡片显示 `'0'`、雷达图关键词匹配不可靠、消息加载无上限。

## DoD

- [ ] 修正 `ability.contract.ts` 合约类型，匹配 IPC 实际返回值
- [ ] 统计卡片 3 列接入 `diagnosisTrend.totalDiagnoses` / `trainingStats.totalCompleted` / 活跃天数
- [ ] 雷达图从 `abilities` 数组提取数据，替换 `SYNDROME_KEYWORD_MAP` 关键词匹配
- [ ] ChatPage 消息列表添加 `session:getMessagesPaged` 分页加载
- [ ] 门禁: typecheck 0 error + test 全绿 + lint 0 error

## 涉及文件

- `src/shared/api-contracts/ability.contract.ts` — 修正合约类型
- `src/renderer/pages/ProjectSpacePage.tsx` — 统计卡片 + 雷达图
- `src/renderer/stores/session.store.ts` — 添加分页加载方法
- `src/renderer/pages/ChatPage.tsx` — 分页加载 + "加载更多"
- `docs/decision-log.md` — 追加 D-091

## 改动概要

### 1. 合约类型修正

`ability.contract.ts` 的 `AbilityProfile` 补充:
- `abilities: AbilityScore[]` — 能力评分列表（替代 `syndromes`）
- `weakPoints: WeakPoint[]` — 弱点标签
- `trainingStats: TrainingStats` — 训练统计
- `diagnosisTrend: DiagnosisTrend` — 诊断趋势
- `computedAt: string` — 计算时间
- 保留 `syndromes` 字段向后兼容（标记 `@deprecated`）

### 2. 统计卡片

- `profile.diagnosisTrend.totalDiagnoses` → "诊断" 卡片
- `profile.trainingStats.totalCompleted` → "训练" 卡片
- 从 `diagnosisTrend.syndromeFrequency` 的 keys 推断活跃天数 → "学习天" 卡片
- 移除 `'0'` 硬编码注释

### 3. 雷达图

- 新增 `extractAbilityRadarValues(abilities)` 从 `AbilityScore[]` 提取 5 维值
- `abilityId` → 关键词匹配雷达维度索引
- 保留 `SYNDROME_KEYWORD_MAP` 降级路径（数据不足时备用）

### 4. 消息分页

- `session.store.ts` 新增 `loadMessagesPaged(sessionId, offset, limit)` 方法
- `ChatPage.tsx` 初始加载 200 条，添加"加载更多消息"按钮

## 门禁

- typecheck: 0 error
- test: 全绿
- lint: 0 error
