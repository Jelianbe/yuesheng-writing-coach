// ─────────────────────────────────────────────────────────────
// CharacterListView — 角色列表主体（可嵌入组件，无 Scaffold / AppBar）
//
// 从 character_page.dart 抽出的「列表主体」，供：
//   ① 作品详情页 Tab1（角色）内嵌 —— 架构 §2.1 / §3.3；
//   ② 独立路由页 CharacterPage 薄壳的 body（保留 Scaffold+AppBar）。
//
// A1 裁定（舰长已拍板）：`＋ 新建角色` 按钮**跟角色列表走**，置于
// 列表上方（由 [_CreateCharacterButton] 承载）；独立页 AppBar 的「+ 新建」
// 与列表头按钮**共用同一创建逻辑** —— 见 [showAndCreateCharacter]，
// 两处均调用它，禁止复制两份（架构 §3.3.3 关键约束 2）。
//
// 无 Scaffold / 无 AppBar：直接塞进 TabBarView 不会产生双层标题栏
// （架构 R4-10）。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/app_theme.dart';
import '../../data/database/database.dart';
import '../../data/database/utils.dart';
import '../../data/repositories/chapter_repository.dart';
import '../../data/repositories/character_fact_repository.dart';
import '../../providers/app_providers.dart';
import '../../providers/manuscript_providers.dart';
import '../../types/character_types.dart';
import '../../utils/chapter_number.dart';
import 'character_detail_page.dart';
import 'character_dialogs.dart';
import 'pending_confirm_card.dart';

/// 断言摘要最多展示的条目数
const int _kSummaryMax = 3;

/// ★ A1 共享创建逻辑（架构 §3.3.3）：弹出「新建角色」弹窗并落库。
///
/// 「新建角色」存在**两个触发点**（架构 §2.3 A1 裁定）——
///   ① [CharacterListView] 列表头的「＋ 新建角色」按钮；
///   ② 独立页 [CharacterPage] 薄壳 AppBar 的「+ 新建」action。
/// **两处必须共用本函数**，否则出现行为分叉（禁止复制粘贴两份逻辑）。
///
/// 返回值：创建成功返回 `true`（供调用方决定是否刷新）；
/// 取消或名字为空返回 `false`。
Future<bool> showAndCreateCharacter(
  BuildContext context,
  WidgetRef ref,
  String manuscriptId,
) async {
  final created = await showCreateCharacterDialog(context);
  if (created == null) return false;
  // ADR-C95 / `N12-F3a`：弹层填的是**章序位**，本列存的是**身份键** ⇒ 写入前归一。
  final firstSeen = await _firstSeenSortOrder(
    ref,
    manuscriptId,
    created.firstSeenChapter,
  );
  final repo = CharacterFactRepository(ref.read(appDatabaseProvider));
  await repo.upsertCharacter(
    manuscriptId: manuscriptId,
    name: created.name,
    firstSeenChapter: firstSeen,
    firstSeenAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
  );
  if (created.description.isNotEmpty) {
    await repo.updateCharacterDescription(
      manuscriptId: manuscriptId,
      name: created.name,
      description: created.description,
    );
  }
  if (!context.mounted) return false;
  _notifyCharacterCreated(
    context,
    created.name,
    created.firstSeenChapter,
    firstSeen,
  );
  return true;
}

/// 创建角色后的结果提示（R-019：由 [showAndCreateCharacter] 抽出）。
///
/// 用户填了章号、而**该序位在作品里不存在**时**如实告知**：该值按 ADR-C95 裁定 2
/// **不落库**（不编造章号），但静默丢弃会让用户以为「填了没反应」。
void _notifyCharacterCreated(
  BuildContext context,
  String name,
  int? typed,
  int? stored,
) {
  final msg = (typed != null && stored == null)
      ? '已创建角色「$name」；该作品当前没有第 $typed 章，首见章节未记录'
      : '已创建角色「$name」，可打标签、关联设定或补充断言';
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}

/// 用户输入的「第几章」（**序位**，1 基）→ 该章 `sortOrder`（**身份键**）。
///
/// 归一后 `first_seen_chapter` **只有一个语义**（身份），展示层才能可靠解析成序位；
/// 不归一则该列继续混装身份与序位两种基号（`N12-F3` 报告 §3.1）。
///
/// 序位不存在（越界 / 空作品）→ `null`：**不编造**（ADR-C95 裁定 2），由调用方如实提示。
///
/// 用 `ChapterRepository.listChapters` 而非 `chapterListProvider`：后者由 microtask
/// 触发**异步**加载，此刻可能仍是空列表 —— 那会把用户填的合法序位静默归一成 null
/// （**输入丢失**）。库读是权威值，不依赖订阅时序。
Future<int?> _firstSeenSortOrder(
  WidgetRef ref,
  String manuscriptId,
  int? position,
) async {
  if (position == null) return null;
  final chapters = await ChapterRepository(
    ref.read(appDatabaseProvider),
  ).listChapters(manuscriptId);
  return sortOrderAtPosition(buildChapterNoMap(chapters), position);
}

