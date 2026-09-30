// ─────────────────────────────────────────────────────────────
// WorldFactDetailPage — 世界观主题详情页（批次 W1，R3 / R4 / R5）
//
// 承载「主题详情态」（PRD §5.5 线框）的全部交互：
//   · 断言列表（只读，R3；本批**无**改写 / 删除按钮，O-2）
//   · ＋ 追加设定（R4，表单含「原文依据」+「章节」，A2）
//   · 归档本主题（R5，确认弹窗 → §6-F SnackBar → 返回列表）
//   · 恢复本主题（Q1 暂定：归档后可查看 + 可恢复）
//
// 同构参照 character_detail_page.dart（仅取断言区块）；不过它不接 F05、
// 不接事件、不接别名（世界观无别名 / 无 merged，tables.dart）。判据零改动（A4）。
//
// 状态管理照搬 character 口径：ConsumerStatefulWidget + 局部 setState +
// ref.read(appDatabaseProvider) 直建服务/仓储；**不建 provider**。
// ─────────────────────────────────────────────────────────────

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app_settings/setting_description_card.dart';
import '../app_settings/setting_extract_bar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/app_palette.dart';
import '../../config/app_theme.dart';
import '../../data/database/database.dart';
import '../../data/repositories/world_fact_repository.dart';
import '../../providers/app_providers.dart';
import '../../providers/manuscript_providers.dart';
import '../../router/app_routes.dart';
import '../../services/world_editor_service.dart';
import '../../types/character_types.dart';
import '../../utils/chapter_number.dart';
import '../../data/repositories/setting_link_repository.dart';
import '../app_settings/setting_links_section.dart';
import '../app_settings/setting_progressions_section.dart';
import '../app_settings/setting_tags_section.dart';
import 'world_dialogs.dart';
import '../../theme/app_typography.dart';

class WorldFactDetailPage extends ConsumerStatefulWidget {
  final String worldId;
  final String manuscriptId;

  const WorldFactDetailPage({
    super.key,
    required this.worldId,
    required this.manuscriptId,
  });

  @override
  ConsumerState<WorldFactDetailPage> createState() =>
      _WorldFactDetailPageState();
}

class _WorldFactDetailPageState extends ConsumerState<WorldFactDetailPage> {
  bool _loading = true;
  WorldFact? _row;
  List<CharacterAssertion> _assertions = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  WorldEditorService get _editor =>
      WorldEditorService(ref.read(appDatabaseProvider));

  Future<void> _load() async {
    final row = await WorldFactRepository(
      ref.read(appDatabaseProvider),
    ).getWorldById(widget.worldId);
    if (!mounted) return;
    if (row == null) {
      // §6-G：并发 / 异常下主题已不存在 → 轻提示并返回（对齐 character_detail_page.dart:96-102）
      _snack('该设定主题已不存在');
      Navigator.pop(context);
      return;
    }
    setState(() {
      _row = row;
      _assertions = WorldFactRepository.parseAssertions(row.assertions);
      _loading = false;
    });
  }

  /// 提炼断言落库：upsertWorld 增量合并（不覆盖既有）+ 刷新。
  Future<int> _extractAssertions(List<CharacterAssertion> extracted) async {
    final row = _row;
    if (row == null) return 0;
    await WorldFactRepository(ref.read(appDatabaseProvider)).upsertWorld(
      manuscriptId: widget.manuscriptId,
      name: row.name,
      assertions: extracted,
    );
    await _load();
    return _assertions.length;
  }

  /// 「从正文提炼断言」条（A2：正文非空才显示）。
  Widget _buildExtractBar(WorldFact row) {
    return SettingExtractBar(
      manuscriptId: widget.manuscriptId,
      entityName: row.name,
      description: row.description,
      chapterIdentity: row.firstSeenChapter,
      onExtracted: _extractAssertions,
    );
  }

  /// ＋ 追加设定（R4）：表单同款（含原文依据）→ 服务追加 → 重载。
  Future<void> _append() async {
    final row = _row;
    if (row == null) return;
    final form = await showAppendAssertionDialog(context, themeName: row.name);
    if (form == null || !mounted) return;
    final ok = await _editor.appendAssertion(
      worldId: widget.worldId,
      attribute: form.attribute,
      value: form.value,
      chapter: form.chapter,
      evidence: form.evidence,
    );
    if (!mounted) return;
    if (ok) unawaited(_load());
  }

