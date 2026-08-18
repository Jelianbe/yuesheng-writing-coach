# ADR-A3：选段段落锚点（excerpt_range 从字符偏移改为段落锚点）

- 日期：2026-08-18
- 状态：Accepted（2026-08-18 舰长确认采纳推荐方案）
- 关联：DSH 移植评估 `docs/2026-08-18-dsh-plugins-adaptation-plan.md` 阶段 A-3
- 性质：核心模块变更（引用数据模型 + 上下文注入链路），按 R-009/R-020 相关纪律先写 ADR

---

## 1. 背景与问题（Context）

当前 `session_reference.excerpt_range`（`tables.dart:324`）存储为 JSON `{start,end}` **字符偏移**：

- 写入：`reference_repository.addReference` 把 `({int start,int end})` 序列化为 `{start,end}`（`reference_repository.dart:276-277`）。
- 读取：`chat_context_builder.parseExcerptRange`（`chat_context_builder.dart:621`）按字符偏移截取章节正文。
- 现状痛点（路线图 A-3）：
  1. **编辑漂移**：用户/模型修改章节正文后，字符偏移错位，摘录指向错误片段（甚至越界）。
  2. **只对主引用 chapter 生效**：`excerpt_range` 目前仅主引用落库，非主引用不记选段（`chat_context_builder.dart:621` 仅对 primary 使用）。
  3. **长文静默丢失**：配合 A-1 预算，smartTruncate 保首弃中（`chat_context_builder.dart:42`），中段内容被静默丢弃。

路线图明确："段落以换行分段为基线"——用稳定段落锚点（`chapterId + startPara + endPara`）替代字符偏移，可把漂移缩到"段落级"。

---

## 2. 当前 excerpt 链路（已确认代码证据）

- **存储**：`session_reference.excerpt_range` 为 TEXT，存 `{"start":N,"end":M}`（`reference_repository.dart`）。
- **自动摘录**：`chat_service_send.dart` 的 `findKeywordExcerpt(chapter.content, keyword)` 按关键词定位并截取一段字符，`chat_service_diagnosis.dart:550/642` 透传 `excerptRange`。
- **注入**：`chat_context_builder._excerptSuffix`（`chat_context_builder.dart:344-348`）拼成 `（原文：「…」）` 注入上下文。
- **用途**：目前 excerpt 主要由诊断/事件/支线检测的关键词命中自动生成，**不是用户在选择器里手动选区**。

---

## 3. 决策（Decision，已采纳）

### 3.1 数据模型

`excerpt_range` 改为段落锚点 JSON：**`{chapterId, startPara, endPara}`**

- `chapterId`：章节主键（锚点自包含，不依赖 session_reference 自身的 ref_id）。
- `startPara / endPara`：基于**换行**（`\n`）切分的段落序号（0-based），闭区间 `[startPara, endPara]`。
- 仍用 TEXT 列，**无需 drift schema 迁移**（仅改变 JSON 内容语义，列类型不变）。

### 3.2 解析与提取

- 新增 `parseParagraphAnchor(String?)` → `{chapterId, startPara, endPara}?`（旧 `{start,end}` 兼容读取：若缺 `chapterId` 视为非法/兜底忽略）。
- 新增 `extractParagraphWindow(chapterContent, startPara, endPara)`：按 `\n` 切段后取区间，合并回文本。
- `chat_context_builder` 改用段落窗口替换原字符截取。

### 3.3 选段来源（已采纳：方案 X + 分隔符 `\n` + 仅主引用）

路线图画的是"用户选择 excerpt"，但当前实现是**关键词自动摘录**，并无手动选区 UI。已采纳：

- **方案 X（最小改动）**：保留自动关键词摘录，底层从字符偏移改为段落锚点——`findKeywordExcerpt` 定位关键词所在段落（按 `\n` 分段），返回该段落（以关键词为锚做句子级截断，上限 120 字）。漂移从字符级降到段落级，UI 零改动。
- 分隔符：`\n`（单换行，中文小说常见）。
- 范围：保持仅主引用（选段展开仅对 `isPrimary==1` 生效）。
- 方案 Y（手动选区 UI）暂不做，留待真实反馈。

### 3.4 范围（最小范围原则）

- **已做**：数据语义变更 + 解析/提取 helper + 主引用注入改用段落窗口 + findKeywordExcerpt 段落锚点化 + 单测。
- **未做（留待方案 Y）**：手动选区 UI、非主引用也记选段——等真实反馈再定。
- **后补（2026-08-18 晚）**：主引用反查 N+1 已消除——`chat_service_observers._preloadReferenceDetails` 改为按 refType 分组批量查询（仓库层新增 `getChaptersByIds` / `listChaptersForManuscripts` / `getManuscriptsByIds` / `getAttachedFilesByIds`），N 条引用从最多 2N 次查询降为固定 ≤5 次。MentionParser/ReferencePicker 侧的查询合并仍未做。

---

## 4. 被否决的方案

- **保留字符偏移 + 每次重算**：漂移无法根治，否决。
- **整段落哈希锚定**：实现复杂且中文重写段落会改变哈希，反而失效，否决。

---

## 5. 实施步骤（待评审后执行）

1. `reference_repository`：`addReference` 入参由 `({int start,int end})` 改为 `({String chapterId, int startPara, int endPara})`；序列化改为段落锚点 JSON。
2. `chat_context_builder`：新增段落切分/提取 helper，替换 `parseExcerptRange` 与 `_excerptSuffix` 的字符逻辑。
3. `chat_service_send` 的 `findKeywordExcerpt` 改为返回段落锚点（命中关键词所在段落区间）。
4. 单测：段落切分、窗口提取、旧格式兼容、越界保护。
5. 全量门禁（`dart analyze` + `flutter test`）保持绿色。

---

## 6. 开放问题（已解决 → 已采纳方案 X）

1. **选段来源**：✅ 方案 X（自动、零 UI 改动）。
2. **段落分隔符**：✅ `\n`（单换行）。
3. **范围**：✅ 仅主引用。

> 未决（留待方案 Y）：手动选区 UI、非主引用选段、MentionParser/ReferencePicker 的 N+1 查询合并（主引用批量反查已于 2026-08-18 晚实施，见 §3.4 后补）。
