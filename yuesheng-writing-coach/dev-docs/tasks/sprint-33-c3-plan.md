# Sprint 33 C-3: 4 子页数据通路打通

> 依据: sprint-33-user-gaps-plan.md, C-3 (D-DEBT-32)
> GStack: Plan → Build

## 现状评估

### 4 子页 4 态检查

| 页面 | Loading | Error | Empty | Data | Store |
|------|:-------:|:-----:|:-----:|:----:|-------|
| GrowthReportPage | ✅ | ✅ | ✅ | ✅ | growth.store |
| TrainingPlanPage | ✅ | ✅ | ✅ | ✅ | prescription.store |
| BookshelfPage | ✅ | ✅ | ✅ | ✅ | manuscript.store |
| ConversationsPage | ❌ 无 loading | ❌ 无 error | ✅ | ✅ | session.store |

### 4 Store 关键问题

所有 4 个 store 在数据为 null/空时设置 `error: 'XXX为空'`（如"全局趋势为空"、"阶段列表为空"、"画像为空"），导致页面错误横幅和空状态**同时显示**。空数据不是错误，不应走 error 路径。

| Store | 空数据行为 | 问题 |
|-------|-----------|------|
| growth.store | `set({ error: '全局趋势为空', loading: false })` | 误导性 error |
| prescription.store | `set({ error: '阶段列表为空', loading: false })` | 误导性 error |
| ability.store | `set({ error: '画像为空', loading: false })` | 误导性 error |
| retro.store | `set({ error: '复盘数据为空' })` | 合理(用户主动触发) |
| session.store | 无 loading 字段 | 缺少 loading 状态 |

## 实施

### 1. session.store — 添加 loading 状态
- 添加 `loading: boolean` 到 SessionState
- `loadSessions` 开头 `set({ loading: true })`，结尾 `set({ loading: false })`

### 2. ConversationsPage — 添加加载指示器
- 读取 `loading` 字段，在 `loading && sessions.length === 0` 时显示"加载中…"

### 3. growth.store — 空数据不应为 error
- `data` 为 null 时仅 `set({ loading: false })`，不设 `error`

### 4. prescription.store — 空数据不应为 error
- `stages.length === 0` 时仅 `set({ loading: false })`，不设 `error`

### 5. ability.store — 空数据不应为 error
- `result?.profile` 为 null 时仅 `set({ profile: null, loading: false })`，不设 `error`

## 门禁

- typecheck: 0 error
- test: 全绿
- lint: 0 warning