  Future<void> _editDescription() async {
    final next = await showDescriptionEditDialog(
      context,
      initial: _row?.description ?? '',
    );
    if (next == null || !mounted) return;
    await WorldFactRepository(
      ref.read(appDatabaseProvider),
    ).updateWorldDescription(
      manuscriptId: widget.manuscriptId,
      name: _row!.name,
      description: next,
    );
    unawaited(_load());
  }

  /// 归档本主题（R5）：确认弹窗 → 软归档 → §6-F SnackBar → 返回列表。
  Future<void> _archive() async {
    final row = _row;
    if (row == null) return;
    final confirmed = await showArchiveWorldConfirmDialog(
      context,
      themeName: row.name,
      assertionCount: _assertions.length,
    );
    if (confirmed != true || !mounted) return;
    final ok = await _editor.archiveWorld(widget.worldId);
    if (!mounted || !ok) return;
    _snack('已归档「${row.name}」');
    Navigator.pop(context);
  }

  /// 恢复本主题（Q1 暂定）：软恢复 → SnackBar → 返回列表。
  Future<void> _restore() async {
    final row = _row;
    if (row == null) return;
    final ok = await _editor.restoreWorld(widget.worldId);
    if (!mounted || !ok) return;
    _snack('已恢复「${row.name}」');
    Navigator.pop(context);
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  /// 标签区块（R-019 拆分：详情页 build 临界，挂载抽方法）。
  Widget _buildTagsSection() {
    return SettingTagsSection(
      manuscriptId: widget.manuscriptId,
      kind: SettingEntityKind.world,
      entityId: widget.worldId,
    );
  }

  /// Progressions 章节演进区块（R-019 拆分：详情页 build 临界，挂载抽方法）。
  ///
  /// `N12-F3c`：世界观侧**已有身份写入方** —— `world_fact.first_seen_chapter` 在写入前
  /// 经 `identityForUserPosition` 归一到身份；断言在三个写入点带上 `chapterSortOrder`
  /// ⇒ 本区块**开始出节点**（此前两个来源都不是身份载体，故静默为空）。
  ///
  /// ⚠️ **phase 3 在本方法留下的旧注释已失效，勿据它回退**：当时写「刻意不传
  /// `firstSeenChapter`」，理由是「该列不是身份」—— 该前提已被本批写侧归一**消除**；
  /// 继续不传反而让时间轴少一个「首次出现」节点，与角色侧不对称。
  ///
  /// ★ phase 3 的**其余裁定仍然有效**：分组键必须是**严格身份载体**（不是
  /// `chapterIdentity` 那种带回退的读法）；**无身份的行跳过、不建「未知」桶** ——
  /// 位置有序视图里位序本身就是语义（`DECISIONS §4-33`）。
  Widget _buildProgressionsSection(Map<int, int> chapterNoMap) {
    return SettingProgressionsSection(
      assertions: _assertions,
      firstSeenChapter: _row?.firstSeenChapter,
      chapterNoMap: chapterNoMap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final row = _row;
    // `N12-F3c`：本页三处章标（头部卡 / 断言瓦片 / 时间轴）都只吃**身份载体** ⇒
    // 映射算一次、下传三处（每处各 watch 一次会重复订阅同一个 provider）。
    final chapterNoMap = buildChapterNoMap(
      ref.watch(chapterListProvider(widget.manuscriptId)),
    );
    return Scaffold(
      backgroundColor: context.palette.background,
      appBar: AppBar(title: Text(row?.name ?? '设定主题')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _buildContent(row!, chapterNoMap),
    );
  }

  /// 详情页正文（R-019 真分解：由 `build` 抽出，`N12-F3c` 起同时下传章号映射）。
  Widget _buildContent(WorldFact row, Map<int, int> chapterNoMap) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.page),
      children: [
        _WorldHeaderCard(
          firstSeenChapter: row.firstSeenChapter,
          chapterNoMap: chapterNoMap,
          assertionCount: _assertions.length,
          onAppend: _append,
        ),
        SettingDescriptionCard(
          description: row.description,
          onEdit: _editDescription,
        ),
        _buildExtractBar(row),
        _bodyChangedHint(),
        ..._assertionWidgets(chapterNoMap),
        _buildProgressionsSection(chapterNoMap),
        _buildTagsSection(),
        SettingLinksSection(
          manuscriptId: widget.manuscriptId,
          kind: SettingEntityKind.world,
          entityId: widget.worldId,
          onJump: (kind, id) {
            if (kind == SettingEntityKind.character) {
              context.push(
                AppRoutes.characterDetail,
                extra: {'manuscriptId': widget.manuscriptId, 'id': id},
              );
            }
          },
        ),
        _WorldArchiveAction(
          archived: row.status != 'active',
          onArchive: _archive,
          onRestore: _restore,
        ),
      ],
    );
  }

