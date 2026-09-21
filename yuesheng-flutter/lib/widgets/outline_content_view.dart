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
//
// ★ 批次 N6「大纲类型体系」（2026-09-18）—— 三处改动，全部在本文件内
//   ① **新增「章节结构」只读投影段**：卷/章由 `volumes` / `chapters` **现算得出**
//      （复用 `utils/volume_group.dart` 的 `buildChapterSections`，即章节树抽屉与
//      稿件详情章节列表的**同一份全局序口径**），节点点击 = **跳转到该章**。
//      **不提供**改名/移卷/新建章 —— 那些操作的真源在章节列表抽屉，
//      两处可写 = 两处真源。
//      ⇒ 卷/章**不写入** `outline_entity`：那会同时引入两处真源、唯一键撞名
//        （`uniqueKeys` 是 `{manuscriptId, entityKey}`，**不含 type**）与 prompt 改动。
//   ② **修「一片空白」缺陷**：旧判据是 `entities.isNotEmpty`，而 `volume`/`chapter`
//      这类不在 `kOutlineTypeOrder` 内的类型会被分组循环整圈 `continue` ⇒
//      **既无分组、也无空态文案**的全白抽屉（此前由 `#N12-6` 钉住）。
//      新判据 = **可见分组是否为空**。
//   ③ **补「其他」兜底分组**：把 `kOutlineTypeOrder` 从**白名单**降为**排序优先表**，
//      不在表内的类型不再被**静默丢弃**。
//
//   ⚠️ 与设计稿（`.ai/reports/2026-09-18-N6-…-设计.md` §4.3）的**一处有意偏差**：
//      设计稿把判据写成「**可见分组为空 ⇒ 进空态**」。若照字面落在**整页**
//      （即 `if (可见分组为空) return _OutlineEmpty(…)`），后果是：
//      **有章节、无实体**的稿件（= 新稿 / 尚未诊断的稿）会把**整段结构投影
//      一并撤掉** —— 而结构投影恰在那类稿件里是**唯一**有内容可显示的东西
//      ⇒ N6 的核心能力在最需要它的场景下不可见。
//      ⇒ 故落地为**按段判定**：结构段与要素段**各自**判空态。
//        · 两段皆空 → `_OutlineEmpty`（整页；语义 = 真的什么都没有）
//        · 仅要素段空 → 结构段照常渲染，要素段落**同一份**空态引导
//          （「还没有大纲」指的是**要素**而非整页 ⇒ 文案语义也不再失真）
//      ⇒ 该偏差由 `#N6-1` 钉住（改成整页判据时它会红）。
//
//   ⚠️ **本批自纠**：本注释初稿把该偏差的理由写成「整页判据会把引导文案从
//      『有章节』的用户面前撤掉」。**实测否掉** —— 在整页判据的变异体下，
//      恰恰是那两条断言引导文案的用例（`#83-6` / `#83-9`）**仍然全绿**：
//      被撤掉的是**结构**，不是引导。理由已按实测改写为上文。
//      ⇒ 教训：**写下的理由与写下的数字同级，同样会错，同样要实测。**
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_theme.dart';
import '../config/shared_constants.dart';
import '../data/database/database.dart';
import '../data/repositories/outline_repository.dart';
import '../providers/app_providers.dart';
import '../providers/manuscript_providers.dart';
import '../utils/chapter_number.dart';
import '../utils/volume_group.dart';
import 'outline_shared.dart';
import '../theme/app_typography.dart';
import '../config/app_palette.dart';

/// 「章节结构」投影段的根节点 Key（N6）。
///
/// 存在的**唯一理由**：投影段的**章标题**与要素段的**来源章标**在文案上可能
/// 完全相同 —— 用户把章命名为「第3章」时，`find.text('第3章')` 会同时命中两处，
/// 是**同名不同物**。测试需要能按段划界，否则该口径的断言只能退化成计数。
const Key kOutlineStructureSectionKey = Key('outline-structure-section');

/// 投影段内单个**章节点**的 Key（N6）—— 供测试点按跳转用。
Key outlineStructureChapterKey(String chapterId) =>
    ValueKey('outline-structure-chapter-$chapterId');

