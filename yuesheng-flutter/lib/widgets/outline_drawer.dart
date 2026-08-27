// ─────────────────────────────────────────────────────────────
// OutlineDrawer — 大纲边写边看（批次83 大纲边写边看）
// 写作页右侧抽屉（endDrawer）：展示作品大纲记忆（批次72 大纲层数据）
//   - 实体按类型分组：人物 / 设定 / 情节（固定顺序）
//   - 实体卡：规范名 + 别名 + 状态（pending「待确认」提示）
//   - 印象行：一句话梗概 + 来源章节（第N章）+ pending「待确认」标记
//   - 只展示 pending/active 的实体与印象（rejected/superseded/expired 跳过）
//
// 设计说明：
//   - 纯读视图（边写边看），确认/拒绝动作留在教练面板的确认卡
//   - 抽屉每次打开由 WritingPage 以新 ValueKey 重建 + 失效
//     outlineViewProvider，保证数据最新
//   - 跳转/新建动作经回调交 WritingPage 执行（本组件保持纯 UI）
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_theme.dart';
import '../data/database/database.dart';
import '../data/repositories/outline_repository.dart';
import '../providers/app_providers.dart';
import '../providers/manuscript_providers.dart';

/// 实体类型中文名 + 展示顺序
const List<({String type, String label})> kOutlineTypeOrder = [
  (type: 'character', label: '人物'),
  (type: 'setting', label: '设定'),
  (type: 'plot', label: '情节'),
];

/// 实体/印象可展示的状态（rejected/superseded/expired 视为无效跳过）
const Set<String> _visibleStatuses = {'pending', 'active'};

class OutlineDrawer extends ConsumerWidget {
  /// 所属作品 ID（null/空 = 无法加载，走空态）
  final String? manuscriptId;

  /// 右上角关闭按钮（由 WritingPage 关闭 endDrawer）
  final VoidCallback onClose;

  const OutlineDrawer({
    super.key,
    required this.manuscriptId,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final msId = manuscriptId ?? '';
    final viewAsync = msId.isEmpty
        ? null
        : ref.watch(outlineViewProvider(msId));

    return Drawer(
      backgroundColor: AppColors.background,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── 头部：标题 + 关闭 ──
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.md,
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.article_outlined,
                    size: 18,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    '大纲',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textInk,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(
                      Icons.close,
                      size: 20,
                      color: AppColors.textTertiary,
                    ),
                    tooltip: '关闭大纲',
                    onPressed: onClose,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // ── 内容 ──
            Expanded(
              child: viewAsync == null
                  ? const _OutlineEmpty()
                  : viewAsync.when(
                      loading: () => const Center(
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                      error: (e, _) => const _OutlineEmpty(),
                      data: (view) => view.entities.isEmpty
                          ? const _OutlineEmpty()
                          : _OutlineList(
                              view: view,
                              onConfirmEntity: _confirmEntity(
                                context,
                                ref,
                                msId,
                              ),
                              onConfirmImpression: _confirmImpression(
                                context,
                                ref,
                                msId,
                              ),
                              onRejectImpression: _rejectImpression(
                                context,
                                ref,
                                msId,
                              ),
                            ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 批次87-4：抽屉内快速确认/拒绝（落库 + 刷新大纲 + 轻提示） ──

  ValueChanged<String> _confirmEntity(
    BuildContext context,
    WidgetRef ref,
    String msId,
  ) {
    return (id) => _act(context, ref, msId, () async {
      await OutlineRepository(ref.read(appDatabaseProvider)).approveEntity(id);
    }, '已确认该设定');
  }

  ValueChanged<String> _confirmImpression(
    BuildContext context,
    WidgetRef ref,
    String msId,
  ) {
    return (id) => _act(context, ref, msId, () async {
      await OutlineRepository(
        ref.read(appDatabaseProvider),
      ).approveImpression(id);
    }, '已确认这条梗概');
  }

  ValueChanged<String> _rejectImpression(
    BuildContext context,
    WidgetRef ref,
    String msId,
  ) {
    return (id) => _act(context, ref, msId, () async {
      await OutlineRepository(
        ref.read(appDatabaseProvider),
      ).rejectImpression(id);
    }, '已拒绝这条梗概');
  }

  Future<void> _act(
    BuildContext context,
    WidgetRef ref,
    String msId,
    Future<void> Function() action,
    String message,
  ) async {
    await action();
    ref.invalidate(outlineViewProvider(msId));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
      );
  }
}

/// 实体分组列表：人物 → 设定 → 情节（固定顺序，组内按 updatedAt 倒序）
class _OutlineList extends StatelessWidget {
  final OutlineView view;

  /// 批次87-4：快速确认/拒绝回调（id 参数）
  final ValueChanged<String> onConfirmEntity;
  final ValueChanged<String> onConfirmImpression;
  final ValueChanged<String> onRejectImpression;

  const _OutlineList({
    required this.view,
    required this.onConfirmEntity,
    required this.onConfirmImpression,
    required this.onRejectImpression,
  });

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (final group in kOutlineTypeOrder) {
      final entities = view.entities
          .where((e) => e.entityType == group.type)
          .where((e) => _visibleStatuses.contains(e.status))
          .toList();
      if (entities.isEmpty) continue;
      children.add(_TypeSection(label: group.label, count: entities.length));
      children.addAll(
        entities.map(
          (e) => _EntityCard(
            entity: e,
            impressions:
                view.impressionsByEntity[e.id] ?? const <OutlineImpression>[],
            onConfirm: () => onConfirmEntity(e.id),
            onConfirmImpression: onConfirmImpression,
            onRejectImpression: onRejectImpression,
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xs,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      children: children,
    );
  }
}

/// 类型分组标题：人物（3）
class _TypeSection extends StatelessWidget {
  final String label;
  final int count;

  const _TypeSection({required this.label, required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        top: AppSpacing.md,
        bottom: AppSpacing.xsm,
      ),
      child: Row(
        children: [
          Text(
            label,
            style: AppTextStyles.subBody.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 6),
          Text('$count', style: AppTextStyles.caption),
        ],
      ),
    );
  }
}

/// 实体卡：规范名 + 别名 + 印象行
class _EntityCard extends StatelessWidget {
  final OutlineEntity entity;
  final List<OutlineImpression> impressions;

  /// 批次87-4：pending 实体快速确认回调
  final VoidCallback onConfirm;

  /// 批次87-4：印象确认/拒绝回调（id 参数，每印象行包闭包）
  final ValueChanged<String> onConfirmImpression;
  final ValueChanged<String> onRejectImpression;

  const _EntityCard({
    required this.entity,
    required this.impressions,
    required this.onConfirm,
    required this.onConfirmImpression,
    required this.onRejectImpression,
  });

  @override
  Widget build(BuildContext context) {
    final visibleImps = impressions
        .where((i) => _visibleStatuses.contains(i.status))
        .toList();
    final aliases = OutlineRepository.parseAliases(entity.aliases);
    final isPendingEntity = entity.status == 'pending';

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.smx,
        AppSpacing.md,
        AppSpacing.smx,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceWhite,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  entity.entityKey,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.titleMd,
                ),
              ),
              if (isPendingEntity) ...[
                const SizedBox(width: 8),
                _Tag(
                  label: '待确认',
                  bg: AppColors.warningBg,
                  fg: AppColors.warning,
                ),
                const SizedBox(width: 4),
                // 批次87-4：抽屉内快速确认
                TextButton(
                  onPressed: onConfirm,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xsm,
                    ),
                    minimumSize: const Size(0, 24),
                  ),
                  child: const Text('确认', style: TextStyle(fontSize: 12)),
                ),
              ],
            ],
          ),
          if (aliases.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              '别名：${aliases.join('、')}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.microCaption,
            ),
          ],
          if (visibleImps.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: AppSpacing.xsm),
              child: Text('还没有梗概', style: AppTextStyles.caption),
            )
          else
            ...visibleImps.map(
              (im) => _ImpressionRow(
                impression: im,
                onConfirm: () => onConfirmImpression(im.id),
                onReject: () => onRejectImpression(im.id),
              ),
            ),
        ],
      ),
    );
  }
}

