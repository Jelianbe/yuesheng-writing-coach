# B74 prompt 端到端打通 — 交付提交日志

**日期**：2026-08-09
**类型**：功能（大纲层 prompt 协议告知 + 协议改名 + 展示剥离）
**前置**：`5de5ac6`（批次 73，确认卡片 UI）

---

## 背景与立项

批次 72/73 落地大纲层后端与确认卡 UI，但闭环存在两个前置缺陷（审计发现，经用户确认方案后实施）：

1. **鸡生蛋问题**：AI 从未被告知新实体协议的完整 schema。5.1.8 仅在「诊断标记 + 已有实体」时注入，且只描述用法不给出字段结构。首次诊断零实体 → 协议不可达 → AI 永不输出实体块 → 闭环无法启动。
2. **标记命名冲突**：`[YS_OUTLINE]` 已被批次 17 旧「大纲诊断」skill（`outline-diagnosis`，schema 为 diagnosis/nodes）占用，同标记两套 schema 会令 AI 混淆。

经用户确认：① 走方案 1（prompt 端到端打通）；② 新协议独立改名以隔离。

另审计发现一个必要配套：协议打通后 AI 会真实输出 `[YS_ENTITY]` 块，但流式拦截与落库内容均未剥离该块 → 原始 JSON 将泄漏给用户，本批一并修复。

## 改动内容

### 协议改名（outline_parser.dart）
- [outline_parser.dart](../lib/services/outline_parser.dart)：标记 `[YS_OUTLINE]` → **`[YS_ENTITY]`**（常量 `kOutlineStart`/`kOutlineEnd`），与旧大纲诊断 skill 隔离；旧 skill（skill_registry.dart L5489-5526）保持原样
- 新增 `stripOutlineBlock(String)`：从文本剥离 `[YS_ENTITY]...[/YS_ENTITY]` 块（无标记原样返回 / 有起始无结束自标记截断 / 完整块整块移除），纯函数不 throw

### 协议告知（outline_service.dart）
- [outline_service.dart](../lib/services/outline_service.dart)：
  - 新增 `buildEntityProtocolContext()`：**输出顺序强约束 + 2-5 实体抽取期望 + 高优先级声明**（原 v1「可选协议」+「末尾附加」→ AI 先耗 token 在诊断建议，后截断实体块）；v2 改为「必须遵守输出顺序」+「宁可压缩自然语言诊断说明也不得省略」+「[YS_DIAGNOSIS] → [YS_ENTITY] → 自然语言」三段式固定顺序
  - `buildEntityIndexContext()`：**索引印象改为带 id**（`[印象id] 文本`）——原索引只列文本，AI 无法填写合法的 conflict_with（服务端仅采信同实体已有印象 id），协议缺失一环

### 挂接与展示剥离 + 空判断兜底（chat_service.dart + diagnosis_parser.dart）
- [diagnosis_parser.dart](../lib/services/diagnosis_parser.dart)：
  - `parseDiagnosis` 展示逻辑从「仅保留诊断块前缀」升级为 **`[前缀自然语言] + [后缀自然语言]`，两段分别剥离协议块**（前缀本就无协议，后缀调用 `stripOutlineBlock` 剥 `[YS_ENTITY]`；无诊断块时也全局做一次 stripOutlineBlock 兜底）
  - 新增 `_concatDiagnosisDisplay`：前缀/后缀间按换行情况给合适分隔（避免拼接成一坨或出现三空行）。对应批次74 V4 修复——AI 以 `YS_DIAGNOSIS → YS_ENTITY → 自然语言` 三段式输出时，assistant 展示端不再被兜底成「诊断完成。」，能完整读到后缀自然语言诊断说明
- [chat_service.dart](../lib/services/chat_service.dart)：
  - 5.1.8：**协议说明无条件注入**（诊断标记 + 章节主引用 + 装配 outlineRepo 时，零实体也注入）→ 闭环从首轮可启动；有实体时再追加实体索引
  - 流式拦截：`inDiagnosisBlock` 检测同时覆盖 `[YS_DIAGNOSIS]` 与 `[YS_ENTITY]` 两个标记（`_earliestMarkerIndex` + `_blockPendingPrefix` 跨 chunk 保护），防协议 JSON 泄漏到流式展示
  - 落库剥离：sendMessage 与 commitDiagnosisFromContent 在写入前 `stripOutlineBlock(displayContent)`，展示/存储内容不含协议原文
  - 步骤 10 空判断兜底（V3 live 测出）：仅大纲装配的章节诊断，若 diagnosis 成功或已落库实体 → `combinedContent` 空不 onError，默认回「诊断完成。」继续；否则维持原语义。对应新增 `_readOutlineEntityCount(chapterId)` 辅助

### SSE 超时兜底（llm_client.dart + shared_constants.dart）
- [shared_constants.dart](../lib/config/shared_constants.dart)：`streamTimeoutMs = 180000`（流式 3 分钟兜底，SSE 大响应 40s+ 深求索可能主动关连接）
- [llm_client.dart](../lib/services/llm_client.dart)：`streamChat` 显式配置 sendTimeout/receiveTimeout = 3min；`_buildDioError` 错误消息按实际超时配置，不再硬写 60s

