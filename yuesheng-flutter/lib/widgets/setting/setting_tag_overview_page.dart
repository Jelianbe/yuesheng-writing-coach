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
import 'setting_empty_state.dart';
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final db = ref.read(appDatabaseProvider);
      final tagRepo = SettingTagRepository(db);
      final tags = await tagRepo.listAllForManuscript(widget.manuscriptId);
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
      final groups = buildTagGroups(
        tags: tags,
        characterNames: characterNames,
        worldNames: worldNames,
        settingNames: settingNames,
      );
      if (!mounted) return;
      setState(() {
        _groups = groups;
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
    if (_groups.isEmpty) {
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
      children: [for (final group in _groups) _buildGroup(group)],
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
            style: context.text.titleMd,
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
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(kind.label, style: context.text.caption),
    );
  }
}
