// ─────────────────────────────────────────────────────────────
// file_parser — 文件选择 + 内容解析服务
// 真源：yuesheng-android/src/services/file-parser.ts
//
// 职责：
//   1. pickDocument：调 file_picker 选择 txt/md 文件
//   2. readFileContent：读取本地文件文本（UTF-8 优先，GBK/GB18030 回退）
//   3. parseTxtFile：按章节/卷标记切分（第X章/Chapter N/序章/卷级变体）
//   4. parseMdFile：按 md 层级切分（# 章 / ## 卷 / ### 章 + txt 风格标题）
//   5. parseDocument：按扩展名路由到对应解析器
//
// 产物 ParsedFile：title + genre('未知') + chapters[]（章节可带 volumeTitle）
// ─────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:fast_gbk/fast_gbk.dart';
import 'package:file_picker/file_picker.dart';
import 'package:xml/xml.dart';

import '../config/shared_constants.dart';
import 'decode_guard.dart';

/// 解析出的章节
class ParsedChapter {
  final String title;
  final String content;

  /// 所属卷标题（导入时据此建卷；null = 未分卷）
  final String? volumeTitle;

  const ParsedChapter({
    required this.title,
    required this.content,
    this.volumeTitle,
  });
}

/// 解析出的文件（作品雏形）
class ParsedFile {
  final String title;
  final String genre;
  final List<ParsedChapter> chapters;

  const ParsedFile({
    required this.title,
    required this.genre,
    required this.chapters,
  });
}

/// 选中的文件
class PickedDocument {
  final String path;
  final String name;

  const PickedDocument({required this.path, required this.name});
}

/// 打开系统文件选择器（txt / markdown / docx），取消或失败返回 null
Future<PickedDocument?> pickDocument() async {
  try {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      // C144 W1：放行 docx（ZIP→纯文本，readFileContent 按扩展名分流）
      allowedExtensions: const ['txt', 'md', 'markdown', 'docx'],
    );
    if (result == null || result.files.isEmpty) return null;
    final file = result.files.first;
    final path = file.path;
    if (path == null) return null;
    return PickedDocument(path: path, name: file.name);
  } catch (e, st) {
    logDecodeFailure(field: 'fileContent', error: e, stack: st);
    return null;
  }
}

/// 读取本地文件文本（失败抛异常，由调用方处理）
///
/// 编码探测顺序：
///   1. BOM 嗅探：`EF BB BF`(UTF-8 BOM) / `FF FE`(UTF-16 LE) / `FE FF`(UTF-16 BE)
///   2. 无 BOM：UTF-8 严格解码 → 失败回退 GBK/GB18030
/// （`utf8.decode` 对非法序列抛 FormatException；GBK 解码覆盖 GB18030
///  常用汉字区，四字节扩展字失败时经 decode_guard 留痕后抛出）。
///
/// A7：读字节前先 stat 拿大小，超过 [FileParserLimits.maxImportBytes] 直接抛
/// [StateError]「文件过大已跳过」，不把整文件读进内存（防 OOM）。
Future<String> readFileContent(String path) async {
  final file = File(path);
  final stat = await file.stat();
  if (stat.size > FileParserLimits.maxImportBytes) {
    throw StateError('文件过大已跳过');
  }
  final bytes = await file.readAsBytes();
  // C144 W1：.docx = ZIP 容器，字节不是文本，不复用编码探测，走专用提取。
  // 失败（非 ZIP / 缺 document.xml / XML 损坏）经 decode_guard 留痕后上抛，
  // 由调用方边界提示（与 txt 路径同一契约：不静默吞、不崩）。
  if (path.toLowerCase().endsWith('.docx')) {
    try {
      return extractDocxText(bytes);
    } catch (e, st) {
      logDecodeFailure(field: 'docxContent', error: e, stack: st);
      rethrow;
    }
  }
  return _decodeByBom(bytes);
}

