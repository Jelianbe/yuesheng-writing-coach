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

import 'package:fast_gbk/fast_gbk.dart';
import 'package:file_picker/file_picker.dart';

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

/// 打开系统文件选择器（txt / markdown），取消或失败返回 null
Future<PickedDocument?> pickDocument() async {
  try {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['txt', 'md', 'markdown'],
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
/// 编码探测顺序：UTF-8 严格解码 → 失败则回退 GBK/GB18030
/// （`utf8.decode` 对非法序列抛 FormatException；GBK 解码覆盖
///  GB18030 常用汉字区，四字节扩展字失败时经 decode_guard 留痕后抛出）。
Future<String> readFileContent(String path) async {
  final file = File(path);
  final bytes = await file.readAsBytes();
  try {
    return utf8.decode(bytes);
  } on FormatException {
    try {
      return gbk.decode(bytes);
    } catch (e, st) {
      logDecodeFailure(field: 'fileContent', error: e, stack: st);
      rethrow;
    }
  }
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
  var currentChapterContent = '';
  String? currentVolumeTitle;
  String? chapterVolumeAtTitle;

  // 开始新章：提交旧章、设标题、快照当前卷
  void beginChapter(String newTitle) {
    _flushChapter(
      chapters,
      currentChapterTitle,
      currentChapterContent,
      chapterVolumeAtTitle ?? currentVolumeTitle,
    );
    currentChapterContent = '';
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
      currentChapterContent += '$line\n';
    }
  }
  _flushChapter(
    chapters,
    currentChapterTitle,
    currentChapterContent,
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

/// 解析 markdown 文件：按 md 层级切分。
/// 层级约定（FIX-3，对照 Kindle 教程 ##卷 ###章）：
///   - `# ` 一级标题 → 章（维持原行为）
///   - `## ` 二级标题 → 卷（切换当前卷，不闭合当前章）
///   - `### ` 三级标题 → 章
///   - 无井号前缀的 txt 风格标题（第一章/第1章）同样识别
ParsedFile parseMdFile(String content, String fileName) {
  final title = _stripExtension(fileName) ?? '未命名作品';
  final chapters = <ParsedChapter>[];
  final lines = content.split(RegExp(r'\r?\n'));
  var currentChapterTitle = '第一章';
  var currentChapterContent = '';
  String? currentVolumeTitle;
  String? chapterVolumeAtTitle;

  // 开始新章：提交旧章、设标题、快照当前卷
  void beginChapter(String newTitle) {
    _flushChapter(
      chapters,
      currentChapterTitle,
      currentChapterContent,
      chapterVolumeAtTitle ?? currentVolumeTitle,
    );
    currentChapterContent = '';
    currentChapterTitle = _cleanTitle(newTitle);
    chapterVolumeAtTitle = currentVolumeTitle;
  }

  for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.startsWith('## ') &&
        trimmed.length < FileParserLimits.heading1MaxLength) {
      currentVolumeTitle = _cleanTitle(trimmed);
    } else if (_isMdChapterHeading(trimmed)) {
      beginChapter(trimmed);
    } else if (_volumePattern.hasMatch(trimmed) &&
        trimmed.length < FileParserLimits.chapterTitleMaxLength) {
      currentVolumeTitle = _cleanTitle(trimmed);
    } else if (_chapterPattern.hasMatch(trimmed) &&
        trimmed.length < FileParserLimits.chapterTitleMaxLength) {
      beginChapter(trimmed);
    } else {
      currentChapterContent += '$line\n';
    }
  }
  _flushChapter(
    chapters,
    currentChapterTitle,
    currentChapterContent,
    chapterVolumeAtTitle ?? currentVolumeTitle,
  );
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
