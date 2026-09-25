// ─────────────────────────────────────────────────────────────
// WorldFactListView — 世界观设定列表主体（可嵌入组件，无 Scaffold / AppBar）
//
// 参照 character_list_view.dart 同构（零新范式）：
//   · 本组件是「列表主体」，供独立薄壳页 WorldFactPage 的 body；
//   · 无 Scaffold / 无 AppBar ⇒ 直接塞进任意 TabBarView / 页面 body 都不会
//     产生双层标题栏（将来进 Tab 零重构）；
//   · 公开 State [WorldFactListViewState] + [WorldFactListViewState.refresh]，
//     供薄壳经 GlobalKey 触发刷新（照搬 character 的 R4-11 教训：薄壳
//     setState 不会重建子 State）。
//
// 状态管理照搬 character 四件套（架构 §1.2 口径）：ConsumerStatefulWidget +
// 局部 setState + ref.read(appDatabaseProvider) 直读仓储；**不建 provider**。
//
// 判据零改动（A4）：本组件只读写 world_fact 表，不 import conflict_detector。
// ★ 追加/新建的「原文依据」字段在 world_dialogs.dart（承 A2）。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/app_theme.dart';
import '../../data/database/database.dart';
import '../../data/database/utils.dart';
import '../../data/repositories/chapter_repository.dart';
import '../../data/repositories/world_fact_repository.dart';
import '../../providers/app_providers.dart';
import '../../providers/manuscript_providers.dart';
import '../../types/character_types.dart';
import '../../utils/chapter_number.dart';
import '../../features/manuscript/setting_empty_state.dart';
import 'world_dialogs.dart';
import 'world_fact_detail_page.dart';
import '../../theme/app_typography.dart';
import '../../config/app_palette.dart';

/// 断言摘要最多展示的条目数（照搬 character_list_view.dart:30）
const int _kSummaryMax = 3;

/// ★ A1 共享创建逻辑：弹出「新建设定主题」弹窗并落库（含首条设定断言）。
///
/// 「新建」存在**两个触发点**——① [WorldFactListView] 列表头的
/// 「＋ 新建设定主题」按钮；② 独立页 [WorldFactPage] 薄壳 AppBar 的
/// 「＋ 新建」action。**两处必须共用本函数**，禁止复制两份（防行为分叉）。
///
/// R11 重名处理（N5 暂定）：提交前查同作品同名 active 主题，命中给**轻提示**
/// （§6-E），**不阻断** —— upsertWorld 命中同名走合并分支（= 追加语义）。
///
/// 返回：成功写入返回 true（供调用方决定是否刷新）；取消返回 false。
Future<bool> showAndCreateWorldTheme(
  BuildContext context,
  WidgetRef ref,
  String manuscriptId,
) async {
  final created = await showCreateWorldThemeDialog(context);
  if (created == null) return false;
  final repo = WorldFactRepository(ref.read(appDatabaseProvider));
  final existing = await repo.getWorld(manuscriptId, created.name);
  if (existing != null && existing.status == 'active') {
    if (!context.mounted) return false;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text('该主题已存在，可进入「${created.name}」直接追加设定')),
      );
  }
  // ADR-C95 / `N12-F3c`：弹层填的是**序位**，库里存的是**身份键** ⇒ 写入前归一。
  final identity = await _identityForPosition(
    ref,
    manuscriptId,
    created.chapter,
  );
  await _persistWorldTheme(repo, manuscriptId, created, identity);
  if (!context.mounted) return false;
  _notifyWorldCreated(context, created.name, created.chapter, identity);
  return true;
}

