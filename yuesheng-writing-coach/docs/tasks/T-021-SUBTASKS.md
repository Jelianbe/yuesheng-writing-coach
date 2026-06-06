# T-021 子任务拆分 V3

> V3 更新：T-021.1 已完成（证据分组重构），新增全子任务系统性评估 + 拆分细化

---

## T-021.2 执行记录（已完成）

### 实施方案变更（V3 → 方案A）

**原方案（V3）**：硬编码关键词表做内容分类（narrative/worldbuilding/fragment/clarify）+ 置信度降级机制。

**发现的问题**：
1. 关键词表永远枚举不完——语言是无限的，同一个词在不同上下文含义不同（"王国"在叙事和世界观中含义不同）
2. 用一个关键词表去判断"该不该让 LLM 来分析"，架构上自相矛盾
3. 世界观内容不应该走诊断流程——设计上需要 guide 而非 diagnose

**方案A（实际执行）**：让 AI 自身判断内容类型。

核心思路：**不改路由，改 prompt**。Diagnosis Agent 在症候检测前先做一步内容类型判断。

### 改动清单

| 改动 | 文件 | 说明 |
|------|------|------|
| `DiagnosisAnalysis` 新增 `contentType` 字段 | `types.ts` | `'narrative' \| 'non-narrative'` |
| 增加内容类型判断步骤（"第零步"） | `diagnosis-agent-prompt-v1.md` | AI 先判断内容类型，non-narrative 立即停止并返回空 JSON |
| 始终调用 DiagnosisAgent，按 contentType 决定 | `chat.handler.ts` | 移除 `shouldRunDiagnosis` 判断，`contentType !== 'non-narrative'` 时才生成诊断条目 |
| 删除硬编码关键词路由表 | `content-aware-router.ts` | 已删除 |
| 简化 MessageRouter | `message-router.ts` | `shouldRunDiagnosis` 始终返回 true |
| 更新测试 | `full-flow.wiremock.test.ts` | 场景3/7 适配新架构 |

### 路由决策逻辑

```
用户输入 → DiagnosisAgent（第零步）
  ├── 判断为 non-narrative（世界观设定/碎片/提问/闲聊）
  │     └── 输出空 JSON，不触发症候诊断 → TeachingAgent 正常回复
  │
  └── 判断为 narrative（叙事文本）
        └── 完整分析症候 → 生成 DiagnosisEntry → TeachingAgent 注入教学策略
```

**降级规则**：AI 未输出 contentType 时，默认按 narrative 处理（宁可多诊断不可漏诊）。

### 测试结果

```
✓ 320 passed | 6 skipped (30 test files)
✓ TypeScript compilation: zero errors
```

## 子任务列表

| 编号 | 名称 | 依赖 | 说明 |
|------|------|------|------|
| **T-021.1** | 证据体系重构 — KeyPassage 按症候分组 | — | ✅ 已完成 |
| **T-021.2** | 内容感知路由层 — ContentAwareRouter | 无 | ✅ 已完成 |
| **T-021.3** | 中心面板模式切换 — centerMode + training.store | 无 | 前端模式切换基础设施 |
| **T-021.4** | 后端训练 IPC — training.handler + 推荐服务 | 无 | 训练推荐/分配/完成/跳过/历史 |
| **T-021.5a** | TrainingWorkshop 框架（三区块布局） | .1+.3+.4 | 错误卡片 + 推荐列表 + 历史 |
| **T-021.5b** | 步骤式练习交互（3 个核心 mode） | .5a | narrow_focus / show_dont_tell / perspective_lock |
| **T-021.5c** | Mode 扩展 + CH-P007 阅读任务 | .5b | 剩余 mode + reading_task 特殊交互 |
| **T-021.6** | TrainingBridgeCard 桥接卡片 | .3+.4 | 对话流推荐跳转 |
| **T-021.7** | 训练完成反馈 | .5+.6 | 切回 chat 显示评估 |
| **T-021.8** | ⚡ 全项目硬编码扫描（规则/关键词/正则地狱）| — | T-021.2 启发，排查项目是否有同类"埋雷" |

---

## T-021.1 执行记录（已完成）

### 实现方案（实际执行）

**核心发现**：现有代码中已有 `keyPassages` 机制，但所有症候共享前 3 个。方案是**改造已有字段的映射逻辑**，而非新增字段。

| 改动 | 文件 | 复杂度 |
|------|------|--------|
| `KeyPassage` 新增 `syndromeRef?: string` | `types.ts` | 低 |
| prompt keyPassages 格式增加 `syndromeRef` | `diagnosis-agent-prompt-v1.md` | 低 |
| 新建证据分组工具 | `evidence-grouping.ts` | 中 |
| `analysisToDiagnosisEntry` 按 syndromeRef 分组 | `chat.handler.ts` | 中 |
| 单元测试 | `evidence-grouping.test.ts` | 中 |

**不需要**：改 DB schema、新表、独立证据表、TeachingState 改造。

### 改动文件清单

