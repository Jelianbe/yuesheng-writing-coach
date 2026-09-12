// ─────────────────────────────────────────────────────────────
// bookshelf_edit_manuscript_dialog — 编辑作品信息弹窗
//
// 从 bookshelf_page.dart 家族真分解而来：原 `_handleEditInfo`（68 行 R-019
// 债务）中的弹窗 UI 在此提为独立有状态 Widget，控制器只负责「弹窗 → 校验 →
// 落库」编排。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../data/database/database.dart';

/// 编辑弹窗返回值（已 trim 的三项文本）
class ManuscriptEditInput {
  final String title;
  final String description;
  final String genre;

  const ManuscriptEditInput({
    required this.title,
    required this.description,
    required this.genre,
  });
}

/// 编辑作品信息弹窗（标题 / 简介 / 类型）
class BookshelfEditManuscriptDialog extends StatefulWidget {
  final Manuscript manuscript;

  const BookshelfEditManuscriptDialog({super.key, required this.manuscript});

  @override
  State<BookshelfEditManuscriptDialog> createState() =>
      _BookshelfEditManuscriptDialogState();
}

class _BookshelfEditManuscriptDialogState
    extends State<BookshelfEditManuscriptDialog> {
  late final TextEditingController _titleC = TextEditingController(
    text: widget.manuscript.title,
  );
  late final TextEditingController _descC = TextEditingController(
    text: widget.manuscript.description,
  );
  late final TextEditingController _genreC = TextEditingController(
    text: widget.manuscript.genre,
  );

  @override
  void dispose() {
    _titleC.dispose();
    _descC.dispose();
    _genreC.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.pop(
      context,
      ManuscriptEditInput(
        title: _titleC.text.trim(),
        description: _descC.text.trim(),
        genre: _genreC.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('编辑作品信息'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('edit-title-field'),
            controller: _titleC,
            maxLength: 30,
            decoration: const InputDecoration(
              labelText: '标题',
              hintText: '输入作品标题',
            ),
          ),
          TextField(
            controller: _descC,
            maxLines: 3,
            maxLength: 200,
            decoration: const InputDecoration(
              labelText: '简介',
              hintText: '一句话介绍你的作品',
            ),
          ),
          TextField(
            controller: _genreC,
            decoration: const InputDecoration(
              labelText: '类型',
              hintText: '如：奇幻、都市',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
          onPressed: _submit,
          child: const Text('保存'),
        ),
      ],
    );
  }
}
