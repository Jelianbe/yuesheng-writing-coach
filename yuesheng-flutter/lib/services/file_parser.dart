// ─────────────────────────────────────────────────────────────
// file_parser — 文件选择 + 内容解析服务
// 真源：yuesheng-android/src/services/file-parser.ts
//
// 职责：
//   1. pickDocument：调 file_picker 选择 txt/md 文件
//   2. readFileContent：读取本地文件文本
//   3. parseTxtFile：按「第X章/Chapter N」正则切章
//   4. parseMdFile：按 `# ` 一级标题切章
//   5. parseDocument：按扩展名路由到对应解析器
//
// 产物 ParsedFile：title + genre('未知') + chapters[]
// ─────────────────────────────────────────────────────────────

import 'dart:io';

import 'package:file_picker/file_picker.dart';

import '../config/shared_constants.dart';

/// 解析出的章节
class ParsedChapter {
  final String title;
  final String content;

  const ParsedChapter({required this.title, required this.content});
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
  } catch (_) {
    return null;
  }
}

/// 读取本地文件文本（失败抛异常，由调用方处理）
Future<String> readFileContent(String path) async {
  final file = File(path);
  return file.readAsString();
}

/// 解析 txt 文件：按「第X章/第X节/Chapter N」等章节标记切分
ParsedFile parseTxtFile(String content, String fileName) {
  final title = _stripExtension(fileName) ?? '未命名作品';

  final chapters = <ParsedChapter>[];
  final lines = content.split(RegExp(r'\r?\n'));

  var currentChapterTitle = '第一章';
  var currentChapterContent = '';

  // 真源正则：/^(第[一二三四五六七八九十百千万\d]+[章节回幕篇]|Chapter\s*\d+)/i
  final chapterPattern = RegExp(
    r'^(第[一二三四五六七八九十百千万\d]+[章节回幕篇]|Chapter\s*\d+)',
    caseSensitive: false,
  );

  for (final line in lines) {
    final trimmed = line.trim();

    if (chapterPattern.hasMatch(trimmed) &&
        trimmed.length < FileParserLimits.chapterTitleMaxLength) {
      if (currentChapterContent.trim().isNotEmpty) {
        chapters.add(
          ParsedChapter(
            title: currentChapterTitle,
            content: currentChapterContent.trim(),
          ),
        );
      }
      currentChapterTitle = trimmed;
      currentChapterContent = '';
    } else {
      currentChapterContent += '$line\n';
    }
  }

  if (currentChapterContent.trim().isNotEmpty) {
    chapters.add(
      ParsedChapter(
        title: currentChapterTitle,
        content: currentChapterContent.trim(),
      ),
    );
  }

  if (chapters.isEmpty) {
    chapters.add(ParsedChapter(title: '第一章', content: content.trim()));
  }

  return ParsedFile(title: title, genre: '未知', chapters: chapters);
}

/// 解析 markdown 文件：按 `# ` 一级标题切分
ParsedFile parseMdFile(String content, String fileName) {
  final title = _stripExtension(fileName) ?? '未命名作品';

  final chapters = <ParsedChapter>[];
  final lines = content.split(RegExp(r'\r?\n'));

  var currentChapterTitle = '第一章';
  var currentChapterContent = '';

  for (final line in lines) {
    if (line.startsWith('# ') &&
        line.length < FileParserLimits.heading1MaxLength) {
      if (currentChapterContent.trim().isNotEmpty) {
        chapters.add(
          ParsedChapter(
            title: currentChapterTitle,
            content: currentChapterContent.trim(),
          ),
        );
      }
      currentChapterTitle = line.replaceFirst(RegExp(r'^#\s*'), '');
      currentChapterContent = '';
    } else {
      currentChapterContent += '$line\n';
    }
  }

  if (currentChapterContent.trim().isNotEmpty) {
    chapters.add(
      ParsedChapter(
        title: currentChapterTitle,
        content: currentChapterContent.trim(),
      ),
    );
  }

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