/// 从 .docx（ZIP 容器）字节提取纯文本（C144 W1，公开以便单测直接喂字节）。
///
/// .docx 结构：ZIP 包 `word/document.xml`，正文在 `<w:p>`（段落）内的
/// `<w:t>`（文本 run）。本函数只取文本层：段落间换行分隔，随后复用既有
/// [parseDocument] 的 txt 切章——不改 prompt、不解析样式/图片。
///
/// 命名按 XML local 名匹配（`p`/`t`），与 `w:` 前缀解耦。
/// 非 ZIP / 缺 document.xml / XML 损坏时抛异常（R-028 边界由调用方留痕）。
String extractDocxText(List<int> bytes) {
  final archive = ZipDecoder().decodeBytes(bytes, verify: true);
  ArchiveFile? docEntry;
  for (final f in archive.files) {
    if (f.isFile && f.name == 'word/document.xml') {
      docEntry = f;
      break;
    }
  }
  if (docEntry == null) {
    throw const FormatException('docx 容器缺少 word/document.xml');
  }
  final raw = docEntry.content;
  final document = XmlDocument.parse(utf8.decode(raw as List<int>));
  final buffer = StringBuffer();
  for (final el in document.rootElement.descendants.whereType<XmlElement>()) {
    if (el.name.local != 'p') continue;
    // 段落内所有 <w:t> 文本 run 顺序拼接（含 run 内不补空格，还原 Word 连写）
    for (final t in el.descendants.whereType<XmlElement>()) {
      if (t.name.local == 't') buffer.write(t.innerText);
    }
    buffer.write('\n');
  }
  return buffer.toString().trim();
}

/// 按 BOM / 编码探测解码字节串，返回正文（已剥 BOM）
String _decodeByBom(List<int> bytes) {
  // UTF-8 BOM：EF BB BF → 剥 BOM 字节后走 UTF-8 严格解码
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    return _stripBom(utf8.decode(bytes.sublist(3)));
  }
  // UTF-16 LE BOM：FF FE → 剥 BOM 按小端解码
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
    return _decodeUtf16(bytes.sublist(2), littleEndian: true);
  }
  // UTF-16 BE BOM：FE FF → 剥 BOM 按大端解码
  if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
    return _decodeUtf16(bytes.sublist(2), littleEndian: false);
  }
  // 无 BOM：维持原有 UTF-8 严格 → GBK 回退路径（不退化）
  try {
    return _stripBom(utf8.decode(bytes));
  } on FormatException {
    try {
      return gbk.decode(bytes);
    } catch (e, st) {
      logDecodeFailure(field: 'fileContent', error: e, stack: st);
      rethrow;
    }
  }
}

/// B6：剥离开头的 U+FEFF。UTF-8 带 BOM 时 `utf8.decode` 会把 `EF BB BF`
/// 解成一个 U+FEFF 留在串首——`String.trim()` 不剔除它，而章节正则 `\s`
/// 也不匹配它，导致首行「第X章」不被识别、首章内容错位。
String _stripBom(String s) =>
    s.isNotEmpty && s.codeUnitAt(0) == 0xFEFF ? s.substring(1) : s;

/// 手动解码 UTF-16（dart:convert 无内置 UTF-16 解码器，且禁止新增依赖）。
/// BOM 已由调用方剥除；按端序拼出 16 位 code unit 列表，交由
/// [String.fromCharCodes] 正确处理代理对（增补字符/emoji）。末尾落单字节忽略。
String _decodeUtf16(List<int> bytes, {required bool littleEndian}) {
  final units = <int>[];
  for (var i = 0; i + 1 < bytes.length; i += 2) {
    final b0 = bytes[i];
    final b1 = bytes[i + 1];
    units.add(littleEndian ? (b0 | (b1 << 8)) : ((b0 << 8) | b1));
  }
  return String.fromCharCodes(units);
}

// ─────────────────────────────────────────────────────────────
// 章节/卷标题识别（FIX-3 扩展）
// 对照同行（Reader Copilot 七后缀、VS Code 序开头、txt-to-epub 多编码）
// ─────────────────────────────────────────────────────────────

/// 标题数字部分：阿拉伯 / 全角 / 中文大小写数字（上限 12 位，对齐 Reader Copilot）
final RegExp _titleNum = RegExp(r'[0-9０-９一二三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾]{1,12}');

