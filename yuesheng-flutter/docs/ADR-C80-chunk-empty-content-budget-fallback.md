# ADR-C80：分块分析空内容——预算分级降级 + 失败显式留痕

- 状态：**已采纳并实施**（P0 修复批；诊断链路属核心模块，按 AGENTS.md L124 先立 ADR）
- 日期：2026-09-06
- 关联：AGENTS.md「构建与测试」V4.18（变异验证判据）、R-010 最小化范围、R-019 函数行数、
  R-027 六道门禁、R-028 边界防御；ADR-C63（reject-reason 可观测范式）；ADR-C69（分块症候覆盖）
- 影响模块：`lib/config/shared_constants.dart`、`lib/services/llm_client.dart`、
  `lib/services/progressive_diagnosis.dart`（+2 个测试 fake 签名同步）
- 实证来源：`docs/audits/真机行为回归-报告-2026-09-06-生产模型批.md` §4.1（空内容 5/9）
  及本 ADR §1 的 API 探针记录

---

## 1. 背景与实证

### 1.1 现象（生产模型批报告 §4.1，2026-09-06）

应用分块诊断路径（`progressive_diagnosis.dart` → `LlmClient.chatCompletion`，参数
temperature 0.3 / max_tokens 4096）在生产模型 deepseek-v4-flash 上，9 次采样 **5 次返回
空 content**。机制唯一且稳定：该模型为推理型，`reasoning_tokens` 全额计入 completion
预算，病理样本把 4096 全部耗在 reasoning 上（实证 5 例 reasoning = 4095–4098、content
0 token、finish=length），正文零输出。

应用侧后果链：`extractJson('') → '{}' → _parseChunkNotes → 空 notes →
ChunkAnalysisResult(success: true)`——该块**静默计为「成功分析但零症候」**：不抛异常、
不进 failedChunks、无任何日志。用户表现为长文诊断系统性偏少且无从追溯。教学路径
（streamChat，不传 max_tokens，供方默认预算）16/16 正常，与机制自洽。

### 1.2 关键事实：推理能吃满任何预算（本 ADR 探针，2026-09-06 实测）

对 chunk1（system 1385 字符 + 正文 2851 字符，prompt 2830 tokens）逐参数实测：

| 参数组合 | reasoning_tokens | content | 时延 | 结论 |
|:--|:--|:--|:--|:--|
| max_tokens 1500（无控制） | 1500（烧满） | 空 | 14s | 复现缺陷 |
| max_tokens 8192（无控制）＝**方案 a 单独** | 8191（烧满） | 空 | 80s | **a 单独不成立**：推理会吃满任何预算，只是把空内容推迟到更大预算，且时延翻倍 |
| `reasoning_effort` low / minimal | 1499 / 1282 | 空 / 361 字 | 14s | 被静默忽略（不可靠） |
| `enable_thinking: false` | 1054 | 372 字 | 11s | 被静默忽略 |
| `reasoning: {enabled: false}` | 1500（烧满） | 空 | 15s | 被静默忽略 |
| `thinking: {enabled, budget_tokens}` 1024/256 | 8191 / 8192（烧满） | 空 | 75s | budget_tokens 不被支持 |
| **`thinking: {"type": "disabled"}`** | **None（归零）** | 正常 | 3–6s | **唯一被采纳的推理控制参数**，3/3 稳定 |

判读：API 对不认识的参数一律静默忽略（不报 400），所以「参数发出去了」不等于「生效」，
必须以 `usage.completion_tokens_details.reasoning_tokens` 归零为生效判据。

### 1.3 质量权衡（诚实记录）

关闭推理后，chunk1 的 P003 埋点段（愤怒/悲伤/委屈，引证逐字一致）被标为 **P037 心理
内耗症**（3/3 探针；P003 与 P037 在手册中有已登记重叠关系）。推理开启的成功样本 n=1
判 P003。即：**推理关闭可能把症候编号推向重叠兄弟**，证据质量（原文引证、severity）
不变。该权衡在验收重采样（§5）中按判据度量；若坐实，属症候 ID 裁决层面问题（B-2 家族），
归内容线，不回退本修复——空内容是「零诊断」，编号偏移是「换了一条相邻诊断」，损害
不在同一量级。