/// 印象行：来源章节 tag + 一句话梗概（pending 带「待确认」标记 + 快速确认/拒绝）
class _ImpressionRow extends StatelessWidget {
  final OutlineImpression impression;

  /// 批次87-4：确认/拒绝回调（仅 pending 时显示按钮）
  final VoidCallback onConfirm;
  final VoidCallback onReject;

  const _ImpressionRow({
    required this.impression,
    required this.onConfirm,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final isPending = impression.status == 'pending';
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (impression.sourceChapterNo != null) ...[
                _Tag(
                  label: '第${impression.sourceChapterNo}章',
                  bg: AppColors.primarySoft,
                  fg: AppColors.primary,
                ),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  impression.impression,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: AppColors.textBody,
                  ),
                ),
              ),
              if (isPending) ...[
                const SizedBox(width: 6),
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xxs),
                  child: _Tag(
                    label: '待确认',
                    bg: AppColors.warningBg,
                    fg: AppColors.warning,
                  ),
                ),
              ],
            ],
          ),
          // 批次87-4：抽屉内快速确认/拒绝
          if (isPending)
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: onConfirm,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.success,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xsm,
                    ),
                    minimumSize: const Size(0, 24),
                  ),
                  child: const Text('确认', style: TextStyle(fontSize: 12)),
                ),
                TextButton(
                  onPressed: onReject,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textTertiary,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xsm,
                    ),
                    minimumSize: const Size(0, 24),
                  ),
                  child: const Text('拒绝', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// 小标签（章节号 / 待确认）
class _Tag extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;

  const _Tag({required this.label, required this.bg, required this.fg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xsm,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Text(label, style: TextStyle(fontSize: 10, color: fg)),
    );
  }
}

/// 空态：还没有大纲记忆 → 引导去教练面板诊断
class _OutlineEmpty extends StatelessWidget {
  const _OutlineEmpty();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(
              Icons.article_outlined,
              size: 40,
              color: AppColors.placeholder,
            ),
            SizedBox(height: 12),
            Text('还没有大纲', style: AppTextStyles.body),
            SizedBox(height: 4),
            Text(
              '写一段后去教练面板做次诊断，AI 会帮你记住人物、设定和情节梗概',
              textAlign: TextAlign.center,
              style: AppTextStyles.caption,
            ),
          ],
        ),
      ),
    );
  }
}
