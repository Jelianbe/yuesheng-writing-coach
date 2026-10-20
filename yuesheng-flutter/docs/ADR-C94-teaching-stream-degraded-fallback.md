# ADR-C94：教学路径流式输出分级降级（deepseek 系空流，解封 C80 教学红线）

- 状态：**已采纳（舰长签发 2026-09-13 19:16，Q4 裁定「甲：分级降级」的正式落地）**
- 日期：2026-09-13
- 关联：ADR-C80（§3.4 红线解封对象；§1.2 探针协议；§1.3 质量权衡实证；§5 重采样）、
  ADR-C74（新逻辑独立类纪律）、诊断 IO 批增量 PRD Q4 舰长裁定（§7.1 留痕，R5）、
  增量架构 `docs/designs/2026-09-13-diagnosis-io-optimization-architecture.md` §1.4（方案源）、
  侦察 v2 §9（实证）、R-019（函数 ≤50 行）、R-027（十二门禁）
- 影响模块：`lib/services/llm_client.dart`、`lib/services/llm_model_profile.dart`【新】、
  `lib/config/shared_constants.dart`、`test/services/llm_client_stream_fallback_test.dart`【新】
- 性质说明：本 ADR 解封 ADR-C80 §3.4「教学路径 streamChat 不动」。该句是 C80 **当批任务
  红线**（当时批次要求教学行为零变更），不是永久禁令；舰长已在诊断 IO 批 Q4 裁定
  「甲：C80 同款分级降级」，本 ADR 将该裁定落成正式决策文档。签发后 T04 方可动代码。

---

## 1. 背景与实证

### 1.1 C80 红线的由来（系有意决策，非疏漏）

C80 修复分块路径空内容（9 采样 5 次空 content 且静默计成功）时，教学路径
（streamChat，不传 max_tokens，供方默认预算）实测 **16/16 正常**，与空内容机制自洽；
且当批任务红线要求教学行为零变更。故 C80 §3.4 明示「教学路径 streamChat 不动」——
在当时的实证与边界下，这是正确的最小化范围（R-010），不是遗漏。

### 1.2 侦察 v2 §9：红线下方存在两个缺口【实测】

| # | 缺口 | 证据 |
|:--|:--|:--|
| 1 | **参数裸奔**：`_buildStreamRequestBody` 对 deepseek-v4-flash 既无 max_tokens 也无 thinking 控制；`streamChat` 签名不支持 extraBody，调用方无法补传；`classifyLlmModel` 不匹配 deepseek 系 | `llm_client.dart:669-689` / `:464-468` / `:132-135` |
| 2 | **半静默**：空正文但含诊断块/实体 → 落库「诊断完成。」占位文案，用户见占位而非报错 | `diagnosis_flow_handler.dart:814-833` |

- **上层防线现状**：纯空流 → `onError('AI 返回为空')` 显式报错（`diagnosis_flow_handler.dart:813-830`），
  非静默计成功——比 C80 修复前的分块路径健康，但**有报错无降级**。
- **风险评估【推断】**：供方默认预算下若推理烧满 → 零输出 → 教学回合失败，重试成本
  由用户承担。机制上完全可能踩中：C80 §1.2 已证「推理能吃满任何预算」，教学路径的
  默认预算只会更大、烧得更慢，但同样烧得满。
- **诚实标注**：教学路径至今无空流生产实证（C80 批 16/16 正常）。本 ADR 属**防御性
  修复**而非止血，验收口径据此设定（见 §6：空输出率「不升高」而非「归零」）。
- 缺口 2（半静默文案）由架构 S4b（任务 S1-T05）承接，**不在本 ADR 范围**。

### 1.3 判据纪律（承 C80 §1.2，直接复用其探针结论）

API 对不认识的参数一律静默忽略（不报 400），所以「参数发出去了」≠「生效」，
必须以 `usage.completion_tokens_details.reasoning_tokens` 归零为生效判据。
`thinking: {"type": "disabled"}` 是 C80 探针 7 参数组合中**唯一被采纳的推理控制参数**
（3/3 稳定），本 ADR 兜底参数与其同值。

---

## 2. 候选方案

**方案一：维持不动**（等空流实证再修）。省一次改动，但空流回合的失败与重试成本由
用户承担；而本修复成功路径零行为变更、改动面收敛于单文件，防御成本远低于等待成本。