  /// 断言区块（R-019 真分解：由 build 抽出）；空主题 → 「暂无设定」。
  List<Widget> _assertionWidgets(Map<int, int> chapterNoMap) {
    if (_assertions.isEmpty) {
      return [
        Padding(
          padding: EdgeInsets.all(AppSpacing.lg),
          child: Text('暂无设定', style: context.text.body),
        ),
      ];
    }
    final row = _row;
    return [
      for (final a in _assertions)
        _WorldAssertionTile(
          assertion: a,
          chapterNoMap: chapterNoMap,
          // A4：pending 断言才有「确认/拒绝」入口（用户裁决，不代写）。
          // confirmed/rejected/superseded 态不传回调 ⇒ 瓦片保持只读。
          onConfirm: a.status == 'pending' && row != null
              ? () => _confirmWorldAssertion(a)
              : null,
          onReject: a.status == 'pending' && row != null
              ? () => _rejectWorldAssertion(a)
              : null,
        ),
    ];
  }

  /// C10：正文/断言联动轻提示（零 DB 写）。
  ///
  /// 行 `updatedAt` 晚于本主题**所有**断言的时间戳 ⇒ 正文很可能在最近一次提炼
  /// 之后又被改过，旁挂一条「建议重新提炼」提示。纯展示，不改断言 / 不写库。
  Widget _bodyChangedHint() {
    final row = _row;
    if (row == null || _assertions.isEmpty) return const SizedBox.shrink();
    var maxTs = 0;
    for (final a in _assertions) {
      if (a.timestamp > maxTs) maxTs = a.timestamp;
    }
    if (row.updatedAt <= maxTs) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Text('正文有改动，建议重新提炼设定', style: context.text.caption),
    );
  }

  /// A4：确认一条 pending 世界观断言 → confirmed（接既有 SettingLibraryService）。
  Future<void> _confirmWorldAssertion(CharacterAssertion a) async {
    final row = _row;
    if (row == null) return;
    await ref
        .read(settingLibraryServiceProvider)
        .confirmWorld(
          manuscriptId: widget.manuscriptId,
          name: row.name,
          attribute: a.attribute,
          value: a.value,
          target: a,
        );
    if (!mounted) return;
    unawaited(_load());
  }

  /// A4：拒绝一条 pending 世界观断言 → rejected（拒绝记忆本体）。
  Future<void> _rejectWorldAssertion(CharacterAssertion a) async {
    final row = _row;
    if (row == null) return;
    await ref
        .read(settingLibraryServiceProvider)
        .rejectWorld(
          manuscriptId: widget.manuscriptId,
          name: row.name,
          attribute: a.attribute,
          value: a.value,
          target: a,
        );
    if (!mounted) return;
    unawaited(_load());
  }
}

/// 头部卡：首见章节文案 + 断言计数 + 「＋ 追加设定」（R4 入口）。
class _WorldHeaderCard extends StatelessWidget {
  final int? firstSeenChapter;

  /// 章号映射（`sortOrder → 展示序位`）。`N12-F3c`：`firstSeenChapter` 是**身份**，
  /// 必须经它解析才能显示成用户认得的「第N章」。
  final Map<int, int> chapterNoMap;
  final int assertionCount;
  final VoidCallback onAppend;

