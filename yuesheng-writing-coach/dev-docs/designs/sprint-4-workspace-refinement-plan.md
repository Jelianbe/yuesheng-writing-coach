# Sprint 4 — Workspace 细化实施计划

## 定位
Issue #? 的实施计划。以 TrainingWorkshop 为中心，UI 质量提升 + 功能区深化。

## 现状

| 组件 | 状态 | 问题 |
|:-----|:------|:------|
| TrainingWorkshop | ✅ 功能完整 | 多处内联 style（违反 R-019），无进度时间轴 |
| HistorySection | ✅ 列表展示 | 无筛选/搜索，纯平面列表 |
| ProgressWorkspace | ✅ 基础实现 | 未关联教学进度 |
| TeachingProgressBar | ❌ 未实现 | Spec 11.1 明确列出 |
| ProgressTimeline | ❌ 未实现 | Spec 11.1 明确列出 |

## 实施范围

### 1. TrainingWorkshop — CSS Modules 重构
- 去除所有内联 `style={{}}`，替换为 CSS Modules class
- 接入 `variables.css` design tokens
- 涉及：header 区域、阅读完成横幅、加载状态、错误状态

### 2. Progress Timeline — 教学进度时间轴
- 新建 `ProgressTimeline.tsx` + `ProgressTimeline.module.css`
- 位于 TrainingWorkshop 右侧或嵌入为子区块
- 显示：诊断→教学→验证→复盘 各阶段状态
- 数据来自 `training.store` 的 `history[]`

### 3. History 增强 — 筛选与详情
- HistorySection 增加：状态筛选（完成/进行中/跳过）
- 每条记录点击展开详情（内容预览 + 评分）

### 4. AttitudeIndicator — 输入框态度指示器
- 输入框上方显示当前态度档位（豆包/月笙如歌/sensei）
- 可点击切换（走已有的 `attitudePreference` 逻辑）

## 不涉及
- WorksWorkspace（只读显示，Sprint 3 已替代方案为 CenterPanel 编辑器）
- 学生模型 Phase 2（独立方向）
- 权限与设置（独立方向）
- 文本片段引用系统（大功能，暂缓）

## 文件变更清单

| 文件 | 改动量 | 说明 |
|:-----|:------:|:------|
| `TrainingWorkshop.tsx` | ~50行 | 内联 style → CSS Modules |
| `TrainingWorkshop.module.css` | 新增 ~100行 | 完整样式定义 |
| `ProgressTimeline.tsx` | 新增 ~80行 | 时间轴组件 |
| `ProgressTimeline.module.css` | 新增 ~60行 | 时间轴样式 |
| `HistorySection.tsx` | ~30行 | 筛选 + 展开详情 |
| `Footer.tsx` | ~20行 | AttitudeIndicator 集成 |
| `Footer.module.css` | ~20行 | 态度指示器样式 |
| `training.store.ts` | ~10行 | 导出进度状态 |
| `CenterPanel/index.tsx` | ~5行 | Timeline 传入 TrainingWorkshop |

## 门禁
- typecheck 0 errors
- test 319/319 pass
- lint 0 errors
- R-019 合规（无内联 style）
