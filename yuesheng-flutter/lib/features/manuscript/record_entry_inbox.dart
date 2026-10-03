// ─────────────────────────────────────────────────────────────
// RecordEntryInbox — 记录条目收件箱（C147 · 资料库 tab 待整理/已留档）
//
// 数据来源：record_entry 表（ADR-C143 v44）。本组件是「记一下 / 存入设定库」
// 的**作者裁决界面**：
//   - pending 区：作者确认 → kept / 拒绝 → rejected / 编辑摘录。
//   - kept 区：已留档摘录（只读展示）。
//
// R-009（写死）：裁决权全在作者——AI 只提议（proposePending），本组件只做
// 作者的确认/拒绝/编辑动作，不替作者定性、不打分、不处方。
// R-027：纯本地 DB 读写 UI，零 prompt/注入。
//
// 空态（pending 与 kept 均空）→ 返回 SizedBox.shrink()，不占位，
// 既有「角色/大纲/世界观/其他」四段结构零破坏。
// ─────────────────────────────────────────────────────────────

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/app_palette.dart';
import '../../config/app_theme.dart';
import '../../data/database/database.dart';
import '../../data/repositories/record_entry_repository.dart';
import '../../providers/app_providers.dart';
import '../../theme/app_typography.dart';
import 'remember_entry_sheet.dart';

class RecordEntryInbox extends ConsumerStatefulWidget {
  final String manuscriptId;

  const RecordEntryInbox({super.key, required this.manuscriptId});

  @override
  ConsumerState<RecordEntryInbox> createState() => _RecordEntryInboxState();
}

class _RecordEntryInboxState extends ConsumerState<RecordEntryInbox> {
  List<RecordEntry> _pending = [];
  List<RecordEntry> _kept = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  RecordEntryRepository get _repo =>
      RecordEntryRepository(ref.read(appDatabaseProvider));

  Future<void> _reload() async {
    final all = await _repo.listByManuscript(widget.manuscriptId);
    if (!mounted) return;
    setState(() {
      _pending = all
          .where((e) => e.status == RecordEntryStatus.pending)
          .toList();
      _kept = all.where((e) => e.status == RecordEntryStatus.kept).toList();
      _loading = false;
    });
  }

  Future<void> _confirm(RecordEntry e) async {
    await _repo.confirm(e.id);
    await _reload();
  }

  Future<void> _reject(RecordEntry e) async {
    await _repo.reject(e.id);
    await _reload();
  }

  Future<void> _editExcerpt(RecordEntry e) async {
    final controller = TextEditingController(text: e.excerpt);
    final saved = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('编辑摘录', style: context.text.titleLg),
        content: TextField(
          controller: controller,
          maxLines: 6,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (saved == null || saved.isEmpty) return;
    await _repo.updateExcerpt(e.id, saved);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox.shrink();
    if (_pending.isEmpty && _kept.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        AppSpacing.sm,
        AppSpacing.page,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_pending.isNotEmpty) ..._buildPendingSection(),
          if (_kept.isNotEmpty) ..._buildKeptSection(),
        ],
      ),
    );
  }

  List<Widget> _buildPendingSection() {
    return [
      Text('待整理（${_pending.length}）', style: context.text.subBody),
      const SizedBox(height: AppSpacing.xs),
      ..._pending.map(_buildPendingCard),
      const SizedBox(height: AppSpacing.sm),
    ];
  }

  Widget _buildPendingCard(RecordEntry e) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: context.palette.borderSoft, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _TargetBadge(section: e.targetSection),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 16),
                visualDensity: VisualDensity.compact,
                onPressed: () => _editExcerpt(e),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(e.excerpt, style: context.text.body),
          const SizedBox(height: AppSpacing.sm),
          _buildPendingActions(e),
        ],
      ),
    );
  }

  Widget _buildPendingActions(RecordEntry e) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
          onPressed: () => _reject(e),
          child: Text(
            '拒绝',
            style: TextStyle(color: context.palette.textSecondary),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        FilledButton(
          onPressed: () => _confirm(e),
          style: FilledButton.styleFrom(
            backgroundColor: context.palette.primary,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          ),
          child: const Text('确认留档'),
        ),
      ],
    );
  }

  List<Widget> _buildKeptSection() {
    return [
      Text('已留档（${_kept.length}）', style: context.text.subBody),
      const SizedBox(height: AppSpacing.xs),
      ..._kept.map(_buildKeptRow),
    ];
  }

  Widget _buildKeptRow(RecordEntry e) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TargetBadge(section: e.targetSection),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              e.excerpt,
              style: context.text.subBody,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// 目标位置小徽章（人设/世界观/大纲/未定）。
class _TargetBadge extends StatelessWidget {
  final String section;

  const _TargetBadge({required this.section});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: context.palette.background,
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Text(
        RememberTarget.labelOf(section),
        style: TextStyle(fontSize: 11, color: context.palette.textSecondary),
      ),
    );
  }
}
