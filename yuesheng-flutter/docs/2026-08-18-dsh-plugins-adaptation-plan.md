# DSH 插件方案移植评估：dsh-at-file（文件引用）+ dsh-genui（GenUI）

> 日期：2026-08-18
> 状态：设计提案（待舰长评审）
> 来源：DeepSeek Harness 开源插件生态（omdsh-dev/dsh-at-file v0.6.3、omdsh-dev/dsh-genui）
> 性质：不引入插件本身（它们是 DSH 生态的），**移植其架构方案**到 yuesheng-flutter

---

## 0. 结论摘要

| 插件 | 对 App 的价值 | 移植判定 |
|:---|:---|:---|
| **dsh-at-file** | 修复文件引用系统的 5 个实际痛点（token 爆炸、改名失效、选段漂移） | ✅ 高价值，分 3 阶段移植 |
| **dsh-genui** | 补上「模型回复→交互组件」的渲染缺口，尤其是 diff/quiz 两个教学刚需组件 | ✅ 高价值，但首版只做 5 种组件，不搬 30+ |

另有一个**调研中发现的意外 P0**：消息气泡是纯 Text 渲染，模型输出的 markdown（`#`、`**`、列表）会**原样显示为字面字符**（`message_bubble.dart` L100/L215）。这比 GenUI 更基础，建议最先修。

---

## Part A：文件引用系统移植（dsh-at-file）

### A1. 现状与痛点（代码证据）

| # | 痛点 | 证据 |
|:--|:-----|:-----|
| A-1 | **双预算体系 token 爆炸**：素材文件走独立 50KB 预算，远超正文引用的 15K 字符预算；且每轮把书籍下**全部**素材注入 | `chat_context_builder.dart` L611 `fileBudget = 50*1024`；L71 `formatAttachedFilesContext` |
| A-2 | **@ 引用按标题前缀匹配**：作品/章节改名后旧引用失效降级纯文本；`@书一` 误匹配仅靠长度降序缓解 | `mention_parser.dart` L7 注释自认 trade-off |
| A-3 | **选段机制半成品**：`excerpt_range` 只对主引用 chapter 生效，字符偏移随编辑漂移 | `chat_context_builder.dart` L627 |
| A-4 | **无索引/排除控制**：长文 smartTruncate 保首 60% 弃中段，中部内容**静默丢失** | `chat_context_builder.dart` L42 |
| A-5 | **性能**：每次解析全量加载 manuscripts+chapters+files；ReferencePicker 串行 N+1 查询 | `mention_parser.dart`、`reference_picker.dart` |

### A2. dsh-at-file 的可移植方案（对照）

| DSH 机制 | 月笙 App 对应移植 |
|:---------|:------------------|
| `workspace-reference` 路径标记（稳定路径，与显示名解耦） | `session_reference` 已有表结构（refType + refId + isPrimary + excerpt_range），**补稳定 ID 标记语法**，@ 显示标题、存储用 ID，改名不失效 |
| 选择器只插标记、**不读文件内容**，agent 按需读取 | 引用时只注入「引用元数据 + 指针」，发送时才按需取内容窗口注入（现在是全文注入） |
| 索引排除规则（版本控制/构建产物/系统文件） | App 侧对应「素材类型白名单 + 大小上限 + 预算统一」，治 A-1 |
| 路径分段匹配 + 目录导航 + 前缀排名 | @ 选择器升级：模糊过滤、章/卷层级导航、重名显示父级 |
| 文件名过滤规则（Exact/Regex，全局+工作区） | 暂缓（App 素材量级用不上，YAGNI） |

### A3. 分阶段方案

**阶段 A-1（P0，止血，~半天）**
1. 素材预算并入统一 15K 体系：`fileBudget` 删除，素材与正文引用共享预算池，按条目数均分
2. `formatAttachedFilesContext` 不再全量注入：仅注入主引用相关素材，其余降为「可用素材清单」（标题+摘要 200 字）

**阶段 A-2（P1，稳定引用语法，~1 天）**
1. `session_reference` 增加 `refTitle`（引用时的标题快照）字段；解析层改为 **ID 优先、标题兜底**
2. mention_parser 重构：`@` 输入产出 `{type, id, title}` 三元组，发送时由 ID 反查当前标题（改名免疫）
3. @ 选择器升级：输入过滤（前缀匹配）、重名章节显示所属卷

**阶段 A-3（P2，选段锚点，~2 天）**
1. `excerpt_range` 从字符偏移改为**段落锚点**（`chapterId + startPara + endPara`），段落以换行分段为基线，编辑漂移大幅缩小
2. 引用注入按锚点取窗口而非全文；配合 A-1 预算，长篇引用不再静默截断中段
3. MentionParser / ReferencePicker 查询合并为单次 join，消 N+1

---

## Part B：GenUI 移植（dsh-genui）

### B1. 现状（代码证据）

- **气泡渲染**：`MessageBubble` 纯 `Text`，无任何 markdown 包（`message_bubble.dart` L100/L215）
- **卡片体系已相当成熟**：`MessageCardDispatcher` 按 `messageType` 分派 8 种卡片；卡片由「模型协议块 → parser → validator → service 确定性插入」（`message_card_service.dart` L5-16）
- **协议块基建完善**：6 条 `[YS_*]` 通道（DIAGNOSIS/FACT/ENTITY/TEACHER/REVIEWER/EDITOR），统一「标记提取→剥离→容错解析→schema 校验→失败降级 null」模式，含流式跨 chunk 前缀检测
- **交互卡片已有**：PartialAgreementCard（文本+chip 提交）、TeacherSuggestionCard（5 按钮）、PracticeTaskCard——但**所有回传都走模型往返**
- **本地判分先例**：`training_evaluator.dart` 纯确定性规则判分（FSRS/严重度趋势/状态机），证明「本地判分零模型往返」架构在 App 里已验证可行，只是没接到卡片上

