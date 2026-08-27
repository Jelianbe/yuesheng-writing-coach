// ─────────────────────────────────────────────────────────────
// PhaseSummaryCard — 阶段总结卡片（缺口清单 B 类：消息卡片类型）
// 真源：yuesheng-android/src/components/chat/message-cards/PhaseSummaryCard.tsx
//
// 展示型卡片：训练阶段结束后汇总——
//   1. 结果图标圆底（passed/partial/failed 矿物色）
//   2. 标题 + 鼓励文案
//   3. 统计行：解决症候数 / 练习次数 / 进步趋势
//   4. 症候变化列表（≤5 条）
//   5. 三按钮：继续训练 / 查看学员画像 / 返回对话
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../services/message_card_service.dart';

/// 趋势 → 中文标签（对齐 RN getTrendLabel）
String _trendLabel(String trend) {
  switch (trend) {
    case 'improving':
      return '改善';
    case 'worsening':
      return '恶化';
    default:
      return '稳定';
  }
}

/// 结果配置（对齐 RN resultStyles：图标/标题/颜色/底/鼓励文案）
({IconData icon, String title, Color color, Color bgColor, String encourage})
_resultConfig(String result) {
  switch (result) {
    case 'passed':
      return (
        icon: Icons.celebration,
        title: '训练达标',
        color: AppColors.l1Text,
        bgColor: AppColors.l1,
        encourage: '太棒了！你的努力得到了回报，继续保持！',
      );
    case 'failed':
      return (
        icon: Icons.fitness_center,
        title: '继续加油',
        color: AppColors.l3Text,
        bgColor: AppColors.l3,
        encourage: '别灰心，调整策略后继续努力！',
      );
    case 'partial':
      return (
        icon: Icons.auto_awesome,
        title: '部分达标',
        color: AppColors.l2Text,
        bgColor: AppColors.l2,
        encourage: '进步明显，还有一些细节可以优化。',
      );
    default:
      return (
        icon: Icons.insert_chart_outlined,
        title: '阶段总结',
        color: AppColors.textTertiary,
        bgColor: AppColors.surface,
        encourage: '总结经验，继续前行。',
      );
  }
}

class PhaseSummaryCard extends StatelessWidget {
  final String result; // 'passed' | 'partial' | 'failed'
  final int resolvedSyndromeCount;
  final int trainingCount;
  final String trend; // 'improving' | 'stable' | 'worsening'
  final List<SyndromeChangeItem> syndromeChanges;

  /// 继续训练回调（对齐 RN onContinueTraining）
  final VoidCallback? onContinueTraining;

  /// 查看学员画像回调（对齐 RN onViewProfile）
  final VoidCallback? onViewProfile;

  /// 返回对话回调（对齐 RN onBackToChat）
  final VoidCallback? onBackToChat;

  const PhaseSummaryCard({
    super.key,
    required this.result,
    required this.resolvedSyndromeCount,
    required this.trainingCount,
    required this.trend,
    required this.syndromeChanges,
    this.onContinueTraining,
    this.onViewProfile,
    this.onBackToChat,
  });

  /// 便利构造：从 Message.content 的 JSON 解析 payload 渲染
  /// 由 MessageList message_type='phase_summary' 分支直接调用
  static PhaseSummaryCard fromMessageContent(
    String content, {
    Key? key,
    VoidCallback? onContinueTraining,
    VoidCallback? onViewProfile,
    VoidCallback? onBackToChat,
  }) {
    try {
      final payload = PhaseSummaryCardPayload.fromJson(
        jsonDecode(content) as Map<String, dynamic>,
      );
      return PhaseSummaryCard(
        key: key,
        result: payload.result,
        resolvedSyndromeCount: payload.resolvedSyndromeCount,
        trainingCount: payload.trainingCount,
        trend: payload.trend,
        syndromeChanges: payload.syndromeChanges,
        onContinueTraining: onContinueTraining,
        onViewProfile: onViewProfile,
        onBackToChat: onBackToChat,
      );
    } catch (_) {
      return PhaseSummaryCard(
        key: key,
        result: 'partial',
        resolvedSyndromeCount: 0,
        trainingCount: 0,
        trend: 'stable',
        syndromeChanges: const [],
        onContinueTraining: onContinueTraining,
        onViewProfile: onViewProfile,
        onBackToChat: onBackToChat,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = _resultConfig(result);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: AppSpacing.xsm),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: const BoxDecoration(
            color: AppColors.surfaceWhite,
            border: Border.fromBorderSide(BorderSide(color: AppColors.border)),
          ),
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            children: [
              // 结果图标圆底（对齐 RN iconContainer）
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: config.bgColor,
                  shape: BoxShape.circle,
                ),
                child: Icon(config.icon, size: 28, color: config.color),
              ),
              const SizedBox(height: 12),
              Text(
                config.title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                config.encourage,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  color: AppColors.textTertiary,
                ),
              ),
              const SizedBox(height: 14),
              _buildStatsRow(config.color),
              if (syndromeChanges.isNotEmpty) ...[
                const SizedBox(height: 12),
                _buildChangesSection(config.color),
              ],
              const SizedBox(height: 12),
              _buildButtons(config.color),
            ],
          ),
        ),
      ),
    );
  }

  /// 统计行：解决症候数 / 练习次数 / 进步趋势
  Widget _buildStatsRow(Color color) {
    Widget stat(String value, String label) {
      return Expanded(
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(label, style: AppTextStyles.microCaption),
          ],
        ),
      );
    }

    Widget divider() =>
        Container(width: 1, height: 30, color: AppColors.border);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          stat('$resolvedSyndromeCount', '解决症候数'),
          divider(),
          stat('$trainingCount', '练习次数'),
          divider(),
          stat(_trendLabel(trend), '进步趋势'),
        ],
      ),
    );
  }

  /// 症候变化列表（≤ MAX_SYNDROME_CHANGES）
  Widget _buildChangesSection(Color color) {
    final changes = syndromeChanges.length > 5
        ? syndromeChanges.sublist(0, 5)
        : syndromeChanges;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '症候变化',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        for (final change in changes) ...[
          Container(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xsm),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AppColors.divider, width: 0.5),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    change.syndromeName,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                Text(
                  _trendLabel(change.trend),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// 按钮：继续训练（primary 色底）| 查看学员画像 + 返回对话（描边）
  Widget _buildButtons(Color color) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 40,
          child: FilledButton(
            onPressed: onContinueTraining ?? () {},
            style: FilledButton.styleFrom(
              backgroundColor: color,
              padding: EdgeInsets.zero,
              textStyle: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            child: const Text('继续训练'),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 36,
                child: OutlinedButton(
                  onPressed: onViewProfile ?? () {},
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textTertiary,
                    side: const BorderSide(color: AppColors.border),
                    padding: EdgeInsets.zero,
                    textStyle: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  child: const Text('查看学员画像'),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SizedBox(
                height: 36,
                child: OutlinedButton(
                  onPressed: onBackToChat ?? () {},
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textTertiary,
                    side: const BorderSide(color: AppColors.border),
                    padding: EdgeInsets.zero,
                    textStyle: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  child: const Text('返回对话'),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
