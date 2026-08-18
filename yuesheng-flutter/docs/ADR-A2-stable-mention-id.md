# ADR-A2：稳定 ID 引用标记（mention 改名免疫）

- 日期：2026-08-18
- 状态：Accepted
- 关联：DSH 插件移植评估 `docs/2026-08-18-dsh-plugins-adaptation-plan.md` 阶段 A-2
- 性质：核心模块变更（DB schema + 引用解析链路），按 R-009/R-020 相关纪律先写 ADR

---

## 1. 背景与问题（Context）

`@` 引用链路现状（批次 39/6/7/71 沉淀）：

- 用户点 `@` → `ReferencePicker(mode:'mention')` 选条目 → `chat_input.insertMention` 把
  **`@标题`（或 `@标题/子标题`，由 `buildMentionPath` 生成）** 文本插到输入框光标处。
- 发送时 `chat_teaching.dart` 调 `MentionParser.parseMentions(text)`：
  - 用**标题前缀匹配**（长度降序）把 `@标题` 反查成 `{refType, refId, title, manuscriptId}`；
  - `ReferenceRepository.addReference(sessionId, refType, refId)` 落库（**存的是 ID，改名免疫**）；
  - 同时序列化 `referencesJson`（`[{refType, refId, manuscriptId, title}]`）随消息落库供气泡徽章展示。
- `session_reference` 表已含 `ref_id`（软引用），`referencesJson` 也带 `refId`。

**真正会"改名失效"的点**：选择器/手打插入的是 `@标题` 文本。一旦作品或章节被改名：
1. 用户**重新**用选择器选改名后的条目 → 没问题（选择器永远显示当前标题）；
2. 但消息正文里残留的 `@旧标题`，以及用户**手打** `@旧标题` 再发 → `parseMentions` 标题库里已无此标题 → 解析失败 → **降级为普通文本**，引用丢失、上下文不再注入。
3. 气泡徽章读的是 `referencesJson` 里的**标题快照**：目标改名后徽章显示旧标题（虽不崩，但陈旧）。

即：存储层（`session_reference.ref_id` / `referencesJson.refId`）已经改名免疫，但**输入/解析层仍以标题为锚**，导致端到端并不免疫。这正是 dsh-at-file "workspace-reference 稳定路径标记（与显示名解耦）"要解决的问题。

---

## 2. 决策（Decision）

引入**稳定 ID 标记语法**，让"输入框里的引用表示"也以 ID 为锚，与显示名解耦：

1. **标记格式**：`@[<refType>:<refId>]`，如 `@[chapter:abc123]`、`@[manuscript:xyz]`、`@[file:qwe]`。
   - 分隔符 `@[` `:` `]` 在普通中文写作中几乎不出现，解析歧义低；`refId` 为生成型 ID（无冒号），安全。
2. **`MentionParser` 改为 ID 优先、标题兜底**：
   - 先扫描 `@[type:id]` 标记 → 由 `refId` 反查当前标题（改名免疫）；
   - 未匹配的 `@标题` 文本走**原有前缀匹配**作为 legacy 兜底（旧消息、用户手打标题仍可用，解析失败降级纯文本）。
3. **`ReferencePicker` mention 模式**选择后传出 `@[refType:refId]` 标记（替代 `@标题` 文本）；`title` 仍传出供选择器内部徽章展示。

> **回溯（Scope Reversal，2026-08-18 同日）**：原决策 4、5（新增 `session_reference.ref_title` 列 + 气泡按 `refId` 实时解析）已被回退。
> 理由（R-010 最小范围 / R-021 不写投机代码）：
> - `ref_title` 列"写入不读"属死 schema；气泡实时解析需 `ProviderScope`，会炸 7+ 消息气泡测试（原气泡为 `StatelessWidget`，渲染 `referencesJson` 快照标题，无 Riverpod 依赖）。
> - 核心路线图 A-2 只要求"解析层 ID 优先 + 标题兜底"，改名免疫已在**发送时**由解析器 `refId` 反查当前标题达成；气泡展示沿用发送时快照即可，不引入实时依赖。
> - 被删目标的回退：标记解析 `_resolveMarker` 在 `refId` 反查不到时返回 null → 降级为纯文本（已在 parser 单测覆盖），不依赖 `ref_title` 快照。

**最终落地范围**（仅核心）：
- 标记格式 `@[<refType:refId>]`；
- `MentionParser` 改为 ID 优先、legacy `@标题` 兜底；
- `ReferencePicker` mention 模式传出标记串；
- 气泡保持原 `StatelessWidget`，渲染发送时 `referencesJson` 标题快照（不做实时 ID 解析）。

---

## 3. 后果（Consequences）

正面：
- 端到端改名免疫：picker 插入标记后，无论作品/章节怎么改名，解析与展示都跟随 ID（发送时由解析器反查当前标题）。
- 向后兼容：旧消息的 `@标题` 文本与新加的标记共存，legacy 兜底保证不崩。
- 目标被删：标记解析 `_resolveMarker` 反查失败时返回 null → 降级为纯文本（parser 单测覆盖），无需额外快照列。

负面 / 代价：
- schema **保持 25**（未新增列，`database.g.dart` 仅因移除死列而重新生成）。
- `referencesJson` 沿用既有 `title` 快照（发送时写入），气泡展示沿用之；改名后历史消息气泡显示旧标题属可接受（不改写历史）。
- 标记 `@[type:id]` 对用户不可读，但选择器插入后输入框显示的是标记串；UI 上气泡徽章仍是可读标题，不影响体验。

---

## 4. 被否决的方案（Alternatives Considered）

- **A. 维持 `@标题`，仅增强前缀匹配**：不解决改名失效，且短标题误匹配风险随作品增多上升。否决。
- **B. 消息正文整体改写为 ID 标记（含历史消息迁移）**：最彻底但改动面大（历史消息 content 重写、流式解析、导出兼容），YAGNI。否决，留待后续若需要再做。
- **C. 解析时按标题模糊匹配 + 缓存 title→id 映射**：复杂度高且仍受改名瞬时态影响。否决。

---

## 5. 实施范围（Tasks）

- T-Parser：`parseMentions` 支持 `@[type:id]` 标记（ID 优先）+ legacy `@标题` 兜底（DONE）。
- T-Picker：mention 模式传出标记串（DONE）。
- T-Test：parser 标记/兜底单测（7 项全绿）+ 全量门禁（1792 通过）。
- ~~T-DB / T-Repo / T-Send / T-Bubble~~：已回退（见回溯），不实现 ref_title 列与气泡实时解析。