### B2. dsh-genui 的可移植方案（对照）

| DSH 机制 | 月笙 App 对应移植 | 判定 |
|:---------|:------------------|:-----|
| `dsh-ui` 代码块 + JSON spec | 新协议通道 `[YS_GENUI]...[/YS_GENUI]`，复用现有 parser 基建 | ✅ 直接复用模式 |
| 30+ 组件白名单 | **首版只做 5 种教学刚需组件**（见 B3） | ✅ 裁剪 |
| spec guard（坏节点丢弃/节点上限/无 eval） | `genui_validator.dart`：组件类型白名单 + 嵌套上限 + 坏节点静默丢弃 | ✅ 仿 validator 层 |
| quiz 本地判分零模型往返 | quiz 组件判分复用 `training_evaluator` 确定性模式 | ✅ 架构已验证 |
| 本地优先（UI 能做的绝不回传模型） | 展开折叠/选项切换本地完成；action 按钮→拼用户消息走现有 `_handleSend` | ✅ 与现有卡片一致 |
| 状态按「会话+指纹」持久化 | drift 存 quiz 答题状态，按 messageId 关联 | ✅ |
| 流式渐进渲染（组件完成即显示） | 复用 `getPendingMarkerPrefix` 流式拦截基建 | ✅ 已有 |
| mermaid / scene3d | 暂缓（Flutter 侧成本高，教学场景非刚需） | ❌ YAGNI |
| 会话面板（Session Panel 停靠栏） | 暂缓 | ❌ 与现有 header/训练入口设计冲突 |

### B3. 首版组件白名单（5 种，全部对准教学场景）

| 组件 | 教学场景 | 对应现有缺口 |
|:-----|:---------|:-------------|
| **diff** | 原文 vs 改写对比（EditPanel→EvaluationCard 链路） | 现在对比展示粗糙 |
| **quiz** | 训练选择题：单选+本地判分+解释 | 「练→评」闭环缺交互载体 |
| **stat** | 能力维度卡片（五维文笔画像展示） | styleProfile 落库后无展示位 |
| **progress** | 训练进度/六步闭环进度 | 教学进度感知 |
| **timeline** | GrowthChain 成长证据链（T-013） | 完全缺失 |

spec 格式示例（模型侧只需学会这一种块）：

```json
[YS_GENUI]
{"type":"quiz","title":"这句的问题在哪？","items":[
  {"q":"「他很愤怒」违反了什么原则？","options":["展示而非告知","视角一致","句速控制"],"answer":0,"explanation":"情绪直接命名，未转化为可观察行为"}
]}
[/YS_GENUI]
```

### B4. 哲学红线（教练定位约束）

GenUI 移植必须守住 R-009 用户主权 + 「不替写、不替决定」：

1. quiz 只用于**训练检验**，不用于「替用户判断作品好坏」
2. diff 组件只展示**用户已完成的改写**，不展示模型生成的改写供采纳
3. 表单类组件收集的是用户观点/选择（如部分认同原因），不做「一键应用模型建议」按钮
4. 无 action 按钮渲染为禁用（dsh-genui 的「诚实交互」原则原样保留）

### B5. 实施路径

**阶段 B-0（P0，前置，~半天）**：引入 `gpt_markdown`，`MessageBubble` 支持 markdown 渲染。这是一切富渲染的地基，且独立见效（现在模型输出的标题/加粗/列表全是字面字符）。

**阶段 B-1（P1，GenUI v1，~3 天）**：
1. `genui_parser.dart`（`[YS_GENUI]` 通道）+ `genui_validator.dart`（5 组件白名单 + spec guard）
2. `GenUICard` + 5 个子组件 Widget，走 `dispatchMessageCard` 新增 `messageType:'genui'` 分支
3. quiz 本地判分 + drift 答题状态持久化
4. prompt 侧：教学 prompt 增补「何时输出 YS_GENUI 块」规范（参考 dsh-genui SKILL.md 的提示词写法）

**阶段 B-2（P2，按需扩展）**：table、更多组件、action 事件去抖、指纹持久化细化——等 v1 真实使用反馈再定。

---

## 优先级总表（建议执行顺序）

| 序 | 事项 | 量级 | 理由 |
|:--|:-----|:-----|:-----|
| 1 | **B-0 markdown 渲染** | 半天 | 独立 P0：现在模型回复的排版全是字面字符，体验硬伤 |
| 2 | **A-1 素材预算止血** | 半天 | 独立 P0：token 爆炸是真实成本 bug，每轮全量注入素材 |
| 3 | A-2 稳定 ID 引用语法 | 1 天 | 改名失效是引用系统可信度问题 |
| 4 | B-1 GenUI v1（diff+quiz 优先） | 3 天 | 对准「练→评」闭环和 T-013 成长可视化 |
| 5 | A-3 选段段落锚点 | 2 天 | 长篇体验，可等 |

> 1、2 互相独立可并行；3 与 4 无依赖可并行。

---

## 附录：dsh-genui 值得原样抄走的三条工程原则

1. **诚实交互**：无 action 的按钮渲染为禁用，消灭「看起来能点但没反应」的假按钮
2. **本地优先**：UI 自身能完成的状态变更（判分/展开/重置）绝不回传模型；模型只参与「真正需要新内容」的环节
3. **spec guard 兜底**：对模型输出的 UI spec 永远白名单+限额+坏节点丢弃，模型输出错格式不崩 UI，只降级
