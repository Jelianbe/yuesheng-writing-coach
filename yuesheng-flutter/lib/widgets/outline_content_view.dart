// ─────────────────────────────────────────────────────────────
// OutlineContentView — 大纲记忆「内容体」（批次 N12：「大纲 Drawer 解绑」）
//
// ★ 来源与动机
//   本文件是从 `outline_drawer.dart` **逐字迁出**的内容部分。原文件把整块
//   内容直接挂在 `Drawer` 之下（`:55 return Drawer(`）⇒ 类根节点就是**抽屉外壳**，
//   内容无法在抽屉之外复用 —— 这正是
//   `docs/designs/2026-09-13-detail-tab-refactor-architecture.md` §1.3 / §8 A4
//   记的「强绑 `Drawer` 语义」。
//   ⇒ 本文件只留**内容**；外壳（Drawer / SafeArea / 头部标题栏）留在
//     `OutlineDrawer`（薄壳，构造器签名原样保留）。
//
// ★ 职责
//   · 读 `outlineViewProvider` → 分组展示实体（人物 / 设定 / 情节）+ 印象行；
//   · 承载「快速确认 / 拒绝」落库动作（批次87-4）；
//   · **不含** Drawer、SafeArea、头部标题与关闭按钮 —— 那是外壳的职责。
//   ⇒ 因此可被直接嵌入其他承载（独立页面 / Tab / 弹层）。
//
// ★ 本批次的行为边界
//   **不改任何表现**：字号、文案、过滤条件、动作时序与迁出前**逐字一致**。
//   分类常量与类型标签查找已改指 `outline_shared.dart`（同值同语义，仅去重）。
//
// ★ 后续批次 N12-F1 的**有意**表现变更（ADR-C95）
//   来源章标由「直渲染 `sourceChapterNo`」→ 「按**作品当前章节列表的序位**解析」。
//   原因：`sourceChapterNo` 存的是 0 基 `chapter.sortOrder`（**身份键**，删除不重编号），
//   原实现会把首章渲染成「第0章」。解析失败（章已删/在回收站）⇒ **不显示章标**。
//   这是本文件**唯一**有意的表现变更；其余仍与迁出前逐字一致。
//   口径与反例：`docs/ADR-C95-chapter-number-convention.md` · 实现 `utils/chapter_number.dart`。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_theme.dart';
import '../data/database/database.dart';
import '../data/repositories/outline_repository.dart';
import '../providers/app_providers.dart';
import '../providers/manuscript_providers.dart';
import '../utils/chapter_number.dart';
import 'outline_shared.dart';

/// 大纲记忆内容体（可嵌入组件：无 Drawer / 无 SafeArea / 无头部）。
class OutlineContentView extends ConsumerWidget {
  /// 所属作品 ID（null/空 = 无法加载，走空态）
  final String? manuscriptId;

  const OutlineContentView({super.key, required this.manuscriptId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final msId = manuscriptId ?? '';
    final viewAsync = msId.isEmpty
        ? null
        : ref.watch(outlineViewProvider(msId));
    // ADR-C95：来源章标按「作品当前章节列表中的序位」解析——库里的
    // `sourceChapterNo` 是 **0 基身份键**（`chapter.sortOrder`），**不得**直接渲染，
    // 也不得用 `+1` 兜底（删除不重编号 ⇒ 会算错）。
    final chapterNoMap = buildChapterNoMap(
      msId.isEmpty ? const <Chapter>[] : ref.watch(chapterListProvider(msId)),
    );

    if (viewAsync == null) return const _OutlineEmpty();
    return viewAsync.when(
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
              chapterNoMap: chapterNoMap,
              onConfirmEntity: _confirmEntity(context, ref, msId),
              onConfirmImpression: _confirmImpression(context, ref, msId),
              onRejectImpression: _rejectImpression(context, ref, msId),
            ),
    );
  }

  // ── 批次87-4：快速确认/拒绝（落库 + 刷新大纲 + 轻提示） ──

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

  /// ADR-C95：`sortOrder → 展示章号(1 基)` 映射（由外壳解析后下传）
  final Map<int, int> chapterNoMap;

  /// 批次87-4：快速确认/拒绝回调（id 参数）
  final ValueChanged<String> onConfirmEntity;
  final ValueChanged<String> onConfirmImpression;
  final ValueChanged<String> onRejectImpression;

  const _OutlineList({
    required this.view,
    required this.chapterNoMap,
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
          .where((e) => kOutlineVisibleStatuses.contains(e.status))
          .toList();
      if (entities.isEmpty) continue;
      children.add(_TypeSection(label: group.label, count: entities.length));
      children.addAll(
        entities.map(
          (e) => _EntityCard(
            entity: e,
            chapterNoMap: chapterNoMap,
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

  /// ADR-C95：`sortOrder → 展示章号(1 基)` 映射
  final Map<int, int> chapterNoMap;

  /// 批次87-4：pending 实体快速确认回调
  final VoidCallback onConfirm;

  /// 批次87-4：印象确认/拒绝回调（id 参数，每印象行包闭包）
  final ValueChanged<String> onConfirmImpression;
  final ValueChanged<String> onRejectImpression;

  const _EntityCard({
    required this.entity,
    required this.impressions,
    required this.chapterNoMap,
    required this.onConfirm,
    required this.onConfirmImpression,
    required this.onRejectImpression,
  });

  @override
  Widget build(BuildContext context) {
    final visibleImps = impressions
        .where((i) => kOutlineVisibleStatuses.contains(i.status))
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
                chapterNoMap: chapterNoMap,
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

  /// ADR-C95：`sortOrder → 展示章号(1 基)` 映射
  final Map<int, int> chapterNoMap;

  /// 批次87-4：确认/拒绝回调（仅 pending 时显示按钮）
  final VoidCallback onConfirm;
  final VoidCallback onReject;

  const _ImpressionRow({
    required this.impression,
    required this.chapterNoMap,
    required this.onConfirm,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final isPending = impression.status == 'pending';
    // ADR-C95 裁定 2：解析失败（章已删/在回收站）⇒ **不显示章标**，不编造数字。
    final chapterTag = chapterLabel(chapterNoMap, impression.sourceChapterNo);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (chapterTag != null) ...[
                _Tag(
                  label: chapterTag,
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
