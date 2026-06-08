# T-015: 翻译层

> **优先级**: P1 | **状态**: completed | **预估**: 1d  
> **依赖**: T-018 | **后续**: T-019

## 目标

将内部诊断结果（P001/L2 等内部术语）翻译为用户可理解的自然语言。每个症候有正面表述名称和教练语言描述，严重度仅用颜色表示不显示文字。违反"不输出病症编号"铁律的问题。

## 设计依据

- **设计依据文档**: [diagnosis-translation-layer_V1.0.md](../design/diagnosis-translation-layer_V1.0.md)
- **关联发现**: 月笙_设计意图vs代码实现_V1.0.md → 发现4 诊断面板违反理念
- **来源任务**: T-018（反思门控稳定后，诊断展示使用其数据流）

## 前后端分工

| 层 | 改动内容 | 涉及文件 |
|----|---------|---------|
| 类型 | 新增翻译映射表 | `src/shared/diagnosis-translations.ts` |
| 前端 | 右侧栏诊断部分使用翻译层 | `src/renderer/components/panels/RightPanel.tsx` |
| 辅助 | app-helpers.ts 集成翻译函数 | `src/renderer/utils/app-helpers.ts` |
| 样式 | CSS 更新诊断芯片展示 | `src/renderer/styles/globals.css` |
| 配置 | vitest 新增 shared 项目 | `vitest.config.ts` |

## 涉及文件清单

| # | 文件路径 | 操作 | 说明 |
|---|---------|:----:|------|
| 1 | `src/shared/diagnosis-translations.ts` | 新增 | P001~P010 的教练语言翻译映射 + UserFacingDiagnosis 接口 |
| 2 | `src/renderer/utils/app-helpers.ts` | 修改 | buildRightPanelDiagnoses 使用 diagnosisToUserFacing |
| 3 | `src/renderer/components/panels/RightPanel.tsx` | 修改 | 诊断芯片展示 description，删除 status 文字 |
| 4 | `src/renderer/styles/globals.css` | 修改 | diagnosis-chip-status → diagnosis-chip-desc |
| 5 | `src/shared/__tests__/diagnosis-translations.test.ts` | 新增 | 8 个测试覆盖翻译函数 |
| 6 | `vitest.config.ts` | 修改 | 新增 shared 测试项目 |

## DoD（完成标准）

- [x] S1. 右侧栏诊断不再展示 P001/L2 等内部术语
- [x] S2. 每个症候有正面表述名称和教练语言描述
- [x] S3. 严重度用颜色表示（L1=绿/L2=橙/L3=红），不显示文字
- [x] S4. TypeScript 编译无错误
- [x] S5. 8 个测试覆盖翻译函数

## 回退方案

1. 回退 git commit: `git revert` 相关 commit
2. 右侧栏恢复为直接展示原始诊断数据
3. 共享类型恢复旧定义

## 执行记录

### 改动文件（实际完成时填写）

| 文件 | 改动摘要 |
|------|---------|
| `src/shared/diagnosis-translations.ts` | **新建**：UserFacingDiagnosis 接口 + DIAGNOSIS_TRANSLATIONS 映射表 + diagnosisToUserFacing() + syndromesToUserFacing() |
| `src/renderer/utils/app-helpers.ts` | buildRightPanelDiagnoses 改为调用 diagnosisToUserFacing 翻译，name 使用翻译正面名称，新增 description 字段 |
| `src/renderer/components/panels/RightPanel.tsx` | 诊断数据类型新增 description，渲染时显示翻译描述替代原始 status 文字 |
| `src/renderer/styles/globals.css` | diagnosis-chip-status 重命名为 diagnosis-chip-desc，添加 line-height |
| `src/shared/__tests__/diagnosis-translations.test.ts` | **新建**：8 个测试覆盖 L1/L2/L3/desc/批量/未知症候 |
| `vitest.config.ts` | 新增 shared 项目配置，include src/shared/**/*.test.ts |

### 验证结果（实际完成时填写）

- [x] TypeScript 编译通过（`npx tsc --noEmit` 0 errors）
- [x] 测试通过（33/34 test files passed，369/375 tests passed，6 skipped 为 pre-existing better-sqlite3 兼容性问题）

### 输出产物（实际完成时填写）

- diagnosis-translations.ts 翻译层，9 个症候的正面表述和教练语言描述
- 右侧栏诊断芯片现在显示"你的故事设定很丰富 + 但主角的出场还不太清晰"而非"P001 世界观膨胀 L2"
- 严重度通过颜色表示（green/orange/red），不再显示 L1/L2/L3 文字


## 下个任务建议

T-019: 从零构建引导流程（核心链路终点，整合全部核心功能后做新用户引导）
