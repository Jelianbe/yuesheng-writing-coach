// ─────────────────────────────────────────────────────────────
// setting_progressions_section — Progressions 章节演进时间轴（第三批）
//
// 章节视角：把断言变化 / 事件 / 首次出现按章节聚合为垂直时间轴。
// 与现有区块互补——AssertionGroups=属性视角、EventsSection=事件列表、
// 本区块=章节视角（Codex Progressions「按时间点演进」）。
//
// 纯展示层：零 schema 变更、不参与诊断注入。空态隐藏（无任何节点）。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../../config/app_theme.dart';
import '../../data/database/database.dart';
import '../../services/progression_builder.dart';
import '../../types/character_types.dart';

/// 详情页「章节演进」区块（角色/世界观同构挂载）。
class SettingProgressionsSection extends StatelessWidget {
  final List<CharacterAssertion> assertions;
  final List<EventFact> events;
  final int? firstSeenChapter;

  const SettingProgressionsSection({
    super.key,
    required this.assertions,
    this.events = const [],
    this.firstSeenChapter,
  });

  @override
  Widget build(BuildContext context) {
    final points = buildProgressions(
      assertions: assertions,
      events: events,
      firstSeenChapter: firstSeenChapter,
    );
    if (points.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: AppSpacing.section),
        Text('章节演进 (${points.length} 章)', style: AppTextStyles.titleMd),
        const SizedBox(height: AppSpacing.xsm),
        for (var i = 0; i < points.length; i++)
          _buildRow(points[i], isLast: i == points.length - 1),
      ],
    );
  }

  Widget _buildRow(ProgressionPoint point, {required bool isLast}) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              Container(
                width: 12,
                height: 12,
                margin: const EdgeInsets.only(top: 6),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
              ),
              if (!isLast)
                Expanded(child: Container(width: 2, color: AppColors.border)),
            ],
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '第 ${point.chapter} 章',
                    style: AppTextStyles.microCaption,
                  ),
                  const SizedBox(height: 2),
                  for (final item in point.items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(item, style: AppTextStyles.body),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
