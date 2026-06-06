# T-015: 翻译层

> **优先级**: P1 | **状态**: draft | **预估**: 1d  
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
| 类型 | 新增 UserFacingDiagnosis 接口 | `src/renderer/shared/types.ts` |

## 涉及文件清单

| # | 文件路径 | 操作 | 说明 |
|---|---------|:----:|------|
| 1 | `src/shared/diagnosis-translations.ts` | 新增 | P001~P010 的教练语言翻译映射 |
| 2 | `src/renderer/components/panels/RightPanel.tsx` | 修改 | 诊断展示使用翻译函数，不再展示 P001/L2 |
| 3 | `src/renderer/shared/types.ts` | 修改 | 新增 UserFacingDiagnosis 接口 |

## DoD（完成标准）

- [ ] S1. 右侧栏诊断不再展示 P001/L2 等内部术语
- [ ] S2. 每个症候有正面表述名称和教练语言描述
- [ ] S3. 严重度用颜色表示（L1=绿/L2=橙/L3=红），不显示文字
- [ ] S4. TypeScript 编译无错误
- [ ] S5. 至少 3 个测试覆盖翻译函数

## 回退方案

1. 回退 git commit: `git revert` 相关 commit
2. 右侧栏恢复为直接展示原始诊断数据
3. 共享类型恢复旧定义

## 执行记录

### 改动文件（实际完成时填写）

| 文件 | 改动摘要 |
|------|---------|

### 验证结果（实际完成时填写）

- [ ] TypeScript 编译通过（`npm run typecheck`）
- [ ] 测试通过（`npm test`）

### 输出产物（实际完成时填写）


## 下个任务建议

（完成后填写）
