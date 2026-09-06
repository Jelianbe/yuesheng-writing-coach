// ─────────────────────────────────────────────────────────────
// CharacterPage — 角色列表页（C78 批次3，FR-1/FR-7/FR-10）
//
// 入口：写作页 AppBar ⋮ 菜单（ADR-C78 §3.0，独立路由页非 Sheet）；
// 对话页 FR-10 提示卡经 go_router 携 sinceTimestamp 深链（最近批次过滤视图）。
//
// 列表：按作品展示全部角色（listCharacters 默认排除 merged 源行——
// 合并后源行断言已拷进目标行，再显示会双重计数）；搜索（主名/别名）
// + 排序（首见章节 / 最近更新）；每行名字 / 首见章节 / 断言摘要。
//
// 最近批次视图（sinceTimestamp != null）：只显示该时刻后新沉淀过断言的
// 角色，行尾「+N 新」角标；横幅如实标注「按断言落库时间过滤」。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/app_theme.dart';
import '../../data/database/database.dart';
import '../../data/database/utils.dart';
import '../../data/repositories/character_fact_repository.dart';
import '../../providers/app_providers.dart';
import '../../types/character_types.dart';
import 'character_detail_page.dart';
import 'character_dialogs.dart';

/// 断言摘要最多展示的条目数
const int _kSummaryMax = 3;

/// 角色列表页
class CharacterPage extends ConsumerStatefulWidget {
  final String manuscriptId;

  /// 作品标题（AppBar 副标；可空）
  final String? manuscriptTitle;

  /// FR-10：最近批次过滤起点（unix 秒）。null = 全部。
  final int? sinceTimestamp;

  const CharacterPage({
    super.key,
    required this.manuscriptId,
    this.manuscriptTitle,
    this.sinceTimestamp,
  });

  @override
  ConsumerState<CharacterPage> createState() => _CharacterPageState();
}

class _CharacterPageState extends ConsumerState<CharacterPage> {
  bool _loading = true;
  List<CharacterFact> _characters = const [];
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

  Future<void> _load() async {
    final repo = CharacterFactRepository(ref.read(appDatabaseProvider));
    final items = await repo.listCharacters(widget.manuscriptId);
    if (!mounted) return;
    setState(() {
      _characters = items;
      _loading = false;
    });
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
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final rows = _sorted(_filtered());
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('角色 (${rows.length})'),
        actions: [
          TextButton(onPressed: _showCreateDialog, child: const Text('+ 新建')),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_inRecentMode) _buildRecentBanner(),
                _buildSearchField(),
                _buildSortBar(),
                Expanded(
                  child: rows.isEmpty
                      ? const Center(
                          child: Text(
                            '还没有角色，诊断一章或手动新建试试',
                            style: AppTextStyles.body,
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.only(bottom: AppSpacing.xl),
                          itemCount: rows.length,
                          itemBuilder: (_, i) => _buildListItem(rows[i]),
                        ),
                ),
              ],
            ),
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
        onChanged: (v) => setState(() => _query = v),
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
              onSelectionChanged: (s) =>
                  setState(() => _sortByUpdate = s.first),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildListItem(CharacterFact row) {
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
        subtitle: _buildItemSubtitle(row),
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
  Widget _buildItemSubtitle(CharacterFact row) {
    final summary = _parsedOf(row)
        .where((a) => a.status == 'confirmed' && !a.stale)
        .take(_kSummaryMax)
        .map((a) => '${a.attribute}·${a.value}')
        .join(' / ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_firstSeenText(row), style: AppTextStyles.caption),
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

  String _firstSeenText(CharacterFact row) {
    final ch = row.firstSeenChapter;
    return ch == null ? '首次登场章节未知' : '第$ch章登场';
  }

  Future<void> _showCreateDialog() async {
    final created = await showCreateCharacterDialog(context);
    if (created == null || !mounted) return;
    await CharacterFactRepository(
      ref.read(appDatabaseProvider),
    ).upsertCharacter(
      manuscriptId: widget.manuscriptId,
      name: created.name,
      firstSeenChapter: created.firstSeenChapter,
      firstSeenAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
    _load();
  }
}