/// 角色列表主体（无 Scaffold / 无 AppBar），可嵌入任意 TabBarView 或页面 body。
///
/// 内含「＋ 新建角色」按钮（列表上方）—— A1 裁定：新建入口跟列表走。
/// 「最近批次」模式：sinceTimestamp != null 时启用（FR-10 深链）。
class CharacterListView extends ConsumerStatefulWidget {
  final String manuscriptId;

  /// FR-10：最近批次过滤起点（unix 秒）。null = 全部。
  /// 详情页 Tab1 传 null（恒「全部」视图，见架构 §4 R4-6）。
  final int? sinceTimestamp;

  /// 行数变化回调（过滤 + 排序后的行数）。
  /// 独立页薄壳据此显示 AppBar 标题「角色 (N)」，避免重复查询（架构 R4-8）。
  final ValueChanged<int>? onCountChanged;

  const CharacterListView({
    super.key,
    required this.manuscriptId,
    this.sinceTimestamp,
    this.onCountChanged,
  });

  @override
  ConsumerState<CharacterListView> createState() => CharacterListViewState();
}

/// [CharacterListView] 的 State —— **公开**，供薄壳经 `GlobalKey` 调 [refresh]。
///
/// 架构 R4-8：独立页 AppBar 的「+ 新建」创建成功后需让列表刷新，薄壳经
/// `GlobalKey<CharacterListViewState>` 直接触发，避免「薄壳重建但子 State
/// 未重建 ⇒ 列表不更新」的陈旧数据缺陷。
class CharacterListViewState extends ConsumerState<CharacterListView> {
  bool _loading = true;
  List<CharacterFact> _characters = const [];

  /// 设定资料库第一批：AI 抽取待用户裁决的断言（确认卡数据源）
  List<(CharacterFact, CharacterAssertion)> _pending = const [];
  String _query = '';
  int? _since;

  /// false = 按首见章节升序；true = 按最近更新降序（FR-1 两档排序）
  bool _sortByUpdate = false;

