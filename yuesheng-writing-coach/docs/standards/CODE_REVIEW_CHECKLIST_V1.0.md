---
AIGC:
    Label: "1"
    ContentProducer: 001191440300708461136T1XGW3
    ProduceID: f2ac1166b9bdaea71c23aabee181e425_178bbadb640211f196be5254006c9bbf
    ReservedCode1: Hsis95N8s2qjw6rr5niWG1SicTn+Wo6+WauTundVXIoFIUiASwopF/KFr66aUURM46ObhLghgLkCHaDroQvO4YoIBQIM7x4l3uLBOiCXkhUiJZuYkN7zlFMjgOOcrl3mkrakecGSeUMfm7gKYNZEUPg5yDXIJctdY4nbEA3xwXOBoi+2b/ykj6ixRMA=
    ContentPropagator: 001191440300708461136T1XGW3
    PropagateID: f2ac1166b9bdaea71c23aabee181e425_178bbadb640211f196be5254006c9bbf
    ReservedCode2: Hsis95N8s2qjw6rr5niWG1SicTn+Wo6+WauTundVXIoFIUiASwopF/KFr66aUURM46ObhLghgLkCHaDroQvO4YoIBQIM7x4l3uLBOiCXkhUiJZuYkN7zlFMjgOOcrl3mkrakecGSeUMfm7gKYNZEUPg5yDXIJctdY4nbEA3xwXOBoi+2b/ykj6ixRMA=
---

# 代码审查清单 (Code Review Checklist) V1.0

> **用途**：提交代码前或完成任务后，将此清单与目标代码一起交给 AI，AI 逐项检查并输出结构化报告。
> **适用范围**：TypeScript + React + Electron + SQLite 项目
> **使用方式**：复制下面「Prompt Template」区块，替换文件路径后直接发给 AI

---

## Prompt Template

```text
请使用下方的代码审查清单，对以下文件进行逐项审查并输出结构化报告：

[粘贴文件路径或代码]

审查要求：
1. 必须逐项回答，不可跳过
2. 发现问题时给出具体文件+行号
3. 对 P0 问题给出修复建议
4. 最终输出总评分（P0 问题数 / 总分）
```

---

## 审查清单

### 第一层：致命问题（P0 — 有一个就不通过）

> 这些检查项直接关系到程序能否正确运行。**0 容忍**。

| # | 检查项 | 检查方法 |
|---|--------|---------|
| 1.1 | **import 路径正确性**：所有 import 指向的文件是否真实存在？路径是否拼写正确？ | 逐个 import 对照文件系统验证 |
| 1.2 | **函数/组件调用签名匹配**：被调用的函数/组件是否确实接受传入的参数数量和类型？ | 对照函数定义和调用点 |
| 1.3 | **导出/导入一致性**：导入的名称是否确实是目标文件导出的名称？有无 default vs named export 混淆？ | 对照 export 和 import 语句 |
| 1.4 | **Store/Hook 引用正确**：使用的 store 字段和方法是否存在？名称是否正确？ | 对照 store 定义和消费代码 |
| 1.5 | **IPC 通道名称一致性**：主进程注册的 IPC 通道名是否与渲染进程的 invoke/send 调用一致？ | 对照 handler 注册和前端调用 |

### 第二层：架构问题（P1 — 影响可维护性和可扩展性）

| # | 检查项 | 检查方法 |
|---|--------|---------|
| 2.1 | **单一职责**：这个文件/组件是否只做一件事？是否超过 300 行？（超过 300 行是拆分红线） | 检查文件行数和职责数量 |
| 2.2 | **组件可扩展性**：新增一个类似组件（如新增侧边栏项、新增面板）是否需要修改父组件代码？ | OCP 原则检查：是否对扩展开放、对修改封闭 |
| 2.3 | **硬编码与配置分离**：业务常量、文案、阈值是否散落在逻辑代码中？应集中在 constants / config 中 | 搜索魔法数字和硬编码字符串 |
| 2.4 | **循环依赖**：A 依赖 B、B 依赖 A？或 A→B→C→A？ | 画出 import 依赖图检查环 |
| 2.5 | **状态管理一致性**：同一份数据是否在多处维护（store vs local state vs props 混用）？ | 检查同一数据源是否有多个版本 |
| 2.6 | **空壳/占位函数**：是否存在 `return []` / `return {}` / `// TODO` 的函数体，但上层代码期望其返回真实数据？ | 搜索空实现和 TODO 注释 |

