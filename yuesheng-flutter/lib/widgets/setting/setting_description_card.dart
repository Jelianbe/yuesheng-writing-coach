// ─────────────────────────────────────────────────────────────
// setting_description_card — 设定资料库第四批：条目正文卡（共享组件）
//
//   角色 / 世界观详情页共用：
//   SettingDescriptionCard   正文展示卡（无正文 → 占位引导）
//   showDescriptionEditDialog 正文编辑弹窗（返回去 trim 的正文）
//
// 正文是「用户主权区」（R-009）：AI 抽取只写 assertions，不写 description；
// 此卡只由用户操作触发写入（repo.updateXxxDescription）。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../../config/app_theme.dart';
import '../../theme/app_typography.dart';

/// 正文展示卡：正文优先（无正文 → 「尚未写设定正文」占位 + 编辑引导）。
class SettingDescriptionCard extends StatelessWidget {
  final String description;
  final VoidCallback onEdit;

  const SettingDescriptionCard({
    super.key,
    required this.description,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final body = description.trim();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text('设定正文', style: context.text.titleMd)),
                TextButton(onPressed: onEdit, child: const Text('编辑')),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            if (body.isEmpty)
              InkWell(
                onTap: onEdit,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: Text(
                    '尚未写设定正文——点此写下这个设定是什么',
                    style: context.text.body.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              )
            else
              Text(body, style: context.text.body),
          ],
        ),
      ),
    );
  }
}

/// 正文编辑弹窗：多行文本框，取消返回 null，保存返回去 trim 后的正文。
Future<String?> showDescriptionEditDialog(
  BuildContext context, {
  required String initial,
}) {
  final ctrl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('编辑设定正文', style: context.text.titleLg),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        minLines: 6,
        maxLines: 14,
        decoration: const InputDecoration(
          hintText: '写下这个设定的内容——它是什么、怎么运作、有什么规则……',
          alignLabelWithHint: true,
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
          child: const Text('保存'),
        ),
      ],
    ),
  );
}
