// ─────────────────────────────────────────────────────────────
// manuscript_detail_exporter — 作品详情页导出服务（独立类）
//
// 从 manuscript_detail_export.dart（原 part/extension）真分解而来。
// 导出（单章 / 单卷 / 整书，TXT / Markdown）被章节/卷/导航三方共同调用，
// 是共享服务，独立成类语义更清晰。
//
// 依赖经 [ManuscriptDetailHost] 显式注入，不回指宿主文件。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../data/database/database.dart';
import '../data/repositories/chapter_repository.dart';
import '../data/repositories/volume_repository.dart';
import '../providers/app_providers.dart';
import '../services/export_service.dart';
import 'manuscript_detail_host.dart';
import 'yue_sheet.dart';

/// 作品详情页导出动作
class ManuscriptDetailExporter {
  final ManuscriptDetailHost host;

  ManuscriptDetailExporter(this.host);

  /// 导出格式选择弹层（null = 取消）
  Future<ExportFormat?> pickExportFormat() {
    return showYueModalBottomSheet<ExportFormat>(
      context: host.context,
      builder: (ctx) => const _ExportFormatSheet(),
    );
  }

  /// 整书导出
  Future<void> exportManuscript() async {
    final format = await pickExportFormat();
    final ms = host.manuscript;
    if (format == null || !host.mounted || ms == null) return;
    try {
      final db = host.ref.read(appDatabaseProvider);
      final chapters = await ChapterRepository(
        db,
      ).listChapters(host.manuscriptId);
      final volumes = await VolumeRepository(db).listVolumes(host.manuscriptId);
      final text = buildManuscriptExportText(
        ms,
        volumes,
        chapters,
        format: format,
      );
      final fileName = exportFileName('${ms.title}_整书', format);
      host.showSnack('正在导出《${ms.title}》…');
      await shareTextExport(text: text, fileName: fileName, subject: ms.title);
    } catch (e) {
      debugPrint('[ManuscriptDetail] 整书导出失败: $e');
      if (!host.mounted) return;
      host.showSnack('导出失败，请稍后再试');
    }
  }

  /// 单章导出
  Future<void> exportChapter(Chapter chapter) async {
    final format = await pickExportFormat();
    if (format == null || !host.mounted) return;
    try {
      final ms = host.manuscript;
      final base = '${ms?.title ?? ''}_${chapter.title}';
      final text = buildChapterExportText(chapter, format: format);
      host.showSnack('正在导出《${chapter.title}》…');
      await shareTextExport(
        text: text,
        fileName: exportFileName(base, format),
        subject: chapter.title,
      );
    } catch (e) {
      debugPrint('[ManuscriptDetail] 单章导出失败: $e');
      if (!host.mounted) return;
      host.showSnack('导出失败，请稍后再试');
    }
  }

  /// 单卷导出
  Future<void> exportVolume(Volume volume) async {
    final format = await pickExportFormat();
    if (format == null || !host.mounted) return;
    try {
      final db = host.ref.read(appDatabaseProvider);
      final all = await ChapterRepository(db).listChapters(host.manuscriptId);
      final chapters = all.where((c) => c.volumeId == volume.id).toList();
      final text = buildVolumeExportText(volume, chapters, format: format);
      final ms = host.manuscript;
      final base = '${ms?.title ?? ''}_${volume.title}';
      host.showSnack('正在导出《${volume.title}》…');
      await shareTextExport(
        text: text,
        fileName: exportFileName(base, format),
        subject: volume.title,
      );
    } catch (e) {
      debugPrint('[ManuscriptDetail] 卷导出失败: $e');
      if (!host.mounted) return;
      host.showSnack('导出失败，请稍后再试');
    }
  }
}

/// 导出格式选择弹层内容（TXT / Markdown）
class _ExportFormatSheet extends StatelessWidget {
  const _ExportFormatSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.section,
              AppSpacing.lg,
              AppSpacing.section,
              AppSpacing.sm,
            ),
            child: Text(
              '导出为',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(
              Icons.description_outlined,
              size: 18,
              color: AppColors.primary,
            ),
            title: const Text('TXT 纯文本'),
            onTap: () => Navigator.pop(context, ExportFormat.txt),
          ),
          ListTile(
            leading: const Icon(
              Icons.notes_rounded,
              size: 18,
              color: AppColors.primary,
            ),
            title: const Text('Markdown'),
            onTap: () => Navigator.pop(context, ExportFormat.markdown),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
