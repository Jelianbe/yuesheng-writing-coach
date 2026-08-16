// ─────────────────────────────────────────────────────────────
// 本章写作目标对话框（从 writing_page.dart 拆出）
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../../config/app_theme.dart';

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
    return AlertDialog(
      title: const Text('本章写作目标'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '目标字数（0 表示不设目标）',
            style: TextStyle(fontSize: 12, color: AppColors.textBody),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              hintText: '如 5000',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        if (widget.current > 0)
          TextButton(
            onPressed: () => Navigator.of(context).pop(0),
            child: const Text('清除目标'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
          onPressed: () {
            final v = int.tryParse(_controller.text.trim()) ?? 0;
            Navigator.of(context).pop(v < 0 ? 0 : v);
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}
