// ─────────────────────────────────────────────────────────────
// growth_detail_timeline — 成长详情页诊断历史时间线
//
// 从 growth_detail_page.dart 真分解而来（R-019：原 part 伪拆分根除）。
//   - GrowthTimeline     时间线容器（按 timestamp DESC 渲染条目）
//   - GrowthTimelineItem 单条时间线（日期 + 置信度 + 症候名，最多 3 条 +N）
//
// 无状态纯渲染，无宿主状态依赖。
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../data/database/database.dart';

/// 诊断历史时间线容器
class GrowthTimeline extends StatelessWidget {
  final List<DiagnosisRow> items;

  const GrowthTimeline({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < items.length; i++) ...[
          GrowthTimelineItem(item: items[i], isLast: i == items.length - 1),
          if (i < items.length - 1) const SizedBox(height: 12),
        ],
      ],
    );
  }
}

/// 单条诊断时间线（左侧竖线 + 圆点；右侧日期/置信度/症候名）
class GrowthTimelineItem extends StatelessWidget {
  final DiagnosisRow item;
  final bool isLast;

  const GrowthTimelineItem({
    super.key,
    required this.item,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildLeftRail(),
          const SizedBox(width: 12),
          Expanded(child: _buildContent()),
        ],
      ),
    );
  }

  /// 左侧竖线 + 圆点
  Widget _buildLeftRail() {
    return SizedBox(
      width: 16,
      child: Column(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
          ),
          if (!isLast)
            Expanded(child: Container(width: 2, color: AppColors.primary)),
        ],
      ),
    );
  }

  /// 右侧内容（日期 + 置信度 + 症候名）
  Widget _buildContent() {
    // timestamp 是秒级 Unix 时间戳
    final dt = DateTime.fromMillisecondsSinceEpoch(item.timestamp * 1000);
    final dateStr =
        '${dt.month}-${dt.day} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(dateStr, style: AppTextStyles.noteCaption),
            const SizedBox(width: 8),
            Text(
              '置信度 ${(item.confidence * 100).round()}%',
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
        // E3：展示本次诊断出的症候名（从 syndromes JSON 解析），
        // 让时间线不再是"只有时间+置信度"的空壳信息
        ..._buildSyndromeNames(),
      ],
    );
  }

  /// 从 DiagnosisRow.syndromes JSON 解析症候名（最多 3 个，超过显示 +N）
  List<Widget> _buildSyndromeNames() {
    try {
      final list = jsonDecode(item.syndromes) as List<dynamic>;
      final names = <String>[];
      for (final s in list) {
        final name = (s as Map<String, dynamic>)['name'] as String?;
        if (name != null && name.isNotEmpty) names.add(name);
        if (names.length >= 3) break;
      }
      if (names.isEmpty) return const [];
      final total = (list.length).clamp(3, list.length);
      final display = names.join(' · ');
      final suffix = total > 3 ? ' · +${total - 3}' : '';
      return [
        const SizedBox(height: 4),
        Text(
          display + suffix,
          style: const TextStyle(
            fontSize: 12,
            height: 1.4,
            color: AppColors.textDeep,
          ),
        ),
      ];
    } catch (_) {
      return const [];
    }
  }
}
