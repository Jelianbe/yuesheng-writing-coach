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
import 'setting_empty_state.dart';
import '../../theme/app_typography.dart';

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
  bool _error = false;
  List<OutlineEntity> _entities = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final repo = OutlineRepository(ref.read(appDatabaseProvider));
      final items = await repo.listEntities(widget.manuscriptId);
      if (!mounted) return;
      setState(() {
        _entities = items
            .where((e) => kOutlineVisibleStatuses.contains(e.status))
            .toList();
        _loading = false;
        _error = false;
      });
    } catch (_) {
      // 读库失败：置 error（不得退回空态谎报「还没有大纲实体」）。
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = true;
      });
    }
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
    if (_error) {
      return SettingErrorState(message: '加载大纲实体失败，请重试', onRetry: _load);
    }
    if (_entities.isEmpty) {
      // ★ 2026-09-20 观感批：本页**没有手动新建入口** —— 大纲实体全部由
      //   AI 从正文沉淀（`_load()` 只读 `listEntities`），没有任何 UI 路径
      //   能凭空造一条。故空态**不给 CTA 按钮**：塞一个按钮就得编造一个
      //   不存在的动作（本仓「不编造」纪律）。
      //   上一版是光秃秃一行 14px 小字，与同容器内世界观页的「图标+标题+
      //   说明+按钮」形态断裂，是「太丑」的组成部分。
      return const SettingEmptyState(
        icon: Icons.account_tree_outlined,
        title: '还没有大纲实体',
        description: '诊断一章，AI 会从正文里抽出事件与线索，沉淀到这里供你确认。',
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
        title: Text(entity.entityKey, style: context.text.titleMd),
        subtitle: Text(
          '${outlineTypeLabel(entity.entityType)} · ${_statusLabel(entity.status)}',
          style: context.text.caption,
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
                child: Text('确认', style: context.text.microCaption),
              )
            : null,
      ),
    );
  }
}
