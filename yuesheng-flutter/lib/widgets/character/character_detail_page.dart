// ─────────────────────────────────────────────────────────────
// CharacterDetailPage — 角色详情页（C78 批次3，FR-2/3/4/5/8/9）
//
// 状态与动作层：加载（断言/别名/F05/事件/并入候选）+ 六个用户动作；
// 展示区块全部在 character_detail_sections.dart（真分解，各自守硬上限）。
//
// 判据纪律（ADR-C78 §5.3/§6）：
//   F05 只调 detectConflictsForFacts 取判据，文案由 sections 自渲染；
//   事件只调 filterEventsByIdentity——与 AI 侧同源，防止口径分叉。
//   查看原文走 §4.4 采信决策树（evidence 校验 → 反查 → 诚实降级）。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/app_theme.dart';
import '../../data/database/database.dart';
import '../../data/database/utils.dart';
import '../../data/repositories/chapter_repository.dart';
import '../../data/repositories/character_fact_repository.dart';
import '../../data/repositories/event_fact_repository.dart';
import '../../providers/app_providers.dart';
import '../../router/app_routes.dart';
import '../../services/character_editor_service.dart';
import '../../services/character_identity.dart';
import '../../services/chat_context_builder.dart';
import '../../services/conflict_detector.dart';
import '../../services/fact_stale_service.dart';
import '../../types/character_types.dart';
import 'character_detail_sections.dart';
import 'character_dialogs.dart';
import 'character_events_section.dart';

class CharacterDetailPage extends ConsumerStatefulWidget {
  final String characterId;
  final String manuscriptId;

  /// FR-10：最近批次过滤起点（unix 秒）；null = 显示全部
  final int? sinceTimestamp;

  const CharacterDetailPage({
    super.key,
    required this.characterId,
    required this.manuscriptId,
    this.sinceTimestamp,
  });

  @override
  ConsumerState<CharacterDetailPage> createState() =>
      _CharacterDetailPageState();
}

class _CharacterDetailPageState extends ConsumerState<CharacterDetailPage> {
  bool _loading = true;
  CharacterFact? _row;
  List<CharacterAssertion> _assertions = const [];
  List<String> _aliases = const [];
  List<ConflictObservation> _conflicts = const [];
  List<EventFact> _events = const [];
  List<CharacterFact> _candidates = const [];
  int? _since;

