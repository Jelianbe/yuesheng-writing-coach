// ─────────────────────────────────────────────────────────────
// export_service — 作品导出（批次94-1，TXT/Markdown）
//
// 依据：笔落导出教程——单章 / 单卷 / 整书三种粒度，共享系统分享面板。
// 分层：
//   1. 纯函数组装文本（buildXxxExportText）——可单测，不含 IO；
//   2. 系统分享（shareTextExport）——**内存态**交给 share_plus
//      （T-20261031-03 §九 #5：改收内存，不落临时文件 ⇒ 本文件不含平台 io 依赖）。
// 格式约定：
//   TXT       ：标题行 + 「───」分隔线 + 正文；卷之间「《卷名》」分隔
//   Markdown  ：`# 书名` / `## 卷名` / `### 章节标题` + 正文
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:share_plus/share_plus.dart';

import '../data/database/database.dart';
import '../utils/volume_group.dart';

/// 导出格式
enum ExportFormat {
  txt('TXT 纯文本'),
  markdown('Markdown');

  const ExportFormat(this.label);
  final String label;

  String get extension => this == ExportFormat.txt ? 'txt' : 'md';
}

/// 单章导出文本
String buildChapterExportText(
  Chapter chapter, {
  ExportFormat format = ExportFormat.txt,
  int? chapterNo,
}) {
  final title = chapter.title.trim().isEmpty ? '未命名章节' : chapter.title.trim();
  final content = chapter.content.trimRight();
  switch (format) {
    case ExportFormat.txt:
      final head = chapterNo == null ? title : '第$chapterNo章 $title';
      return content.isEmpty ? '$head\n（本章暂无正文）' : '$head\n──────\n$content';
    case ExportFormat.markdown:
      return content.isEmpty
          ? '### $title\n\n（本章暂无正文）'
          : '### $title\n\n$content';
  }
}

/// 单卷导出文本（卷内章节按 sort_order 拼接）
String buildVolumeExportText(
  Volume volume,
  List<Chapter> chapters, {
  ExportFormat format = ExportFormat.txt,
}) {
  final volTitle = volume.title.trim().isEmpty ? '未命名卷' : volume.title.trim();
  final sorted = [...chapters]
    ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  final body = sorted.indexed
      .map(
        (e) =>
            buildChapterExportText(e.$2, format: format, chapterNo: e.$1 + 1),
      )
      .join('\n\n');

  switch (format) {
    case ExportFormat.txt:
      return '《$volTitle》\n\n$body';
    case ExportFormat.markdown:
      return '## $volTitle\n\n$body';
  }
}

/// 整书导出文本（按卷分组，未分卷置末；无卷时按章节顺序平铺）
String buildManuscriptExportText(
  Manuscript manuscript,
  List<Volume> volumes,
  List<Chapter> chapters, {
  ExportFormat format = ExportFormat.txt,
}) {
  final bookTitle = manuscript.title.trim().isEmpty
      ? '未命名作品'
      : manuscript.title.trim();
  final groups = volumes.isEmpty
      ? const <VolumeGroup>[]
      : groupChaptersByVolume(volumes, chapters);
  final body = _buildBody(groups, chapters, format);

  switch (format) {
    case ExportFormat.txt:
      return body.isEmpty ? '《$bookTitle》\n\n（暂无章节）' : '《$bookTitle》\n\n$body';
    case ExportFormat.markdown:
      return body.isEmpty ? '# $bookTitle\n\n（暂无章节）' : '# $bookTitle\n\n$body';
  }
}

/// 组装整书正文：无卷时章节平铺，有卷时按卷分组（未分卷组置末）。
///
/// R-019：由 [buildManuscriptExportText] 抽出，主函数只保留标题解析与
/// 格式包装（53 → 18 行）。分组策略本身未改，仅移动到此处。
String _buildBody(
  List<VolumeGroup> groups,
  List<Chapter> chapters,
  ExportFormat format,
) {
  if (groups.isEmpty) {
    // 无卷：章节顺序平铺
    final sorted = [...chapters]
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return sorted.indexed
        .map(
          (e) =>
              buildChapterExportText(e.$2, format: format, chapterNo: e.$1 + 1),
        )
        .join('\n\n');
  }

  final parts = <String>[];
  for (final group in groups) {
    final v = group.volume;
    parts.add(
      v == null
          // 未分卷组
          ? group.chapters.indexed
                .map(
                  (e) => buildChapterExportText(
                    e.$2,
                    format: format,
                    chapterNo: e.$1 + 1,
                  ),
                )
                .join('\n\n')
          : buildVolumeExportText(v, group.chapters, format: format),
    );
  }
  return parts.where((s) => s.isNotEmpty).join('\n\n');
}

/// 生成安全文件名（去除路径非法字符）
String exportFileName(String base, ExportFormat format) {
  final safe = base.replaceAll(RegExp(r'[\\/:*?"<>|]'), '').trim();
  final name = safe.isEmpty ? '导出' : safe;
  return '$name.${format.extension}';
}

/// 把导出文本以**内存态**交给系统分享面板。
///
/// ★ 移动端零行为变化：share_plus 在移动端会把 `XFile.fromData` 的字节
///   **内部落临时文件**后再交给系统分享 ⇒ 与拆分前「自己写临时目录再分享」
///   的最终产物一致（文件名取 [fileName]、mimeType 同为 `text/plain`）。
///   本函数自己不再碰平台 io 库 ⇒ web 编译期无 io 面。
Future<void> shareTextExport({
  required String text,
  required String fileName,
  String? subject,
}) async {
  await SharePlus.instance.share(
    ShareParams(
      files: [
        XFile.fromData(
          utf8.encode(text),
          name: fileName,
          mimeType: 'text/plain',
        ),
      ],
      // ★ `XFile.fromData` 的 `name` 在**非 web 平台会被 cross_file 忽略**
      //   （share_plus 12.0.2 `lib/share_plus.dart:216-219` 官方文档逐字：
      //   "name property will be ignored by cross_file on all platforms except on web"）
      //   ⇒ 必须显式传 `fileNameOverrides`，否则 share_plus 内部落临时文件时
      //   文件名退化成 `<uuid>.json` ⇒ **移动端分享出去的文件名变了**（判据 2 红）。
      fileNameOverrides: [fileName],
      subject: subject,
    ),
  );
}
