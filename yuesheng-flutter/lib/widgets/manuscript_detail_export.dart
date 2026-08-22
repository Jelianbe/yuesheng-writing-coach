// ignore_for_file: invalid_use_of_protected_member
part of 'manuscript_detail_page.dart';

extension _ManuscriptDetailExport on _ManuscriptDetailPageState {
  // ── 批次94-1：导出（单章 / 单卷 / 整书，TXT / Markdown）──

  /// 导出格式选择弹层（null = 取消）
  Future<ExportFormat?> _pickExportFormat() {
    return showYueModalBottomSheet<ExportFormat>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
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
              onTap: () => Navigator.pop(ctx, ExportFormat.txt),
            ),
            ListTile(
              leading: const Icon(
                Icons.notes_rounded,
                size: 18,
                color: AppColors.primary,
              ),
              title: const Text('Markdown'),
              onTap: () => Navigator.pop(ctx, ExportFormat.markdown),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _exportManuscript() async {
    final format = await _pickExportFormat();
    final ms = _manuscript;
    if (format == null || !mounted || ms == null) return;
    try {
      final db = ref.read(appDatabaseProvider);
      final chapters = await ChapterRepository(
        db,
      ).listChapters(widget.args.manuscriptId);
      final volumes = await VolumeRepository(
        db,
      ).listVolumes(widget.args.manuscriptId);
      final text = buildManuscriptExportText(
        ms,
        volumes,
        chapters,
        format: format,
      );
      final fileName = exportFileName('${ms.title}_整书', format);
      _snack('正在导出《${ms.title}》…');
      await shareTextExport(text: text, fileName: fileName, subject: ms.title);
    } catch (e) {
      debugPrint('[ManuscriptDetail] 整书导出失败: $e');
      if (!mounted) return;
      _snack('导出失败，请稍后再试');
    }
  }

  Future<void> _exportChapter(Chapter chapter) async {
    final format = await _pickExportFormat();
    if (format == null || !mounted) return;
    try {
      final ms = _manuscript;
      final base = '${ms?.title ?? ''}_${chapter.title}';
      final text = buildChapterExportText(chapter, format: format);
      _snack('正在导出《${chapter.title}》…');
      await shareTextExport(
        text: text,
        fileName: exportFileName(base, format),
        subject: chapter.title,
      );
    } catch (e) {
      debugPrint('[ManuscriptDetail] 单章导出失败: $e');
      if (!mounted) return;
      _snack('导出失败，请稍后再试');
    }
  }

  Future<void> _exportVolume(Volume volume) async {
    final format = await _pickExportFormat();
    if (format == null || !mounted) return;
    try {
      final db = ref.read(appDatabaseProvider);
      final all = await ChapterRepository(
        db,
      ).listChapters(widget.args.manuscriptId);
      final chapters = all.where((c) => c.volumeId == volume.id).toList();
      final text = buildVolumeExportText(volume, chapters, format: format);
      final ms = _manuscript;
      final base = '${ms?.title ?? ''}_${volume.title}';
      _snack('正在导出《${volume.title}》…');
      await shareTextExport(
        text: text,
        fileName: exportFileName(base, format),
        subject: volume.title,
      );
    } catch (e) {
      debugPrint('[ManuscriptDetail] 卷导出失败: $e');
      if (!mounted) return;
      _snack('导出失败，请稍后再试');
    }
  }
}
