// ─────────────────────────────────────────────────────────────
// CharacterDetailSections — 角色详情页的展示型区块（C78 批次3）
//
// 全部为无状态纯展示组件：数据与回调由详情页传入，不持有数据库访问。
// 拆分理由（真分解）：详情页的状态/加载/动作与本文件的渲染职责分离，
// 双方各自守住 R-019 函数 ≤50 行 / 文件 ≤300 行硬上限。
//
// F05 文案在此自渲染（attribute：第X章「A」→ 第Y章「B」），绝不复用
// ConflictObservation.description——那是 chat_context_builder 的 AI 注入
// 措辞，prompt 一改 UI 文案会跟着变（ADR-C78 §6 措辞分家）。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../../config/app_theme.dart';
import '../../services/conflict_detector.dart';
import '../../types/character_types.dart';
import 'character_assertion_tile.dart';

/// 头部卡：名字 + 并入主角色入口 + 别名行 + 元信息
class CharacterHeaderCard extends StatelessWidget {
  final String name;
  final List<String> aliases;
  final int assertionCount;
  final int? firstSeenChapter;
  final bool mergeEnabled;
  final VoidCallback onMerge;
  final VoidCallback onEditAliases;

  const CharacterHeaderCard({
    super.key,
    required this.name,
    required this.aliases,
    required this.assertionCount,
    required this.firstSeenChapter,
    required this.mergeEnabled,
    required this.onMerge,
    required this.onEditAliases,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(name, style: AppTextStyles.titleLg)),
                TextButton.icon(
                  onPressed: mergeEnabled ? onMerge : null,
                  icon: const Icon(Icons.merge, size: 16),
                  label: const Text('并入主角色'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xsm),
            _buildAliasRow(),
            const SizedBox(height: AppSpacing.xsm),
            Text(
              '首次登场：${firstSeenChapter == null ? '未知' : '第$firstSeenChapter章'}'
              ' · 断言 $assertionCount 条',
              style: AppTextStyles.caption,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAliasRow() {
    return Wrap(
      spacing: AppSpacing.xsm,
      runSpacing: AppSpacing.xsm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Text('别名', style: AppTextStyles.caption),
        if (aliases.isEmpty)
          const Text('暂无', style: AppTextStyles.caption)
        else
          for (final alias in aliases)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xsm,
                vertical: AppSpacing.xxs,
              ),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.xs),
              ),
              child: Text(alias, style: AppTextStyles.noteCaption),
            ),
        GestureDetector(
          onTap: onEditAliases,
          child: const Text(
            '编辑+',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

/// FR-10 最近批次横幅：如实标注「按落库时间过滤」
class CharacterRecentBanner extends StatelessWidget {
  final int visibleCount;
  final VoidCallback onShowAll;

  const CharacterRecentBanner({
    super.key,
    required this.visibleCount,
    required this.onShowAll,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.sm),
      width: double.infinity,
      color: AppColors.primarySoft,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '正在查看最近批次沉淀（$visibleCount 条，按落库时间过滤）',
              style: AppTextStyles.noteCaption.copyWith(
                color: AppColors.l1Text,
              ),
            ),
          ),
          GestureDetector(
            onTap: onShowAll,
            child: const Text(
              '查看全部',
              style: TextStyle(fontSize: 12, color: AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }
}

/// F05 时序矛盾卡：判据同源（detectConflictsForFacts），文案自渲染
class CharacterConflictsCard extends StatelessWidget {
  final List<ConflictObservation> conflicts;

  const CharacterConflictsCard({super.key, required this.conflicts});

  @override
  Widget build(BuildContext context) {
    if (conflicts.isEmpty) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.only(top: AppSpacing.md),
      color: AppColors.warningBg,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '⚠ 时序矛盾（${conflicts.length}）',
              style: AppTextStyles.titleMd.copyWith(color: AppColors.warning),
            ),
            const SizedBox(height: AppSpacing.xsm),
            for (final o in conflicts)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
                child: Text(
                  _conflictText(o),
                  style: AppTextStyles.noteCaption.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _conflictText(ConflictObservation o) {
    final parts = [
      for (final a in o.orderedValues) '第${a.chapter ?? '?'}章「${a.value}」',
    ];
    return '${o.attribute}：${parts.join(' → ')}';
  }
}

/// FR-9 一键清除本章旧版断言（章号 → stale 条数）
class CharacterStaleClearBar extends StatelessWidget {
  final Map<int, int> staleByChapter;
  final ValueChanged<int> onClear;

  const CharacterStaleClearBar({
    super.key,
    required this.staleByChapter,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    if (staleByChapter.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Wrap(
        spacing: AppSpacing.sm,
        children: [
          for (final entry in staleByChapter.entries)
            OutlinedButton.icon(
              onPressed: () => onClear(entry.key),
              icon: const Icon(Icons.auto_delete_outlined, size: 16),
              label: Text('清除第${entry.key}章旧版断言 (${entry.value})'),
            ),
        ],
      ),
    );
  }
}

/// 断言按属性分组卡（含每组的「+ 补充」入口）
class CharacterAssertionGroups extends StatelessWidget {
  final List<CharacterAssertion> assertions;
  final Future<String?> Function(CharacterAssertion) resolveOriginalText;
  final ValueChanged<CharacterAssertion> onReject;
  final ValueChanged<CharacterAssertion> onCorrect;
  final ValueChanged<String?> onSupplement;

  const CharacterAssertionGroups({
    super.key,
    required this.assertions,
    required this.resolveOriginalText,
    required this.onReject,
    required this.onCorrect,
    required this.onSupplement,
  });

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<CharacterAssertion>>{};
    for (final a in assertions) {
      groups.putIfAbsent(a.attribute, () => []).add(a);
    }
    return Card(
      margin: const EdgeInsets.only(top: AppSpacing.md),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (groups.isEmpty)
              const Text('暂无断言', style: AppTextStyles.body)
            else
              for (final entry in groups.entries)
                _buildGroup(entry.key, entry.value),
          ],
        ),
      ),
    );
  }

  Widget _buildGroup(String attribute, List<CharacterAssertion> items) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '$attribute (${items.length})',
                  style: AppTextStyles.titleMd,
                ),
              ),
              TextButton.icon(
                onPressed: () => onSupplement(attribute),
                icon: const Icon(Icons.add, size: 14),
                label: const Text('补充'),
              ),
            ],
          ),
          for (final a in items)
            CharacterAssertionTile(
              assertion: a,
              resolveOriginalText: () => resolveOriginalText(a),
              onReject: () => onReject(a),
              onCorrect: () => onCorrect(a),
            ),
        ],
      ),
    );
  }
}
