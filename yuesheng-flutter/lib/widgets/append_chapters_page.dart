// ─────────────────────────────────────────────────────────────
// AppendChaptersPage — 追加章节导入页
// 真源：yuesheng-android/src/app/import-confirm.tsx
//
// 流程（对齐 RN handlePickFile → processContent → handleConfirm）：
//   1. 选择文件：pickDocument → readFileContent → parseDocument
//   2. 与已有章节标题比对（listChapters → Set(title.trim())）标记「已存在」
//   3. 章节列表：checkbox + 标题 + 字数 + 已存在徽标（已存在禁用、默认不选中）
//   4. 全选/取消（仅作用于新章节）
//   5. 确认导入 → createChaptersBatch 批量入库 → ImportSuccessSheet → 回稿件详情
//
// 入口：稿件详情章节列表「导入」按钮（对齐 RN ChapterSection 导入按钮）
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../config/app_theme.dart';
import 'yue_sheet.dart';
import '../data/repositories/chapter_repository.dart';
import '../providers/app_providers.dart';
import '../services/file_parser.dart';
import 'import_success_sheet.dart';

/// 解析后的章节（title + content）
class AppendChapterItem {
  final String title;
  final String content;
  const AppendChapterItem({required this.title, required this.content});
}

/// 追加章节导入页
class AppendChaptersPage extends ConsumerStatefulWidget {
  final String manuscriptId;
  final String manuscriptTitle;

  /// 选文件 + 解析回调（默认走 pickDocument 链路）。
  /// 测试注入用：FilePicker 插件在 widget 测试中不可用，返回 null 视为用户取消。
  final Future<List<AppendChapterItem>?> Function()? pickAndParseOverride;

  const AppendChaptersPage({
    super.key,
    required this.manuscriptId,
    required this.manuscriptTitle,
    this.pickAndParseOverride,
  });

  @override
  ConsumerState<AppendChaptersPage> createState() => _AppendChaptersPageState();
}

class _AppendChaptersPageState extends ConsumerState<AppendChaptersPage> {
  List<AppendChapterItem> _chapters = [];

  /// 已存在章节的索引集合（与已有章节标题重复，禁选）
  final Set<int> _exists = {};

  /// 当前选中的索引集合
  final Set<int> _selected = {};

  bool _picking = false;
  bool _importing = false;
  String? _error;

  int get _newChapterCount => _chapters.length - _exists.length;

  /// 默认选文件 + 解析链路（对齐 RN handlePickFile）
  Future<List<AppendChapterItem>?> _defaultPickAndParse() async {
    final picked = await pickDocument();
    if (picked == null) return null;
    final content = await readFileContent(picked.path);
    final parsed = parseDocument(content, picked.name);
    return [
      for (final ch in parsed.chapters)
        AppendChapterItem(title: ch.title, content: ch.content),
    ];
  }