  @override
  void initState() {
    super.initState();
    _since = widget.sinceTimestamp;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  /// 重新拉取角色列表。
  ///
  /// 供薄壳（[CharacterPage]）的 AppBar「+ 新建」在创建成功后**从外部触发刷新** ——
  /// 经 `GlobalKey<CharacterListViewState>` 调用（架构 R4-8：薄壳与 body
  /// 共享同一数据源，避免双份查询）。
  Future<void> refresh() => _load();

  Future<void> _load() async {
    final repo = CharacterFactRepository(ref.read(appDatabaseProvider));
    final items = await repo.listCharacters(widget.manuscriptId);
    final pending = await repo.listPendingAssertions(widget.manuscriptId);
    if (!mounted) return;
    setState(() {
      _characters = items;
      _pending = pending;
      _loading = false;
    });
    _reportCount();
  }

  /// 列表头「＋ 新建角色」（A1）：与独立页 AppBar action 共用共享逻辑。
  Future<void> _create() async {
    final ok = await showAndCreateCharacter(context, ref, widget.manuscriptId);
    if (ok && mounted) await _load();
  }

  List<CharacterAssertion> _parsedOf(CharacterFact row) {
    return CharacterFactRepository.parseAssertions(row.assertions);
  }

  /// 搜索（主名/别名包含）+ 最近批次过滤
  List<CharacterFact> _filtered() {
    final q = _query.trim();
    return [
      for (final row in _characters)
        if (_matchesQuery(row, q) && (!_inRecentMode || _newCount(row) > 0))
          row,
    ];
  }

  bool _matchesQuery(CharacterFact row, String q) {
    if (q.isEmpty) return true;
    return row.name.contains(q) ||
        parseJsonStringList(row.aliases).any((s) => s.contains(q)) ||
        _parsedOf(
          row,
        ).any((a) => a.attribute.contains(q) || a.value.contains(q));
  }

  bool get _inRecentMode => _since != null;

  /// 最近批次模式下行角标数：该时刻后落库的断言条数
  int _newCount(CharacterFact row) {
    if (!_inRecentMode) return 0;
    return _parsedOf(row).where((a) => a.timestamp >= _since!).length;
  }

  List<CharacterFact> _sorted(List<CharacterFact> rows) {
    final sorted = [...rows];
    sorted.sort((a, b) {
      if (_sortByUpdate) return b.updatedAt.compareTo(a.updatedAt);
      final av = a.firstSeenChapter ?? 1 << 30;
      final bv = b.firstSeenChapter ?? 1 << 30;
      return av.compareTo(bv);
    });
    return sorted;
  }

  /// 上报过滤+排序后的行数（薄壳 AppBar 标题用）。
  void _reportCount() {
    final cb = widget.onCountChanged;
    if (cb == null) return;
    cb(_sorted(_filtered()).length);
  }

  Future<void> _openDetail(CharacterFact row) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => CharacterDetailPage(
          characterId: row.id,
          manuscriptId: widget.manuscriptId,
          sinceTimestamp: _since,
        ),
      ),
    );
    // 返回后刷新列表（保留原 character_page.dart:130 语义，架构 R4-7）。
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    // ADR-C95 裁定 4（`N12-F3a`）：`first_seen_chapter` 存的是**身份键**
    // （`chapter.sortOrder`），展示必须解析为「当前章节列表里的序位」；
    // 解析失败（章已删 / 在回收站）⇒ 不显示数字，不编造。
    final chapterNoMap = buildChapterNoMap(
      ref.watch(chapterListProvider(widget.manuscriptId)),
    );
    return _buildBody(_sorted(_filtered()), chapterNoMap);
  }

  Widget _buildBody(List<CharacterFact> rows, Map<int, int> chapterNoMap) {
    return Column(
      children: [
        if (_inRecentMode) _buildRecentBanner(),
        // 设定资料库第一批：AI 抽取待用户裁决（确认 / 拒绝 → 刷新）
        PendingConfirmCard(
          manuscriptId: widget.manuscriptId,
          items: _pending,
          onChanged: _load,
        ),
        _buildSearchField(),
        _buildSortBar(),
        // ★ A1：新建角色入口随列表走，置于列表上方。
        _CreateCharacterButton(onPressed: _create),
        Expanded(
          child: rows.isEmpty
              ? const Center(
                  child: Text('还没有角色，诊断一章或手动新建试试', style: AppTextStyles.body),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xl),
                  itemCount: rows.length,
                  itemBuilder: (_, i) => _buildListItem(rows[i], chapterNoMap),
                ),
        ),
      ],
    );
  }

  Widget _buildRecentBanner() {
    final total = _characters.fold<int>(0, (sum, r) => sum + _newCount(r));
    return Container(
      width: double.infinity,
      color: AppColors.primarySoft,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.page,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '最近批次沉淀 $total 条（按断言落库时间过滤；提示卡仅本次会话内有效）',
              style: AppTextStyles.noteCaption.copyWith(
                color: AppColors.l1Text,
              ),
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _since = null),
            child: const Icon(Icons.close, size: 16, color: AppColors.l1Text),
          ),
        ],
      ),
    );
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
          hintText: '搜索名字 / 别名 / 属性 / 值',
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
          const Text('排序', style: AppTextStyles.caption),
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

  Widget _buildListItem(CharacterFact row, Map<int, int> chapterNoMap) {
    return Card(
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.page,
        vertical: AppSpacing.xs,
      ),
      child: ListTile(
        title: Row(
          children: [
            Expanded(
              child: Text(row.name, style: AppTextStyles.titleMd, maxLines: 1),
            ),
            _buildNewBadge(row),
          ],
        ),
        subtitle: _buildItemSubtitle(row, chapterNoMap),
        onTap: () => _openDetail(row),
      ),
    );
  }

  /// FR-10：最近批次视图下的「+N 新」角标（非批次视图恒为空）
  Widget _buildNewBadge(CharacterFact row) {
    final newCount = _newCount(row);
    if (newCount <= 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xsm,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        '+$newCount 新',
        style: AppTextStyles.microCaption.copyWith(color: AppColors.l1Text),
      ),
    );
  }

  /// 副标题：首见章节 + 有效断言摘要（前 3 条 confirmed 且非 stale）
  Widget _buildItemSubtitle(CharacterFact row, Map<int, int> chapterNoMap) {
    final summary = _parsedOf(row)
        .where((a) => a.status == 'confirmed' && !a.stale)
        .take(_kSummaryMax)
        .map((a) => '${a.attribute}·${a.value}')
        .join(' / ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_firstSeenText(row, chapterNoMap), style: AppTextStyles.caption),
        if (summary.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xxs),
            child: Text(
              summary,
              style: AppTextStyles.noteCaption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
  }

  String _firstSeenText(CharacterFact row, Map<int, int> chapterNoMap) {
    // 解析失败（章已删 / 在回收站）与「从未记录」同样显示未知 —— 不编造数字。
    final label = chapterLabel(chapterNoMap, row.firstSeenChapter);
    return label == null ? '首次登场章节未知' : '$label登场';
  }
}

/// 「＋ 新建角色」按钮（A1 裁定：置于角色列表上方）。
///
/// 由 [CharacterListView] 渲染，与独立页 AppBar 的「+ 新建」共用
/// [showAndCreateCharacter] 创建逻辑。
class _CreateCharacterButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _CreateCharacterButton({required this.onPressed});

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
          label: const Text('新建角色'),
        ),
      ),
    );
  }
}