/// 要素段**来源章标**的实例 Key（N6）—— 供测试把章标与投影章标题区分开。
Key outlineImpressionTagKey(String impressionId) =>
    ValueKey('outline-impression-tag-$impressionId');

/// 投影段章节点的行高（dp）。
///
/// 取 48 而非「贴着文字高」：本行是**跳转**动作，命中区按 N4-1 的面包屑口径
/// 取 ≥48dp（章节树抽屉里的同类行约 37dp，此处取更严的下限）。
const double _kStructureRowHeight = 48;

/// 可展示的实体（[kOutlineVisibleStatuses] 过滤）。
///
/// **唯一实现**：空态判据与分组渲染共用它，避免「一处放宽、另一处不放宽」
/// 的口径分叉（`DECISIONS §4-41`）。
List<OutlineEntity> _visibleEntities(List<OutlineEntity> all) =>
    all.where((e) => kOutlineVisibleStatuses.contains(e.status)).toList();

/// 大纲记忆内容体（可嵌入组件：无 Drawer / 无 SafeArea / 无头部）。
class OutlineContentView extends ConsumerWidget {
  /// 所属作品 ID（null/空 = 无法加载，走空态）
  final String? manuscriptId;

  /// N4-3：空态的**主行动**——去教练面板做次诊断（null = 不渲染该按钮）
  ///
  /// 缺省为 null：既保证 `writePages` 之外的独立承载（如被嵌进别的页面）
  /// 与原行为**逐字等价**，也让「动作」永远由**有路由权限的外壳**注入。
  final VoidCallback? onOpenCoach;

  /// N6：「章节结构」投影里**章节点**的点击回调（null = 不可点、无箭头）
  ///
  /// 与 [onOpenCoach] 同一条纪律：动作由**有路由权限的外壳**注入，
  /// 缺省时投影段仍照常渲染（只读列表），**零变化**。
  final void Function(String chapterId, String title)? onJumpToChapter;

  const OutlineContentView({
    super.key,
    required this.manuscriptId,
    this.onOpenCoach,
    this.onJumpToChapter,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final msId = manuscriptId ?? '';
    final viewAsync = msId.isEmpty
        ? null
        : ref.watch(outlineViewProvider(msId));

    if (viewAsync == null) return _OutlineEmpty(onOpenCoach: onOpenCoach);
    return viewAsync.when(
      loading: () => _buildLoading(context),
      error: (e, _) => _OutlineEmpty(onOpenCoach: onOpenCoach),
      data: (view) => _buildLoaded(context, ref, msId, view),
    );
  }

  /// 加载中（R-019 清偿拆出，N6）。⚠️ 当前无调用点（N6 拆出后未被接线）；
  /// P1-6：改收 BuildContext 取 palette 色（接线即随主题翻）。
  static Widget _buildLoading(BuildContext context) => Center(
    child: SizedBox(
      width: 18,
      height: 18,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        color: context.palette.primary,
      ),
    ),
  );

