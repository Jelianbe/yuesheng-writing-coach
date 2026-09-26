// ─────────────────────────────────────────────────────────────
// ObservationAuditCard — Editor 观察记录审计卡片（成长页）
//
// 复刻 yuesheng-android/src/components/profile/ObservationAuditCard.tsx
// 展示 Editor 对学员写作的叙事层观察记录统计：
//   - 总数 / 教练触发数 / 触发率
//   - 最近 N 条 observation 摘要（默认 5）
//
// 视觉（月色竹青）：
//   折叠态：标题 + 摘要 + 箭头；展开态：统计 + 列表 + 刷新
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/app_palette.dart';
import '../../config/app_theme.dart';
import '../../data/database/database.dart';
import '../../data/repositories/editor_observation_repository.dart';
import '../../providers/app_providers.dart';
import '../../theme/app_typography.dart';

/// Editor 观察记录审计卡片（用户态）
class ObservationAuditCard extends ConsumerStatefulWidget {
  /// 当前会话 ID，缺省时展示空态
  final String? sessionId;

  /// 最近列表条数，默认 5
  final int recentLimit;

  const ObservationAuditCard({super.key, this.sessionId, this.recentLimit = 5});

  @override
  ConsumerState<ObservationAuditCard> createState() =>
      _ObservationAuditCardState();
}

class _ObservationAuditCardState extends ConsumerState<ObservationAuditCard> {
  bool _expanded = false;
  bool _loading = false;
  String? _error;
  int? _total;
  int? _triggered;
  List<EditorObservationRow> _recent = [];

  Future<void> _load() async {
    final sessionId = widget.sessionId;
    if (sessionId == null || sessionId.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = EditorObservationRepository(ref.read(appDatabaseProvider));
      final results = await Future.wait([
        repo.countObservations(sessionId),
        repo.countTriggeredObservations(sessionId),
        repo.getRecentObservations(sessionId, limit: widget.recentLimit),
      ]);
      if (!mounted) return;
      setState(() {
        _total = results[0] as int;
        _triggered = results[1] as int;
        _recent = results[2] as List<EditorObservationRow>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String get _rate {
    final total = _total ?? 0;
    if (total == 0) return '—';
    final triggered = _triggered ?? 0;
    return '${(triggered / total * 100).toStringAsFixed(1)}%';
  }

  String get _collapsedSummary {
    if (_total != null) {
      return '共 $_total 条 · 教练触发 $_triggered 次';
    }
    return 'Editor 对你写作的叙事层观察记录';
  }

  String _formatTime(int timestamp) {
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final hasSession = widget.sessionId != null && widget.sessionId!.isNotEmpty;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: context.palette.surfaceWhite,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: context.palette.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeaderRow(context, hasSession),
          if (_expanded) ...[
            const SizedBox(height: 8),
            Text('Editor 对你写作的叙事层观察记录', style: context.text.caption),
            const SizedBox(height: 12),
            ..._buildExpandedBody(context, hasSession),
          ],
        ],
      ),
    );
  }

  /// 标题行（点击折叠/展开）
  Widget _buildHeaderRow(BuildContext context, bool hasSession) {
    return InkWell(
      onTap: () {
        setState(() {
          _expanded = !_expanded;
        });
        if (_expanded && _total == null && !_loading) {
          _load();
        }
      },
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
        child: Row(
          children: [
            Icon(
              Icons.visibility_outlined,
              size: 20,
              color: context.palette.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Editor 观察记录',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: context.palette.textPrimary,
                ),
              ),
            ),
            if (!_expanded && _total != null) _buildCollapsedSummary(context),
            Icon(
              _expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
              size: 20,
              color: context.palette.textTertiary,
            ),
          ],
        ),
      ),
    );
  }

  /// 折叠态摘要（有数据时在标题行右侧显示）
  Widget _buildCollapsedSummary(BuildContext context) {
    return Flexible(
      child: Text(
        _collapsedSummary,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12, color: context.palette.textTertiary),
      ),
    );
  }

  /// 展开态正文：按加载状态分支出 统计/列表/刷新
  List<Widget> _buildExpandedBody(BuildContext context, bool hasSession) {
    if (!hasSession) {
      return [
        Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Text('无当前会话', style: context.text.subBody),
        ),
      ];
    }
    if (_error != null) {
      return [
        Text(
          '错误：$_error',
          style: TextStyle(fontSize: 13, color: context.palette.danger),
        ),
      ];
    }
    if (_loading) {
      return [
        Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
          child: Center(
            child: CircularProgressIndicator(color: context.palette.primary),
          ),
        ),
      ];
    }
    if (_total == null) {
      return [
        Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Text('暂无数据', style: context.text.subBody),
        ),
      ];
    }
    return [
      _buildStatRow(context),
      const SizedBox(height: 12),
      if (_total == 0)
        Text('暂无 observation 数据', style: context.text.subBody)
      else if (_recent.isEmpty)
        Text('暂无最近 observation', style: context.text.subBody)
      else
        ..._buildRecentList(context),
      const SizedBox(height: 12),
      _buildRefreshButton(context),
    ];
  }

  /// 统计行：总数 / 教练触发 / 触发率
  Widget _buildStatRow(BuildContext context) {
    return Row(
      children: [
        _StatItem(value: '$_total', label: '总数'),
        const SizedBox(width: 8),
        _StatItem(value: '$_triggered', label: '教练触发'),
        const SizedBox(width: 8),
        _StatItem(value: _rate, label: '触发率'),
      ],
    );
  }

  /// 最近 observation 列表（每条：时间·触发·命中 + 摘要预览）
  List<Widget> _buildRecentList(BuildContext context) {
    return _recent.map((obs) {
      final triggerTag = obs.teacherTriggered == 1 ? '触发' : '未触发';
      final impression = obs.overallImpression.isEmpty
          ? '—'
          : obs.overallImpression;
      final preview = impression.length > 60
          ? '${impression.substring(0, 60)}...'
          : impression;
      return Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: context.palette.divider)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_formatTime(obs.timestamp)} · $triggerTag · '
              'pronounced ${obs.pronouncedCount} / against ${obs.againstCount}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.microCaption,
            ),
            const SizedBox(height: 2),
            Text(
              preview,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.text.noteCaption,
            ),
          ],
        ),
      );
    }).toList();
  }

  /// 刷新按钮（重新拉取观察记录）
  Widget _buildRefreshButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _load,
        icon: const Icon(Icons.refresh, size: 16),
        label: const Text('刷新'),
        style: OutlinedButton.styleFrom(
          foregroundColor: context.palette.primary,
          side: BorderSide(color: context.palette.primarySoft),
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.smx),
        ),
      ),
    );
  }
}

/// 统计项：数值 + 标签
class _StatItem extends StatelessWidget {
  final String value;
  final String label;

  const _StatItem({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        decoration: BoxDecoration(
          color: context.palette.primarySoft,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: context.palette.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: context.palette.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
