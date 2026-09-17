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

import '../setting/setting_description_card.dart';
import '../setting/setting_extract_bar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/app_theme.dart';
import '../../data/database/database.dart';
import '../../data/repositories/world_fact_repository.dart';
import '../../providers/app_providers.dart';
import '../../router/app_routes.dart';
import '../../services/world_editor_service.dart';
import '../../types/character_types.dart';
import '../../data/repositories/setting_link_repository.dart';
import '../setting/setting_links_section.dart';
import '../setting/setting_progressions_section.dart';
import '../setting/setting_tags_section.dart';
import 'world_dialogs.dart';

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
      chapter: row.firstSeenChapter,
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
  Widget _buildProgressionsSection() {
    return SettingProgressionsSection(
      assertions: _assertions,
      firstSeenChapter: _row?.firstSeenChapter,
    );
  }

  @override
  Widget build(BuildContext context) {
    final row = _row;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(row?.name ?? '设定主题')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.page),
              children: [
                _WorldHeaderCard(
                  firstSeenChapter: row!.firstSeenChapter,
                  assertionCount: _assertions.length,
                  onAppend: _append,
                ),
                SettingDescriptionCard(
                  description: row.description,
                  onEdit: _editDescription,
                ),
                _buildExtractBar(row),
                ..._assertionWidgets(),
                _buildProgressionsSection(),
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
            ),
    );
  }

  /// 断言区块（R-019 真分解：由 build 抽出）；空主题 → 「暂无设定」。
  List<Widget> _assertionWidgets() {
    if (_assertions.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.all(AppSpacing.section),
          child: Text('暂无设定', style: AppTextStyles.body),
        ),
      ];
    }
    return [for (final a in _assertions) _WorldAssertionTile(assertion: a)];
  }
}

/// 头部卡：首见章节文案 + 断言计数 + 「＋ 追加设定」（R4 入口）。
class _WorldHeaderCard extends StatelessWidget {
  final int? firstSeenChapter;
  final int assertionCount;
  final VoidCallback onAppend;

  const _WorldHeaderCard({
    required this.firstSeenChapter,
    required this.assertionCount,
    required this.onAppend,
  });

  @override
  Widget build(BuildContext context) {
    final ch = firstSeenChapter;
    final firstSeen = ch == null ? '首次提出章节未知' : '第$ch章首次提出';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$firstSeen · 共 $assertionCount 条设定',
              style: AppTextStyles.caption,
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

/// 单条断言（只读，R3）：属性 / 取值 / 章节 / 是否有依据。
/// 本批**无**改写 / 删除按钮（O-2）。
class _WorldAssertionTile extends StatelessWidget {
  final CharacterAssertion assertion;

  const _WorldAssertionTile({required this.assertion});

  @override
  Widget build(BuildContext context) {
    final ch = assertion.chapter;
    final chapterText = ch == null ? '章节未知' : '第$ch章';
    final hasEvidence = (assertion.evidence ?? '').isNotEmpty;
    return Card(
      child: ListTile(
        title: Text(
          '${assertion.attribute}：${assertion.value}',
          style: AppTextStyles.titleMd,
        ),
        subtitle: Text(
          '$chapterText · ${hasEvidence ? '✓ 有依据' : '— 无依据'}',
          style: AppTextStyles.caption,
        ),
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
                foregroundColor: AppColors.danger,
              ),
              child: const Text('归档本主题'),
            ),
    );
  }
}
