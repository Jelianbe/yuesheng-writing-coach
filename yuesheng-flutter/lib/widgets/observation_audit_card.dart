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

import '../config/app_theme.dart';
import '../data/database/database.dart';
import '../data/repositories/editor_observation_repository.dart';
import '../providers/app_providers.dart';

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
        color: AppColors.surfaceWhite,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题行（点击折叠/展开）
          InkWell(
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
                  const Icon(
                    Icons.visibility_outlined,
                    size: 20,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Editor 观察记录',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  if (!_expanded && _total != null)
                    Flexible(
                      child: Text(
                        _collapsedSummary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 20,
                    color: AppColors.textTertiary,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const SizedBox(height: 8),
            const Text(
              'Editor 对你写作的叙事层观察记录',
              style: AppTextStyles.caption,
            ),
            const SizedBox(height: 12),
            if (!hasSession)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Text(
                  '无当前会话',
                  style: AppTextStyles.subBody,
                ),
              )
            else if (_error != null)
              Text(
                '错误：$_error',
                style: const TextStyle(fontSize: 13, color: AppColors.danger),
              )
            else if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                ),
              )
            else if (_total == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Text(
                  '暂无数据',
                  style: AppTextStyles.subBody,
                ),
              )
            else ...[
              // 统计行
              Row(
                children: [
                  _StatItem(value: '$_total', label: '总数'),
                  const SizedBox(width: 8),
                  _StatItem(value: '$_triggered', label: '教练触发'),
                  const SizedBox(width: 8),
                  _StatItem(value: _rate, label: '触发率'),
                ],
              ),
              const SizedBox(height: 12),
              if (_total == 0)
                const Text(
                  '暂无 observation 数据',
                  style: AppTextStyles.subBody,
                )
              else if (_recent.isEmpty)
                const Text(
                  '暂无最近 observation',
                  style: AppTextStyles.subBody,
                )
              else
                ..._recent.map((obs) {
                  final triggerTag = obs.teacherTriggered == 1 ? '触发' : '未触发';
                  final impression = obs.overallImpression.isEmpty
                      ? '—'
                      : obs.overallImpression;
                  final preview = impression.length > 60
                      ? '${impression.substring(0, 60)}...'
                      : impression;
                  return Container(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                    decoration: const BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: AppColors.divider),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_formatTime(obs.timestamp)} · $triggerTag · '
                          'pronounced ${obs.pronouncedCount} / against ${obs.againstCount}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.microCaption,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          preview,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.noteCaption,
                        ),
                      ],
                    ),
                  );
                }),
              const SizedBox(height: 12),
              // 刷新按钮
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('刷新'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primarySoft),
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.smx),
                  ),
                ),
              ),
            ],
          ],
        ],
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
          color: AppColors.primarySoft,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                fontSize: 10,
                color: AppColors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
