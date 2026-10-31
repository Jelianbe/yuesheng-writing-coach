// ─────────────────────────────────────────────────────────────
// ExcludedFoldedSection — 「本轮还考虑过」默认折叠（T-20261030-02 · U1 落地）
//
// 设计说明：.ai/reports/2026-10-31-设计说明-30-02-L3折叠-excluded呈现.md
//   §2.1 默认态：一行「本轮还考虑过 N 项 ⌄」（往轮另有 M 项）
//   §2.2 展开态：内联逐条，条目样式与单轮卡片逐字一致（11px / tertiary）
//   §4   往轮：按轮分组、只分不并（不做跨轮去重），最近轮在上
//
// 教学判据：
//   3 否定语义 + 弱视觉 —— 折叠行固定含「还考虑过」；12px / textTertiary /
//     无底色 / 无边框；展开条目 11px。
//   5 过载 —— 默认只占 1 行，不把报出症候推出首屏。
//
// 数据：本轮来自 DiagnosisCard.excluded（轮次级）；往轮由卡片按
// DiagnosisRepository.excludedOf(row) 读出后传入（零新查询路径）。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../config/app_motion.dart';
import '../config/app_theme.dart';
import '../config/app_palette.dart';
import '../services/syndrome_registry.dart';
import '../theme/app_typography.dart';
import '../types/teaching_types.dart';

/// 往轮排除记录（一轮一组）。轮次号为会话内第 N 次诊断（1 起）。
class ExcludedRoundGroup {
  /// 会话内轮次序号（第 1 轮 = 该会话最早一次诊断）。
  final int roundNumber;

  /// 该轮「考虑过但未报出」条目，顺序与落库一致（不排序、不去重）。
  final List<ParsedExclusion> items;

  const ExcludedRoundGroup({required this.roundNumber, required this.items});
}

class ExcludedFoldedSection extends StatefulWidget {
  /// 本轮排除记录（轮次级）。空列表 ⇒ 本轮计数为 0。
  final List<ParsedExclusion> excluded;

  /// 往轮排除记录（已按轮分组、最近轮在上）。空列表 ⇒ 不显示往轮。
  final List<ExcludedRoundGroup> history;

  const ExcludedFoldedSection({
    super.key,
    this.excluded = const [],
    this.history = const [],
  });

  @override
  State<ExcludedFoldedSection> createState() => _ExcludedFoldedSectionState();
}

class _ExcludedFoldedSectionState extends State<ExcludedFoldedSection> {
  /// 展开态：组件本地、不持久化（滚动回收重建后回到折叠 —— 默认弱）。
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final historyCount = widget.history.fold<int>(
      0,
      (sum, group) => sum + group.items.length,
    );
    if (widget.excluded.isEmpty && historyCount == 0) {
      // 不造空区（与改造前语义一致）。
      return const SizedBox.shrink();
    }
    final body = _expanded
        ? _buildExpandedBody(context)
        : const SizedBox(width: double.infinity);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFoldedRow(context, historyCount),
          // prefers-reduced-motion：直接换子树（时长归零在 AnimatedSize 上会
          // 触发 RenderAnimatedSize 自脏断言，故不建动画组件）。
          if (MediaQuery.disableAnimationsOf(context))
            body
          else
            AnimatedSize(
              duration: AppMotion.durationStandard,
              curve: AppMotion.curveFade,
              alignment: Alignment.topCenter,
              child: body,
            ),
        ],
      ),
    );
  }

  /// 折叠行：固定「本轮还考虑过 N 项」，有往轮时续「（往轮另有 M 项）」。
  String _foldedLabel(int historyCount) {
    final base = '本轮还考虑过 ${widget.excluded.length} 项';
    return historyCount == 0 ? base : '$base（往轮另有 $historyCount 项）';
  }

  Widget _buildFoldedRow(BuildContext context, int historyCount) {
    final label = _foldedLabel(historyCount);
    return Semantics(
      button: true,
      label: '$label，${_expanded ? '收起' : '展开'}',
      child: InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        child: ConstrainedBox(
          // 触控区 ≥ 44（竖屏可达性）。
          constraints: const BoxConstraints(minHeight: 44),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: context.text.caption.copyWith(
                    color: context.palette.textTertiary,
                  ),
                ),
              ),
              Icon(
                _expanded ? Icons.expand_less : Icons.expand_more,
                size: 12,
                color: context.palette.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 展开体：本轮逐条 → 往轮分组（最近轮在上），只分不并。
  Widget _buildExpandedBody(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xxs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...widget.excluded.map(_buildItem),
          for (final group in widget.history) ...[
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                '第 ${group.roundNumber} 轮 · ${group.items.length} 项',
                style: context.text.caption.copyWith(
                  color: context.palette.textTertiary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ...group.items.map(_buildItem),
          ],
        ],
      ),
    );
  }

  /// 单条：`· 名称：理由`（与改造前逐字一致；reason 空则不展示理由）。
  Widget _buildItem(ParsedExclusion e) {
    final name = syndromeNameOf(e.syndromeId) ?? e.syndromeId;
    final reason = e.reason.trim();
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xxs),
      child: Text(
        reason.isEmpty ? '· $name' : '· $name：$reason',
        style: context.text.caption.copyWith(
          color: context.palette.textTertiary,
          fontSize: 11,
          height: 1.4,
        ),
      ),
    );
  }
}
