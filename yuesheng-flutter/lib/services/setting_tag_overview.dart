// ─────────────────────────────────────────────────────────────
// setting_tag_overview — 全稿标签聚合纯逻辑（标签批次后续）
//
// 把全稿 setting_tag 行 + 三实体 id→name 映射聚合为「标签 → 条目」
// 分组视图。纯函数可单测；UI 页负责取数（仓储 listAllForManuscript
// + 三列表构建名称映射）。
// ─────────────────────────────────────────────────────────────

import '../../data/database/database.dart';
import '../../data/repositories/setting_link_repository.dart'
    show SettingEntityKind;

/// 一个条目（类型 + id + 名称）。
class TagOverviewItem {
  final SettingEntityKind kind;
  final String entityId;
  final String name;

  const TagOverviewItem({
    required this.kind,
    required this.entityId,
    required this.name,
  });
}

/// 一个标签组（#tag → 条目列表）。
class TagOverviewGroup {
  final String tag;
  final List<TagOverviewItem> items;

  const TagOverviewGroup({required this.tag, required this.items});
}

/// 聚合：按 tag 分组（tag 字典序）；组内按类型序（角色→世界观→其他）
/// 再按名称排序。名称映射缺失的条目跳过（目标已删容错）。
List<TagOverviewGroup> buildTagGroups({
  required List<SettingTag> tags,
  required Map<String, String> characterNames,
  required Map<String, String> worldNames,
  required Map<String, String> settingNames,
}) {
  final byTag = <String, List<TagOverviewItem>>{};
  for (final t in tags) {
    final name = switch (t.entityKind) {
      'character' => characterNames[t.entityId],
      'world' => worldNames[t.entityId],
      'setting' => settingNames[t.entityId],
      _ => null,
    };
    if (name == null) continue;
    byTag
        .putIfAbsent(t.tag, () => [])
        .add(
          TagOverviewItem(
            kind: SettingEntityKind.values.firstWhere(
              (k) => k.name == t.entityKind,
              orElse: () => SettingEntityKind.setting,
            ),
            entityId: t.entityId,
            name: name,
          ),
        );
  }

  final groups = <TagOverviewGroup>[];
  final tagNames = byTag.keys.toList()..sort();
  for (final tag in tagNames) {
    final items = byTag[tag]!
      ..sort((a, b) {
        final kindOrder = a.kind.index.compareTo(b.kind.index);
        if (kindOrder != 0) return kindOrder;
        return a.name.compareTo(b.name);
      });
    groups.add(TagOverviewGroup(tag: tag, items: items));
  }
  return groups;
}
