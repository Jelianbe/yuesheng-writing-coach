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
import '../../data/repositories/world_fact_repository.dart';
import '../../providers/app_providers.dart';
import '../../types/character_types.dart';
import 'world_dialogs.dart';

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
  final evidence = created.evidence;
  await repo.upsertWorld(
    manuscriptId: manuscriptId,
    name: created.name,
    firstSeenChapter: created.chapter,
    firstSeenAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    assertions: [
      if (created.attribute != null && created.value != null)
        CharacterAssertion(
          attribute: created.attribute!,
          value: created.value!,
          chapter: created.chapter,
          timestamp: nowSec(),
          status: 'confirmed',
          source: 'user',
          evidence: evidence == null || evidence.isEmpty ? null : evidence,
        ),
    ],
  );
  return true;
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
      if (!mounted) return;
      setState(() {
        _worlds = items;
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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error) return _buildErrorState();
    return _buildBody(_sorted(_filtered()));
  }

  Widget _buildBody(List<WorldFact> rows) {
    return Column(
      children: [
        // 已有主题才显示搜索 / 排序 / 归档开关 / 列表头新建按钮（空态由 CTA 承担入口）。
        if (_worlds.isNotEmpty) ...[
          _buildSearchField(),
          _buildSortBar(),
          _buildArchivedToggle(),
          _CreateWorldThemeButton(onPressed: _create),
        ],
        Expanded(child: rows.isEmpty ? _buildEmpty() : _buildList(rows)),
      ],
    );
  }

  Widget _buildList(List<WorldFact> rows) {
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      itemCount: rows.length,
      itemBuilder: (_, i) => _buildListItem(rows[i]),
    );
  }

  Widget _buildEmpty() {
    if (_worlds.isEmpty) return _buildFirstRunEmpty();
    return Center(
      child: Text('没有匹配「${_query.trim()}」的设定主题', style: AppTextStyles.body),
    );
  }

  Widget _buildFirstRunEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.section),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('还没有世界观设定', style: AppTextStyles.titleLg),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              '手动记录你的世界规则与设定，写作时教练会据此复查前后是否一致。',
              style: AppTextStyles.body,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton(onPressed: _create, child: const Text('＋ 新建设定主题')),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('加载世界观设定失败，请重试', style: AppTextStyles.body),
          const SizedBox(height: AppSpacing.md),
          TextButton(onPressed: _load, child: const Text('重试')),
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

  Widget _buildArchivedToggle() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
      child: Row(
        children: [
          const Expanded(child: Text('显示已归档', style: AppTextStyles.caption)),
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

  Widget _buildListItem(WorldFact row) {
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
            if (_isArchived(row)) _buildTag('已归档', AppColors.l2Text),
            if (!_hasValidAssertion(row))
              _buildTag(kWorldThemeEmptyHint, AppColors.textTertiary),
          ],
        ),
        subtitle: _buildItemSubtitle(row),
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
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        label,
        style: AppTextStyles.microCaption.copyWith(color: color),
      ),
    );
  }

  /// 副标题：首见章节 + 有效断言摘要（前 3 条 confirmed 且非 stale）
  Widget _buildItemSubtitle(WorldFact row) {
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

  String _firstSeenText(WorldFact row) {
    final ch = row.firstSeenChapter;
    return ch == null ? '首次提出章节未知' : '第$ch章首次提出';
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