  @override
  void initState() {
    super.initState();
    _since = widget.sinceTimestamp;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  CharacterEditorService get _editor =>
      CharacterEditorService(ref.read(appDatabaseProvider));

  List<CharacterAssertion> get _visibleAssertions {
    final since = _since;
    if (since == null) return _assertions;
    return _assertions.where((a) => a.timestamp >= since).toList();
  }

  Map<int, int> get _staleByChapter {
    final counts = <int, int>{};
    for (final a in _assertions) {
      if (a.stale && a.status != 'rejected' && a.chapter != null) {
        counts[a.chapter!] = (counts[a.chapter!] ?? 0) + 1;
      }
    }
    return counts;
  }

  Future<void> _load() async {
    final db = ref.read(appDatabaseProvider);
    final row = await CharacterFactRepository(
      db,
    ).getCharacterById(widget.characterId);
    if (!mounted) return;
    if (row == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('该角色已不存在')));
      Navigator.pop(context);
      return;
    }
    final aliases = parseJsonStringList(row.aliases);
    final assertions = CharacterFactRepository.parseAssertions(row.assertions);
    final facts = await CharacterFactRepository(
      db,
    ).listCharacters(row.manuscriptId);
    final conflicts = detectConflictsForFacts(facts);
    final events = await EventFactRepository(db).listEvents(row.manuscriptId);
    if (!mounted) return;
    setState(() {
      _row = row;
      _assertions = assertions;
      _aliases = aliases;
      _conflicts = conflicts.where((o) => o.characterName == row.name).toList();
      _events = filterEventsByIdentity(
        events,
        {row.name, ...aliases},
      )..sort((a, b) => (a.chapter ?? 1 << 30).compareTo(b.chapter ?? 1 << 30));
      _candidates = facts.where((f) => f.id != row.id).toList();
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final row = _row;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(row?.name ?? '角色详情')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.page),
              children: [
                CharacterHeaderCard(
                  name: row!.name,
                  aliases: _aliases,
                  assertionCount: _assertions.length,
                  firstSeenChapter: row.firstSeenChapter,
                  mergeEnabled: _candidates.isNotEmpty,
                  onMerge: _mergeInto,
                  onEditAliases: _editAliases,
                ),
                if (_since != null)
                  CharacterRecentBanner(
                    visibleCount: _visibleAssertions.length,
                    onShowAll: () => setState(() => _since = null),
                  ),
                CharacterConflictsCard(conflicts: _conflicts),
                CharacterStaleClearBar(
                  staleByChapter: _staleByChapter,
                  onClear: _clearStaleChapter,
                ),
                CharacterAssertionGroups(
                  assertions: _visibleAssertions,
                  resolveOriginalText: _resolveOriginalText,
                  onReject: _reject,
                  onCorrect: _correct,
                  onSupplement: _supplement,
                ),
                CharacterEventsSection(events: _events, onJump: _jumpToChapter),
              ],
            ),
    );
  }

  // ── 动作：拒绝 / 修正 / 补充 / 别名 / 并入 / 清除旧版 / 跳章 / 原文 ──

  Future<void> _reject(CharacterAssertion a) async {
    final choice = await showRejectReasonSheet(context);
    if (choice == null || !choice.confirmed || !mounted) return;
    await _editor.rejectAssertion(
      characterId: widget.characterId,
      target: a,
      reason: choice.reason,
    );
    _load();
  }

  Future<void> _correct(CharacterAssertion a) async {
    final form = await showAssertionFormDialog(
      context,
      title: '修正断言',
      initialAttribute: a.attribute,
      initialValue: a.value,
      initialChapter: a.chapter,
    );
    if (form == null || !mounted) return;
    await _editor.correctAssertion(
      characterId: widget.characterId,
      target: a,
      newValue: form.value,
      chapter: form.chapter,
    );
    _load();
  }

  Future<void> _supplement(String? attribute) async {
    final form = await showAssertionFormDialog(
      context,
      title: '补充断言',
      initialAttribute: attribute,
    );
    if (form == null || !mounted) return;
    await _editor.addUserAssertion(
      characterId: widget.characterId,
      attribute: form.attribute,
      value: form.value,
      chapter: form.chapter,
    );
    _load();
  }

  Future<void> _editAliases() async {
    final next = await showAliasEditDialog(context, _aliases);
    if (next == null || !mounted) return;
    await _editor.updateAliases(characterId: widget.characterId, aliases: next);
    _load();
  }

  /// D-5 并入主角色：本页 = 目标行，选另一行作源。断言迁移保 source，
  /// 源名收进别名，源行标记 merged（列表与 F05 自动排除）。
  Future<void> _mergeInto() async {
    final source = await showMergePickerDialog(
      context,
      candidates: _candidates,
    );
    if (source == null || !mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) =>
          _MergeConfirmDialog(sourceName: source.name, targetName: _row!.name),
    );
    if (confirmed != true || !mounted) return;
    final ok = await CharacterFactRepository(
      ref.read(appDatabaseProvider),
    ).mergeCharacter(targetId: widget.characterId, sourceId: source.id);
    if (!mounted) return;
    _snack(ok ? '已并入「${source.name}」' : '并入失败');
    if (ok) _load();
  }

  Future<void> _clearStaleChapter(int chapterNo) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清除旧版断言', style: AppTextStyles.titleLg),
        content: Text(
          '删除第$chapterNo章的全部旧版断言（含该章旧版事件）？此操作不可撤销。',
          style: AppTextStyles.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await FactStaleService(ref.read(appDatabaseProvider)).clearStaleChapter(
      manuscriptId: widget.manuscriptId,
      chapterNo: chapterNo,
    );
    _load();
  }

  /// 相关事件跳章节（章节已删/未记录 → 轻提示，不假装跳转）
  Future<void> _jumpToChapter(EventFact event) async {
    if (event.chapter == null) {
      _snack('该事件未记录章节');
      return;
    }
    final chapter = await ChapterRepository(
      ref.read(appDatabaseProvider),
    ).getChapterByOrder(widget.manuscriptId, event.chapter!);
    if (!mounted) return;
    if (chapter == null) {
      _snack('该章节已不存在，无法打开');
      return;
    }
    await context.push(
      AppRoutes.writingChapter.replaceAll(':chapterId', chapter.id),
      extra: <String, dynamic>{
        'manuscriptId': widget.manuscriptId,
        'chapterTitle': chapter.title,
      },
    );
  }

  /// 查看原文（ADR-C78 §4.4 采信决策树）：
  ///   user 来源 evidence 无条件采信（当前 UI 不产 evidence，留接口）；
  ///   ai 来源 evidence 先过正文 contains 校验（防幻觉当原文）；
  ///   未命中 / 缺失 → findKeywordExcerpt(value) 用「断言所属章」正文反查；
  ///   都失败 → null（弹层如实显示「未定位到原文」）。
  Future<String?> _resolveOriginalText(CharacterAssertion a) async {
    if (a.chapter == null) return null;
    final chapter = await ChapterRepository(
      ref.read(appDatabaseProvider),
    ).getChapterByOrder(widget.manuscriptId, a.chapter!);
    if (chapter == null) return null;
    final evidence = a.evidence;
    if (evidence != null && evidence.isNotEmpty) {
      if (a.source == 'user' || chapter.content.contains(evidence)) {
        return evidence;
      }
    }
    return findKeywordExcerpt(chapter.content, a.value);
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }
}

/// 并入确认弹窗（D-5：迁移语义明示，用户知情后才动手）
class _MergeConfirmDialog extends StatelessWidget {
  final String sourceName;
  final String targetName;

  const _MergeConfirmDialog({
    required this.sourceName,
    required this.targetName,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('确认并入', style: AppTextStyles.titleLg),
      content: Text(
        '把「$sourceName」并入「$targetName」？\n\n'
        '· 该行全部断言迁入本角色（AI/手来源保留）\n'
        '· 「$sourceName」自动收进本角色别名\n'
        '· 源行不再出现在角色列表',
        style: AppTextStyles.body,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('并入'),
        ),
      ],
    );
  }
}
