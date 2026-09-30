// ─────────────────────────────────────────────────────────────
// setting_tag_overview_page — 全稿标签总览页（标签批次后续）
//
// 跨实体聚合：按标签分组展示该作品所有挂了该标签的条目
// （角色/世界观/其他），点击条目跳对应详情页（其他无详情页，不跳）。
// 纯展示层：不参与诊断注入。入口 = 设定库 SegmentedButton 行右侧图标。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/app_theme.dart';
import '../../data/database/database.dart';
import '../../data/repositories/character_fact_repository.dart';
import '../../data/repositories/setting_entry_repository.dart';
import '../../data/repositories/setting_link_repository.dart'
    show SettingEntityKind;
import '../../config/app_palette.dart';
import '../../data/repositories/setting_tag_repository.dart';
import '../../data/repositories/world_fact_repository.dart';
import '../../providers/app_providers.dart';
import '../../router/app_routes.dart';
import '../../services/setting_tag_overview.dart';
import '../manuscript/setting_empty_state.dart';
import '../../theme/app_typography.dart';

/// 标签总览页（全稿聚合）。
class SettingTagOverviewPage extends ConsumerStatefulWidget {
  final String manuscriptId;

  const SettingTagOverviewPage({super.key, required this.manuscriptId});

  @override
  ConsumerState<SettingTagOverviewPage> createState() =>
      _SettingTagOverviewPageState();
}

class _SettingTagOverviewPageState
    extends ConsumerState<SettingTagOverviewPage> {
  bool _loading = true;
  bool _error = false;
  List<TagOverviewGroup> _groups = const [];

  /// C9：因实体已归档 / 合并而**不显示**的标签条目数（不再静默消失）。
  int _hiddenArchivedCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final db = ref.read(appDatabaseProvider);
      final tags = await SettingTagRepository(
        db,
      ).listAllForManuscript(widget.manuscriptId);
      final names = await _buildEntityNameMaps(db);
      final hidden = await _countHiddenArchived(
        db,
        tags,
        characterNames: names.$1,
        worldNames: names.$2,
      );
      final groups = buildTagGroups(
        tags: tags,
        characterNames: names.$1,
        worldNames: names.$2,
        settingNames: names.$3,
      );
      if (!mounted) return;
      setState(() {
        _groups = groups;
        _hiddenArchivedCount = hidden;
        _loading = false;
        _error = false;
      });
    } catch (_) {
      // 读库失败：置 error（不得静默退回空态谎报「还没有标签」——
      // 库里其实可能有标签，只是这次没读到。见 EMPTY-STATE-MATRIX §3.1 判据 5）
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = true;
      });
    }
  }

  /// 构造三类实体的 id→名字 映射（仅含当前可见实体，供分组显示）。
  Future<(Map<String, String>, Map<String, String>, Map<String, String>)>
  _buildEntityNameMaps(AppDatabase db) async {
    final characterNames = <String, String>{};
    for (final c in await CharacterFactRepository(
      db,
    ).listCharacters(widget.manuscriptId)) {
      characterNames[c.id] = c.name;
    }
    final worldNames = <String, String>{};
    for (final w in await WorldFactRepository(
      db,
    ).listWorlds(widget.manuscriptId)) {
      worldNames[w.id] = w.name;
    }
    final settingNames = <String, String>{};
    for (final s in await SettingEntryRepository(
      db,
    ).listEntries(widget.manuscriptId)) {
      settingNames[s.id] = s.name;
    }
    return (characterNames, worldNames, settingNames);
  }

  /// 数出因实体归档/合并而**不显示**的标签条数（C9）。
  ///
  /// buildTagGroups 会静默丢弃解析不到名字的条目，这里把「全集」拉一遍
  /// 数出到底丢了几条，显式告诉用户（决策口径与互链侧相反）。
  Future<int> _countHiddenArchived(
    AppDatabase db,
    List<SettingTag> tags, {
    required Map<String, String> characterNames,
    required Map<String, String> worldNames,
  }) async {
    final allCharIds = {
      for (final c in await CharacterFactRepository(
        db,
      ).listCharacters(widget.manuscriptId, includeMerged: true))
        c.id,
    };
    final allWorldIds = {
      for (final w in await WorldFactRepository(
        db,
      ).listWorlds(widget.manuscriptId, includeArchived: true))
        w.id,
    };
    var hidden = 0;
    for (final t in tags) {
      final archived = switch (t.entityKind) {
        'character' =>
          allCharIds.contains(t.entityId) &&
              !characterNames.containsKey(t.entityId),
        'world' =>
          allWorldIds.contains(t.entityId) &&
              !worldNames.containsKey(t.entityId),
        _ => false,
      };
      if (archived) hidden++;
    }
    return hidden;
  }

  void _jump(TagOverviewItem item) {
    switch (item.kind) {
      case SettingEntityKind.character:
        context.push(
          AppRoutes.characterDetail,
          extra: {'manuscriptId': widget.manuscriptId, 'id': item.entityId},
        );
      case SettingEntityKind.world:
        context.push(
          AppRoutes.worldDetail,
          extra: {'manuscriptId': widget.manuscriptId, 'id': item.entityId},
        );
      case SettingEntityKind.setting:
        break; // 「其他」无详情页，不跳（克制）
      case SettingEntityKind.outline:
        break; // outline 不纳入标签（克制）
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.palette.background,
      appBar: AppBar(title: const Text('标签总览')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error) {
      return SettingErrorState(message: '加载标签失败，请重试', onRetry: _load);
    }
    if (_groups.isEmpty && _hiddenArchivedCount == 0) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.page),
          child: Text(
            '还没有标签\n在角色/世界观/其他设定里给条目打上标签后，这里会按标签汇总',
            style: context.text.caption,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.page),
      children: [
        if (_hiddenArchivedCount > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Text(
              '$_hiddenArchivedCount 条标签因所属条目已归档 / 合并而未显示',
              style: context.text.caption,
            ),
          ),
        for (final group in _groups) _buildGroup(group),
      ],
    );
  }

  Widget _buildGroup(TagOverviewGroup group) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '#${group.tag} (${group.items.length})',
            style: context.text.title,
          ),
          const SizedBox(height: AppSpacing.xs),
          for (final item in group.items)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: _KindBadge(kind: item.kind),
              title: Text(item.name, style: context.text.body),
              trailing: item.kind == SettingEntityKind.setting
                  ? null
                  : const Icon(Icons.chevron_right, size: 18),
              onTap: item.kind == SettingEntityKind.setting
                  ? null
                  : () => _jump(item),
            ),
        ],
      ),
    );
  }
}

/// 类型徽标（复用互链枚举 label）。
class _KindBadge extends StatelessWidget {
  final SettingEntityKind kind;

  const _KindBadge({required this.kind});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: context.palette.primarySoft,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(kind.label, style: context.text.caption),
    );
  }
}