### 测试（净 +5 用例 + live 大纲验证）
- 新增 [diagnosis_parser_test.dart](../test/services/diagnosis_parser_test.dart)：5 用例（无标记透传 / 无诊断块但含大纲块剥协议 / 仅诊断块前缀保留 / 诊断+大纲+后缀自然语言三段式拼 prefix+suffix / 诊断块占首位时 suffix 自然语言被完整取回）
- [outline_parser_test.dart](../test/services/outline_parser_test.dart)：标记改 `[YS_ENTITY]` + strip 三用例（完整块移除 / 无标记原样 / 截断）
- [outline_service_test.dart](../test/services/outline_service_test.dart)：#2 增强（索引含印象 id）+ 新增 #12（协议说明含标记与规则）
- [chat_service_outline_test.dart](../test/services/chat_service_outline_test.dart)：Fake LLM 回包改 `[YS_ENTITY]`；#1 增强（落库 assistant 消息不含协议 JSON）；#2 增强（协议说明已注入）；#3 增强（未装配不注入协议/索引）
- **更新 [live_outline_entity_test.dart](../test/live_outline_entity_test.dart)**：
  - `_RecordingLlmClient` 改为 List<List<String>> 保存所有调用（按序），新增 `firstSystemContents / firstRawResponse / totalCalls` 访问主调用——避免后续 TeacherDecision 二次调用（system=1 条）覆盖主调用协议注入记录
  - `onStream` 不再只看最后一次调用返回，最后一次回调仍取最后一次调用的回包（保证 TeacherDecision 二次补自然语言路径不回错包）
  - V4 新增展示内容长度断言（不再默认回「诊断完成。」）——diagnosis_parser suffix 回拼修后应出现自然语言诊断说明
  - 注：仍使用非流式 `chatCompletion` + 强制 `max_tokens=8192`（深求索 SSE 在 2k 字响应时易主动关连接）

## 关键设计

- **闭环启动路径**：首次诊断（零实体）→ 协议说明注入 → AI 输出 `[YS_ENTITY]` 块 → 9.1 落库 pending → 确认卡 → 用户确认 active → 二次诊断注入协议 + 索引 → AI 增量更新（含 conflict_with 引用已有印象 id）
- **冲突 id 引用链补齐**：索引带印象 id 后，AI 的 conflict_with 可被服务端 `impressionIds.contains` 校验采信，冲突防幻觉路径完整可用
- **展示隔离**：协议块与诊断块同等对待——流式不转发、落库不保留，用户只见自然语言诊断输出
- **零协议改动风险**：确认卡由系统事件确定性插入（步骤 9.1），不依赖 AI 输出，未受影响

## 四闸验证 + 真实链路验证

- `dart format`：全过
- `flutter analyze`：0 error 0 warning（**32 info = 历史基线**，本批零新增 warning/error；2026-08-09 12:03 核查）
- `flutter test`：全量 **1024 全绿 + 5 skipped**（净 +5 = diagnosis_parser_test.dart 新增 5 用例）
- `flutter test --tags live test/live_outline_entity_test.dart`（本次第四次 live 重跑 2026-08-09 12:02，DeepSeek real）：
  - **调用概况**：总 2 次 LLM 调用（主诊断调用 + TeacherDecision 补自然语言）。主调用 5 条 system message / 66105 字；补调用 1 条 TeachingDecision 2110 字
  - **V1 协议注入**：✅ 主调用 system #3 注入「## 大纲实体记忆沉淀（必须遵守输出顺序）」743 字，含输出顺序强约束 + schema + 规则 + [YS_ENTITY] 标记
  - **V2 提取合规性**：✅ 1786 字主回包严格按 `[YS_DIAGNOSIS] → [YS_ENTITY] → 自然语言` 三段式输出；3 症候（视角漂移L2 / 基础语病P022L1 / 信息倾泻P004L1）+ 4 实体
  - **V2 提取质量（人工审阅）**：✅ 4 实体全中，印象文本高质量（无截断幻觉、原文事实对齐）
    - character 王建国 × 1 — 巷口攥拳 / 母亲遗言不要报仇 / 仍为父亲行动
    - character 王叔 × 1 — 老部下 / 守三十年 / 左眼疤与王建国童年有关 / 三人通报 / 油纸包笔记
    - character 林小芸 × 1 — 二楼窗口 / 银色小手枪 / 松紧反应
    - plot 父亲的笔记「油纸包、笔记」× 1 — 王叔交 / 外婆旧屋房梁 / 父亲线索
  - **V3 落库**：✅ 4 实体 4 印象全部 pending；4 张 outline_confirmation 卡写入（单实体单卡闭环）
  - **V4 剥离 + 展示修复**：✅ displayContent = 291 字，内容完整是后缀自然语言诊断说明（含"开头的张力其实已经立住了…你先说说当时的安排？"），0 处协议 JSON / 标记泄漏（`[YS_DIAGNOSIS]`/`[YS_ENTITY]`/`syndromes`/实体键值 均未出现在 assistant 落库内容与 onComplete 回调）。**此前「V4 兜底显示诊断完成。」问题已通过 diagnosis_parser suffix 回拼完全修复**
- 文档同步：本日志

## 已知限制（仅记录不代改）

- `commitDiagnosisFromContent`（D4-A 渐进诊断路径）未做 9.1 大纲提取落库——仅剥离展示，不落库；如需渐进诊断也沉淀大纲，另行批次
- 协议说明注入面仍限诊断标记路径（5.1.8 原触发条件，`content.contains('写作诊断分析')`），非诊断的章节日常对话不注入——保持最小范围
- 调用#2 TeacherDecision 补自然语言（system 仅 1 条）路径，未注入协议说明——该调用用于补「自然语言版诊断」而非诊断协议，不影响大纲层闭环

## 提交

| Commit | 日期 | 标题 |
|--------|------|------|
| （本次） | 2026-08-09 | feat: 批次74 大纲层 prompt 端到端（协议改名 [YS_ENTITY] + 协议说明无条件注入 + 顺序强约束破 token 截断 + 索引带印象id + 流式/落库剥离 + SSE 3min超时 + combinedContent三空空判兜底 + live端到端验证 + 4新用例 + 本日志） |