  /// 选文件 → 解析 → 与已有章节比对（对齐 RN processContent）
  Future<void> _handlePickFile() async {
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      final loader = widget.pickAndParseOverride ?? _defaultPickAndParse;
      final chapters = await loader();
      if (chapters == null) {
        // 用户取消选择：复位
        if (mounted) setState(() => _picking = false);
        return;
      }
      if (!mounted) return;
      await _applyParsed(chapters);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e is StateError ? e.message : '文件读取失败，请稍后重试';
          _picking = false;
        });
      }
    }
  }

  /// 解析结果应用：比对已有章节 → 初始化选中集（对齐 RN processContent）
  Future<void> _applyParsed(List<AppendChapterItem> chapters) async {
    final repo = ChapterRepository(ref.read(appDatabaseProvider));
    final existing = await repo.listChapters(widget.manuscriptId);
    final existingTitles = {for (final c in existing) c.title.trim()};

    final exists = <int>{};
    for (var i = 0; i < chapters.length; i++) {
      if (existingTitles.contains(chapters[i].title.trim())) exists.add(i);
    }
    final selected = <int>{
      for (var i = 0; i < chapters.length; i++)
        if (!exists.contains(i)) i,
    };

    if (!mounted) return;
    setState(() {
      _chapters = chapters;
      _exists
        ..clear()
        ..addAll(exists);
      _selected
        ..clear()
        ..addAll(selected);
      _picking = false;
    });
  }

  void _handleToggleSelect(int index) {
    if (_exists.contains(index)) return;
    setState(() {
      if (_selected.contains(index)) {
        _selected.remove(index);
      } else {
        _selected.add(index);
      }
    });
  }

  void _handleSelectAll() {
    setState(() {
      _selected
        ..clear()
        ..addAll([
          for (var i = 0; i < _chapters.length; i++)
            if (!_exists.contains(i)) i,
        ]);
    });
  }

  void _handleDeselectAll() {
    setState(_selected.clear);
  }

  /// 确认导入：批量入库 → ImportSuccessSheet（对齐 RN handleConfirm）
  Future<void> _handleConfirm() async {
    if (_selected.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请至少选择一个章节')));
      return;
    }
    setState(() => _importing = true);
    try {
      final repo = ChapterRepository(ref.read(appDatabaseProvider));
      final toImport = [
        for (final i in _selected.toList()..sort())
          (title: _chapters[i].title, content: _chapters[i].content),
      ];
      final count = await repo.createChaptersBatch(
        widget.manuscriptId,
        toImport,
      );
      if (!mounted) return;
      setState(() => _importing = false);
      _showSuccessSheet(count);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '导入失败，请稍后重试';
          _importing = false;
        });
      }
    }
  }

  /// 成功引导弹层：chapterId 不传 → 不触发诊断，主按钮「返回作品」
  /// （对齐 RN import-confirm L248-260：onClose → replace /manuscript-detail）
  /// 批次78 M2：diagnoseEnabled=false 隐藏「立即诊断」引导，按钮名实相符；
  /// 批次78 L6：isDismissible=false 成功弹层强制按钮关闭，遮罩行为与按钮一致
  void _showSuccessSheet(int count) {
    showYueModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      builder: (_) => ImportSuccessSheet(
        manuscriptTitle: widget.manuscriptTitle,
        chapterCount: count,
        manuscriptId: widget.manuscriptId,
        diagnoseEnabled: false,
        onClose: _goBackToDetail,
        onDiagnose: _goBackToDetail,
      ),
    );
  }

  /// 回稿件详情（对齐 RN router.replace /manuscript-detail）
  void _goBackToDetail() {
    context.go(
      '/manuscript-detail',
      extra: <String, dynamic>{
        'manuscriptId': widget.manuscriptId,
        'title': widget.manuscriptTitle,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('追加章节'),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        toolbarHeight: 48,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, size: 22),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/bookshelf'),
          tooltip: '返回',
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildImportSection(),
                    if (_chapters.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      _buildChapterListSection(),
                    ],
                  ],
                ),
              ),
            ),
            if (_chapters.isNotEmpty) _buildFooter(),
          ],
        ),
      ),
    );
  }

  /// 选择导入方式区（对齐 RN「选择导入方式」section）
  Widget _buildImportSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '选择导入方式',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '将新章节追加到「${widget.manuscriptTitle}」',
          style: const TextStyle(fontSize: 13, color: AppColors.textTertiary),
        ),
        const SizedBox(height: 12),
        // 选择文件按钮（虚线边框，对齐 RN fileBtn）
        InkWell(
          onTap: _picking ? null : _handlePickFile,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Container(
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppColors.primary, width: 2),
            ),
            child: _picking
                ? const Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: AppColors.primary,
                      ),
                    ),
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // 批次66：📁 emoji → Material 图标（taste 审核：UI 图标走图标库）
                      Icon(
                        Icons.folder_open,
                        size: 20,
                        color: AppColors.primary,
                      ),
                      SizedBox(width: 8),
                      Text(
                        '选择文件',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.dangerBg,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Text(
              _error!,
              style: const TextStyle(fontSize: 13, color: AppColors.danger),
            ),
          ),
        ],
      ],
    );
  }

  /// 章节列表区（对齐 RN「章节列表」section）
  Widget _buildChapterListSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              '章节列表',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            Row(
              children: [
                _SelectAction(text: '全选', onTap: _handleSelectAll),
                const SizedBox(width: 12),
                _SelectAction(text: '取消', onTap: _handleDeselectAll),
              ],
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '已存在的章节会被标记，默认不选中（共 ${_chapters.length} 章，$_newChapterCount 章新增）',
          style: const TextStyle(fontSize: 13, color: AppColors.textTertiary),
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < _chapters.length; i++) ...[
          _ChapterRow(
            item: _chapters[i],
            index: i,
            isSelected: _selected.contains(i),
            isDisabled: _exists.contains(i),
            onToggle: () => _handleToggleSelect(i),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  /// 底部确认栏（对齐 RN footer）
  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 8, AppSpacing.lg, 24),
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: AppColors.borderSoft)),
      ),
      child: SafeArea(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '已选 ${_selected.length} 章',
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textTertiary,
              ),
            ),
            FilledButton(
              onPressed: (_selected.isEmpty || _importing)
                  ? null
                  : _handleConfirm,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                disabledBackgroundColor: AppColors.disabled,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xxl,
                  vertical: AppSpacing.md,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
              ),
              child: _importing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.onPrimary,
                      ),
                    )
                  : const Text(
                      '确认导入',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.onPrimary,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 全选 / 取消 小按钮（对齐 RN selectBtn）
class _SelectAction extends StatelessWidget {
  final String text;
  final VoidCallback onTap;
  const _SelectAction({required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xsm,
        ),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Text(
          text,
          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
      ),
    );
  }
}

/// 章节行：checkbox + 标题 + 字数 + 已存在徽标（对齐 RN chapterRow）
class _ChapterRow extends StatelessWidget {
  final AppendChapterItem item;
  final int index;
  final bool isSelected;
  final bool isDisabled;
  final VoidCallback onToggle;

  const _ChapterRow({
    required this.item,
    required this.index,
    required this.isSelected,
    required this.isDisabled,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: isDisabled ? null : onToggle,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Opacity(
        opacity: isDisabled ? 0.5 : 1,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.surfaceWhite,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.divider),
          ),
          child: Row(
            children: [
              // checkbox（对齐 RN checkbox）
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                  border: Border.all(
                    color: isSelected
                        ? AppColors.primary
                        : isDisabled
                        ? AppColors.disabled
                        : AppColors.border,
                    width: 2,
                  ),
                ),
                alignment: Alignment.center,
                child: isSelected
                    ? const Icon(
                        Icons.check,
                        size: 14,
                        color: AppColors.onPrimary,
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title.isEmpty ? '未命名章节' : item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${item.content.length} 字',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.disabledText,
                      ),
                    ),
                  ],
                ),
              ),
              if (isDisabled)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xxs,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.xs),
                  ),
                  child: const Text(
                    '已存在',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
