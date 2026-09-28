// ─────────────────────────────────────────────────────────────
// yue_input_sheet — 月笙统一「文本输入」底部弹层
//
// P0-3：非破坏性输入（重命名 / 新建卷 / 新建章等单字段表单）从居中
// AlertDialog 收敛到底部 Sheet，统一走 showYueModalBottomSheet 展示。
// 独立 StatefulWidget 持有 TextEditingController，保证控制器随弹层
// 退出动画结束后再 dispose（对齐 goal_dialog 的寿命约束）。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../config/app_palette.dart';
import '../config/app_theme.dart';

/// 通用文本输入弹层（底部 Sheet 内容，配合 [showYueModalBottomSheet] 使用）
///
/// 通过 `Navigator.pop(context, text)` 返回用户输入；取消时 `pop(null)`。
class YueInputSheet extends StatefulWidget {
  /// 弹层标题
  final String title;

  /// 输入框占位提示
  final String hintText;

  /// 输入最大长度（TextField maxLength；null = 不限）
  final int? maxLength;

  /// 输入框 Key（测试定位用）
  final Key? fieldKey;

  /// 确认按钮文案
  final String confirmText;

  /// 初始值（重命名场景回填原名）
  final String? initialValue;

  /// 最大行数（多行输入场景，如粘贴/正文；默认 1 = 单行）
  final int maxLines;

  /// 最小行数（多行输入可选）
  final int? minLines;

  const YueInputSheet({
    super.key,
    required this.title,
    required this.hintText,
    this.maxLength,
    this.fieldKey,
    this.confirmText = '保存',
    this.initialValue,
    this.maxLines = 1,
    this.minLines,
  });

  @override
  State<YueInputSheet> createState() => _YueInputSheetState();
}

class _YueInputSheetState extends State<YueInputSheet> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        // 键盘弹起时上推内容，避免遮挡输入框
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(context),
            const Divider(height: 1),
            _buildBody(context),
            _buildActions(context),
          ],
        ),
      ),
    );
  }

  /// 弹层标题行
  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.section,
        AppSpacing.lg,
        AppSpacing.section,
        AppSpacing.sm,
      ),
      child: Text(
        widget.title,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: context.palette.textPrimary,
        ),
      ),
    );
  }

  /// 输入框区域
  Widget _buildBody(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.section),
      child: TextField(
        key: widget.fieldKey,
        controller: _controller,
        autofocus: true,
        maxLength: widget.maxLength,
        maxLines: widget.maxLines,
        minLines: widget.minLines,
        decoration: InputDecoration(
          hintText: widget.hintText,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  /// 取消 / 确认按钮行
  Widget _buildActions(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.section,
        0,
        AppSpacing.section,
        AppSpacing.section,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          const SizedBox(width: 8),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: context.palette.primary,
            ),
            onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
            child: Text(widget.confirmText),
          ),
        ],
      ),
    );
  }
}
