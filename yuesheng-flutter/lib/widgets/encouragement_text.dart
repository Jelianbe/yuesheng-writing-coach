// ─────────────────────────────────────────────────────────────
// EncouragementText — 教练鼓励文案（缺口清单第 5 项）
// 真源：yuesheng-android/src/components/chat/EncouragementText.tsx
//
// 结构（对齐 RN）：
//   - 15 条鼓励文案池（ENCOURAGEMENTS，常数数组）
//   - 种子稳定随机：seed % 15 取一条（同一 seed 结果稳定）
//   - 竹青淡底胶囊：primarySoft 底 + primary 字 + 图标
//
// 显示条件（对齐 RN chat.tsx L404）：诊断完成（latestDiagnosis
// syndromes 非空）后显示；Flutter 侧由 messages 含 diagnosis_result 判定
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../config/app_theme.dart';

/// 教练鼓励文案池（对齐 RN ENCOURAGEMENTS，15 条）
const List<String> encouragements = [
  '坚持练习，进步在不知不觉中发生',
  '每一次修改都是向更好的自己迈进',
  '写作是一场马拉松，你已经跑得很棒了',
  '相信自己，你的文字有独特的力量',
  '不怕慢，就怕站。继续加油！',
  '今天的努力，是明天作品的光芒',
  '每个好作家都曾是不断修改的初学者',
  '你的坚持，终将开花结果',
  '勇敢地写下第一句，世界会因你而不同',
  '好作品是改出来的，你已经走在正确的路上',
  '相信自己，你比昨天更好了',
  '写作没有捷径，但你有月笙陪你',
  '每个字都是砖石，你在建造自己的文学殿堂',
  '继续写下去，故事还在等你完成',
  '你的进步，月笙都看在眼里',
];

/// 基于种子获取稳定随机鼓励文案（对齐 RN getEncouragementBySeed）
String getEncouragementBySeed(int seed) {
  final index = seed % encouragements.length;
  return encouragements[index];
}

class EncouragementText extends StatelessWidget {
  /// 可选：指定固定文案，否则随机
  final String? text;

  /// 随机种子（同一 seed 结果稳定）
  final int? seed;

  const EncouragementText({super.key, this.text, this.seed});

  @override
  Widget build(BuildContext context) {
    final message = text ?? getEncouragementBySeed(seed ?? 0);
    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.chat_bubble_outline,
            size: 14,
            color: AppColors.primary,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
