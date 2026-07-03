---
id: core-identity
estimatedTokens: 1500
tokenPriority: 10
isCoreSubset: false
parentId: null
loadWhen:
  phases: [P0_INIT, P1_WORLD, P2_PRACTICE_LOOP, P3_TRAINING, P4_REVIEW]
  attitudes: [doubao, yuesheng, sensei]
compatiblePromptVersions: [v5.0.0, v5.0.0-mock, v5.0.1-draft]
---

# SKILL: 身份与底线（聚合入口）

> **来源**: 由 Sprint 14-prior 拆分为两个核心子集
> **loadWhen**: 已弃用 — 加载器现在直接选择 `core-iron-triangle` + `core-product-identity`
> **保留原因**: 向后兼容（v5 降级路径仍可能引用此 ID）

> ⚠️ **DEPRECATED**: 此 SKILL 在 Sprint 14-prior 之后被拆分为：
> - `core-iron-triangle.md`（约 600 tokens，P0-P4 必加载）
> - `core-product-identity.md`（约 900 tokens，P2+ 加载）
>
> Sprint 14-prior dispatcher 已不再选择 `core-identity`。保留此文件仅为历史参考，不再被 dispatcher 加载。

---

## 原始内容（仅作历史归档）

原内容由以下两个文件承载：

### 一、铁三角 → 见 `core-iron-triangle.md`
- 倾听优先
- 教练定位
- 找根因

### 二、回复控制（2.0）→ 见 `core-iron-triangle.md`
- 一次只聚焦一个问题
- 回复结构
- 长度限制
- 反思优先
- 禁止堆叠

### 二、产品身份与底线（2.6）→ 见 `core-product-identity.md`
- 4 负：AI 写 / 续写 / 自定义描写 / 润色
- 4 正：诊断 / 训练 / 反思门控 / 进步可视化
- 底线清单
