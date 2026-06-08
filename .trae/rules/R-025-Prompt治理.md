---
name: "R-025-Prompt治理"
description: "适用于 Prompt 文件的创建、修改、版本管理和回滚操作。要求所有 Prompt 作为一等公民进行治理：可见、可控、可回滚。"
alwaysApply: false
priority: "high"
trigger:
  - "创建新 Prompt 文件时"
  - "修改现有 Prompt 内容时"
  - "Prompt 版本切换时"
  - "PromptBuilder 接入消费链路后（强制激活）"
checkLogic:
  - "Prompt 文件是否有版本号标记？"
  - "修改是否有变更记录？"
  - "是否能秒级回滚到上一版本？"
  - "Prompt 是否纳入 Git 版本管理？"
enforcement: "未按治理流程修改的 Prompt 变更视为高风险，不接入消费链路"
---

# R-025: Prompt 治理

## 原则

**Prompt 是产品核心体验的决定者，但它的工程化治理完全空白。**
V3 和 Teaching Agent V1 并存已久，切换逻辑隐式，没有版本号、没有评测、没有回滚能力。改坏 Prompt 只能靠用户反馈发现——这是不可接受的。

## 一等公民四原则

| 原则 | 含义 | 当前状态 | 目标状态 |
|------|------|:-------:|:-------:|
| **可见** | 存档可追溯，知道哪个版本在线上 | 多文件散落，无版本号 | 统一版本号 + 变更日志 |
| **可控** | 像管代码一样管 Prompt，有审核流程 | 改完即生效，无审核 | 改动→跑回归→通过才上线 |
| **可回滚** | 秒级切换到历史版本 | 无法回滚 | Git tag + 运行时版本加载 |
| **可知** | 知道每个版本的准确率和效果 | 无评测数据 | 回归测试用例集 |

## 版本管理规范

### 版本号格式
语义化版本：`vX.Y.Z`
- X：重大重构（如 V3→V4 合并）
- Y：行为规则增删（如新增症候/调整教学策略）
- Z：文案微调/错别字修复

### 文件命名
```
resources/prompts/yuesheng-prompt-v4.0.0.md
resources/prompts/yuesheng-prompt-v4.1.0.md
```

### 变更日志（每个 Prompt 文件头部必须包含）

```markdown
<!--
Version: v4.1.0
Date: 2026-06-09
Author: [who]
Change: [一句话描述改了什么]
Trigger: [为什么改 — 用户反馈/Bug/新功能]
Baseline: [改前版本号]
Rollback: git checkout v4.0.0 -- resources/prompts/yuesheng-prompt-v4.0.0.md
-->
```

## 回滚机制

### 快速回滚（秒级）
```bash
# 切换到上一版本
git checkout v4.0.0 -- resources/prompts/yuesheng-prompt-v4.0.0.md
# 重启应用即可生效
```

### 安全回滚（确认后再切）
1. 先在测试环境验证旧版本可用
2. 记录回滚原因到变更日志
3. 执行快速回滚
4. 通知相关方（如果有协作者）

## 与 PromptBuilder 的关系

当 PromptBuilder 接入 AI 消费链路后（P0-3 任务）：
- PromptBuilder 成为唯一的 Prompt 加载入口
- 版本选择通过 PromptBuilder 的配置实现，不再硬编码路径
- A/B 分流逻辑（N-03）在 PromptBuilder 层实现
- 本规则的版本管理规范成为 PromptBuilder 的数据基础

## 暂未激活的部分

以下能力在本规则中定义但需等待基础设施就绪：

| 能力 | 前置条件 | 预计激活时机 |
|------|---------|------------|
| 回归测试自动运行 | N-02 测试用例集 ≥20 个 | P0-4 完成后 |
| A/B 灰度发布 | PromptBuilder 接入 + ≥2 真实用户 | P2-5 |
| 准确率仪表盘 | N-05 评测体系运转 | P2-3 后 |

## 检查清单

```
Prompt 修改前：
□ 是否有明确的改动理由？（不能是"感觉可以更好"）
□ 是否知道当前版本号？

Prompt 修改后：
□ 是否更新了版本号？（至少 Z 位+1）
□ 是否写了变更日志？（Version/Date/Change/Trigger）
□ 是否 commit 到 Git？
□ 回滚命令是否可用？
```

## 与其他规则的协作

| 规则 | 关系 | 协作方式 |
|------|------|----------|
| R-026 Prompt工程规范 | 依赖 | R-025 的治理流程（版本管理、回滚）依赖 R-026 的 Prompt 结构规范作为治理对象 |
| R-018 变更溯源规范 | 依赖 | Prompt 的每次变更必须遵循 R-018 溯源链，记录变更理由和依据 |
| R-029 安全与隐私 | 依赖 | Prompt 治理必须包含安全审查，确保 Prompt 中不包含硬编码的 API Key |

## 优先级
高优先级 — Prompt 是产品核心，治理缺失是架构级风险
