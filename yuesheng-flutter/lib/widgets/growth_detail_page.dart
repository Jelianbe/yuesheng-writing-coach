// ─────────────────────────────────────────────────────────────
// GrowthDetailPage — 成长详情页（用户级能力画像详情）
//
// 视觉规范（月色竹青，对齐 GrowthPage）：
//   AppBar       #F7F8F6 + 48dp + 深字 #2D3142
//   Scaffold 背景 #F7F8F6
//   卡片         #F2F4F2 + 左侧 4dp 竹青色条
//   时间线       左侧 2dp 竹青竖线 + 8dp 圆点
//
// 布局：
//   1. 能力画像卡片：ProficiencyRing + 认知风格 + 总会话数
//   2. 症候分布列表：按教学状态分组（练习中/待诊断/巩固中/已掌握，批次 48 对齐 RN）
//   3. 诊断历史时间线：按 timestamp DESC
//
// 空状态：暂无诊断数据（图标 + 文本）
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../config/app_theme.dart';
import 'yue_sheet.dart';
import '../data/database/database.dart';
import '../data/repositories/diagnosis_repository.dart';
import '../data/repositories/session_repository.dart';
import '../providers/app_providers.dart';
import '../providers/growth_providers.dart';
import '../router/app_routes.dart';
import '../services/growth_service.dart';
import '../services/progress_service.dart';
import '../types/teaching_types.dart';
import 'ability_chart.dart';
import 'growth_overview_card.dart';
import 'proficiency_ring.dart';
import 'syndrome_history_list.dart';
import 'teaching_state_badge.dart';
import 'writing_curve_chart.dart';
part 'growth_nav.dart';
part 'growth_content.dart';

/// 成长详情页
class GrowthDetailPage extends ConsumerStatefulWidget {
  const GrowthDetailPage({super.key});

  @override
  ConsumerState<GrowthDetailPage> createState() => _GrowthDetailPageState();
}

class _GrowthDetailPageState extends ConsumerState<GrowthDetailPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(growthStoreProvider.notifier).loadGrowthData();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(growthStoreProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('能力画像'),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        toolbarHeight: 48,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, size: 22),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/growth'),
          tooltip: '返回',
        ),
      ),
      body: state.isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : state.error != null
          ? _ErrorView(
              error: state.error!,
              onRetry: () =>
                  ref.read(growthStoreProvider.notifier).loadGrowthData(),
            )
          : _buildContent(state),
    );
  }

  // 批次53c：写作风格五维中文标签见顶层函数 _sensoryLabel 等（批次57 提升为
  // 模块级，供 State 与 _StyleCorrectionSheet 复用）
}

// ─────────────────────────────────────────────────────────────
// 内部组件
// ─────────────────────────────────────────────────────────────

/// 批次53c：写作风格五维中文标签（对齐 writing-style.ts 五维坐标）
String _sensoryLabel(SensoryPreference v) {
  switch (v) {
    case SensoryPreference.visual:
      return '视觉型';
    case SensoryPreference.auditory:
      return '听觉型';
    case SensoryPreference.kinesthetic:
      return '体感型';
    case SensoryPreference.balanced:
      return '均衡型';
  }
}

String _rhythmLabel(RhythmPreference v) {
  switch (v) {
    case RhythmPreference.long:
      return '长句型';
    case RhythmPreference.short:
      return '短句型';
    case RhythmPreference.alternating:
      return '错落型';
    case RhythmPreference.repetitive:
      return '重复型';
  }
}

String _narrativeLabel(NarrativeDistance v) {
  switch (v) {
    case NarrativeDistance.intimate:
      return '贴身型';
    case NarrativeDistance.observational:
      return '观察型';
    case NarrativeDistance.editorial:
      return '评述型';
    case NarrativeDistance.fluid:
      return '游移型';
  }
}

String _toneLabel(ToneTexture v) {
  switch (v) {
    case ToneTexture.poetic:
      return '诗意型';
    case ToneTexture.spare:
      return '冷峻型';
    case ToneTexture.colloquial:
      return '口语型';
    case ToneTexture.elegant:
      return '文雅型';
  }
}

String _structureLabel(StructureInstinct v) {
  switch (v) {
    case StructureInstinct.linear:
      return '线性型';
    case StructureInstinct.fragmented:
      return '碎片型';
    case StructureInstinct.circular:
      return '回环型';
    case StructureInstinct.divergent:
      return '发散型';
  }
}

