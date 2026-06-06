# 架构修正：移除规则引擎，统一 AI 诊断

**版本**: V1.0  
**创建日期**: 2026-06-04  
**依据**: `docs/design/design-philosophy_V1.0.md` — 第四章「Agent 专业化与职责边界」  
**替代**: intent-consistency.service.ts（规则引擎）、author-profile-v2.service.ts（硬编码评分）

---

## 1. 问题陈述

当前存在两条平行的意图一致性检测路径，导致架构矛盾：

```
路径 A（正确）：diagnosis-agent-prompt → LLM 判断 I001/I002/I003
路径 B（错误）：intent-consistency.service.ts → 693 行硬编码 regex 规则
```

### 路径 B 的三个问题

**问题一：规则覆盖范围与 AI 能力重叠**
- C001-C005 仅覆盖「凡人废柴流」一种写作场景——5 条 regex 无法泛化到其他类型
- LLM 已经在 Prompt 侧做了同样的判断（I001/I002/I003），规则引擎做的是重复劳动

**问题二：动词强弱不可用 regex 准确判断**
- `STRONG_VERBS = ['撕','扯','砍','砸'...]` 和 `WEAK_VERBS = ['被','受','感觉'...]` 的硬编码
- 动词强弱是上下文决定的 — "撕"在战斗场景是合理用词，"感觉"在心理描写中完全恰当
- regex 无法理解语境，会导致大量误报

**问题三：数字评分缺乏教学价值**
- `author-profile-v2.service.ts` 每次诊断后扣 2-3 分
- 65 分与 63 分对用户没有实际指导意义
- 用户需要的是「哪里可以改进」的文字建议，不是分数

---

## 2. 修正方案

### 2.1 移除什么

| 模块 | 文件 | 替代方案 |
|------|------|---------|
| 规则引擎 | `intent-consistency.service.ts` | 由 LLM 在 Prompt 中统一判断 |
| 作者画像 V2 | `author-profile-v2.service.ts` | 简化保留基础数据，去掉硬编码评分 |
| 作者画像 IPC | `author-profile-v2.handler.ts` | 不再需要独立 handler |
| 前端 Store | `author-profile.store.ts` | 不再需要前端 store |
| 能力雷达图 | `AbilityRadarChart.tsx` | V2 阶段做成长时间线时再设计 |

### 2.2 强化什么

`diagnosis-agent-prompt-v1.md` 的意图一致性维度（第 2.7 节）需要从 3 条增强到 6 条：

| 当前（3 条） | 增强后（6 条） |
|-------------|--------------|
| I001 凡人逆袭矛盾 | 保留 |
| I002 爽文矛盾 | 保留 |
| I003 情绪基调矛盾 | 保留 |
| — | **I004 动词风格自洽性**（LLM 判断 role-verb 匹配度） |
| — | **I005 角色行为一致性**（LLM 判断角色动作是否符设） |
| — | **I006 设定-执行断裂**（LLM 判断设定承诺与实际描写落差） |

### 2.3 保留什么

高手的教学方法论**不丢失**——从代码中提取教学精华，转化到 Teaching Agent 的教学 Prompt 中：
- 角色→动词匹配的教学思路
- intent→execution 对比的分析框架
- 作为教学案例保存

---

## 3. 涉及文件清单

| 操作 | 文件 | 说明 |
|------|------|------|
| 删除 | `src/main/services/intent-consistency.service.ts` | 规则引擎本体 |
| 删除 | `src/main/services/author-profile-v2.service.ts` | 硬编码评分 |
| 删除 | `src/main/ipc/author-profile-v2.handler.ts` | 独立 IPC handler |
| 删除 | `src/renderer/stores/author-profile.store.ts` | 前端 store |
| 删除 | `src/renderer/components/AbilityRadarChart.tsx` | UI 组件 |
| 删除 | `src/main/services/__tests__/intent-consistency.service.test.ts` | 规则引擎测试 |
| 删除 | `src/main/services/__tests__/author-profile-v2.service.test.ts` | 评分测试 |
| 修改 | `src/main/ipc/diagnosis.handler.ts` | 移除规则引擎引用 |
| 修改 | `src/main/index.ts` | 移除依赖注入 |
| 修改 | `src/preload/index.ts` | 移除白名单 |
| 修改 | `src/renderer/shared/constants.js` + `.ts` | 移除 IPC 通道 |
| 修改 | `src/renderer/shared/types.ts` + `.d.ts` | 移除类型定义 |
| 修改 | `resources/prompts/diagnosis-agent-prompt-v1.md` | 强化 LLM 检测 |
| 修改 | `src/test/reporter.ts` | 移除模块映射 |
| 修改 | `vitest.config.ts` | 移除 exclude 条目 |

---

## 4. 预计影响

| 指标 | 当前 | 修正后 | 变化 |
|------|------|--------|------|
| Service 文件数 | 8 | 6 | -2 |
| IPC 通道数 | 34 | 27 | -7 |
| 测试用例数 | 239 | ~290 | 保留可用测试，新增 Prompt 测试 |
| IPC Handler 文件 | 8 | 7 | -1 |
| TypeScript 编译 | 5 errors | 0 errors | 清理冗余引用后消除错误 |

---

## 变更记录

| 版本 | 日期 | 变更内容 |
|------|------|---------|
| V1.0 | 2026-06-04 | 初始规格，提出移除规则引擎+统一 AI 诊断的方案 |
