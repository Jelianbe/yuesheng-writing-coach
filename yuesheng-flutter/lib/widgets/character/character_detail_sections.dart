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
import '../../utils/chapter_number.dart';
import 'character_assertion_tile.dart';
import '../../theme/app_typography.dart';

/// 头部卡：名字 + 并入主角色入口 + 别名行 + 元信息
class CharacterHeaderCard extends StatelessWidget {
  final String name;
  final List<String> aliases;
  final int assertionCount;

  /// `character_fact.first_seen_chapter` —— **身份键**（`chapter.sortOrder`），
  /// 不是展示号；必须经 [chapterNoMap] 解析（ADR-C95 裁定 4 / `N12-F3a`）。
  final int? firstSeenChapter;

  /// `sortOrder → 展示章号(1 基)`（[buildChapterNoMap] 产出）。
  final Map<int, int> chapterNoMap;
  final bool mergeEnabled;
  final VoidCallback onMerge;
  final VoidCallback onEditAliases;

  const CharacterHeaderCard({
    super.key,
    required this.name,
    required this.aliases,
    required this.assertionCount,
    required this.firstSeenChapter,
    required this.chapterNoMap,
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
                Expanded(child: Text(name, style: context.text.titleLg)),
                TextButton.icon(
                  onPressed: mergeEnabled ? onMerge : null,
                  icon: const Icon(Icons.merge, size: 16),
                  label: const Text('并入主角色'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xsm),
            _buildAliasRow(context),
            const SizedBox(height: AppSpacing.xsm),
            Text(
              '首次登场：${chapterLabel(chapterNoMap, firstSeenChapter) ?? '未知'}'
              ' · 断言 $assertionCount 条',
              style: context.text.caption,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAliasRow(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.xsm,
      runSpacing: AppSpacing.xsm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('别名', style: context.text.caption),
        if (aliases.isEmpty)
          Text('暂无', style: context.text.caption)
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
              child: Text(alias, style: context.text.noteCaption),
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
              style: context.text.noteCaption.copyWith(color: AppColors.l1Text),
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

  /// `sortOrder → 展示章号(1 基)`（`N12-F3b` phase 2：章标只吃身份载体）。
  final Map<int, int> chapterNoMap;

  const CharacterConflictsCard({
    super.key,
    required this.conflicts,
    required this.chapterNoMap,
  });

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
              style: context.text.titleMd.copyWith(color: AppColors.warning),
            ),
            const SizedBox(height: AppSpacing.xsm),
            for (final o in conflicts)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
                child: Text(
                  _conflictText(o),
                  style: context.text.noteCaption.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// `N12-F3b` phase 2：章标**只吃身份载体**（`a.chapterSortOrder`，经 map 解析）。
  /// 无身份（存量行）⇒ 不渲染号，改说「早期」—— **不回退到 `a.chapter`**：
  /// 那一列是 AI 标称号，回退会让矛盾卡显示一个错的号（方案 `S1`）。
  String _conflictText(ConflictObservation o) {
    final parts = [for (final a in o.orderedValues) _valueWithChapter(a)];
    return '${o.attribute}：${parts.join(' → ')}';
  }

  String _valueWithChapter(CharacterAssertion a) {
    final chapter = chapterLabel(chapterNoMap, a.chapterSortOrder) ?? '早期';
    return '$chapter「${a.value}」';
  }
}

/// FR-9 一键清除本章旧版断言（章号 → stale 条数）
///
/// `N12-F3b` phase 2：`staleByChapter` 的 **key 是身份**（`chapterSortOrder` 优先），
/// 与 `FactStaleService.clearStaleChapter` → `_markAssertions` 的匹配口径
/// （`a.chapterIdentity == chapterNo`）**同源** —— 此前 key 取 `a.chapter`，
/// 新行上两者不等 ⇒ 按钮点了清 0 条（静默失效），本批一并修正。
class CharacterStaleClearBar extends StatelessWidget {
  final Map<int, int> staleByChapter;

  /// `sortOrder → 展示章号(1 基)`（`N12-F3b` phase 2：显示侧只吃身份）。
  final Map<int, int> chapterNoMap;

  final ValueChanged<int> onClear;

  const CharacterStaleClearBar({
    super.key,
    required this.staleByChapter,
    required this.chapterNoMap,
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
              label: Text(_label(entry.key, entry.value)),
            ),
        ],
      ),
    );
  }

  /// 无章标（无身份 / 该章已删）⇒ 只说数量，**不编造一个数字**。
  String _label(int identity, int count) {
    final chapter = chapterLabel(chapterNoMap, identity);
    return chapter == null ? '清除旧版断言 ($count)' : '清除$chapter旧版断言 ($count)';
  }
}

/// 断言按属性分组卡（含每组的「+ 补充」入口）
class CharacterAssertionGroups extends StatelessWidget {
  final List<CharacterAssertion> assertions;

  /// `sortOrder → 展示章号(1 基)`（`N12-F3b` phase 2：下传给每条断言瓦片）。
  final Map<int, int> chapterNoMap;

  final Future<String?> Function(CharacterAssertion) resolveOriginalText;
  final ValueChanged<CharacterAssertion> onReject;
  final ValueChanged<CharacterAssertion> onCorrect;
  final ValueChanged<String?> onSupplement;

  const CharacterAssertionGroups({
    super.key,
    required this.assertions,
    required this.chapterNoMap,
    required this.resolveOriginalText,
    required this.onReject,
    required this.onCorrect,
    required this.onSupplement,
    this.onToggleNegative,
  });

  /// 负断言开关（仅 rejected 断言显示；null = 不显示开关）
  final void Function(CharacterAssertion assertion, bool value)?
  onToggleNegative;

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
              Text('暂无断言', style: context.text.body)
            else
              for (final entry in groups.entries)
                _buildGroup(context, entry.key, entry.value),
          ],
        ),
      ),
    );
  }

  Widget _buildGroup(
    BuildContext context,
    String attribute,
    List<CharacterAssertion> items,
  ) {
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
                  style: context.text.titleMd,
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
              chapterNoMap: chapterNoMap,
              resolveOriginalText: () => resolveOriginalText(a),
              onReject: () => onReject(a),
              onCorrect: () => onCorrect(a),
              onToggleNegative: onToggleNegative == null
                  ? null
                  : (v) => onToggleNegative!(a, v),
            ),
        ],
      ),
    );
  }
}
