# TXT 导入逻辑 — 解析正则与错误处理细节

**适用版本**：Flutter 版月笙写作教练（`lib/services/file_parser.dart` + `lib/services/work_import_service.dart` + `lib/widgets/book_import_sheet.dart`）
**真源**：RN 版 `yuesheng-android/src/services/file-parser.ts` + `WorkImportModal.tsx`
**入口**：书架「新建作品」弹窗 → 「从 TXT 文件导入书籍」→ BookImportSheet → 选择文件

---

## 1. 导入链路总览

```
BookImportSheet._handlePickFile
  └─ WorkImportService.importBookFromFile()      （书架场景：无会话上下文）
       ├─ file_parser.pickDocument()            选择文件（.txt/.md/.markdown）
       ├─ file_parser.readFileContent()         读取文本
       ├─ file_parser.parseDocument()           按扩展名路由解析 → ParsedFile
       └─ importWork(sessionId: null)           事务建稿件 + 逐章建章节（不建引用）
```

对话页导入（ChatInput「+」入口）走 `importFromFile/importFromText`，区别仅在 **sessionId 非空时第一章设为主引用**；解析与入库逻辑与书架导入完全一致。

---

## 2. 章节解析正则

### 2.1 TXT 正则（核心）

```dart
RegExp(r'^(第[一二三四五六七八九十百千万\d]+[章节回幕篇]|Chapter\s*\d+)',
       caseSensitive: false)
```

| 片段 | 含义 |
|------|------|
| `^` | 锚定行首（先 `trim()` 再去匹配，行首空白不影响） |
| `第[一二三四五六七八九十百千万\d]+[章节回幕篇]` | 中文章节标记：如「第一章 / 第十二节 / 第一百零五回 / 第十幕 / 第3篇」 |
| `\|Chapter\s*\d+` | 英文章节标记：`Chapter 1`、`chapter 2`（`caseSensitive: false` 大小写不敏感，`\s*` 允许空格） |

**匹配规则（两条件同时满足才切章）**：

1. `chapterPattern.hasMatch(trimmed)` — 行首命中章节标记；
2. `trimmed.length < FileParserLimits.chapterTitleMaxLength` — 章节标题长度 **< 50 字**（`Chapter 标题过长 → 不当章节标记`，整行并入正文）。

**切章语义**：
- 命中标记 → 结算前一个章节（`content.trim()` 非空才入列表），开启新章节；
- 未命中 → 当前行追加进当前章节内容（保留原始行 + `\n`，不丢失空白）；
- 结算时 `content.trim()` — 章节首尾空白被裁剪；
- 遍历结束再结算最后一个章节；
- **无任何章节标记 → 兜底整篇为「第一章」**（标题固定为「第一章」，非文件名）。

### 2.2 Markdown 正则

```dart
line.startsWith('# ') && line.length < FileParserLimits.heading1MaxLength
```

- 仅一级标题 `# ` 切章，`##` 二级标题不切（归入当前章节）；
- 标题取 `line.replaceFirst(RegExp(r'^#\s*'), '')` — 剥掉 `# ` 前缀；
- 标题长度上限 **< 80 字**；
- 无 `# ` → 兜底整篇为「第一章」。

### 2.3 扩展名路由

```dart
parseDocument(content, fileName):
  .md / .markdown → parseMdFile
  其余（含 .txt / 无扩展名）→ parseTxtFile
```

### 2.4 作品标题来源

`_stripExtension(fileName)`：取文件名去掉最后一个 `.` 之后的部分；**无扩展名（`dotIndex <= 0`）→ 兜底「未命名作品」**。`genre` 固定为「未知」。

---

## 3. 入库链路（事务）

`WorkImportService.importWork`（核心，`sessionId` 可空）：

```
1. 校验 parsed.chapters 非空，否则抛 StateError('未识别到有效章节内容')
2. _db.transaction：
   a. createManuscript(title, description「从文件导入的作品（N章）」, genre)
   b. 逐章 createChapter(title, content, sortOrder: i+1)
      （记录第一章 id）
   c. 若 sessionId 非空 → addReference(sessionId, 'chapter', 第一章节 id, isPrimary: true)
      sessionId 为 null（书架导入）→ 跳过建引用
   d. 汇总 totalWords = Σ content.length → WorkImportResult
```

**原子性**：任一环节失败整体回滚（drift 事务），**不留半成品稿件**；章节 sort_order 从 1 开始递增。

---

## 4. 错误处理明细

| 环节 | 异常来源 | 处理方式 | 用户看到 |
|------|---------|---------|---------|
| `pickDocument` | 文件选择器异常 | 内部 `catch` 吞掉 | 返回 `null`（等同取消，不报错） |
| 用户取消选择 | 选择器返回 null / 空列表 / path 为 null | 返回 `null` | BookImportSheet 复位，无提示 |
| `readFileContent` | 文件不存在 / 无权限 / 读取失败 | **向上抛** | 「导入失败，请稍后重试」 |
| `parseDocument` | 解析逻辑（正则不抛异常） | 无异常路径 | — |
| `importWork` 空章节 | `StateError('未识别到有效章节内容')` | 向上抛 | 展示 StateError.message（「未识别到有效章节内容」） |
| 入库异常 | DB 约束 / IO | 向上抛（事务内回滚） | 「导入失败，请稍后重试」 |

### 4.1 BookImportSheet 错误呈现

```dart
String _friendlyError(Object e) {
  if (e is StateError) return e.message;   // 业务语义错误 → 透出原文
  return '导入失败，请稍后重试';            // 其余异常 → 通用文案，不暴露技术细节（release 静默）
}
```

错误显示在弹层内的红色警示框（`dangerBg` 底 + `danger` 字），**不弹系统对话框**；错误展示后 `_uploading` 复位，用户可再次点击「选择文件」重试。

### 4.2 成功反馈

书架导入成功后：关闭弹层 → SnackBar「已导入《X》（N章）」→ 刷新书架列表（`manuscriptStoreProvider.loadManuscripts`）。

### 4.3 重复导入

无幂等限制——同一文件可重复导入生成多本同标题书籍（每次均为新稿件，不查重）。

---

## 5. 测试覆盖

- `test/services/file_parser_test.dart`（8 条）：中文切章 / 英文 Chapter / 无标记兜底 / 标题过长不当标记 / md 切章 / md 兜底 / 扩展名路由 / 无扩展名标题兜底
- `test/services/work_import_service_test.dart`：导入事务（建书+章 / 主引用 / 回滚）
- `test/widgets/work_import_sheet_test.dart`：对话页导入弹层（取消 / 成功回调 / 错误展示，file_picker 用 fake 注入）
- `test/widgets/bookshelf_page_test.dart` #14/#15：书架入口 → 弹层 → 导入落库

---

## 6. 与 RN 的差异

| 项目 | RN | Flutter |
|------|-----|---------|
| 正则 | `/^(第[一二三四五六七八九十百千万\d]+[章节回幕篇]|Chapter\s*\d+)/i` | 语义一致，`caseSensitive: false` 等价 `/i` |
| 章节标题上限 | `FILE_PARSER_LIMITS.CHAPTER_TITLE_MAX_LENGTH = 50` | `< 50`（严格小于，RN 亦为 `<`） |
| md 标题上限 | `HEADING1_MAX_LENGTH = 80` | `< 80` |
| 书架导入建引用 | RN 书架无直接导入（仅对话页） | Flutter 新增 `importBookFromFile`（无会话 → 不建引用） |
| 取消语义 | 返回 null / 静默 | 同 |
| 错误文案 | 直接展示异常信息 | StateError 透出 + 其余通用文案（release 不暴露细节） |