  /// 数据就绪：投影段 + 类型分组（R-019 清偿拆出，N6）。
  ///
  /// N6：章节列表**两用** —— 既供 ADR-C95 的章标解析，也供「章节结构」投影。
  /// 该 provider 派生自 `chapterStoreProvider`（ADR-C90 单一真源，首次 watch
  /// 即自动微任务加载）⇒ 无需在此手工 load / invalidate。
  /// 卷列表是 **FutureProvider**，未就绪按空处理（散落章节不依赖卷，照常平铺）。
  ///
  /// ★ N6 判据修订：由「`entities` 是否非空」→「**可见分组是否为空**」。
  ///   判据缺陷的旧后果：`entities` 非空、但一条都不属于可见分组 ⇒
  ///   既不进空态、也渲染不出分组 ⇒ **全白抽屉**。
  ///   ⚠️ 「可见实体为空」**等价于**「可见分组为空」，其成立**依赖**「其他」兜底
  ///      分组的存在（任何可见实体必落进某个分组）。若删除该兜底，
  ///      本判据必须随之改回「按分组计数」。
  Widget _buildLoaded(
    BuildContext context,
    WidgetRef ref,
    String msId,
    OutlineView view,
  ) {
    final chapters = ref.watch(chapterListProvider(msId));
    final volumes =
        ref.watch(volumeListProvider(msId)).value ?? const <Volume>[];
    final sections = buildChapterSections(volumes, chapters);
    final visible = _visibleEntities(view.entities);

    if (sections.isEmpty && visible.isEmpty) {
      return _OutlineEmpty(onOpenCoach: onOpenCoach);
    }
    return _OutlineList(
      view: view,
      sections: sections,
      // ADR-C95：来源章标按「作品当前章节列表中的序位」解析——库里的
      // `sourceChapterNo` 是 **0 基身份键**（`chapter.sortOrder`），**不得**直接渲染，
      // 也不得用 `+1` 兜底（删除不重编号 ⇒ 会算错）。
      chapterNoMap: buildChapterNoMap(chapters),
      onJumpToChapter: onJumpToChapter,
      onOpenCoach: onOpenCoach,
      onConfirmEntity: _confirmEntity(context, ref, msId),
      onConfirmImpression: _confirmImpression(context, ref, msId),
      onRejectImpression: _rejectImpression(context, ref, msId),
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

/// 大纲内容：**章节结构（只读投影）** + **类型分组列表**（人物 → 设定 → 情节，
/// 组内按 updatedAt 倒序）+ 末尾「其他」兜底分组（N6）。
///
/// 两段共处**同一个** `ListView`（不嵌套滚动视图）—— 契约由测试钉住。
class _OutlineList extends StatelessWidget {
  final OutlineView view;

  /// N6：「章节结构」投影的渲染段（`buildChapterSections` 的输出）
  final List<ChapterSection> sections;

  /// ADR-C95：`sortOrder → 展示章号(1 基)` 映射（由外壳解析后下传）
  final Map<int, int> chapterNoMap;

  /// N6：投影章节点跳转（null = 不可点）
  final void Function(String chapterId, String title)? onJumpToChapter;

  /// N4-3：要素段的空态主行动（null = 不渲染该按钮）
  final VoidCallback? onOpenCoach;

  /// 批次87-4：快速确认/拒绝回调（id 参数）
  final ValueChanged<String> onConfirmEntity;
  final ValueChanged<String> onConfirmImpression;
  final ValueChanged<String> onRejectImpression;

  const _OutlineList({
    required this.view,
    required this.sections,
    required this.chapterNoMap,
    required this.onJumpToChapter,
    required this.onOpenCoach,
    required this.onConfirmEntity,
    required this.onConfirmImpression,
    required this.onRejectImpression,
  });

  @override
  Widget build(BuildContext context) {
    final groups = _buildGroups(_visibleEntities(view.entities));
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xs,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      children: [
        if (sections.isNotEmpty)
          _ChapterStructureSection(
            sections: sections,
            onJumpToChapter: onJumpToChapter,
          ),
        if (sections.isNotEmpty && groups.isNotEmpty)
          const Divider(height: AppSpacing.xxl),
        // N6：要素段**自分段**空态 —— 有结构、无实体时，N4-3 的引导文案
        // （含主行动按钮）**仍然在场**，不被结构段顶掉。
        if (groups.isEmpty)
          _OutlineEmpty(onOpenCoach: onOpenCoach)
        else
          ...groups,
      ],
    );
  }

  /// 专属分组（人物 → 设定 → 情节）+ 末尾「其他」兜底分组。
  ///
  /// ★ 「其他」是**出口纪律**（N6）：不在 [kOutlineTypeOrder] 内的类型
  ///   **不得被静默丢弃**。组内卡片额外打出该类型**原值**（[outlineTypeLabel]
  ///   的回退），使「有但认不出」与「真的没有」在界面上可区分。
  List<Widget> _buildGroups(List<OutlineEntity> visible) {
    final children = <Widget>[];
    for (final group in kOutlineTypeOrder) {
      final items = visible.where((e) => e.entityType == group.type).toList();
      if (items.isEmpty) continue;
      children.add(_TypeSection(label: group.label, count: items.length));
      children.addAll(items.map((e) => _card(e)));
    }
    final others = visible
        .where((e) => !outlineHasOwnGroup(e.entityType))
        .toList();
    if (others.isNotEmpty) {
      children.add(
        _TypeSection(label: kOutlineOtherGroupLabel, count: others.length),
      );
      children.addAll(
        others.map((e) => _card(e, typeTag: outlineTypeLabel(e.entityType))),
      );
    }
    return children;
  }

  Widget _card(OutlineEntity entity, {String? typeTag}) {
    return _EntityCard(
      entity: entity,
      typeTag: typeTag,
      chapterNoMap: chapterNoMap,
      impressions:
          view.impressionsByEntity[entity.id] ?? const <OutlineImpression>[],
      onConfirm: () => onConfirmEntity(entity.id),
      onConfirmImpression: onConfirmImpression,
      onRejectImpression: onRejectImpression,
    );
  }
}

/// 「章节结构」只读投影段（N6）—— 卷/章由 `volumes` / `chapters` **现算得出**。
///
/// ★ 为什么是投影：卷/章的身份与标题**已有唯一真源**（`volumes` / `chapters`），
///   再写一份进 `outline_entity` 必然产生同步债（改名/删章/移卷都要联动）。
/// ★ 为什么只读：改名/移卷/新建章的真源在**章节列表抽屉**，保持**唯一可写点**。
/// ★ 为什么复用 [buildChapterSections]：散落章节与卷组的**全局序**口径
///   （批次96-4）已在章节树抽屉、稿件详情章节列表两处落地；另写一套分组
///   必致「同一件事两处推算」的口径分叉（`DECISIONS §4-41`）。
///   ⇒ 故本段**不出现「未分卷」组头**：散落章节按全局序平铺（与上述两处一致），
///     设计稿 §4.1 草图里的「（未分卷）」行**有意不实现**。
class _ChapterStructureSection extends StatelessWidget {
  final List<ChapterSection> sections;

  /// null = 只读不可点（独立承载时的零变化路径）
  final void Function(String chapterId, String title)? onJumpToChapter;

  const _ChapterStructureSection({
    required this.sections,
    this.onJumpToChapter,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      key: kOutlineStructureSectionKey,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(context),
        for (final section in sections)
          if (section.volume != null)
            ..._volumeRows(context, section)
          else
            _chapterRow(context, section.looseChapter!),
      ],
    );
  }

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        top: AppSpacing.sm,
        bottom: AppSpacing.smx,
      ),
      child: Row(
        children: [
          Text(
            '章节结构',
            style: context.text.subBody.copyWith(fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          Text(
            onJumpToChapter == null ? '来自章节列表' : '来自章节列表 · 点按跳转',
            style: context.text.microCaption,
          ),
        ],
      ),
    );
  }