/// 批次57：风格纠正底部弹层（纠错非重写——仅纠正五维坐标，summary 保留 AI 描述只读）
class _StyleCorrectionSheet extends StatefulWidget {
  final WritingStyleProfile profile;
  final Future<void> Function(WritingStyleProfile updated) onSave;

  const _StyleCorrectionSheet({required this.profile, required this.onSave});

  @override
  State<_StyleCorrectionSheet> createState() => _StyleCorrectionSheetState();
}

class _StyleCorrectionSheetState extends State<_StyleCorrectionSheet> {
  late SensoryPreference _sensory;
  late RhythmPreference _rhythm;
  late NarrativeDistance _narrative;
  late ToneTexture _tone;
  late StructureInstinct _structure;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final p = widget.profile;
    _sensory = p.sensory;
    _rhythm = p.rhythm;
    _narrative = p.narrativeDistance;
    _tone = p.toneTexture;
    _structure = p.structure;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.onSave(
        WritingStyleProfile(
          sensory: _sensory,
          rhythm: _rhythm,
          narrativeDistance: _narrative,
          toneTexture: _tone,
          structure: _structure,
          summary: widget.profile.summary,
          confidence: widget.profile.confidence,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _dimensionRow<T>({
    required String title,
    required List<T> options,
    required T selected,
    required String Function(T) label,
    required ValueChanged<T> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final opt in options)
              ChoiceChip(
                label: Text(label(opt)),
                selected: opt == selected,
                onSelected: (_) => onChanged(opt),
                selectedColor: AppColors.primary,
                backgroundColor: AppColors.surface,
                side: BorderSide(color: AppColors.border),
                labelStyle: TextStyle(
                  fontSize: 12,
                  color: opt == selected
                      ? AppColors.onPrimary
                      : AppColors.textPrimary,
                ),
              ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.section,
            AppSpacing.lg,
            AppSpacing.section,
            AppSpacing.xl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '纠正风格画像',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '风格由 AI 从你的文本自动识别。如判断有误，可在此纠正坐标；'
                '下次诊断仍会按你的新文本重新识别。',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'AI 描述',
                style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
              ),
              const SizedBox(height: 4),
              Text(
                widget.profile.summary,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              _dimensionRow(
                title: '感官偏好',
                options: SensoryPreference.values,
                selected: _sensory,
                label: _sensoryLabel,
                onChanged: (v) => setState(() => _sensory = v),
              ),
              const SizedBox(height: 12),
              _dimensionRow(
                title: '节奏偏好',
                options: RhythmPreference.values,
                selected: _rhythm,
                label: _rhythmLabel,
                onChanged: (v) => setState(() => _rhythm = v),
              ),
              const SizedBox(height: 12),
              _dimensionRow(
                title: '叙事距离',
                options: NarrativeDistance.values,
                selected: _narrative,
                label: _narrativeLabel,
                onChanged: (v) => setState(() => _narrative = v),
              ),
              const SizedBox(height: 12),
              _dimensionRow(
                title: '语气质地',
                options: ToneTexture.values,
                selected: _tone,
                label: _toneLabel,
                onChanged: (v) => setState(() => _tone = v),
              ),
              const SizedBox(height: 12),
              _dimensionRow(
                title: '结构本能',
                options: StructureInstinct.values,
                selected: _structure,
                label: _structureLabel,
                onChanged: (v) => setState(() => _structure = v),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.md,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                  ),
                  child: Text(_saving ? '保存中…' : '保存纠正'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 写作总览六格网格（批次 51c，对齐 RN growth-detail overviewGrid：
/// 写作天数 / 当前阶段 / 已解决 / 待改进 + 首次/最近写作整宽两格）
class _OverviewGrid extends StatelessWidget {
  final GrowthOverview overview;

  const _OverviewGrid({required this.overview});

  String _phaseLabel(TeachingPhase phase) {
    return progressPhaseLabels[phase] ?? phase.value;
  }

  String _formatDate(int? ts) {
    if (ts == null) return '暂无';
    final d = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
    return '${d.month}月${d.day}日';
  }

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '写作总览',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _GridItem(
                    value: '${overview.writingDays}',
                    label: '写作天数',
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _GridItem(
                    value: _phaseLabel(overview.currentPhase),
                    label: '当前阶段',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _GridItem(
                    value: '${overview.totalResolved}',
                    label: '已解决',
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _GridItem(
                    value: '${overview.totalActive}',
                    label: '待改进',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _GridItem(
              value: _formatDate(overview.firstWritingAt),
              label: '首次写作',
            ),
            const SizedBox(height: 12),
            _GridItem(
              value: _formatDate(overview.lastWritingAt),
              label: '最近写作',
            ),
          ],
        ),
      ),
    );
  }
}

class _GridItem extends StatelessWidget {
  final String value;
  final String label;

  const _GridItem({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: AppColors.textTertiary),
        ),
      ],
    );
  }
}

/// 查看学习进度详情链接（批次 51c，对齐 RN growth-detail progressLink）
class _ProgressLink extends StatelessWidget {
  final VoidCallback onTap;

  const _ProgressLink({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primarySoft,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: 14,
          ),
          child: const Row(
            children: [
              Expanded(
                child: Text(
                  '查看学习进度详情',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
              ),
              Text(
                '›',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 通用卡片（左侧 4dp 竹青色条，与 GrowthPage._Card 一致）
class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.border),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4, color: AppColors.primary),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

/// 批次65（B62h）：单条症候复发率行（症候名 + 出现/好转/再犯 + 复发率%）
class _RecurrenceRow extends StatelessWidget {
  final SyndromeRecurrence recurrence;
  const _RecurrenceRow({required this.recurrence});

  @override
  Widget build(BuildContext context) {
    final rate = (recurrence.rate * 100).round();
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                recurrence.syndromeName,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '出现 ${recurrence.occurrences} 次 · 好转 ${recurrence.recovered} 次 · '
                '再犯 ${recurrence.recurrences} 次',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textTertiary,
                ),
              ),
            ],
          ),
        ),
        Text(
          '$rate%',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: rate >= 50 ? AppColors.danger : AppColors.primary,
          ),
        ),
      ],
    );
  }
}