  const _WorldHeaderCard({
    required this.firstSeenChapter,
    required this.chapterNoMap,
    required this.assertionCount,
    required this.onAppend,
  });

  @override
  Widget build(BuildContext context) {
    // 只吃身份载体；解析不出 ⇒ 「未知」，不编造数字（`ADR-C95` 裁定 2）。
    final label = chapterLabel(chapterNoMap, firstSeenChapter);
    final firstSeen = label == null ? '首次提出章节未知' : '$label首次提出';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$firstSeen · 共 $assertionCount 条设定',
              style: context.text.caption,
            ),
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: onAppend,
                child: const Text('＋ 追加设定'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 单条断言：属性 / 取值 / 章节 / 是否有依据。
/// pending 态（A4）在瓦片底部给出「确认 / 拒绝」按钮 —— 这是**用户对 AI 抽取的裁决入口**，
/// 不是系统改写或代写（R-009）；其余态（confirmed/rejected/superseded）保持只读。
class _WorldAssertionTile extends StatelessWidget {
  final CharacterAssertion assertion;

  /// 章号映射（`sortOrder → 展示序位`）。`N12-F3c` 起章标**只吃身份载体**。
  final Map<int, int> chapterNoMap;

  /// A4：pending 断言的确认 / 拒绝回调；非 pending 态为 null（瓦片只读）。
  final VoidCallback? onConfirm;
  final VoidCallback? onReject;

  const _WorldAssertionTile({
    required this.assertion,
    required this.chapterNoMap,
    this.onConfirm,
    this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    // ★ 读 `chapterSortOrder`（**身份载体**），**不是** `assertion.chapter` ——
    // 后者装的是**用户原写的数**（R1′ 不覆盖），一列多源、读时无法分辨；
    // 直出它等于把「用户写的序位」当身份再解析一遍，在有删除 / 重排的稿上
    // 会渲染成**另一章**（`DECISIONS §4-35` / `ADR-C96 §3` 反例）。
    // 无身份 ⇒ 「章节未知」：本视图**逐条陈列**，位置不承载语义，故保留条目并标注
    // 未知是对的（与位置有序的时间轴不同，见 `DECISIONS §4-33`）。
    final chapterText =
        chapterLabel(chapterNoMap, assertion.chapterSortOrder) ?? '章节未知';
    final hasEvidence = (assertion.evidence ?? '').isNotEmpty;
    final pending = assertion.status == 'pending';
    return Card(
      child: Column(
        children: [
          ListTile(
            title: Text(
              '${assertion.attribute}：${assertion.value}',
              style: context.text.title,
            ),
            subtitle: Text(
              '$chapterText · ${hasEvidence ? '✓ 有依据' : '— 无依据'}',
              style: context.text.caption,
            ),
          ),
          if (pending) _buildPendingActions(context),
        ],
      ),
    );
  }

  /// pending 断言的「拒绝 / 确认」裁决行（A4；R-009：用户裁决入口，非代写）。
  Widget _buildPendingActions(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          Text('待你确认', style: context.text.caption),
          const Spacer(),
          TextButton(
            onPressed: onReject,
            style: TextButton.styleFrom(
              foregroundColor: context.palette.danger,
            ),
            child: const Text('拒绝'),
          ),
          const SizedBox(width: AppSpacing.sm),
          FilledButton(onPressed: onConfirm, child: const Text('确认')),
        ],
      ),
    );
  }
}

/// 归档 / 恢复动作（R5 / Q1）：中性动词，无「删除」字样（O-1）。
class _WorldArchiveAction extends StatelessWidget {
  final bool archived;
  final VoidCallback onArchive;
  final VoidCallback onRestore;

  const _WorldArchiveAction({
    required this.archived,
    required this.onArchive,
    required this.onRestore,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg),
      child: archived
          ? OutlinedButton(onPressed: onRestore, child: const Text('恢复本主题'))
          : OutlinedButton(
              onPressed: onArchive,
              style: OutlinedButton.styleFrom(
                foregroundColor: context.palette.danger,
              ),
              child: const Text('归档本主题'),
            ),
    );
  }
}