  List<Widget> _volumeRows(BuildContext context, ChapterSection section) {
    final volume = section.volume!;
    final words = section.chapters.fold<int>(0, (sum, c) => sum + c.wordCount);
    return [
      Padding(
        padding: const EdgeInsets.only(
          top: AppSpacing.md,
          bottom: AppSpacing.xxs,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                volume.title.trim().isEmpty ? '未命名卷' : volume.title.trim(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.text.subBody.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              '${section.chapters.length} 章 · ${formatWordCount(words)}',
              style: context.text.microCaption,
            ),
          ],
        ),
      ),
      ...section.chapters.map((c) => _chapterRow(context, c)),
    ];
  }

  /// 章节点：整行可点 → 跳转到该章；未注入回调时不可点、无箭头（零变化）。
  Widget _chapterRow(BuildContext context, Chapter chapter) {
    final onJump = onJumpToChapter;
    final title = chapter.title.trim().isEmpty ? '未命名章节' : chapter.title;
    final row = SizedBox(
      height: _kStructureRowHeight,
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.body,
            ),
          ),
          if (onJump != null)
            Icon(
              Icons.chevron_right,
              size: 16,
              color: context.palette.placeholder,
            ),
        ],
      ),
    );
    final padded = Padding(
      padding: const EdgeInsets.only(left: AppSpacing.md),
      child: row,
    );
    if (onJump == null) return padded;
    return InkWell(
      key: outlineStructureChapterKey(chapter.id),
      onTap: () => onJump(chapter.id, chapter.title),
      child: padded,
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
            style: context.text.subBody.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 6),
          Text('$count', style: context.text.caption),
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

  /// N6：类型标签（**仅「其他」分组**内非空）—— 打出的类型**原值**，
  /// 使「有但认不出」与「真的没有」在界面上可区分。
  final String? typeTag;

  /// 批次87-4：pending 实体快速确认回调
  final VoidCallback onConfirm;

  /// 批次87-4：印象确认/拒绝回调（id 参数，每印象行包闭包）
  final ValueChanged<String> onConfirmImpression;
  final ValueChanged<String> onRejectImpression;

  const _EntityCard({
    required this.entity,
    required this.impressions,
    required this.chapterNoMap,
    this.typeTag,
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

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.smx,
        AppSpacing.md,
        AppSpacing.smx,
      ),
      decoration: BoxDecoration(
        color: context.palette.surfaceWhite,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: context.palette.borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTitleRow(context, entity.status == 'pending'),
          if (aliases.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              '别名：${aliases.join('、')}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.microCaption,
            ),
          ],
          ..._buildImpressions(context, visibleImps),
        ],
      ),
    );
  }

  /// 印象区：无可见印象时给「还没有梗概」占位，否则逐条渲染印象行。
  ///
  /// **R-019 清偿拆出（N6）**：原内联在 [build] 内。本批加类型标签块后
  /// `build` 达 84 行（> 50 硬限）⇒ 按职责拆出（标题行 / 印象区各成一段），
  /// 手法同 [_buildTitleRow]。
  List<Widget> _buildImpressions(
    BuildContext context,
    List<OutlineImpression> visibleImps,
  ) {
    if (visibleImps.isEmpty) {
      return [
        Padding(
          padding: EdgeInsets.only(top: AppSpacing.xsm),
          child: Text('还没有梗概', style: context.text.caption),
        ),
      ];
    }
    return visibleImps
        .map(
          (im) => _ImpressionRow(
            impression: im,
            chapterNoMap: chapterNoMap,
            onConfirm: () => onConfirmImpression(im.id),
            onReject: () => onRejectImpression(im.id),
          ),
        )
        .toList();
  }

  /// 标题行：规范名 + （N6）类型标签 + （批次87-4）待确认标记与快速确认按钮
  ///
  /// **R-019 清偿拆出（N6）**：本行原内联在 [build] 内。加上 N6 的类型标签块后
  /// `build` 达 93 行（> 50 硬限）⇒ 拆出；两者现均 < 50 行。
  /// 手法同既有先例（本章节树抽屉的 `_buildStatusBadge` / `_buildTrailing`）。
  Widget _buildTitleRow(BuildContext context, bool isPendingEntity) {
    return Row(
      children: [
        Flexible(
          child: Text(
            entity.entityKey,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.text.titleMd,
          ),
        ),
        // N6：「其他」分组内打出类型**原值**（认不出的类型也要说明它是什么）
        if (typeTag != null) ...[
          const SizedBox(width: 6),
          _Tag(
            label: typeTag!,
            bg: context.palette.borderSoft,
            fg: context.palette.textTertiary,
          ),
        ],
        if (isPendingEntity) ...[
          const SizedBox(width: 8),
          _Tag(
            label: '待确认',
            bg: context.palette.warningBg,
            fg: context.palette.warning,
          ),
          const SizedBox(width: 4),
          // 批次87-4：抽屉内快速确认
          TextButton(
            onPressed: onConfirm,
            style: TextButton.styleFrom(
              foregroundColor: context.palette.primary,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xsm),
              minimumSize: const Size(0, 24),
            ),
            child: const Text('确认', style: TextStyle(fontSize: 12)),
          ),
        ],
      ],
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
          _buildSummaryRow(context, chapterTag, isPending),
          if (isPending) _buildActionRow(context),
        ],
      ),
    );
  }

  /// 摘要行：来源章节 tag + 一句话梗概 + （pending 时）「待确认」标记。
  ///
  /// **R-019 清偿拆出（N6）**：原内联在 [build] 内；本批给章标加稳定锚点后
  /// `build` 由 78 行涨到 81 行（> 50 硬限）⇒ 按职责拆出
  /// （摘要行 / 操作行各成一段），手法同 [_EntityCard._buildTitleRow]。
  ///
  /// ★ `chapterTag == null` 时整段**不渲染**章标（ADR-C95 裁定 2），
  ///   而不是渲染一个空 tag。
  Widget _buildSummaryRow(
    BuildContext context,
    String? chapterTag,
    bool isPending,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (chapterTag != null) ...[
          _Tag(
            // N6：章标与投影段章标题可能**同名不同物**（用户把章命名为
            // 「第3章」）⇒ 给稳定锚点，使该口径的断言不必依赖文本计数。
            key: outlineImpressionTagKey(impression.id),
            label: chapterTag,
            bg: context.palette.primarySoft,
            fg: context.palette.primary,
          ),
          const SizedBox(width: 6),
        ],
        Expanded(
          child: Text(
            impression.impression,
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: context.palette.textBody,
            ),
          ),
        ),
        if (isPending) ...[
          const SizedBox(width: 6),
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xxs),
            child: _Tag(
              label: '待确认',
              bg: context.palette.warningBg,
              fg: context.palette.warning,
            ),
          ),
        ],
      ],
    );
  }

  /// 操作行（批次87-4）：抽屉内快速确认 / 拒绝，仅 pending 时渲染。
  Widget _buildActionRow(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
          onPressed: onConfirm,
          style: TextButton.styleFrom(
            foregroundColor: context.palette.success,
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xsm),
            minimumSize: const Size(0, 24),
          ),
          child: const Text('确认', style: TextStyle(fontSize: 12)),
        ),
        TextButton(
          onPressed: onReject,
          style: TextButton.styleFrom(
            foregroundColor: context.palette.textTertiary,
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xsm),
            minimumSize: const Size(0, 24),
          ),
          child: const Text('拒绝', style: TextStyle(fontSize: 12)),
        ),
      ],
    );
  }
}