| 文件 | 状态 |
|------|------|
| `src/renderer/shared/types.ts` | ✅ KeyPassage 新增 `syndromeRef?: string` |
| `resources/prompts/diagnosis-agent-prompt-v1.md` | ✅ keyPassages 格式示例 + 规则强化 |
| `src/main/services/evidence-grouping.ts` | ✅ 新建（groupPassagesBySyndrome + getEvidenceForSyndrome） |
| `src/main/ipc/chat.handler.ts` | ✅ 引入证据分组工具 |
| `src/main/services/__tests__/evidence-grouping.test.ts` | ✅ 15 个测试用例 |

### 核心功能

1. **按症候分组**：AI 输出的 keyPassages 按 syndromeRef 分组，每个症候取对应原文片段作为 evidence
2. **降级策略**：AI 未输出 syndromeRef 时，所有症候共享前 3 个 keyPassages（向后兼容）
3. **证据限制**：每个症候最多 2 条证据（prompt 限制）
4. **证据去重**：同症候内相同的 text 只保留一条
5. **有效性校验**：过滤无效的 syndromeRef（拼写错误如 P00l 代替 P001）
6. **日志告警**：症候无对应证据或 syndromeRef 无效时输出 warn 日志

### 测试结果

```
✓ 15 passed (证据分组 8 + 获取证据 4 + 集成场景 3)
```

### 修正决策记录

| 决策点 | 原方案 | 实际方案 | 理由 |
|--------|--------|----------|------|
| 原文片段来源 | AI 输出时引用 + 事后文本匹配 | KeyPassage.syndromeRef 标注 | AI 在分析时就知道哪段原文对应哪个问题，让它标注更准确 |
| 存储位置 | 新增 sourceSnippets 字段 + 独立证据表 | 复用已有 evidence 字段 | 改动最小，自动跟随 JSON 存入 diagnosis_results 表 |
| 展示策略 | 聚合所有轮次 | 最近引用（Phase 1） | 训练工坊错误卡片只需要最近一次，聚合是 T-025 的事 |
| 全局证据上限 | 每诊断 3 条 | 每症候 2 条 | prompt 限制更精确，控制总证据量 |

---

## 全子任务系统性评估（V3）

### 各子任务风险评分

| 子任务 | 风险评分 | 核心风险点 | 建议优先级 |
|--------|---------|-----------|-----------|
| T-021.1 | 4/10 | 已完成，主要风险在 AI 输出稳定性 | — |
| T-021.2 | 7/10 | 规则引擎误判率、onboarding 判断、置信度阈值 | P1 |
| T-021.3 | 6/10 | 状态切换不丢消息、task.store 依赖链、chat/training store 切换 | P0 |
| T-021.4 | 6/10 | 推荐策略、AI 评估 prompt、taskId/challengeId 语义 | P1 |
| T-021.5a | 7/10 | 三区块布局框架搭建 | P1 |
| T-021.5b | 8/10 | mode 定制复杂度（前端校验逻辑） | P1 |
| T-021.5c | 5/10 | CH-P007 阅读任务特殊交互 | P2 |
| T-021.6 | 3/10 | 桥接卡片插入时机、dismissed 状态 | P0 |
| T-021.7 | 7/10 | 评估 prompt、切回时机、展示形式 | P1 |

### 关键决策记录

| 决策点 | 决策 | 理由 |
|--------|------|------|
| T-021.2 onboarding 判断 | Phase 1 用会话级判断（诊断历史是否为空），Phase 2 查跨会话历史 | 先跑通，后续迭代 |
| T-021.4 taskId → challengeId | IPC 层别名映射，不动 DB schema | 避免迁移成本 |
| T-021.5 ErrorCard 兼容 | 直接用 evidence（T-021.1 完成后已是原文片段），无需兼容两种状态 | 灰色地带已消除 |
| T-021.5 CH-P007 阅读任务 | 通用三步框架 + mode 定制内容，不需要完全不同的流程 | V4.0 设计已决策 |
| T-021.5 情绪词列表 | 单独维护为 JSON 配置文件，不从 prompt 解析 | prompt 情绪词是 AI 诊断信号，不是前端校验词表 |
| T-021.7 自动切回 chat | 改为"提供选择"弹窗：切回对话 or 继续练习 | 教练不替用户决定 |
| T-021.5 拆分 | 拆为 5a（框架）+ 5b（核心 mode）+ 5c（扩展 mode） | 7 个 mode 的前端定制不是一个任务能消化的 |

### 待解决问题（需要用户确认）

| 问题 | 选项 | 建议 |
|------|------|------|
| T-021.2 置信度阈值 | 固定值 0.7 / 动态调整 | 先用 0.7，后续数据驱动调整 |
| T-021.4 推荐策略 | 全部推荐 / 按严重度筛选 / 按优先级 | 按严重度排序，只推荐 L2+ |
| T-021.5b mode 定制 | 先实现 3 个 / 全部 7 个 | 先实现 3 个核心 mode |

---

## 执行顺序

1. **T-021.1** ✅ 已完成
2. **T-021.2 + T-021.3 + T-021.4** 可并行（互不依赖）
3. **T-021.5a** 依赖 .2+.3+.4
4. **T-021.5b** 依赖 .5a
5. **T-021.5c** 依赖 .5b
6. **T-021.6** 依赖 .3+.4
7. **T-021.7** 依赖 .5+.6