**方案二：对 deepseek 流式请求常态注入 `thinking:{type:disabled}`**。根除空流，但
成功路径行为随参数改变——C80 §1.3 实证的质量风险进入常态，Q4 裁定明确否决。

**方案三（采纳）：C80 同款分级降级**——尝试 1 保持现参数原样；空流且模型属降级名单
→ 尝试 2 注入兜底 extraBody；仍空 → 正常返回（上层既有报错防线接住）。

---

## 3. 决策

### 3.1 模型分类：LlmModelProfile 扩充

`LlmModelProfile` 增字段 `fallbackDisableThinking`（默认 false）；`classifyLlmModel`
增分支 `m.startsWith('deepseek')` → true。**非 deepseek 的请求体逐字节不变**（AC-3，
锚点测试固化）；deepseek **尝试 1** 的请求体同样不变——只在空流后才换兜底参数。

### 3.2 接口：streamChat 增可选 extraBody（调用点零改动）

`streamChat` 增可选命名参数 `{Map<String, dynamic>? extraBody}`，缺省（不传）行为与
现签名完全一致，三处现网调用点（chat_service / teacher_service / progressive_diagnosis）
零改动。合并纪律承 C80：`addAll` 前防御性剥离 `model / messages / stream` 保留键，
extraBody 不得覆盖请求骨架。

### 3.3 降级编排（streamChat 内部，R-019 拆 `_streamAttemptLoop`）

- **尝试 1**：现参数原样（成功路径零行为变更，承 C80 §3.1 价值——推理开启的判定
  质量是已验证基线）。
- **判空**：按 §3.4 联合判据，判空成立且 `profile.fallbackDisableThinking` 为真
  → 进入尝试 2。
- **尝试 2**：仅换兜底参数 `LlmConfig.teachingStreamFallbackExtraBody =
  {'thinking': {'type': 'disabled'}}`（与 `chunkAnalysisFallbackExtraBody` 值同源、
  命名分立，注释互指 C80 §1.2）。**不重试 2 次以上**：原样重掷对确定性耗尽无效
  （C80 §3.3 同理），一次换参机会用尽即止。
- **尝试 2 仍空 → 正常返回**，不引入新异常路径：上层既有 `onError('AI 返回为空')`
  防线不动，半静默文案由 S4b 另批治理。
- **`isDone` 恰好一次契约**：包装回调缓存首次 isDone，降级发生则吞掉尝试 1 的 isDone，
  全程对调用方恰好投递一次。三处现网调用方虽均 no-op，契约仍须保持，防未来调用方踩坑。
- **留痕**：降级触发时 debugPrint（尝试次数、模型、emitted 状态）；未触发零日志。

### 3.4 判空联合判据与 reasoning_tokens 落点（A-2 定稿）

**运行时判空判据（尝试 1 / 尝试 2 同一判据，写死）**：

> 一次流式尝试被判为「空流」，须同时满足：
> **(a) `emitted == false`**——`emitted` 仅由 **content token** 置位；`reasoning_content`
> 增量**不计入** emitted（若计入，纯推理流会被误判为非空，降级永不触发——本判据的
> 关键细节）；
> **(b) 流正常收尾**——`isDone` 达成，非异常、非取消。

**`reasoning_tokens == 0` 的落点（生效判据，非运行时触发判据）**：生产请求体**不加**
`stream_options: {include_usage: true}`（保持非 deepseek 字节级不变 + 生产响应形状
不变），运行时读不到 reasoning_tokens；其读数由**验收探针**取得。A-2 二选一定稿为：
**镜像 C80 §1.2 用同参数非流式调用读 usage**（不选流式 include_usage 探针：少一个
生产/探针差异面）。验收联合判据 = 触发降级的样本满足 (a)+(b)，且尝试 2 后
`reasoning_tokens` 归零。

**半输出不降级（A-2 默认语义，写死）**：`emitted == true` 后中断（含部分内容后断流）
一律**不降级**——半输出已向用户投递内容，重发会复读，交由上层既有错误语义处理。
若验收探针发现「reasoning 未烧满但 content 为空」的其他空流形态，**回本 ADR 复议
判据**，不得静默扩大判空范围。

### 3.5 与 C80 的差异对照

