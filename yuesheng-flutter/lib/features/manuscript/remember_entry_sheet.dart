// ─────────────────────────────────────────────────────────────
// RememberEntrySheet — 「记一下 / 存入设定库」统一确认卡（C147）
//
// 两处入口共用：
//   1. 聊天页长按消息 →「记一下」（message_list.dart）
//   2. 写作页划词菜单 →「存入设定库」（writing_page_chrome.dart）
//
// R-009（写死）：
//   - 原文摘录 = 整句/整段**搬运**进可编辑框，作者可改；本卡不改写/提炼原文。
//   - 目标位置（人设/世界观/大纲）**仅作者自选**，AI 不替作者定性。
//   - 确认后由调用方落 record_entry.proposePending（pending）；作者后续在
//     资料库 tab 裁决 kept/rejected。两级裁决，AI 不替作者决定哪条值得记。
//
// R-027：本卡是纯本地 UI + DB 操作，不触任何 prompt/注入链。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../../config/app_palette.dart';
import '../../config/app_theme.dart';
import '../../theme/app_typography.dart';
import '../../widgets/yue_sheet.dart';

/// 记录条目目标位置常量（与 record_entry.target_section 列对齐；消费方不得裸写字符串）。
class RememberTarget {
  /// 未定（作者未选归入位置）
  static const String unset = '';

  /// 人设（角色）
  static const String character = 'character';

  /// 大纲
  static const String outline = 'outline';

  /// 世界观
  static const String world = 'world';

  const RememberTarget._();

  /// 展示名（资料库 pending 列表/确认卡用）
  static String labelOf(String value) {
    switch (value) {
      case character:
        return '人设';
      case outline:
        return '大纲';
      case world:
        return '世界观';
      default:
        return '未定';
    }
  }
}

/// 确认卡返回结果（作者已确认）。
class RememberEntryResult {
  final String excerpt;
  final String targetSection;

  const RememberEntryResult({
    required this.excerpt,
    required this.targetSection,
  });
}

/// 弹出确认卡。取消/点外部返回 null；确认返回 [RememberEntryResult]。
Future<RememberEntryResult?> showRememberEntrySheet(
  BuildContext context, {
  required String initialExcerpt,
}) {
  return showYueModalBottomSheet<RememberEntryResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.palette.surface,
    builder: (_) => _RememberSheet(initialExcerpt: initialExcerpt),
  );
}

class _RememberSheet extends StatefulWidget {
  final String initialExcerpt;

  const _RememberSheet({required this.initialExcerpt});

  @override
  State<_RememberSheet> createState() => _RememberSheetState();
}

class _RememberSheetState extends State<_RememberSheet> {
  late final TextEditingController _controller;
  String _target = RememberTarget.character;

  @override
  void initState() {
    super.initState();
    // 原文整句搬运进可编辑框（作者可改）——不做任何改写/截断。
    _controller = TextEditingController(text: widget.initialExcerpt);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _confirm() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    Navigator.of(
      context,
    ).pop(RememberEntryResult(excerpt: text, targetSection: _target));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(context),
            const SizedBox(height: AppSpacing.lg),
            _buildExcerptField(context),
            const SizedBox(height: AppSpacing.lg),
            _buildTargetSelector(context),
            const SizedBox(height: AppSpacing.lg),
            _buildActions(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Column(
      children: [
        Text('记一下', textAlign: TextAlign.center, style: context.text.titleLg),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '原文已整段填入，可编辑；归入位置由你决定。确认后进资料库待整理。',
          textAlign: TextAlign.center,
          style: context.text.subBody,
        ),
      ],
    );
  }

  Widget _buildExcerptField(BuildContext context) {
    return TextField(
      controller: _controller,
      maxLines: 6,
      minLines: 3,
      autofocus: true,
      style: context.text.body,
      decoration: InputDecoration(
        hintText: '原文摘录',
        filled: true,
        fillColor: context.palette.background,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: context.palette.borderSoft),
        ),
      ),
    );
  }

  Widget _buildTargetSelector(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('归入位置', style: context.text.subBody),
        const SizedBox(height: AppSpacing.sm),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: RememberTarget.character, label: Text('人设')),
            ButtonSegment(value: RememberTarget.outline, label: Text('大纲')),
            ButtonSegment(value: RememberTarget.world, label: Text('世界观')),
          ],
          selected: {_target},
          showSelectedIcon: false,
          onSelectionChanged: (s) => setState(() => _target = s.first),
        ),
      ],
    );
  }

  Widget _buildActions(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextButton(
            onPressed: () => Navigator.of(context).pop(),
            style: AppButtonStyles.secondary,
            child: Text(
              '取消',
              style: TextStyle(
                color: context.palette.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: FilledButton(
            onPressed: _confirm,
            style: FilledButton.styleFrom(
              backgroundColor: context.palette.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            ),
            child: Text(
              '确认存入',
              style: TextStyle(
                color: context.palette.onPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
