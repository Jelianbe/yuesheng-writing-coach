// ─────────────────────────────────────────────────────────────
// setting_progressions_section — Progressions 章节演进时间轴（第三批）
//
// 章节视角：把断言变化 / 事件 / 首次出现按章节聚合为垂直时间轴。
// 与现有区块互补——AssertionGroups=属性视角、EventsSection=事件列表、
// 本区块=章节视角（Codex Progressions「按时间点演进」）。
//
// 纯展示层：零 schema 变更、不参与诊断注入。空态隐藏（无任何节点）。
//
// ★ 章标口径（`N12-F3b` phase 3，2026-09-18）：节点的键是**身份**
//   （`ProgressionPoint.chapterIdentity`），「第N章」文案**只能**经
//   `chapterLabel(chapterNoMap, …)` 解析 —— 见 `utils/chapter_number.dart` 文件头。
//   解析不出（已删章 / 回收站 / 越界）⇒ 渲染「章节未知」，**不编造数字**。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../../config/app_theme.dart';
import '../../data/database/database.dart';
import '../../services/progression_builder.dart';
import '../../types/character_types.dart';
import '../../utils/chapter_number.dart';
import '../../theme/app_typography.dart';
import '../../config/app_palette.dart';

/// 详情页「章节演进」区块（角色/世界观同构挂载）。
class SettingProgressionsSection extends StatelessWidget {
  final List<CharacterAssertion> assertions;
  final List<EventFact> events;
  final int? firstSeenChapter;

  /// `sortOrder → 展示章号(1 基)`（`utils/chapter_number.dart` 的
  /// [buildChapterNoMap]；入参须是已按 `sort_order` 升序的章节列表）。
  ///
  /// **必填、且刻意不给默认值**：给个默认空表会让「忘了传」编译通过、运行成
  /// 每节点都「章节未知」—— 那是「传错参数不报错、只是显示错东西」的同一类坑
  /// （见 `chapter_number.dart` 文件头对 `S1` 的说明）。
  final Map<int, int> chapterNoMap;

  const SettingProgressionsSection({
    super.key,
    required this.assertions,
    this.events = const [],
    this.firstSeenChapter,
    required this.chapterNoMap,
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
        Text('章节演进 (${points.length} 章)', style: context.text.titleMd),
        const SizedBox(height: AppSpacing.xsm),
        for (var i = 0; i < points.length; i++)
          _buildRow(context, points[i], isLast: i == points.length - 1),
      ],
    );
  }

  Widget _buildRow(
    BuildContext context,
    ProgressionPoint point, {
    required bool isLast,
  }) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildTrack(context, isLast: isLast),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    // 只吃身份；解析不出 ⇒ 「章节未知」，不编造数字（`S1`）。
                    chapterLabel(chapterNoMap, point.chapterIdentity) ?? '章节未知',
                    style: context.text.microCaption,
                  ),
                  const SizedBox(height: 2),
                  for (final item in point.items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(item, style: context.text.body),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 时间轴刻度：实心圆点 + （非末行时）向下延伸的连接线。
  ///
  /// ★ 2026-09-22（批次 M3）：由 `_buildRow` 抽出 —— 该函数因补
  ///   `BuildContext` 形参 + 迁 `context.palette` 从 <=50 行涨到 53 行，
  ///   触红 R-019（只卡新增）。抽出这个内聚单元后回到限内，
  ///   且**不靠豁免**（不是把债登记成基线，而是真的拆开）。
  Widget _buildTrack(BuildContext context, {required bool isLast}) {
    final palette = context.palette;
    return Column(
      children: [
        Container(
          width: 12,
          height: 12,
          margin: const EdgeInsets.only(top: 6),
          decoration: BoxDecoration(
            color: palette.primary,
            shape: BoxShape.circle,
          ),
        ),
        if (!isLast)
          Expanded(child: Container(width: 2, color: palette.border)),
      ],
    );
  }
}
