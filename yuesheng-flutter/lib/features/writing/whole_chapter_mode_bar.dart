// ─────────────────────────────────────────────────────────────
// WholeChapterModeBar — M4 第二格「完整章模式」开关 + 最小支持引导
//   （ADR-C137 批1；在 C134 M4a IndependentDraftingBar 之下）
//
// 形态裁定（与 M4a 同纪律）：**纯页面引导**，不进 chat_service / 不注入对话 prompt。
//   理由：批1 只做「开关 + 状态 + 可退回」；按需介入的对话层 prompt 注入属批2
//   （R-027 停线项 1），本批零注入、零 prompt 面、锚点零漂移。
//
// R-009 形态（写死，逐条自查）：
//   - 开关文案：「这一章我自己写」——学员主动声明，非系统探测/强制；
//   - 激活提示：「目标字数达成前，我只在你叫我时说话」——明写最小支持、不主动点评；
//   - **可随时退回**：退出按钮恒在场，点一下即恢复教练正常介入（无锁定、无二次确认拦截）；
//   - 无代写句子/段落、无打分、无「写得好不好」判定、无处方/加码建议。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/app_palette.dart';
import '../../config/app_theme.dart';
import '../../theme/app_typography.dart';
import 'whole_chapter_mode_provider.dart';

/// 完整章模式激活后的最小支持引导（固定教学性提示；零代写文本）。
///
/// 正向形态锁：每条都是「存在感 + 求助即答 + 边界重申」，
/// 不含任何范文/成段/续写/大纲建议/打分。
const List<String> kWholeChapterMinimalSupportNotes = [
  '写到本章目标字数前，我尽量不打断你。',
  '卡住了随时叫我——你提问，我才深答。',
  '想让我恢复正常陪写，点右上角退出即可。',
];

/// 完整章模式开关 + 最小支持引导条（挂在 M4a 独立起稿条之下、消息列表上方）。
class WholeChapterModeBar extends ConsumerWidget {
  final String chapterId;

  const WholeChapterModeBar({super.key, required this.chapterId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(wholeChapterDraftingProvider(chapterId));
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: active
            ? context.palette.primarySoft
            : context.palette.background,
        border: Border(bottom: BorderSide(color: context.palette.borderLight)),
      ),
      child: active ? _buildActive(context, ref) : _buildIdle(context, ref),
    );
  }

  /// idle：安静入口（弱色，不抢写作注意力）。
  Widget _buildIdle(BuildContext context, WidgetRef ref) {
    return InkWell(
      key: const Key('wholeChapterModeToggle'),
      onTap: () =>
          ref.read(wholeChapterDraftingProvider(chapterId).notifier).state =
              true,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Row(
        children: [
          Icon(
            Icons.menu_book_outlined,
            size: 16,
            color: context.palette.textTertiary,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text('这一章我自己写（完整章）', style: context.text.caption)),
          Icon(
            Icons.chevron_right,
            size: 16,
            color: context.palette.textTertiary,
          ),
        ],
      ),
    );
  }

  /// active：最小支持提示 + 可随时退回入口。
  Widget _buildActive(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildActiveHeader(context, ref),
        const SizedBox(height: AppSpacing.sm),
        _buildNotes(context),
      ],
    );
  }

  /// 激活态头部行：图标 +「最小支持」提示 + 退出入口（= 随时退回求助）。
  Widget _buildActiveHeader(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        Icon(
          Icons.menu_book_outlined,
          size: 16,
          color: context.palette.primary,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            '完整章模式：目标字数达成前，我只在你叫我时说话，不代写',
            style: context.text.caption.copyWith(
              color: context.palette.primaryDeep,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        GestureDetector(
          key: const Key('wholeChapterModeExit'),
          onTap: () =>
              ref.read(wholeChapterDraftingProvider(chapterId).notifier).state =
                  false,
          child: Icon(
            Icons.close,
            size: 16,
            color: context.palette.textTertiary,
          ),
        ),
      ],
    );
  }

  /// 最小支持提示清单（存在感 + 求助即答；零代写文本）。
  Widget _buildNotes(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final n in kWholeChapterMinimalSupportNotes)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('· ', style: context.text.subBody),
                Expanded(child: Text(n, style: context.text.subBody)),
              ],
            ),
          ),
      ],
    );
  }
}
