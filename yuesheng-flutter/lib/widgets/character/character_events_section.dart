// ─────────────────────────────────────────────────────────────
// CharacterEventsSection — 角色相关事件区（C78 批次3，FR-4）
//
// 数据 = filterEventsByIdentity(全量事件, 主名 ∪ 别名)（判据与 AI 侧同源，
// character_identity.dart）；展示 事件名 + 章节 + 类型 + 一句话描述，
// 点按跳对应章节（章节已删 / 章号缺失 → 轻提示不跳）。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../../config/app_theme.dart';
import '../../data/database/database.dart';
import '../../utils/chapter_number.dart';
import '../../theme/app_typography.dart';

class CharacterEventsSection extends StatelessWidget {
  final List<EventFact> events;

  /// `sortOrder → 展示章号(1 基)`（`buildChapterNoMap` 产出）。
  ///
  /// `N12-F3b` phase 2：章标**只由身份载体**渲染 —— 即 `e.chapterSortOrder`
  /// （`event_fact.chapter_sort_order`），**不是** `e.chapter`（一列三源、
  /// 读时不可分辨）。无身份（存量行）⇒ 「章节未知」，遵 `ADR-C95` 裁定 2。
  final Map<int, int> chapterNoMap;

  /// 跳章节（详情页实现反查 + push；空实现 = 不响应）
  final ValueChanged<EventFact>? onJump;

  const CharacterEventsSection({
    super.key,
    required this.events,
    required this.chapterNoMap,
    this.onJump,
  });

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: AppSpacing.section),
        Text('相关事件 (${events.length})', style: context.text.titleMd),
        const SizedBox(height: AppSpacing.xsm),
        for (final e in events)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Row(
              children: [
                _TypeChip(eventType: e.eventType),
                const SizedBox(width: AppSpacing.xsm),
                Expanded(
                  child: Text(e.name, style: context.text.titleMd, maxLines: 1),
                ),
                Text(_chapterText(e), style: context.text.microCaption),
              ],
            ),
            subtitle: e.description.isEmpty
                ? null
                : Text(
                    e.description,
                    style: context.text.caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
            onTap: onJump == null ? null : () => onJump!(e),
          ),
      ],
    );
  }

  /// 章标：**只吃身份载体**（`N12-F3b` phase 2 / 方案 `S1`）。
  ///
  /// 无身份 ⇒ 「章节未知」（**不回退到 `e.chapter`**：那一列装的是 AI 标称号，
  /// 若恰好等于某个真实 `sortOrder`，回退会渲染**另一个章**的号 ⇒ 错位）。
  String _chapterText(EventFact e) {
    return chapterLabel(chapterNoMap, e.chapterSortOrder) ?? '章节未知';
  }
}

/// 事件类型角标（决定/转折/突发/冲突/日常）
class _TypeChip extends StatelessWidget {
  final String eventType;
  const _TypeChip({required this.eventType});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xsm,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Text(
        eventType,
        style: context.text.microCaption.copyWith(color: AppColors.l1Text),
      ),
    );
  }
}
