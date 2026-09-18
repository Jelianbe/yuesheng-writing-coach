// ─────────────────────────────────────────────────────────────
// OutlineEntityListView — 大纲实体清单（资料 Tab「大纲」子列表）
//
// 设定资料库第三批：收编拆三处 → 详情页「资料」Tab。
// 展示 AI 从正文沉淀的大纲实体（entityKey + 类型 + 状态），
// pending 实体可在此确认（approveEntity——与大纲抽屉同一裁决语义）。
//
// 无 Scaffold / 无 AppBar：直接嵌入 SettingLibraryTab 子列表区。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/app_theme.dart';
import '../../data/database/database.dart';
import '../../data/repositories/outline_repository.dart';
import '../../providers/app_providers.dart';
import '../../router/app_routes.dart';
import '../outline_shared.dart';

/// 状态 → 中文徽标
String _statusLabel(String status) => switch (status) {
  'pending' => '待确认',
  'active' => '已生效',
  'rejected' => '已拒绝',
  _ => status,
};

/// 大纲实体清单（可嵌入组件，无 Scaffold）。
class OutlineEntityListView extends ConsumerStatefulWidget {
  final String manuscriptId;

  const OutlineEntityListView({super.key, required this.manuscriptId});

  @override
  ConsumerState<OutlineEntityListView> createState() =>
      OutlineEntityListViewState();
}

class OutlineEntityListViewState extends ConsumerState<OutlineEntityListView> {
  bool _loading = true;
  List<OutlineEntity> _entities = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final repo = OutlineRepository(ref.read(appDatabaseProvider));
    final items = await repo.listEntities(widget.manuscriptId);
    if (!mounted) return;
    setState(() {
      _entities = items
          .where((e) => kOutlineVisibleStatuses.contains(e.status))
          .toList();
      _loading = false;
    });
  }

  Future<void> _confirm(OutlineEntity entity) async {
    await OutlineRepository(
      ref.read(appDatabaseProvider),
    ).approveEntity(entity.id);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_entities.isEmpty) {
      return const Center(
        child: Text('还没有大纲实体，诊断一章后 AI 会沉淀', style: AppTextStyles.body),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      itemCount: _entities.length,
      itemBuilder: (_, i) => _buildItem(_entities[i]),
    );
  }

  Widget _buildItem(OutlineEntity entity) {
    final isPending = entity.status == 'pending';
    return Card(
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.page,
        vertical: AppSpacing.xs,
      ),
      child: ListTile(
        title: Text(entity.entityKey, style: AppTextStyles.titleMd),
        subtitle: Text(
          '${outlineTypeLabel(entity.entityType)} · ${_statusLabel(entity.status)}',
          style: AppTextStyles.caption,
        ),
        onTap: () => context.push(
          AppRoutes.outlineDetail,
          extra: {'manuscriptId': widget.manuscriptId, 'id': entity.id},
        ),
        trailing: isPending
            ? FilledButton(
                onPressed: () => _confirm(entity),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xxs,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('确认', style: AppTextStyles.microCaption),
              )
            : null,
      ),
    );
  }
}
