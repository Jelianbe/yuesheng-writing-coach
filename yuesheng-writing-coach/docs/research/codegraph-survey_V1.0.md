# CodeGraph 项目调研报告

> 调研日期：2026-06-01  
> 调研目的：了解 CodeGraph 类工具，评估是否适用于月笙项目开发辅助

---

## 一、项目概览

### 1.1 什么是 CodeGraph？

CodeGraph 是一类将代码库转换为**可查询知识图谱**的工具。它通过解析代码的抽象语法树（AST），提取类、函数、变量、调用关系和依赖结构，构建图形化的代码关系网络，让开发者（或 AI 代理）能够以结构化方式理解代码库，而非逐行扫描文件。

### 1.2 核心价值主张

| 传统方式 | CodeGraph 方式 |
|---------|---------------|
| grep 全文搜索字符串匹配 | 查询"谁调用了这个函数"的精确结构关系 |
| AI 逐行扫描文件消耗大量 Token | AI 直接查询预索引的知识图谱 |
| 手动绘制架构图，容易过时 | 自动从代码生成，永远与代码同步 |
| 新人入职需要数周理解代码 | 交互式查询，快速定位关键路径 |

---

## 二、主要项目对比

### 2.1 CodeGraph CLI（colbymchenry/codegraph）

**定位**：AI 编码代理的本地代码搜索引擎

| 属性 | 值 |
|------|-----|
| GitHub | github.com/colbymchenry/codegraph |
| 语言 | TypeScript |
| 安装 | `npm install -g @codegraph/cli` |
| 核心优势 | 专为 Claude Code/Cursor 等 AI 代理优化 |

**核心功能**：
- ✅ 预索引知识图谱（类、函数、变量、调用关系）
- ✅ 减少 57% Token 消耗、46% 响应时间、71% 工具调用
- ✅ 100% 本地运行，代码不离开电脑
- ✅ 支持 7 种编程语言（TS/JS、Python、Java、C/C++、Rust、Go、C#）

**支持的 AI 客户端**：
- Claude Code（原生集成，体验最佳）
- Cursor 0.45+
- Windsurf 1.5+
- VS Code + GitHub Copilot
- DeepSeek-TUI

**典型用法**：
```bash
# 生成项目索引
codegraph index --exclude node_modules/ dist/

# 查询代码关系
codegraph query "find all calls to the sendData function"
codegraph query "show the inheritance hierarchy of the User class"
codegraph query "which files import the axios library"
```

---

### 2.2 CodeGraph（FalkorDB/code-graph）

**定位**：将 Git 仓库转换为可查询的 FalkorDB 知识图谱

| 属性 | 值 |
|------|-----|
| GitHub | github.com/FalkorDB/code-graph |
| 数据库 | FalkorDB（图数据库） |
| 查询语言 | Cypher |
| 在线演示 | code-graph.falkordb.com |

**核心功能**：
- 类型化节点：`Module`、`Class`、`Function`、`Variable`
- 关系边：`CONTAINS`、`CALLS`、`INHERITS_FROM`、`DEPENDS_ON`
- 自然语言查询（GPT-4o 或 Llama 3-70B 自动转 Cypher）
- 影响分析、死代码检测、调用链追踪

**典型查询示例**：
```cypher
# 查找所有调用 sendData 的函数
MATCH (f:Function)-[:CALLS]->(g:Function {name: 'sendData'})
RETURN f.name, f.file

# 查找未使用的函数
MATCH (f:Function)
WHERE NOT (f)<-[:CALLS]-()
RETURN f.name, f.file

# 查找 User 类的继承链
MATCH path = (c:Class)-[:INHERITS_FROM*]->(base:Class {name: 'User'})
RETURN path
```

---

### 2.3 CodeGraph（俄罗斯企业版）

**定位**：企业级代码属性图（CPG）平台

| 属性 | 值 |
|------|-----|
| 网站 | codegraph.ru |
| 支持语言 | 11 种 |
| 部署方式 | 本地部署，DLP/SIEM 集成 |

**核心功能**：
- 代码属性图（CPG）构建
- 跨过程数据流分析
- 变更影响验证
- 审计合规支持

**适用场景**：
- 大型代码库理解（10 万+ 行）
- 发布风险评估
- 安全审计
- 开发者入职

---

## 三、架构思想解析

### 3.1 核心概念

```
代码库 ──► AST 解析 ──► 符号提取 ──► 关系构建 ──► 知识图谱
                                        │
                                        ▼
                                   查询引擎 ◄── 自然语言/Cypher/CLI
                                        │
                                        ▼
                                   AI 代理 / 开发者
```

### 3.2 图谱模型

**节点类型**：
- `Module` - 模块/文件
- `Class` - 类
- `Function` - 函数/方法
- `Variable` - 变量
- `Interface` - 接口
- `Type` - 类型定义

**边类型**：
- `CONTAINS` - 包含关系（文件包含类，类包含方法）
- `CALLS` - 调用关系
- `INHERITS_FROM` - 继承关系
- `IMPORTS` - 导入关系
- `DEPENDS_ON` - 依赖关系
- `HAS_ARGUMENT` - 参数关系
- `HAS_RETURN_TYPE` - 返回类型关系

### 3.3 与传统 RAG 的对比

| 维度 | 向量数据库 RAG | 知识图谱 RAG（CodeGraph） |
|------|---------------|-------------------------|
| 检索方式 | 语义相似度匹配 | 结构化关系遍历 |
| 精确度 | 近似匹配，可能有噪声 | 精确匹配，零噪声 |
| 多跳推理 | 困难，需要多次查询 | 天然支持，一次遍历 |
| 影响分析 | 不支持 | 原生支持 |
| 调用链追踪 | 困难 | 原生支持 |