---

## 2. 候选方案

**方案一：仅提高预算（a）**。§1.2 实证驳回——推理吃满任何预算，80s 时延后仍空。

**方案二：仅关闭推理（b）**。能根除空内容，但 `chatCompletion` 成功路径的行为随
参数改变（所有非流式调用方共享该方法），且失去推理对判定质量的潜在贡献。

**方案三：换非推理模型跑抽取调用（c）**。涉及模型策略（多端点、成本、备案），
归舰长裁决，本批不动。

**方案四（采纳）：分级降级——尝试 1 保持应用现参数，空则尝试 2 换兜底参数，
仍空显式失败留痕。**

---

## 3. 决策

### 3.1 尝试 1：应用现参数原样（4096，推理开启）

成功路径**零行为变更**：两批生产采样中所有成功调用的 reasoning ≤ 2244，4096 足够；
推理开启的判定质量是已验证的基线（C75/C77 盖章、S-8 靶点命中均在此形态下取得）。
4096 下推理耗尽约 40s，在 `chatTimeoutMs = 60000` 之内——尝试 1 不会因超时中断，
分级降级链完整可达。

### 3.2 尝试 2（仅当 content 为空）：8192 + thinking disabled

兜底参数为新常量（`LlmConfig.chunkAnalysisFallbackMaxTokens = 8192` +
`chunkAnalysisFallbackExtraBody = {'thinking': {'type': 'disabled'}}`）：推理归零根除
空内容成因，8192 作为纯输出余量（实测单块输出 510–750 tokens，5 倍裕度，finish=length
对现实分块不可达）。生效判据以 reasoning_tokens 归零为准（§1.2）。

### 3.3 空检测、重试与显式留痕（无论参数如何都必须做，任务指令）

- **判据**：`content.trim().isEmpty`。合法「零症候」（非空 JSON、notes 空）不受影响
  ——两形态的差别是「模型一个字没说」vs「模型说了没有」。
- **重试**：一次，且换兜底参数（§3.2）——重试不是原样重掷（原样重掷对确定性
  耗尽无效，任务批报告实证同一输入 reasoning 稳定烧满）。
- **仍空**：`ChunkAnalysisResult(success: false, failureReason: 'empty_content')`，
  计入 failedChunks，并按 ADR-C63 范式显式留痕（服务层 `ErrorHandler.captureError`，
  level warn / category api，context 带 chunkIndex + reason）。**「静默计为零症候」
  这一行为本身被消灭**：空块从此要么被重试救回，要么以独立原因码进入 error_logs
  与 failedChunks，merge prompt 侧维持既有失败块跳过语义（不在本批改变）。
- **异常路径顺带留痕**：分块调用抛异常原本也静默（catch 只置 success=false，零日志）
  ——同一疾病，补 `failureReason: 'exception'` + 同款留痕，3 行内，不扩范围。

### 3.4 接口与波及面

`chatCompletion` 加可选命名参数 `{int? maxTokens, Map<String, dynamic>? extraBody}`，
缺省行为与现签名完全一致（`max_tokens` 缺省仍为 `LlmConfig.chatMaxTokens`；extraBody
仅合并进请求体，不得覆盖 model/messages）。调用方波及面：`selection_ai_sheet.dart`
不传参（行为不变）；测试 fake 覆写 2 处（`progressive_diagnosis_test.dart` /
`writing_page_test.dart`）同步签名。教学路径 streamChat 不动——**教学行为零变更**
（任务红线）。

---

## 4. 实施清单

1. `lib/config/shared_constants.dart`：`LlmConfig` 增 `chunkAnalysisFallbackMaxTokens`
   与 `chunkAnalysisFallbackExtraBody`（注释含探针证据指针）。