### 第三层：质量问题（P2 — 当前可运行但埋坑）

| # | 检查项 | 检查方法 |
|---|--------|---------|
| 3.1 | **TypeScript 类型安全**：是否存在 `any` 类型？是否存在 `@ts-ignore`？ | 搜索 `: any` 和 `@ts-ignore` |
| 3.2 | **console.log 残留**：是否存在遗漏的调试日志？ | 搜索 `console.log` / `console.debug` |
| 3.3 | **命名一致性**：同一概念是否在代码中存在多个不同命名？（如 manuscriptId / manuscript_id / mId） | 检查关键领域对象的命名是否统一 |
| 3.4 | **错误处理完整性**：每个 async 调用是否有 try-catch？每个 IPC invoke 是否处理了 reject 情况？ | 检查 async 函数和 IPC 调用的错误处理 |
| 3.5 | **空值安全**：对可能为 null/undefined 的值是否有防御性检查？尤其是从 DB 读取或 IPC 返回的数据 | 检查属性访问链是否有可选链或判空 |

### 第四层：专项检查（按上下文选用）

#### A. 数据库操作

| # | 检查项 |
|---|--------|
| A.1 | 多步写入是否在事务中（SQLite 的 `db.transaction()`）？ |
| A.2 | 主键是否使用 UUID 而非自增/拼接？ |
| A.3 | 是否存在 SQL 注入风险（拼接用户输入到 SQL 字符串）？ |

#### B. React 组件

| # | 检查项 |
|---|--------|
| B.1 | 组件是否正确处理 loading / error / empty / 正常渲染四种状态？ |
| B.2 | useEffect 是否有清理函数（取消订阅、清除定时器）？ |
| B.3 | 传递给子组件的 props 是否稳定（避免每次渲染创建新对象/函数导致不必要的重渲染）？ |
| B.4 | 事件处理函数是否使用了 useCallback？计算值是否使用了 useMemo？ |

#### C. IPC / Electron 主进程

| # | 检查项 |
|---|--------|
| C.1 | IPC handler 的响应格式是否统一（如 `{ success, data?, error? }`）？ |
| C.2 | 错误信息是否在生产环境下暴露了堆栈跟踪？ |
| C.3 | 主进程的同步操作是否会阻塞渲染进程？ |

---

## 输出格式要求

审查完成后，AI 必须按以下格式输出报告：

```markdown
# 代码审查报告

**审查文件**: [文件路径]
**审查时间**: [时间]
**P0 致命问题数**: X
**P1 架构问题数**: X
**P2 质量问题数**: X

## P0 致命问题

| # | 问题 | 文件:行号 | 修复建议 |
|---|------|----------|---------|
| 1 | [问题描述] | [路径]:[行号] | [具体修复方案] |

## P1 架构问题

| # | 问题 | 文件:行号 | 修复建议 |
|---|------|----------|---------|

## P2 质量问题

| # | 问题 | 文件:行号 | 修复建议 |
|---|------|----------|---------|

## 总评

[一句话总结代码质量，P0=0 即通过]
```

---

## 使用示例

```
请使用 docs/standards/CODE_REVIEW_CHECKLIST_V1.0.md 中的审查清单，
对 src/main/services/recommendation-engine.ts 进行审查。

文件内容：[粘贴代码]
```

---

*清单版本: V1.0 | 基于项目的 47 项缺陷扫描结果提炼 | 2026-06-09*
*（内容由AI生成，仅供参考）*