class _SeverityChip extends StatelessWidget {
  final String severity;
  const _SeverityChip({required this.severity});

  @override
  Widget build(BuildContext context) {
    final color = switch (severity) {
      'L1' => AppColors.l1,
      'L2' => AppColors.l2,
      'L3' => AppColors.l3,
      _ => AppColors.border,
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Text(
        severity,
        style: const TextStyle(fontSize: 11, color: AppColors.textPrimary),
      ),
    );
  }
}

class _Timeline extends StatelessWidget {
  final List<DiagnosisRow> items;
  const _Timeline({required this.items});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < items.length; i++) ...[
          _TimelineItem(item: items[i], isLast: i == items.length - 1),
          if (i < items.length - 1) const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _TimelineItem extends StatelessWidget {
  final DiagnosisRow item;
  final bool isLast;
  const _TimelineItem({required this.item, required this.isLast});

  @override
  Widget build(BuildContext context) {
    // timestamp 是秒级 Unix 时间戳
    final dt = DateTime.fromMillisecondsSinceEpoch(item.timestamp * 1000);
    final dateStr =
        '${dt.month}-${dt.day} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 左侧竖线 + 圆点
          SizedBox(
            width: 16,
            child: Column(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(width: 2, color: AppColors.primary),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // 右侧内容
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      dateStr,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '置信度 ${(item.confidence * 100).round()}%',
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
                // E3：展示本次诊断出的症候名（从 syndromes JSON 解析），
                // 让时间线不再是"只有时间+置信度"的空壳信息
                ..._buildSyndromeNames(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 从 DiagnosisRow.syndromes JSON 解析症候名（最多 3 个，超过显示 +N）
  List<Widget> _buildSyndromeNames() {
    try {
      final list = jsonDecode(item.syndromes) as List<dynamic>;
      final names = <String>[];
      for (final s in list) {
        final name = (s as Map<String, dynamic>)['name'] as String?;
        if (name != null && name.isNotEmpty) names.add(name);
        if (names.length >= 3) break;
      }
      if (names.isEmpty) return const [];
      final total = (list.length).clamp(3, list.length);
      final display = names.join(' · ');
      final suffix = total > 3 ? ' · +${total - 3}' : '';
      return [
        const SizedBox(height: 4),
        Text(
          display + suffix,
          style: const TextStyle(
            fontSize: 12,
            height: 1.4,
            color: AppColors.textDeep,
          ),
        ),
      ];
    } catch (_) {
      return const [];
    }
  }
}

class _ErrorView extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _ErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 32, color: AppColors.danger),
            const SizedBox(height: 8),
            const Text(
              '加载失败',
              style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onRetry,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.section,
                  vertical: AppSpacing.smx,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
              ),
              child: const Text('重新加载'),
            ),
          ],
        ),
      ),
    );
  }
}
