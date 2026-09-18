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

import 'dart:async';
import 'package:flutter/material.dart';

import '../setting/setting_description_card.dart';
import '../setting/setting_extract_bar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/app_theme.dart';
import '../../config/shared_constants.dart';
import '../../data/database/database.dart';
import '../../data/database/utils.dart';
import '../../data/repositories/chapter_repository.dart';
import '../../data/repositories/character_fact_repository.dart';
import '../../data/repositories/event_fact_repository.dart';
import '../../data/repositories/setting_link_repository.dart';
import '../../data/repositories/world_fact_repository.dart';
import '../../providers/app_providers.dart';
import '../../providers/manuscript_providers.dart';
import '../../providers/session_providers.dart';
import '../../router/app_routes.dart';
import '../../services/character_editor_service.dart';
import '../../services/llm_client.dart';
import '../../services/character_identity.dart';
import '../../services/chat_context_builder.dart';
import '../../services/conflict_detector.dart';
import '../../services/fact_stale_service.dart';
import '../../services/setting_library_service.dart' as sls;
import '../../types/character_types.dart';
import '../../utils/chapter_number.dart';
import 'character_detail_sections.dart';
import 'character_dialogs.dart';
import '../setting/setting_links_section.dart';
import '../setting/setting_progressions_section.dart';
import '../setting/setting_tags_section.dart';
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

  /// 章号 → stale 条数。**key 取身份**（`chapterIdentity`，`chapterSortOrder` 优先）。
  ///
  /// `N12-F3b` phase 2：此前 key 取 `a.chapter`（AI 标称号），而清除侧
  /// `FactStaleService.clearStaleChapter` → `_markAssertions` 已按
  /// `a.chapterIdentity == chapterNo` 匹配 ⇒ **两侧口径不等**：新行上按钮点了清 0 条
  /// （静默失效）。改用身份后两者同源；存量行两边都走 `chapterIdentity` 的回退，
  /// 故**逐字不变**。（存量断言 `chapterHash == null` ⇒ 永不被标 stale ⇒ 本bar不显示它们。）
  Map<int, int> get _staleByChapter {
    final counts = <int, int>{};
    for (final a in _assertions) {
      final identity = a.chapterIdentity;
      if (a.stale && a.status != 'rejected' && identity != null) {
        counts[identity] = (counts[identity] ?? 0) + 1;
      }
    }
    return counts;
  }

  /// 疑似重复（AI 辅助比较入口）：当前人物断言内的同章同属性异值对。
  List<sls.AssertionConflictPair> get _conflictPairs =>
      sls.detectCharacterConflicts([
        for (final a in _visibleAssertions) (_row?.name ?? '', a),
      ]);

  /// R-019 拆分：疑似重复提示条（无冲突返回空组件）。
  Widget _buildConflictBanner() {
    final count = _conflictPairs.length;
    if (count == 0) return const SizedBox.shrink();
    return _ConflictBanner(count: count, onTap: _resolveNextConflict);
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

  /// 提炼断言落库：upsertCharacter 增量合并（不覆盖既有）+ 刷新。
  Future<int> _extractAssertions(List<CharacterAssertion> extracted) async {
    final repo = CharacterFactRepository(ref.read(appDatabaseProvider));
    await repo.upsertCharacter(
      manuscriptId: widget.manuscriptId,
      name: _row!.name,
      assertions: extracted,
    );
    await _load();
    return _assertions.length;
  }

  /// 「从正文提炼断言」条（A2：正文非空才显示）。
  Widget _buildExtractBar(CharacterFact row) {
    return SettingExtractBar(
      manuscriptId: widget.manuscriptId,
      entityName: row.name,
      description: row.description,
      chapter: row.firstSeenChapter,
      onExtracted: _extractAssertions,
    );
  }

  /// 标签区块（R-019 拆分：详情页 build 临界，挂载抽方法）。
  Widget _buildTagsSection() {
    return SettingTagsSection(
      manuscriptId: widget.manuscriptId,
      kind: SettingEntityKind.character,
      entityId: widget.characterId,
    );
  }

  /// Progressions 章节演进区块（R-019 拆分：详情页 build 临界，挂载抽方法）。
  ///
  /// `N12-F3b` phase 3：时间轴改吃**身份** —— 断言/事件走各自 `chapterSortOrder`，
  /// `firstSeenChapter` 本就是身份键（`N12-F3a` 已在写入前归一），故直接透传。
  Widget _buildProgressionsSection() {
    return SettingProgressionsSection(
      assertions: _assertions,
      events: _events,
      firstSeenChapter: _row?.firstSeenChapter,
      chapterNoMap: _chapterNoMap(),
    );
  }

  /// `sortOrder → 展示章号(1 基)`（ADR-C95 裁定 4 / `N12-F3a`）。
  ///
  /// `first_seen_chapter` 是**身份键**不是展示号；本页只做解析，口径的唯一实现点在
  /// `utils/chapter_number.dart`（此处**禁止**写 `firstSeenChapter + 1` 之类的换算）。
  Map<int, int> _chapterNoMap() =>
      buildChapterNoMap(ref.watch(chapterListProvider(widget.manuscriptId)));

  /// 同上，但走 `ref.read` —— 供 **async 回调**（对话框 / 确认框）使用：
  /// build 之外不允许 `ref.watch`。
  Map<int, int> _chapterNoMapRead() =>
      buildChapterNoMap(ref.read(chapterListProvider(widget.manuscriptId)));

  /// 互链跳转：角色详情页只处理「跳到世界观详情页」（区块回调注入）。
  void _jumpToWorld(SettingEntityKind kind, String id) {
    if (kind != SettingEntityKind.world) return;
    context.push(
      AppRoutes.worldDetail,
      extra: {'manuscriptId': widget.manuscriptId, 'id': id},
    );
  }

  /// 近轮过滤横幅（R-019 拆分：build 临界，抽出 _since 分支）。
  Widget _buildRecentBanner() {
    if (_since == null) return const SizedBox.shrink();
    return CharacterRecentBanner(
      visibleCount: _visibleAssertions.length,
      onShowAll: () => setState(() => _since = null),
    );
  }

  /// 一致性卡片区（R-019 拆分：冲突卡 + 冲突横幅 + 陈旧清除合并）。
  Widget _buildConsistencyCards() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CharacterConflictsCard(
          conflicts: _conflicts,
          chapterNoMap: _chapterNoMap(),
        ),
        _buildConflictBanner(),
        CharacterStaleClearBar(
          staleByChapter: _staleByChapter,
          chapterNoMap: _chapterNoMap(),
          onClear: _clearStaleChapter,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final row = _row;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: _buildAppBar(row),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(row!),
    );
  }

  /// 页面主体列表（R-019 拆分：`build` 临界，抽出 ListView 内容 —— 与
  /// `_buildAppBar` / `_buildConsistencyCards` / `_buildProgressionsSection` 同构）。
  ///
  /// `N12-F3b` phase 2：三处传 `chapterNoMap` —— **展示侧一律只由身份载体渲染章标**
  /// （读法说明见 `utils/chapter_number.dart` 文件头）。
  Widget _buildBody(CharacterFact row) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.page),
      children: [
        CharacterHeaderCard(
          name: row.name,
          aliases: _aliases,
          assertionCount: _assertions.length,
          firstSeenChapter: row.firstSeenChapter,
          chapterNoMap: _chapterNoMap(),
          mergeEnabled: _candidates.isNotEmpty,
          onMerge: _mergeInto,
          onEditAliases: _editAliases,
        ),
        SettingDescriptionCard(
          description: row.description,
          onEdit: _editDescription,
        ),
        _buildExtractBar(row),
        _buildRecentBanner(),
        _buildConsistencyCards(),
        CharacterAssertionGroups(
          assertions: _visibleAssertions,
          chapterNoMap: _chapterNoMap(),
          resolveOriginalText: _resolveOriginalText,
          onReject: _reject,
          onCorrect: _correct,
          onSupplement: _supplement,
          onToggleNegative: _toggleNegative,
        ),
        CharacterEventsSection(
          events: _events,
          chapterNoMap: _chapterNoMap(),
          onJump: _jumpToChapter,
        ),
        _buildProgressionsSection(),
        _buildTagsSection(),
        SettingLinksSection(
          manuscriptId: widget.manuscriptId,
          kind: SettingEntityKind.character,
          entityId: widget.characterId,
          onJump: _jumpToWorld,
        ),
      ],
    );
  }

  // ── 动作：拒绝 / 修正 / 补充 / 别名 / 并入 / 清除旧版 / 跳章 / 原文 ──

  /// R-019 拆分（v35 钉住）：AppBar（标题 + 钉住开关）独立成方法。
  AppBar _buildAppBar(CharacterFact? row) {
    return AppBar(
      title: Text(row?.name ?? '角色详情'),
      actions: [
        if (row != null)
          IconButton(
            tooltip: row.pinned == 1 ? '取消钉住（不再常驻注入）' : '钉住（当轮正文未提及也常驻注入设定）',
            icon: Icon(
              row.pinned == 1 ? Icons.push_pin : Icons.push_pin_outlined,
              color: row.pinned == 1 ? AppColors.primary : null,
            ),
            onPressed: () => _togglePinned(row),
          ),
      ],
    );
  }

  Future<void> _reject(CharacterAssertion a) async {
    final choice = await showRejectReasonSheet(context);
    if (choice == null || !choice.confirmed || !mounted) return;
    await _editor.rejectAssertion(
      characterId: widget.characterId,
      target: a,
      reason: choice.reason,
    );
    unawaited(_load());
  }

  /// 模板可学习：属性名建议 = 静态基础模板 + 作品内 user 属性 ≥2 次回填（去重）。
  Future<List<String>> _attributeSuggestions() async {
    final learned = await CharacterFactRepository(
      ref.read(appDatabaseProvider),
    ).listLearnedAttributes(widget.manuscriptId);
    final seen = <String>{};
    return [
      for (final s in [...AttributeTemplate.suggestions, ...learned])
        if (seen.add(s)) s,
    ];
  }

  /// 逐一处理疑似重复：打开对照面板 → 裁决 → 落库刷新。
  Future<void> _resolveNextConflict() async {
    final pairs = _conflictPairs;
    if (pairs.isEmpty) return;
    final pair = pairs.first;
    final verdict = await showConflictResolutionDialog(
      context,
      pair: pair,
      chapterNoMap: _chapterNoMapRead(),
      aiCompare: () => _aiCompare(pair),
    );
    if (verdict == null || !mounted) return;
    final row = _row;
    if (row == null) return;
    await sls.SettingLibraryService(
      characterRepo: CharacterFactRepository(ref.read(appDatabaseProvider)),
      worldRepo: WorldFactRepository(ref.read(appDatabaseProvider)),
    ).resolveCharacterConflict(
      manuscriptId: row.manuscriptId,
      name: row.name,
      attribute: pair.a.attribute,
      a: pair.a,
      b: pair.b,
      verdict: verdict,
    );
    unawaited(_load());
  }

  /// AI 辅助比较（纯分析不代决）：走共享 LlmClient 非流式，失败降级文案。
  Future<String> _aiCompare(sls.AssertionConflictPair pair) async {
    final prompt = sls.buildConflictComparisonPrompt(
      name: pair.name,
      a: pair.a,
      b: pair.b,
    );
    try {
      return await ref.read(llmClientProvider).chatCompletion([
        ChatMessage(role: 'system', content: prompt),
      ]);
    } catch (_) {
      return 'AI 比较调用失败（仍可手动裁决）。';
    }
  }

  Future<void> _toggleNegative(CharacterAssertion a, bool value) async {
    final row = _row;
    if (row == null) return;
    await _editor.setNegative(
      characterId: widget.characterId,
      target: a,
      negative: value,
    );
    unawaited(_load());
  }

  /// 设定钉选（分级供给 L2，v35）：切换 AppBar 钉住，直接落库。
  Future<void> _togglePinned(CharacterFact row) async {
    await _editor.setPinned(row.id, pinned: row.pinned != 1);
    unawaited(_load());
  }

  Future<void> _correct(CharacterAssertion a) async {
    final suggestions = await _attributeSuggestions();
    if (!mounted) return;
    final form = await showAssertionFormDialog(
      context,
      title: '修正断言',
      initialAttribute: a.attribute,
      initialValue: a.value,
      initialChapter: a.chapter,
      suggestions: suggestions,
    );
    if (form == null || !mounted) return;
    await _editor.correctAssertion(
      characterId: widget.characterId,
      target: a,
      newValue: form.value,
      chapter: form.chapter,
    );
    unawaited(_load());
  }

  Future<void> _supplement(String? attribute) async {
    final suggestions = await _attributeSuggestions();
    if (!mounted) return;
    final form = await showAssertionFormDialog(
      context,
      title: '补充断言',
      initialAttribute: attribute,
      suggestions: suggestions,
    );
    if (form == null || !mounted) return;
    await _editor.addUserAssertion(
      characterId: widget.characterId,
      attribute: form.attribute,
      value: form.value,
      chapter: form.chapter,
    );
    unawaited(_load());
  }

  Future<void> _editAliases() async {
    final next = await showAliasEditDialog(context, _aliases);
    if (next == null || !mounted) return;
    await _editor.updateAliases(characterId: widget.characterId, aliases: next);
    unawaited(_load());
  }

  Future<void> _editDescription() async {
    final next = await showDescriptionEditDialog(
      context,
      initial: _row?.description ?? '',
    );
    if (next == null || !mounted) return;
    await CharacterFactRepository(
      ref.read(appDatabaseProvider),
    ).updateCharacterDescription(
      manuscriptId: widget.manuscriptId,
      name: _row!.name,
      description: next,
    );
    unawaited(_load());
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
    if (ok) unawaited(_load());
  }

  /// 删除确认文案里的章标（`N12-F3b` phase 2：**只吃身份**，无章标 ⇒ 说「该章」）。
  ///
  /// 用 `ref.read` 而非 `_chapterNoMap()`（后者 `watch`）—— 本方法在 async 回调里跑，
  /// build 之外不允许 `watch`。
  String _clearStalePrompt(int identity) {
    final chapter = chapterLabel(_chapterNoMapRead(), identity);
    return chapter == null
        ? '删除该章的全部旧版断言（含该章旧版事件）？'
        : '删除$chapter的全部旧版断言（含该章旧版事件）？';
  }

  Future<void> _clearStaleChapter(int chapterNo) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清除旧版断言', style: AppTextStyles.titleLg),
        content: Text(
          '${_clearStalePrompt(chapterNo)}此操作不可撤销。',
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
    unawaited(_load());
  }

  /// 相关事件跳章节（章节已删/未记录 → 轻提示，不假装跳转）
  ///
  /// `N12-F3b`（`ADR-C96 §1.3` 第 1 行）：查库用的是**身份**，故先取
  /// `chapterSortOrder`（存量行为 null ⇒ 退回 `chapter`，行为逐字不变）。
  /// 原实现直接拿 `event.chapter` 去 `getChapterByOrder` —— 而那一列装的是
  /// **AI 标称号**，于是 AI 给号时会**跳错章**、末章直接查不到。
  Future<void> _jumpToChapter(EventFact event) async {
    final sortOrder = event.chapterSortOrder ?? event.chapter;
    if (sortOrder == null) {
      _snack('该事件未记录章节');
      return;
    }
    final chapter = await ChapterRepository(
      ref.read(appDatabaseProvider),
    ).getChapterByOrder(widget.manuscriptId, sortOrder);
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
    // N12-F3b：查库用**身份**（`a.chapterIdentity` 自带存量回退）。
    // 原实现拿 `a.chapter`（AI 标称号）当身份查 ⇒ AI 给号时**定位到另一章**的正文，
    // 或直接「未定位到原文」。
    final sortOrder = a.chapterIdentity;
    if (sortOrder == null) return null;
    final chapter = await ChapterRepository(
      ref.read(appDatabaseProvider),
    ).getChapterByOrder(widget.manuscriptId, sortOrder);
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

/// 疑似重复提示条（AI 辅助比较入口）：点击逐一处理。
class _ConflictBanner extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const _ConflictBanner({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.sm),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppSpacing.sm),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                const Icon(
                  Icons.report_problem_outlined,
                  size: 18,
                  color: AppColors.warning,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    '疑似重复 $count 处（同章同属性异值）',
                    style: AppTextStyles.subBody,
                  ),
                ),
                const Icon(Icons.chevron_right, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