/// 卷级标题前缀：第X卷/第X部/序卷/序部/卷一/Part 1（可带括号、空格）
/// 「序」分支要求后接空白或行尾（防正文「序言…」误伤）
final RegExp _volumePattern = RegExp(
  r'^\s*[【\[（(]?\s*(?:'
          r'第\s*' +
      _titleNum.pattern +
      r'\s*[卷部]'
          r'|序\s*[卷部](?=[\s　]|$)'
          r'|卷\s*' +
      _titleNum.pattern +
      r''
          r'|Part\s*\d+'
          r')',
  caseSensitive: false,
);

/// 章级标题前缀：第X章/Chapter N/序章（可带括号、空格、# 前缀）
/// 「序」分支要求后接空白或行尾（防正文「序章内容…」误伤）
final RegExp _chapterPattern = RegExp(
  r'^#?\s*[【\[（(]?\s*(?:'
          r'第\s*' +
      _titleNum.pattern +
      r'\s*[章节回幕篇集節]'
          r'|序\s*[章节回幕篇集節](?=[\s　]|$)'
          r'|Chapter\s*\d+'
          r')',
  caseSensitive: false,
);

/// 去掉标题外围的 md 井号 / 括号 / 空白，返回干净标题
String _cleanTitle(String raw) {
  return raw
      .replaceFirst(RegExp(r'^#+\s*'), '')
      .replaceFirst(RegExp(r'^[【\[（(]\s*'), '')
      .replaceFirst(RegExp(r'\s*[】\]）)]$'), '')
      .trim();
}

/// 提交当前章节（内容非空才提交，无章标记的纯内容归当前卷）
void _flushChapter(
  List<ParsedChapter> chapters,
  String title,
  String content,
  String? volumeTitle,
) {
  if (content.trim().isNotEmpty) {
    chapters.add(
      ParsedChapter(
        title: title,
        content: content.trim(),
        volumeTitle: volumeTitle,
      ),
    );
  }
}

/// 解析 txt 文件：按「第X章/序章/第X卷/Chapter N」等标记切分。
///
/// 卷语义（FIX-3）：卷标记（第X卷/第一部/Part N）只切换当前卷、
/// 不闭合当前章；章节在「章标题出现时」快照所属卷（chapterVolumeAtTitle），
/// 提交时用快照（无章标记的纯内容则归当前卷）。
ParsedFile parseTxtFile(String content, String fileName) {
  final title = _stripExtension(fileName) ?? '未命名作品';
  final chapters = <ParsedChapter>[];
  final lines = content.split(RegExp(r'\r?\n'));
  var currentChapterTitle = '第一章';
  // B5：StringBuffer 替代 String +=，避免大文件正文 O(n²) 拷贝卡主线程
  var currentChapterContent = StringBuffer();
  String? currentVolumeTitle;
  String? chapterVolumeAtTitle;

  // 开始新章：提交旧章、设标题、快照当前卷
  void beginChapter(String newTitle) {
    _flushChapter(
      chapters,
      currentChapterTitle,
      currentChapterContent.toString(),
      chapterVolumeAtTitle ?? currentVolumeTitle,
    );
    currentChapterContent = StringBuffer();
    currentChapterTitle = _cleanTitle(newTitle);
    chapterVolumeAtTitle = currentVolumeTitle;
  }

  for (final line in lines) {
    final trimmed = line.trim();
    if (_volumePattern.hasMatch(trimmed) &&
        trimmed.length < FileParserLimits.chapterTitleMaxLength) {
      currentVolumeTitle = _cleanTitle(trimmed);
    } else if (_chapterPattern.hasMatch(trimmed) &&
        trimmed.length < FileParserLimits.chapterTitleMaxLength) {
      beginChapter(trimmed);
    } else {
      currentChapterContent
        ..write(line)
        ..write('\n');
    }
  }
  _flushChapter(
    chapters,
    currentChapterTitle,
    currentChapterContent.toString(),
    chapterVolumeAtTitle ?? currentVolumeTitle,
  );
  if (chapters.isEmpty) {
    chapters.add(ParsedChapter(title: '第一章', content: content.trim()));
  }
  return ParsedFile(title: title, genre: '未知', chapters: chapters);
}

/// md 章级标题（# 或 ### 开头，## 为卷级）
bool _isMdChapterHeading(String trimmed) {
  return (trimmed.startsWith('# ') || trimmed.startsWith('### ')) &&
      trimmed.length < FileParserLimits.heading1MaxLength;
}