/// 小标签（章节号 / 待确认）
class _Tag extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;

  const _Tag({
    super.key,
    required this.label,
    required this.bg,
    required this.fg,
  });

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
///
/// N4-3：从「只说不做」改为「可操作」——文案本就写着「去教练面板做次诊断」，
/// 但此前**没有任何按钮**承载该动作。现由外壳注入 [onOpenCoach]；
/// 未注入时（独立承载）渲染同原实现，**零变化**。
///
/// N6：本组件有**两种承载位置**，文案与结构完全相同——
///   ① 两段皆空 ⇒ 整页空态（[OutlineContentView] 直接返回）；
///   ② 有章节结构、要素段无实体 ⇒ 作为 `ListView` 的一个子项
///      （置于结构段之下）。
///   `Center` 在 `ListView` 里因主轴约束无界而自动 shrink-wrap 高度
///   （`RenderPositionedBox` 的既有行为），不会撑破滚动视图。
class _OutlineEmpty extends StatelessWidget {
  /// N4-3：主行动回调（null = 不渲染按钮）
  final VoidCallback? onOpenCoach;

  const _OutlineEmpty({this.onOpenCoach});

  @override
  Widget build(BuildContext context) {
    final onOpenCoach = this.onOpenCoach;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.article_outlined,
              size: 40,
              color: context.palette.placeholder,
            ),
            const SizedBox(height: 12),
            Text('还没有大纲', style: context.text.body),
            const SizedBox(height: 4),
            Text(
              '写一段后去教练面板做次诊断，AI 会帮你记住人物、设定和情节梗概',
              textAlign: TextAlign.center,
              style: context.text.caption,
            ),
            if (onOpenCoach != null) ...[
              const SizedBox(height: 20),
              ElevatedButton(
                key: const Key('outline-empty-open-coach'),
                onPressed: onOpenCoach,
                style: AppButtonStyles.primary,
                child: const Text('打开教练面板'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
