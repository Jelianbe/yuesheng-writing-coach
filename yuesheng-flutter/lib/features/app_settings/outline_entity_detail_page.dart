// ─────────────────────────────────────────────────────────────
// OutlineEntityDetailPage — 大纲实体详情页（大纲结构化批次）
//
// 大纲实体从「清单」升级为「结构」的第一步：详情页承载互链区块——
// 「第一卷：乡村起步」可关联「本卷出场角色 / 发生地 / 关键道具」。
// 克制边界：
//   - 只读展示 + 互链（不提供正文编辑——大纲随 AI 沉淀演进）
//   - 标签不纳入（outline 无直接写入路径，延续既有克制）
//   - pending 实体同样可建链（互链是用户组织，与确认状态无关）
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/app_palette.dart';
import '../../config/app_theme.dart';
import '../../data/database/database.dart';
import '../../data/database/utils.dart';
import '../../data/repositories/outline_repository.dart';
import '../../data/repositories/setting_link_repository.dart';
import '../../providers/app_providers.dart';
import '../../router/app_routes.dart';
import '../../widgets/outline_shared.dart';
import 'setting_links_section.dart';
import '../../theme/app_typography.dart';

class OutlineEntityDetailPage extends ConsumerStatefulWidget {
  final String entityId;
  final String manuscriptId;

  const OutlineEntityDetailPage({
    super.key,
    required this.entityId,
    required this.manuscriptId,
  });

  @override
  ConsumerState<OutlineEntityDetailPage> createState() =>
      _OutlineEntityDetailPageState();
}

class _OutlineEntityDetailPageState
    extends ConsumerState<OutlineEntityDetailPage> {
  bool _loading = true;
  OutlineEntity? _entity;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final row = await OutlineRepository(
      ref.read(appDatabaseProvider),
    ).getEntityById(widget.entityId);
    if (!mounted) return;
    if (row == null) {
      _snack('该大纲实体已不存在');
      Navigator.pop(context);
      return;
    }
    setState(() {
      _entity = row;
      _loading = false;
    });
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _statusLabel(String status) => switch (status) {
    'pending' => '待确认',
    'active' => '已生效',
    _ => status,
  };

  void _jump(SettingEntityKind kind, String id) {
    switch (kind) {
      case SettingEntityKind.character:
        context.push(
          AppRoutes.characterDetail,
          extra: {'manuscriptId': widget.manuscriptId, 'id': id},
        );
      case SettingEntityKind.world:
        context.push(
          AppRoutes.worldDetail,
          extra: {'manuscriptId': widget.manuscriptId, 'id': id},
        );
      case SettingEntityKind.outline:
        context.push(
          AppRoutes.outlineDetail,
          extra: {'manuscriptId': widget.manuscriptId, 'id': id},
        );
      case SettingEntityKind.setting:
        break; // 「其他」无详情页，不跳（克制）
    }
  }

  @override
  Widget build(BuildContext context) {
    final entity = _entity;
    return Scaffold(
      backgroundColor: context.palette.background,
      appBar: AppBar(title: Text(entity?.entityKey ?? '大纲实体')),
      body: _loading || entity == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.page),
              children: [
                _HeaderCard(
                  typeLabel: outlineTypeLabel(entity.entityType),
                  statusLabel: _statusLabel(entity.status),
                ),
                if (entity.aliases.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: Wrap(
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xs,
                      children: [
                        for (final a in parseJsonStringList(entity.aliases))
                          _AliasChip(label: a),
                      ],
                    ),
                  ),
                SettingLinksSection(
                  manuscriptId: widget.manuscriptId,
                  kind: SettingEntityKind.outline,
                  entityId: widget.entityId,
                  onJump: _jump,
                ),
              ],
            ),
    );
  }
}

/// 类型 + 状态卡（大纲实体元信息，只读）。
class _HeaderCard extends StatelessWidget {
  final String typeLabel;
  final String statusLabel;

  const _HeaderCard({required this.typeLabel, required this.statusLabel});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            _MetaBadge(label: typeLabel),
            const SizedBox(width: AppSpacing.sm),
            _MetaBadge(label: statusLabel),
          ],
        ),
      ),
    );
  }
}

class _MetaBadge extends StatelessWidget {
  final String label;

  const _MetaBadge({required this.label});

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
      child: Text(label, style: context.text.caption),
    );
  }
}

class _AliasChip extends StatelessWidget {
  final String label;

  const _AliasChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(label, style: context.text.caption),
      visualDensity: VisualDensity.compact,
    );
  }
}
