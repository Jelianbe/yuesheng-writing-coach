// ─────────────────────────────────────────────────────────────
// bookshelf_create_modal — 新建作品弹窗
//
// 从 bookshelf_page.dart 宿主内嵌私有 `_CreateManuscriptModal` /
// `_CreateManuscriptModalState` 真分解提公而来。原 `build` 196 行
// （R-019 债务）在此**真拆**为弹窗骨架 + 各表单项工厂，每函数 ≤50 行。
//
// 批次93-5：体裁改 ChoiceChip 预设（番茄作家助手模型），选「其他」展开
// 自定义输入。批次 35：内置「从 TXT 文件导入书籍」入口。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import 'bookshelf_genre_section.dart';

/// 新建作品弹窗
class BookshelfCreateModal extends StatefulWidget {
  final TextEditingController titleController;
  final TextEditingController descController;
  final TextEditingController genreController;
  final VoidCallback onCancel;
  final Future<void> Function() onCreate;

  /// 批次 35：文本导入入口（关闭表单 → 打开导入弹层）
  final VoidCallback onImportTap;

  const BookshelfCreateModal({
    super.key,
    required this.titleController,
    required this.descController,
    required this.genreController,
    required this.onCancel,
    required this.onCreate,
    required this.onImportTap,
  });

  @override
  State<BookshelfCreateModal> createState() => _BookshelfCreateModalState();
}

class _BookshelfCreateModalState extends State<BookshelfCreateModal> {
  bool _isLoading = false;

  /// 标题为空时的行内错误提示（原 SnackBar 被弹窗遮挡不可见，改弹窗内展示）
  String? _titleError;

  /// 当前选中的体裁 Chip（空 = 未选）
  String _genre = '';

  /// 是否展开自定义体裁输入（选中「其他」时）
  bool _customGenre = false;

  Future<void> _handleCreate() async {
    if (_isLoading) return; // P1-1 防连点
    // 标题为空：弹窗内行内提示（原 SnackBar 在 dialog 之下被遮挡，用户不可见）
    if (widget.titleController.text.trim().isEmpty) {
      setState(() => _titleError = '请输入作品标题');
      return;
    }
    setState(() => _isLoading = true);
    try {
      await widget.onCreate();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// 批次93-5：体裁 Chip 选择 → 写入 genreController（onCreate 读取）
  void _selectGenre(String preset) {
    setState(() {
      _genre = preset;
      _customGenre = preset == '其他';
      if (!_customGenre) {
        widget.genreController.text = preset;
      } else {
        // 自定义：清空等待输入（未输入时回退「其他」）
        widget.genreController.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
          padding: const EdgeInsets.all(AppSpacing.xl),
          decoration: BoxDecoration(
            color: AppColors.surfaceWhite,
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '新建作品',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.titleLg,
                ),
                const SizedBox(height: 20),
                _buildTitleField(),
                const SizedBox(height: 14),
                _buildDescField(),
                const SizedBox(height: 14),
                _buildGenreSection(),
                const SizedBox(height: 24),
                _buildActions(),
                const SizedBox(height: 12),
                _buildImportButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 标题输入 + 行内错误提示
  Widget _buildTitleField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('标题', style: AppTextStyles.formLabel),
        const SizedBox(height: 6),
        TextField(
          controller: widget.titleController,
          autofocus: true,
          enabled: !_isLoading,
          onChanged: (_) {
            if (_titleError != null) {
              setState(() => _titleError = null);
            }
          },
          decoration: AppBoxStyles.standardInput(hintText: '输入作品标题'),
        ),
        if (_titleError != null) ...[
          const SizedBox(height: 6),
          Text(
            _titleError!,
            style: const TextStyle(fontSize: 13, color: AppColors.danger),
          ),
        ],
      ],
    );
  }

  /// 简介输入（可选，多行）
  Widget _buildDescField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '简介（可选）',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppColors.textBody,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: widget.descController,
          maxLines: 3,
          enabled: !_isLoading,
          decoration: AppBoxStyles.standardInput(hintText: '一句话介绍你的作品'),
        ),
      ],
    );
  }

  /// 类型区：Chip 预设 + 选中「其他」时展开自定义输入
  Widget _buildGenreSection() {
    return BookshelfGenreSection(
      controller: widget.genreController,
      selected: _genre,
      custom: _customGenre,
      enabled: !_isLoading,
      onPresetSelected: _selectGenre,
      onCustomChanged: (v) {
        // 输入非空时用输入值，留空回退「其他」
        if (v.trim().isNotEmpty) _genre = v.trim();
      },
    );
  }

  /// 底部取消 / 创建按钮行
  Widget _buildActions() {
    return Row(
      children: [
        Expanded(child: _buildCancelButton()),
        const SizedBox(width: 12),
        Expanded(child: _buildCreateButton()),
      ],
    );
  }

  Widget _buildCancelButton() {
    return TextButton(
      onPressed: _isLoading ? null : widget.onCancel,
      style: AppButtonStyles.secondary,
      child: const Text(
        '取消',
        style: TextStyle(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildCreateButton() {
    return ElevatedButton(
      onPressed: _isLoading ? null : _handleCreate,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      ),
      child: _isLoading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                color: AppColors.onPrimary,
                strokeWidth: 2,
              ),
            )
          : const Text(
              '创建',
              style: TextStyle(
                color: AppColors.onPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
    );
  }

  /// 批次 35：文本导入入口（对齐 RN WorkImportModal 选文件分支）
  Widget _buildImportButton() {
    return TextButton.icon(
      onPressed: _isLoading ? null : widget.onImportTap,
      icon: const Icon(
        Icons.file_open_outlined,
        size: 18,
        color: AppColors.primary,
      ),
      label: const Text(
        '从 TXT 文件导入书籍',
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: AppColors.primary,
        ),
      ),
    );
  }
}
