// ─────────────────────────────────────────────────────────────
// diagnosis_card_parts — 诊断卡的侧车部件（R-019 腾空间）
//
// 抽出于 `diagnosis_card.dart`（该文件 2382 行 = 文件级红线，容差 0 行
// ⇒ 加任何入口前必须先腾出等量行数；见 `T-20261119-01` §1.2）。
//
// 两个部件都是**无实例状态依赖**的纯视觉/交互叶子：
//   · [SyndromeSectionDivider]：分组分隔条（原 `_buildSectionDivider`）
//   · [SynPracticeBar]：逐条症候的训练入口（原缺失，本卡新增）
//
// 依赖方向：叶子（config + palette + practice_launcher），不 import
// `diagnosis_card.dart`，无循环。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_palette.dart';
import '../config/app_theme.dart';
import '../features/chat/practice_launcher.dart';
import '../providers/practice_providers.dart';

/// 症候分组分隔条（逻辑/剧情/角色/描写）。
///
/// ADR-C146：分组由 `syndrome_id` 静态反查 `presentationGroup` 得到，
/// 分隔条只负责视觉切分，不承载语义。
class SyndromeSectionDivider extends StatelessWidget {
  final String label;

  const SyndromeSectionDivider({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: Divider(height: 1, color: context.palette.border),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: context.palette.textTertiary,
                  ),
                ),
              ),
              Expanded(
                child: Divider(height: 1, color: context.palette.border),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}

/// 单条症候的「就这条开练」入口。
///
/// 立卡依据：`T-20261119-01`。web `diagnose.html:692` 的 `syn-practice`
/// 按钮是**学员主动**入口，与教练主动推荐的 `TeacherSuggestionCard` 是
/// 两条并行入口；App 侧缺的正是前者（web 有、App 无 ⇒ 非对称）。
///
/// **不走 `chat_gates` 四道闸**：四道闸的职责是抑制「教练主动推」的频次
/// （心流保护 + 会话去重，批次 59/62 实测依据）；学员主动点击本质不同，
/// 故本入口直接读 `practiceStoreProvider`，不经档位/任务/频次/去重过滤。
///
/// 下游复用既有链路，**零新造训练逻辑**：
///   `PracticeLauncherSheet.show(presetSyndromeId)` → 学员选类型+难度
///   → `practiceStoreProvider.startPractice(PracticeTask)`
///   → 既有提交路径落 `training_results`（`TrainingResultRepository`）。
class SynPracticeBar extends ConsumerWidget {
  final String syndromeId;
  final String syndromeName;

  const SynPracticeBar({
    super.key,
    required this.syndromeId,
    required this.syndromeName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        key: Key('syn-practice-$syndromeId'),
        onPressed: () => _open(context, ref),
        icon: const Icon(Icons.play_circle_outline, size: 16),
        label: const Text(SynPracticeText.label),
        style: TextButton.styleFrom(
          foregroundColor: context.palette.primary,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  void _open(BuildContext context, WidgetRef ref) {
    // 候选只给本条症候 ⇒ 弹层 initState 的 `match ?? first` 必然选中它，
    // 学员只需选类型与难度，不会退化成「重新挑一遍问题」。
    final option = PracticeSyndromeOption(id: syndromeId, name: syndromeName);
    PracticeLauncherSheet.show(
      context,
      syndromes: [option],
      presetSyndromeId: syndromeId,
      presetSyndromeName: syndromeName,
      onStart: (choice) {
        final typeText = kPracticeTypeText[choice.taskType] ?? choice.taskType;
        ref
            .read(practiceStoreProvider.notifier)
            .startPractice(
              PracticeTask(
                syndromeId: choice.syndromeId,
                syndromeName: choice.syndromeName,
                taskDescription: '针对「$syndromeName」完成一段$typeText练习',
                taskGoal: '对照评估标准完成写作练习',
                taskType: choice.taskType,
                difficulty: choice.difficulty,
              ),
            );
      },
    );
  }
}

/// 入口文案真源（单点，改文案只改这里；R-027 范围 = 用户可见文案）。
class SynPracticeText {
  static const String label = '就这条开始练';
  const SynPracticeText._();
}
