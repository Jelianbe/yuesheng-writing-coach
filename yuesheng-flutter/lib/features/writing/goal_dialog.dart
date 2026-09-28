// ─────────────────────────────────────────────────────────────
// 本章写作目标对话框（从 writing_page.dart 拆出）
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../../config/app_theme.dart';
import '../../config/app_palette.dart';

/// 独立 StatefulWidget 持有 TextEditingController，保证控制器随路由
/// 退出动画结束后再 dispose（避免「dispose 后再使用」崩溃）
class GoalDialog extends StatefulWidget {
  final int current;
  const GoalDialog({super.key, required this.current});

  @override
  State<GoalDialog> createState() => _GoalDialogState();
}

class _GoalDialogState extends State<GoalDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.current > 0 ? widget.current.toString() : '',
    );
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
        // 键盘弹起时上推内容
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
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Text(
        '本章写作目标',
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: context.palette.textPrimary,
        ),
      ),
    );
  }

  /// 说明 + 字数输入框
  Widget _buildBody(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.sm,
          ),
          child: Text(
            '目标字数（0 表示不设目标）',
            style: TextStyle(fontSize: 12, color: context.palette.textBody),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: TextField(
            key: const ValueKey('goal-word-field'),
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              hintText: '如 5000',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
        ),
      ],
    );
  }

  /// 清除目标 / 取消 / 保存按钮行
  Widget _buildActions(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (widget.current > 0)
            TextButton(
              onPressed: () => Navigator.of(context).pop(0),
              child: const Text('清除目标'),
            ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          const SizedBox(width: 8),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: context.palette.primary,
            ),
            onPressed: () {
              final v = int.tryParse(_controller.text.trim()) ?? 0;
              Navigator.of(context).pop(v < 0 ? 0 : v);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }
}