/// 落库：主题行 + 首条设定断言（R-019：由 [showAndCreateWorldTheme] 抽出）。
///
/// `N12-F3c`：[identity] 与 `created.chapter` **语义不同、分别落库** ——
/// 旧列 `chapter` 存**用户原写的数**（R1′：不覆盖、不篡改），新载体
/// `chapterSortOrder` 存归一后的**身份**（展示侧只吃后者）。
///
/// `firstSeenChapter` 收的是 [identity]（不是用户写的序位）—— 该列此后
/// **单语义 = 身份**，与 `character_fact` 同基（`DECISIONS §4-35` 的判据是
/// **写入方清单**，本函数就是世界观侧的唯一写入方）。
Future<void> _persistWorldTheme(
  WorldFactRepository repo,
  String manuscriptId,
  CreateWorldThemeResult created,
  int? identity,
) async {
  final evidence = created.evidence;
  await repo.upsertWorld(
    manuscriptId: manuscriptId,
    name: created.name,
    firstSeenChapter: identity,
    firstSeenAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    assertions: [
      if (created.attribute != null && created.value != null)
        CharacterAssertion(
          attribute: created.attribute!,
          value: created.value!,
          chapter: created.chapter,
          chapterSortOrder: identity,
          timestamp: nowSec(),
          status: 'confirmed',
          source: 'user',
          evidence: evidence == null || evidence.isEmpty ? null : evidence,
        ),
    ],
  );
  if (created.description.isNotEmpty) {
    await repo.updateWorldDescription(
      manuscriptId: manuscriptId,
      name: created.name,
      description: created.description,
    );
  }
}

/// 创建成功轻提示（A1：用户写入视角的下一步引导）。
///
/// `N12-F3c`：用户填了章号、而**该序位在作品里不存在**时**如实告知** —— 该值按
/// `ADR-C95` 裁定 2 **不落库**（不编造章号），但静默丢弃会让用户以为「填了没反应」
/// （与 `character_list_view._notifyCharacterCreated` 同款处理）。
void _notifyWorldCreated(
  BuildContext context,
  String name,
  int? typed,
  int? identity,
) {
  final msg = (typed != null && identity == null)
      ? '已创建设定主题「$name」；该作品当前没有第 $typed 章，首次提出章节未记录'
      : '已创建设定主题「$name」，可打标签、关联角色或补充断言';
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}

/// 用户在弹层手填的章号 → **身份**（`chapters.sort_order`）。
///
/// 弹层标签是「章节（选填，如：3）」⇒ 用户填的必然是他**看得见**的那个数
/// （= 序位），不是内部身份；不归一则该列会混装序位与身份两种基号，展示层
/// 无从分辨（`N12-F3` 报告 §3.1）。
///
/// 与 `N12-F3a` 的 `character_list_view._firstSeenSortOrder`、与
/// `WorldEditorService._identityForUserInput` **同口径、同实现、同理由**：
/// 读 `ChapterRepository.listChapters` 而非 `chapterListProvider`（后者派生自
/// `chapterStoreProvider`，首次读时其异步加载可能未完成 ⇒ 空列表 ⇒ 把用户填的
/// **合法**序位静默归一成 null，那是**输入丢失**）。库读是权威值。解析不到 ⇒ null。
Future<int?> _identityForPosition(
  WidgetRef ref,
  String manuscriptId,
  int? position,
) async {
  if (position == null) return null;
  final chapters = await ChapterRepository(
    ref.read(appDatabaseProvider),
  ).listChapters(manuscriptId);
  return identityForUserPosition(chapters, position);
}

/// 世界观设定列表主体（无 Scaffold / 无 AppBar），可嵌入任意页面 body。
class WorldFactListView extends ConsumerStatefulWidget {
  final String manuscriptId;

  /// 行数变化回调（过滤 + 排序后的行数）。薄壳据此显示 AppBar 标题「世界观 (N)」。
  final ValueChanged<int>? onCountChanged;

  const WorldFactListView({
    super.key,
    required this.manuscriptId,
    this.onCountChanged,
  });

  @override
  ConsumerState<WorldFactListView> createState() => WorldFactListViewState();
}

/// [WorldFactListView] 的 State —— **公开**，供薄壳经 `GlobalKey` 调 [refresh]。
class WorldFactListViewState extends ConsumerState<WorldFactListView> {
  bool _loading = true;
  bool _error = false;
  List<WorldFact> _worlds = const [];
  String _query = '';

  /// ★ 2026-09-20 观感批：**库里到底有没有行**（含归档），与 `_worlds`
  /// （当前视图的集合）**分开放**。
  ///
  /// 不分开就会出「假空」——实证：库里唯一一条已被归档、而「显示已归档」
  /// 关着 ⇒ `_worlds` 为空 ⇒ 旧逻辑报「还没有世界观设定」，**谎称库里没有**。
  /// 空态分流必须看这个字段，不能看 `_worlds`。
  int _totalCount = 0;

