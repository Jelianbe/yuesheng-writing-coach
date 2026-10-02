// ─────────────────────────────────────────────────────────────
// IndependentDraftingBar — M4 独立起稿开关 + 结构性提问引导（ADR-C134 批3）
//
// 形态裁定（现场）：**纯页面引导**，不进 chat_service / 不注入对话 prompt。
//   理由：
//   - ADR-C134 §5.3 要求「教练引导 = 结构性提问，零代写文本」；
//   - 任务硬约束：起稿引导若需对话 prompt 注入，只能经 writing_coach_panel
//     自有消息构建层，禁止进 chat_service。纯页面引导零注入、零 prompt 面，
//     最守 R-027（停线项 2 一并覆盖的是「注入」本身；纯静态教学提问卡片
//     不改变任何 AI 行为，锚点零漂移）。
//
// R-009 形态（写死，逐条自查）：
//   - 开关文案：「这次我自己来」——学员主动声明，非系统探测；
//   - 激活提示：「教练只给结构性提问，不代写」——明写不代写；
//   - 引导清单：固定四条**教学性提问**（要读者感受到什么 / 画面落在哪里…），
//     不含任何成段/成句/续写/大纲范文；
//   - 无打分、无达标线、无「写得好不好」判定、无自动加码。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/app_palette.dart';
import '../../config/app_theme.dart';
import '../../theme/app_typography.dart';
import 'independent_drafting_provider.dart';

/// 独立起稿引导清单（固定结构性提问；零代写文本）。
///
/// 正向形态锁：每条都是「引导学员自己想」的开放式提问，
/// 不含任何范文/成段/续写/大纲建议。
const List<String> kIndependentDraftingQuestions = [
  '开头要立住什么？',
  '这一段要读者感受到什么？',
  '这个场景的画面落在哪里？',
  '主角此刻最想要什么？',
];

/// 独立起稿开关 + 引导条（挂在教练面板按钮行下方、消息列表上方）。
class IndependentDraftingBar extends ConsumerWidget {
  final String chapterId;

  const IndependentDraftingBar({super.key, required this.chapterId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(independentDraftingProvider(chapterId));
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
      key: const Key('independentDraftingToggle'),
      onTap: () =>
          ref.read(independentDraftingProvider(chapterId).notifier).state =
              true,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Row(
        children: [
          Icon(
            Icons.self_improvement_outlined,
            size: 16,
            color: context.palette.textTertiary,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text('这次我自己来（独立起稿）', style: context.text.caption)),
          Icon(
            Icons.chevron_right,
            size: 16,
            color: context.palette.textTertiary,
          ),
        ],
      ),
    );
  }

  /// active：明确提示 + 结构性提问清单 + 退出入口。
  Widget _buildActive(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildActiveHeader(context, ref),
        const SizedBox(height: AppSpacing.sm),
        _buildQuestionList(context),
      ],
    );
  }

  /// 激活态头部行：图标 +「只提问不代写」提示 + 退出入口。
  Widget _buildActiveHeader(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        Icon(
          Icons.self_improvement_outlined,
          size: 16,
          color: context.palette.primary,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            '本次独立起稿：教练只给结构性提问，不代写',
            style: context.text.caption.copyWith(
              color: context.palette.primaryDeep,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        GestureDetector(
          key: const Key('independentDraftingExit'),
          onTap: () =>
              ref.read(independentDraftingProvider(chapterId).notifier).state =
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

  /// 结构性提问清单（固定教学性提问；零代写文本）。
  Widget _buildQuestionList(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final q in kIndependentDraftingQuestions)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('· ', style: context.text.subBody),
                Expanded(child: Text(q, style: context.text.subBody)),
              ],
            ),
          ),
      ],
    );
  }
}