---

## 四、与月笙项目的关联

### 4.1 教学状态机的图结构思想

我们的 [agent-architecture-reuse_V1.0.md](file:///d:/ai-teacher/yuesheng-writing-coach/docs/design/agent-architecture-reuse_V1.0.md) 文档中已经使用了类似的图结构：

```
[诊断节点] --(A类)--> [循循善诱流]
          --(B类)--> [强拆灵堂流]
          --(C类)--> [缺口补完流]

[世界观节点] --(用户飘了)--> [五感降维器] --(落地)--> [主角锚定节点]
[主角锚定] --(信息不足)--> [追问子图] --(答完)--> [刑侦笔录节点]
[刑侦笔录] --(交不出作业)--> [硬门槛施压环] --(通过)--> [验收节点]
```

这与 CodeGraph 的"图节点 + 条件边"思想高度一致：

| CodeGraph 能力 | 月笙场景 | 技术实现 |
|---------------|---------|---------|
| **图节点（Node）** | 教学阶段（诊断/世界观/主角/笔录/验收） | TypeScript 函数 + 状态枚举 |
| **条件边（Conditional Edge）** | 学员类型 A/B/C → 不同教学流 | 意图识别 + 规则路由 |
| **状态持久化** | 断点续传、跨会话保持 | SQLite teaching_state 表 |
| **循环节点（Cycle）** | 硬门槛施压环（反复练习直到通过） | while 循环 + 最大迭代限制 |
| **子图（Subgraph）** | 追问子图（针对信息不足的深入追问） | 嵌套状态机 |

### 4.2 LangGraph 参考

CodeGraph 的思想与 **LangGraph**（LangChain 的图结构框架）高度相关。LangGraph 专门用于构建有状态的、多角色的 AI 应用，非常适合我们的教学场景：

- **状态图**：定义教学阶段为节点，流转条件为边
- **持久化**：内置检查点机制，支持断点续传
- **人机协作**：支持人类审批节点（用户确认推进）

---

## 五、适用性评估

### 5.1 月笙项目当前规模

| 指标 | 数值 |
|------|------|
| TypeScript 文件 | 39 个 |
| React 组件 | 8 个 |
| 文档文件 | 30+ 个 |
| 总代码行数 | 约 5,000-8,000 行 |

### 5.2 是否需要 CodeGraph 工具？

**当前阶段：不需要**

原因：
1. **项目规模较小**：39 个 TS 文件 + 8 个组件，IDE 的"转到定义"和"查找引用"已经足够
2. **结构清晰**：Electron 的 main/renderer/preload 三层架构，模块职责明确
3. **文档完善**：已有详细的设计文档、任务文档、参考手册
4. **团队规模**：当前开发者数量少，上下文理解成本低

**未来可能需要（当项目达到以下规模时）**：
- 代码文件超过 200 个
- 代码行数超过 50,000 行
- 团队成员超过 5 人
- 模块间依赖关系复杂到难以手动追踪

---

## 六、替代方案：IDE 内置功能

对于当前项目规模，以下 IDE 功能已经足够：

| 功能 | 说明 | 快捷键 |
|------|------|--------|
| 转到定义 | 跳转到函数/变量定义 | F12 |
| 查找所有引用 | 显示谁在使用这个函数 | Shift+F12 |
| 调用层次结构 | 显示函数的调用链 | Ctrl+Shift+H |
| 文件结构 | 显示文件内的类/函数列表 | Ctrl+F12 |
| 依赖图（部分 IDE） | 可视化模块依赖 | 插件支持 |

### VS Code 推荐插件

| 插件 | 功能 | 适用场景 |
|------|------|---------|
| **Dependency Cruiser** | 生成依赖关系图 | 检查模块间循环依赖 |
| **Sourcegraph** | 代码导航和搜索 | 大型项目代码浏览 |
| **GitLens** | Git 历史和代码作者 | 了解代码变更历史 |
| **CodeTour** | 代码 walkthrough 文档 | 新人入职引导 |
| **Graphviz Preview** | 可视化 .dot 图文件 | 绘制架构图 |

---

## 七、结论与建议

### 7.1 当前阶段

**不使用 CodeGraph 工具**，但借鉴其**图结构思想**：
- 继续完善教学状态机的图结构设计
- 参考 LangGraph 的状态图模式优化教学流程
- 保持文档与代码同步，降低理解成本

### 7.2 未来规划

当项目达到以下里程碑时，重新评估：
- [ ] 代码文件超过 100 个
- [ ] 团队成员超过 3 人
- [ ] 模块间依赖关系复杂到难以手动追踪
- [ ] 需要频繁进行影响分析（修改一个函数影响哪些模块）

### 7.3 立即可以做的

1. **使用 Dependency Cruiser 生成依赖图**：验证当前模块划分是否合理
2. **使用 CodeTour 创建代码导览**：方便未来新人理解项目结构
3. **完善 IPC 通道文档**：记录所有主进程↔渲染进程的通信通道

---

## 附录：相关资源

| 资源 | 链接 |
|------|------|
| CodeGraph CLI | https://github.com/colbymchenry/codegraph |
| FalkorDB CodeGraph | https://github.com/FalkorDB/code-graph |
| LangGraph 文档 | https://langchain-ai.github.io/langgraph/ |
| Cypher 查询语言 | https://neo4j.com/docs/cypher-manual/ |
| Dependency Cruiser | https://github.com/sverweij/dependency-cruiser |

---

> 文档版本：V1.0  
> 创建日期：2026-06-01  
> 维护人：AI 助手