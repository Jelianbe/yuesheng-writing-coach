// ─────────────────────────────────────────────────────────────
// chat_self_practice — 「自选练习」启动器的唯一实现
//
// 交互批 #5（2026-09-20）：原 `_openSelfPractice` 私有于
// chat_page_sections.dart，唯一接线点在欢迎态 ChatWelcome ⇒ 会话一旦
// 有历史，「练」的自选入口彻底不可达（且欢迎态时活跃问题必空，
// 入口在场 = 候选必空的自相矛盾）。本函数提为共享叶子文件的公开实现，
// 供两处接线复用（欢迎态 + 活跃问题面板页脚）——不新造第二份 copy
// （#6/V-5 双 copy 教训：共享逻辑住唯一实现）。
//
// 依赖方向：叶子（practice_launcher + providers），不 import 页面壳，
// 与 chat_page_body / chat_page_sections 均单向，无循环。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/diagnosis_repository.dart';
import '../../providers/practice_providers.dart';
import '../../widgets/practice_launcher.dart';

/// P1-6：打开自主练习选择器并启动练习。
/// 反向漏斗：症候仅列当前活跃问题（chatState.activeProblems），
/// 不铺全量症候表，避免 overwhelm；候选为空时弹层自带诚实引导
/// （practice_launcher 空态文案），**调用方负责只在候选可能有值处接线**。
void openSelfPracticeSheet(
  BuildContext context,
  WidgetRef ref,
  List<ActiveProblemView> problems,
) {
  final syndromes = [
    for (final p in problems)
      PracticeSyndromeOption(id: p.syndromeId, name: p.syndromeName),
  ];
  PracticeLauncherSheet.show(
    context,
    syndromes: syndromes,
    onStart: (choice) {
      final typeText = kPracticeTypeText[choice.taskType] ?? choice.taskType;
      final name = choice.syndromeName ?? '当前问题';
      ref
          .read(practiceStoreProvider.notifier)
          .startPractice(
            PracticeTask(
              syndromeId: choice.syndromeId,
              syndromeName: choice.syndromeName,
              taskDescription: '针对「$name」完成一段$typeText练习',
              taskGoal: '对照评估标准完成写作练习',
              taskType: choice.taskType,
              difficulty: choice.difficulty,
            ),
          );
    },
  );
}