2. `lib/services/llm_client.dart`：`chatCompletion` 增可选参数与 body 合并。
3. `lib/services/progressive_diagnosis.dart`：
   - `ChunkAnalysisResult` 增 `failureReason`（可选，向后兼容）；
   - 原因码常量 `kChunkFailureEmptyContent` / `kChunkFailureException`；
   - 新增 `_analyzeChunkWithFallback`（空检测 + 换参重试 + 仍空返 null）；
   - 主循环改造：空块与异常块分别置原因码并经 `_logChunkFailure` 留痕；
     `onProgress` 语义保持（空块此前走成功路径会推进度，保持推进度；异常块此前
     不推进度，保持不推）。
4. 测试 fake 签名同步 ×2；`progressive_diagnosis_test.dart` 增空内容三态用例。

## 5. 验收结果（2026-09-06 生产模型重采样，已执行）

重采样协议：S-8 同一长文、同判据、生产模型 deepseek-v4-flash，×3×3
（chunk1/chunk2/pure），脚本镜像 `_analyzeSingleChunk` 新路径（尝试 1 现参数 →
空则尝试 2 兜底参数）；产物 `PROD2-*`（9 份）+ `_run_log2.jsonl`（逐次参数与
usage，无凭据）。

| 验收项 | 修复前（生产批） | 修复后（重采样） | 判定 |
|:--|:--|:--|:--|
| 空内容率 | **5/9** | **0/9** | ✅ 达成 |
| 兜底路径真实触发 | — | 3 例（chunk1/chunk2/pure 的 r3）：尝试 1 reasoning=4096–4097 烧满 content=0 → 尝试 2 reasoning=None 归零、content 923–1500 字 | ✅ 修复前这 3 块即静默零症候，全部被救回 |
| P003 靶点（chunk1） | 非空 1/1 | 2/3（r1 尝试 1 命中；r3 兜底后命中；r2 空 notes=合法零症候） | ✅ 保持命中 |
| P036 靶点（chunk2） | 非空 1/2 | 1/3（r3 兜底后命中；r1 判相邻 P007；r2 空 notes） | ⚠️ 命中偏弱，见下注 |
| thinking-disabled 编号偏移（§1.3 担忧） | — | **未成立**：兜底样本命中 P003（chunk1 r3，P037 仅并列出现）、P036（chunk2 r3） | ✅ 解除 |
| 全量测试 | — | 2498 通过 / 0 失败（含新增 4 例 ADR-C80 用例） | ✅ |
| 六道门禁 | — | 0 format / 1 analyze / 2 全量（裸跑替代，见台账注记）/ 3 循环依赖 / 4 密钥 / 5 R-019 全绿 | ✅ |

P036 命中偏弱注记：r1 判相邻 P007（句式单调，对同一段流水账素材）、r2 空 notes
（模型自判无症候，非空内容缺陷）。P035/P011 归因新增证据：pure 场景尝试 1 成功的
2 例判 **P035**、兜底 r3 判 P011——跨两批生产采样，纯净寒暄在 P011/P035 间摇摆
（P011: 2、P035: 2、空: 5），**两症候对寒暄对话的判定本身不稳定**，中央裁决
（P011 优先）缺注入面导致行为随采样波动——加强 B-2「需要显式消歧」的论证，
归内容线 ADR。

**门禁 2 跑法偏差记录**：本会话 `env` 前缀调 flutter 静默假绿（生产批报告 §一
实证），`gate.sh` 门禁 2 经 `scripts/_run_flutter_test.sh`（`exec env` 结构）
同样受累——本批门禁 2 以裸跑 `flutter test` 替代（会话无代理变量，V4.18 前提
成立），其余五道照常。wrapper 修复归维护方。

## 6. 后续（不在本批）

- 方案 c（非推理模型跑抽取类调用）的模型策略评估——归舰长；
- P003×P037 重叠在分块路径的裁决（若重采样坐实偏移）——归内容线 B-2 家族；
- merge prompt 对失败块的可见性（当前静默跳过失败块）——独立小批评估。
