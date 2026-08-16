// ─────────────────────────────────────────────────────────────
// export_service — 作品导出（批次94-1，TXT/Markdown）
//
// 依据：笔落导出教程——单章 / 单卷 / 整书三种粒度，共享系统分享面板。
// 分层：
//   1. 纯函数组装文本（buildXxxExportText）——可单测，不含 IO；
//   2. 文件落盘 + 系统分享（shareTextExport）——写临时目录后 SharePlus。
// 格式约定：
//   TXT       ：标题行 + 「───」分隔线 + 正文；卷之间「《卷名》」分隔
//   Markdown  ：`# 书名` / `## 卷名` / `### 章节标题` + 正文
// ─────────────────────────────────────────────────────────────

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
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
      return content.isEmpty
          ? '$head\n（本章暂无正文）'
          : '$head\n──────\n$content';
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
        (e) => buildChapterExportText(
          e.$2,
          format: format,
          chapterNo: e.$1 + 1,
        ),
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
  final groups = volumes.isEmpty ? const <VolumeGroup>[] : groupChaptersByVolume(volumes, chapters);

  String body;
  if (groups.isEmpty) {
    // 无卷：章节顺序平铺
    final sorted = [...chapters]
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    body = sorted.indexed
        .map(
          (e) => buildChapterExportText(
            e.$2,
            format: format,
            chapterNo: e.$1 + 1,
          ),
        )
        .join('\n\n');
  } else {
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
            : buildVolumeExportText(
                v,
                group.chapters,
                format: format,
              ),
      );
    }
    body = parts.where((s) => s.isNotEmpty).join('\n\n');
  }

  switch (format) {
    case ExportFormat.txt:
      return body.isEmpty ? '《$bookTitle》\n\n（暂无章节）' : '《$bookTitle》\n\n$body';
    case ExportFormat.markdown:
      return body.isEmpty ? '# $bookTitle\n\n（暂无章节）' : '# $bookTitle\n\n$body';
  }
}

/// 生成安全文件名（去除路径非法字符）
String exportFileName(String base, ExportFormat format) {
  final safe = base
      .replaceAll(RegExp(r'[\\/:*?"<>|]'), '')
      .trim();
  final name = safe.isEmpty ? '导出' : safe;
  return '$name.${format.extension}';
}

/// 写入临时目录并调起系统分享面板
Future<void> shareTextExport({
  required String text,
  required String fileName,
  String? subject,
}) async {
  final dir = await getTemporaryDirectory();
  final file = File(p.join(dir.path, fileName));
  await file.writeAsString(text, flush: true);
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path, mimeType: 'text/plain')],
      subject: subject,
    ),
  );
}
