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

class CharacterEventsSection extends StatelessWidget {
  final List<EventFact> events;

  /// 跳章节（详情页实现反查 + push；空实现 = 不响应）
  final ValueChanged<EventFact>? onJump;

  const CharacterEventsSection({super.key, required this.events, this.onJump});

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: AppSpacing.section),
        Text('相关事件 (${events.length})', style: AppTextStyles.titleMd),
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
                  child: Text(
                    e.name,
                    style: AppTextStyles.titleMd,
                    maxLines: 1,
                  ),
                ),
                Text(_chapterText(e), style: AppTextStyles.microCaption),
              ],
            ),
            subtitle: e.description.isEmpty
                ? null
                : Text(
                    e.description,
                    style: AppTextStyles.caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
            onTap: onJump == null ? null : () => onJump!(e),
          ),
      ],
    );
  }

  String _chapterText(EventFact e) {
    final ch = e.chapter;
    return ch == null ? '章节未知' : '第$ch章';
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
        style: AppTextStyles.microCaption.copyWith(color: AppColors.l1Text),
      ),
    );
  }
}