| 维度 | C80（分块路径） | C94（本 ADR，教学路径） |
|:--|:--|:--|
| 入口 | `chatCompletion`（非流式） | `streamChat`（SSE 流式） |
| 尝试 1 参数 | max_tokens 4096 | 不传 max_tokens（供方默认） |
| 兜底参数 | 8192 + thinking disabled | 仅 thinking disabled（教学本无 max_tokens） |
| 仍空结局 | `success:false` + 失败留痕 | 正常返回，上层既有 `onError` 接住（教学回合无中间落库态可损坏） |
| 特有契约 | — | isDone 恰好投递一次；emitted 不计 reasoning_content |

---

## 4. 质量权衡（诚实载明 C80 §1.3 实证）

- **实证风险**：C80 §1.3 记录——关闭推理后，chunk1 的 P003 埋点段（愤怒/悲伤/委屈，
  引证逐字一致）被判为 **P037 心理内耗症**（3/3 探针；P003 与 P037 存在已登记重叠
  关系）。推理开启的成功样本判 P003。C80 §5 重采样中该偏移**未成立**（兜底样本命中
  P003/P036），但样本量小（兜底触发 3 例），风险**不视为消除**。
- **因此选分级降级而非直接 disabled**（Q4 裁定精神：成功路径零行为变更，质量风险
  不进常态）：推理关闭只发生在「尝试 1 空流」的 deepseek 教学回合；常态教学回合
  推理全开，判定质量基线不受影响。
- **教学路径的风险形态弱于分块抽取**：教学输出是对话生成，不做症候编号裁决，不存在
  P003→P037 式编号偏移的直接对应物；但「推理贡献的表达深度」损失同理存在，故兜底
  仍限缩于空流回合。
- **时延代价**：限于已空流的回合（该回合本就失败、需用户手动重试）。C80 实测
  thinking disabled 后 3–6s 正常出文，兜底回合大概率快于原样重掷。

---

## 5. 实施清单（对应架构任务 S1-T04；ADR 签发为动码前置）

1. `lib/services/llm_model_profile.dart`【新】：`LlmModelProfile`（含 `fallbackDisableThinking`）。
2. `lib/services/llm_client.dart`：`classifyLlmModel` 增 deepseek 分支；`streamChat` 增
   `extraBody` 可选参数与 §3.2 合并纪律；拆 `_streamAttemptLoop`（每函数 ≤50 行，
   `streamChat` 若超限拆 `_runFallback`，已预案）；降级留痕。
3. `lib/config/shared_constants.dart`：`LlmConfig.teachingStreamFallbackExtraBody`
   （注释含 C80 §1.2 探针证据指针）。
4. `test/services/llm_client_stream_fallback_test.dart`【新】：deepseek 空流 → 尝试 2
   携带兜底 extraBody；非 deepseek 请求体字节级不变；isDone 恰好一次；尝试 2 仍空
   正常返回；reasoning_content 增量不计 emitted。

## 6. 验收

- AC2（R5）：请求体含思考控制参数——**生效以 `reasoning_tokens` 归零为准**（实机
  探针按 §3.4 定稿形态执行，随验收报告出数）。
- AC3（R5）：GLM/doubao 请求体字节级不变（锚点测试）。
- AC4（R5）：兜底形态 = Q4 甲「分级降级」（尝试 1 → 空则尝试 2 → 仍空正常返回）。
- AC5（R5）：实机采样教学路径空输出率**不升高**（本 ADR 为防御性修复的口径体现）。
- R-027 十二门禁全绿；R-019 基线零新增。

## 7. 回滚

- **改动面收敛**：extraBody 为可选参数、三处调用点零改动、兜底参数为独立常量、
  降级编排收敛于 `llm_client.dart` 单文件 `_streamAttemptLoop`——revert 即删除该
  函数 + 恢复 `streamChat` 签名 + 删常量与 profile 字段/分支，单 commit 可逆。
- **正交性**：不触碰 `token_budget_guard.dart` / `message_injector.dart` /
  `chat_context_builder.dart` / `chat_service.dart`——S1/S2/S3 批次改动完全正交，
  本 ADR 回滚不产生连带。
- **风险面**：生产从未触发降级前（无空流实证），回滚零行为差异；触发后回滚则退回
  「空流显式报错、用户手动重试」现状，无数据损坏面（教学流不落库中间态）。