/// md 解析状态机（R-019 真分解：ADR-C112 ④）。
///
/// ★ 两条不变点（改动前务必确认，颠倒即错）：
/// 1. `chapterVolumeAtTitle` **初值为 null**，且只在 `beginChapter` 里被赋成
///    「当时的 `currentVolumeTitle`」⇒ 章挂的是**章开始时的卷快照**，不是结束时。
/// 2. `beginChapter` 内顺序是「**先 flush 旧章，后更新标题/快照**」；
///    提交时卷取 `chapterVolumeAtTitle ?? currentVolumeTitle`（**回退不可删** ——
///    首章之前才出现卷标题时快照为 null，靠它挂到当前卷）。
class _MdParseState {
  _MdParseState(this.chapters);

  final List<ParsedChapter> chapters;

  String currentChapterTitle = '第一章';
  // B5：StringBuffer 替代 String +=，避免大文件正文 O(n²) 拷贝卡主线程
  StringBuffer currentChapterContent = StringBuffer();
  String? currentVolumeTitle;
  String? chapterVolumeAtTitle;

  /// 开始新章：提交旧章（挂旧卷快照 / 无快照则回退当前卷）→ 设新标题 → 快照当前卷。
  void beginChapter(String newTitle) {
    flush();
    currentChapterTitle = _cleanTitle(newTitle);
    chapterVolumeAtTitle = currentVolumeTitle;
  }

  void appendLine(String line) {
    currentChapterContent
      ..write(line)
      ..write('\n');
  }

  /// 提交当前章并重置缓冲（**替换** StringBuffer，不是 clear）。
  void flush() {
    _flushChapter(
      chapters,
      currentChapterTitle,
      currentChapterContent.toString(),
      chapterVolumeAtTitle ?? currentVolumeTitle,
    );
    currentChapterContent = StringBuffer();
  }
}

/// 解析 markdown 文件：按 md 层级切分。
/// 层级约定（FIX-3，对照 Kindle 教程 ##卷 ###章）：
///   - `# ` 一级标题 → 章（维持原行为）
///   - `## ` 二级标题 → 卷（切换当前卷，不闭合当前章）
///   - `### ` 三级标题 → 章
///   - 无井号前缀的 txt 风格标题（第一章/第1章）同样识别
ParsedFile parseMdFile(String content, String fileName) {
  final title = _stripExtension(fileName) ?? '未命名作品';
  final chapters = <ParsedChapter>[];
  final state = _MdParseState(chapters);
  final lines = content.split(RegExp(r'\r?\n'));

  for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.startsWith('## ') &&
        trimmed.length < FileParserLimits.heading1MaxLength) {
      state.currentVolumeTitle = _cleanTitle(trimmed);
    } else if (_isMdChapterHeading(trimmed)) {
      state.beginChapter(trimmed);
    } else if (_volumePattern.hasMatch(trimmed) &&
        trimmed.length < FileParserLimits.chapterTitleMaxLength) {
      state.currentVolumeTitle = _cleanTitle(trimmed);
    } else if (_chapterPattern.hasMatch(trimmed) &&
        trimmed.length < FileParserLimits.chapterTitleMaxLength) {
      state.beginChapter(trimmed);
    } else {
      state.appendLine(line);
    }
  }
  state.flush();
  if (chapters.isEmpty) {
    chapters.add(ParsedChapter(title: '第一章', content: content.trim()));
  }
  return ParsedFile(title: title, genre: '未知', chapters: chapters);
}

/// 按扩展名路由：.md/.markdown → md 解析，其余 → txt 解析
ParsedFile parseDocument(String content, String fileName) {
  final lowerName = fileName.toLowerCase();

  if (lowerName.endsWith('.md') || lowerName.endsWith('.markdown')) {
    return parseMdFile(content, fileName);
  }

  return parseTxtFile(content, fileName);
}

/// 去除文件扩展名（.txt/.md 等）
String? _stripExtension(String fileName) {
  final dotIndex = fileName.lastIndexOf('.');
  if (dotIndex <= 0) return null;
  return fileName.substring(0, dotIndex);
}