  /// 库里有多少条**已归档**行 —— 决定「搜不到」时要不要提示「归档被排除」。
  /// 没有归档行却提示归档，是**过度提示**（同样在误导用户）。
  int _archivedCount = 0;

  /// false = 按首见章节升序；true = 按最近更新降序（R8 两档排序）
  bool _sortByUpdate = false;

  /// Q1 暂定：显示已归档开关（切换后 listWorlds(includeArchived: true)）
  bool _showArchived = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  /// 重新拉取世界观列表（供薄壳经 GlobalKey 从外部触发刷新）。
  Future<void> refresh() => _load();

  Future<void> _load() async {
    try {
      final repo = WorldFactRepository(ref.read(appDatabaseProvider));
      final items = await repo.listWorlds(
        widget.manuscriptId,
        includeArchived: _showArchived,
      );
      // 另取全量（含归档）仅用于**计数** —— 空态分流需要知道「库里有没有」，
      // 而 `items` 是「当前视图有没有」。两个问题，两个答案，不能混用。
      final all = await repo.listWorlds(
        widget.manuscriptId,
        includeArchived: true,
      );
      if (!mounted) return;
      setState(() {
        _worlds = items;
        _totalCount = all.length;
        _archivedCount = all.where(_isArchived).length;
        _loading = false;
        _error = false;
      });
      _reportCount();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = true;
      });
    }
  }

  /// 列表头「＋ 新建设定主题」：与薄壳 AppBar action 共用 [showAndCreateWorldTheme]。
  Future<void> _create() async {
    final ok = await showAndCreateWorldTheme(context, ref, widget.manuscriptId);
    if (ok && mounted) await _load();
  }

  List<CharacterAssertion> _parsedOf(WorldFact row) {
    return WorldFactRepository.parseAssertions(row.assertions);
  }

  bool _hasValidAssertion(WorldFact row) {
    return _parsedOf(row).any((a) => a.status == 'confirmed' && !a.stale);
  }

  bool _isArchived(WorldFact row) => row.status != 'active';

  /// 搜索（主题名 / 属性 / 取值包含匹配；世界观无别名，不比照角色）
  List<WorldFact> _filtered() {
    final q = _query.trim();
    return [
      for (final row in _worlds)
        if (_matchesQuery(row, q)) row,
    ];
  }

  bool _matchesQuery(WorldFact row, String q) {
    if (q.isEmpty) return true;
    return row.name.contains(q) ||
        _parsedOf(
          row,
        ).any((a) => a.attribute.contains(q) || a.value.contains(q));
  }

  /// 「首见章节」档 = 按 `first_seen_chapter` 升序。
  ///
  /// `N12-F3c`：该列存的是**身份** ⇒ 升序即**作品当前章节顺序**，删除 / 交换 /
  /// 跨卷移动后**自动跟随**；未标注（null）的排在末尾（哨兵 `1 << 30`）。
  List<WorldFact> _sorted(List<WorldFact> rows) {
    final sorted = [...rows];
    sorted.sort((a, b) {
      if (_sortByUpdate) return b.updatedAt.compareTo(a.updatedAt);
      final av = a.firstSeenChapter ?? 1 << 30;
      final bv = b.firstSeenChapter ?? 1 << 30;
      return av.compareTo(bv);
    });
    return sorted;
  }

  /// 上报过滤 + 排序后的行数（薄壳 AppBar 标题用）。
  void _reportCount() {
    final cb = widget.onCountChanged;
    if (cb == null) return;
    cb(_sorted(_filtered()).length);
  }

  /// 点列表项 → 主题详情页（R3/R4/R5 承载在详情态）；返回后刷新列表。
  Future<void> _openDetail(WorldFact row) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => WorldFactDetailPage(
          worldId: row.id,
          manuscriptId: widget.manuscriptId,
        ),
      ),
    );
    // 返回后刷新列表（对齐 character_list_view.dart:177-190）。
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error) return _buildErrorState();
    // `N12-F3c`：`first_seen_chapter` 存的是**身份键**（`chapter.sortOrder`，0 基、
    // 可空洞、删除不重编号）⇒ 展示必须解析成「当前章节列表里的序位」；解析失败
    // （章已删 / 在回收站）⇒ **不显示数字、不编造**（`ADR-C95` 裁定 2）。
    // 此处用 provider 而非库读：**读**侧要的正是「UI 当前认定的章节序」，且 store
    // 加载完成会自动通知重建；**写**侧才必须读库（理由见 `_identityForPosition`）。
    final chapterNoMap = buildChapterNoMap(
      ref.watch(chapterListProvider(widget.manuscriptId)),
    );
    return _buildBody(_sorted(_filtered()), chapterNoMap);
  }

  Widget _buildBody(List<WorldFact> rows, Map<int, int> chapterNoMap) {
    return Column(
      children: [
        // 已有主题才显示搜索 / 排序 / 归档开关 / 列表头新建按钮（空态由 CTA 承担入口）。
        if (_worlds.isNotEmpty) ...[
          _buildSearchField(),
          _buildSortBar(),
          _buildArchivedToggle(),
          _CreateWorldThemeButton(onPressed: _create),
        ],
        Expanded(
          child: rows.isEmpty ? _buildEmpty() : _buildList(rows, chapterNoMap),
        ),
      ],
    );
  }

  Widget _buildList(List<WorldFact> rows, Map<int, int> chapterNoMap) {
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      itemCount: rows.length,
      itemBuilder: (_, i) => _buildListItem(rows[i], chapterNoMap),
    );
  }

  /// 空态分流（2026-09-20 观感批重写）。
  ///
  /// ★ 旧实现是 `if (_worlds.isEmpty) 首见空态 else '没有匹配「$_query」'`，
  ///   有两处**判据错位**（本轮由新增用例当场判红，非推测）：
  ///     ① **假空**：`_worlds` 取数带 `includeArchived: _showArchived` ⇒
  ///        库里唯一一条已归档、开关关着 ⇒ `_worlds` 空 ⇒ 报「还没有世界观
  ///        设定」，而库里**明明有**。故首见空态必须看 [_totalCount]。
  ///     ② **过度提示**：无归档行时也提示「已归档的默认不参与搜索」⇒ 用户
  ///        会去找一个不存在的开关。故该提示必须看 [_archivedCount]。
  ///   现按「库里有没有（[_totalCount]）」与「有没有生效筛选」两级分流。
  Widget _buildEmpty() {
    // 一级：库里确实一条都没有 ⇒ 首见空态（引导怎么开始）
    if (_totalCount == 0) return _buildFirstRunEmpty();

    // 二级：库里有行，但当前视图被过滤空 ⇒ 筛选空态（引导怎么回到全量）。
    // 归档行被默认排除时补一句说明 —— 这是「搜不到 ≠ 不存在」的唯一线索。
    final q = _query.trim();
    final excludeHint = _archivedCount > 0 && !_showArchived
        ? '另有 $_archivedCount 条已归档的主题被默认排除，可开启「显示已归档」后查看'
        : null;
    return SettingSearchEmptyState(
      query: q,
      onClear: _clearFilters,
      excludedHint: excludeHint,
    );
  }

  /// 清除搜索词；若当前是「归档行被排除」造成的空列表，一并打开开关
  /// （否则按了「清除筛选」还是空的，用户会以为按钮坏了）。
  void _clearFilters() {
    setState(() {
      _query = '';
      if (_archivedCount > 0 && !_showArchived) _showArchived = true;
    });
    _load();
  }

  /// 首见空态（**库里一条都没有**，与「筛选空态」是两件事）。
  ///
  /// 2026-09-20 观感批：改用公共 [SettingEmptyState]，与角色 / 大纲 / 其他
  /// 三页形态统一。**文案与动作一字未改** —— 本页原先就是四页里形态最正的
  /// 一版（公共组件正是照它抽的），此处只做容器替换，不做行为变更。
  Widget _buildFirstRunEmpty() {
    return SettingEmptyState(
      icon: Icons.public_outlined,
      title: '还没有世界观设定',
      description: '手动记录你的世界规则与设定，写作时教练会据此复查前后是否一致。',
      actionLabel: '＋ 新建设定主题',
      onAction: _create,
    );
  }

  Widget _buildErrorState() {
    // 收敛到公共错误态件（此前本页自带一套手写 Text+TextButton ⇒
    // 统一了空态长相却漏了三态契约，是「四子列表三态不齐」的根因之一）。
    return SettingErrorState(message: '加载世界观设定失败，请重试', onRetry: _load);
  }

  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        AppSpacing.sm,
        AppSpacing.page,
        0,
      ),
      child: TextField(
        onChanged: (v) {
          setState(() => _query = v);
          _reportCount();
        },
        decoration: InputDecoration(
          isDense: true,
          hintText: '搜索主题名 / 属性 / 取值',
          prefixIcon: const Icon(Icons.search, size: 20),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        ),
      ),
    );
  }

  Widget _buildSortBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.page,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Text('排序', style: context.text.caption),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('首见章节')),
                ButtonSegment(value: true, label: Text('最近更新')),
              ],
              selected: {_sortByUpdate},
              showSelectedIcon: false,
              onSelectionChanged: (s) {
                setState(() => _sortByUpdate = s.first);
                _reportCount();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildArchivedToggle() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
      child: Row(
        children: [
          Expanded(child: Text('显示已归档', style: context.text.caption)),
          Switch(
            value: _showArchived,
            onChanged: (v) {
              setState(() => _showArchived = v);
              _load();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildListItem(WorldFact row, Map<int, int> chapterNoMap) {
    return Card(
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.page,
        vertical: AppSpacing.xs,
      ),
      child: ListTile(
        title: Row(
          children: [
            Expanded(
              child: Text(row.name, style: context.text.titleMd, maxLines: 1),
            ),
            if (_isArchived(row)) _buildTag('已归档', context.palette.l2Text),
            if (!_hasValidAssertion(row))
              _buildTag(kWorldThemeEmptyHint, context.palette.textTertiary),
          ],
        ),
        subtitle: _buildItemSubtitle(row, chapterNoMap),
        onTap: () => _openDetail(row),
      ),
    );
  }

  /// 小角标（已归档 / 空主题标识，Q1 / Q3）
  Widget _buildTag(String label, Color color) {
    return Container(
      margin: const EdgeInsets.only(left: AppSpacing.xs),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xsm,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: context.palette.primarySoft,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        label,
        style: context.text.microCaption.copyWith(color: color),
      ),
    );
  }

  /// 副标题：首见章节 + 有效断言摘要（前 3 条 confirmed 且非 stale）
  Widget _buildItemSubtitle(WorldFact row, Map<int, int> chapterNoMap) {
    final summary = _parsedOf(row)
        .where((a) => a.status == 'confirmed' && !a.stale)
        .take(_kSummaryMax)
        .map((a) => '${a.attribute}·${a.value}')
        .join(' / ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_firstSeenText(row, chapterNoMap), style: context.text.caption),
        if (summary.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xxs),
            child: Text(
              summary,
              style: context.text.noteCaption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
  }

  /// 首见章节文案（`N12-F3c`）：只吃**身份键**，经 map 解析成序位。
  ///
  /// 解析不出（为 null / 该章已不在列表中）⇒ 「首次提出章节未知」—— 不编造数字
  /// （`ADR-C95` 裁定 2）。★ **不得**改成 `'第$ch章'` 直出：那会把**身份键**当展示号
  /// （`DECISIONS §4-35`，实现文件头也写着「传错参数不报错、只会显示一个错的号」）。
  String _firstSeenText(WorldFact row, Map<int, int> chapterNoMap) {
    final label = chapterLabel(chapterNoMap, row.firstSeenChapter);
    return label == null ? '首次提出章节未知' : '$label首次提出';
  }
}

/// 「＋ 新建设定主题」按钮（A1：置于列表上方）。
/// 与薄壳 AppBar 的「＋ 新建」共用 [showAndCreateWorldTheme] 创建逻辑。
class _CreateWorldThemeButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _CreateWorldThemeButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        0,
        AppSpacing.page,
        AppSpacing.sm,
      ),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: onPressed,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('＋ 新建设定主题'),
        ),
      ),
    );
  }
}
