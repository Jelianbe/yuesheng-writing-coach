// ─────────────────────────────────────────────────────────────
// GrowthPage — 成长概览页（用户级能力画像入口）
//
// 视觉规范（月色竹青，对齐 C1/C3）：
//   AppBar       #F7F8F6 + 48dp + 深字 #2D3142
//   Scaffold 背景 #F7F8F6
//   卡片         #F2F4F2 + 左侧 4dp 竹青色条（ClipRRect + 内部 Container）
//   主色锚点     #2D5A52
//
// 布局：
//   1. 熟练度卡片：ProficiencyRing + 总会话数
//   2. 症候概览卡片：SeverityBar + 活跃问题数
//   3. 详情入口（onOpenDetail 回调存在时显示）
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../config/app_theme.dart';
import 'yue_sheet.dart';
import '../data/repositories/diagnosis_repository.dart';
import '../data/repositories/session_repository.dart';
import '../providers/app_providers.dart';
import '../providers/chat_store.dart';
import '../providers/growth_providers.dart';
import '../router/app_router.dart';
import '../types/teaching_types.dart';
import 'diagnosis_picker_sheet.dart';
import 'observation_audit_card.dart';
import 'proficiency_ring.dart';
import 'severity_bar.dart';

/// 成长概览页
class GrowthPage extends ConsumerStatefulWidget {
  final VoidCallback? onOpenDetail;

  const GrowthPage({super.key, this.onOpenDetail});

  @override
  ConsumerState<GrowthPage> createState() => _GrowthPageState();
}

class _GrowthPageState extends ConsumerState<GrowthPage> {
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
    // B8：当前会话 ID（供 ObservationAuditCard 展示会话级观察记录，对齐 RN useChatStore().currentSessionId）
    final currentSessionId = ref.watch(chatStoreProvider).currentSessionId;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('成长'),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        toolbarHeight: 48,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline, size: 22),
            onPressed: widget.onOpenDetail,
            tooltip: '能力画像详情',
          ),
        ],
      ),
      body: Column(
        children: [
          // 快捷入口（批次 11：对齐 RN GROWTH_ENTRIES，总显示）
          _QuickEntries(
            onSettings: () => context.push(AppRoutes.settings),
            onDiagnosis: () => _openDiagnosisPicker(context),
            onProgress: _openProgressDetail,
          ),
          Expanded(
            child: state.isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  )
                : state.error != null
                ? _ErrorView(
                    error: state.error!,
                    onRetry: () =>
                        ref.read(growthStoreProvider.notifier).loadGrowthData(),
                  )
                : _GrowthContent(
                    state: state,
                    onOpenDetail: widget.onOpenDetail,
                    sessionId: currentSessionId,
                  ),
          ),
        ],
      ),
    );
  }

  /// 批次 38：学习进度入口 → 最新会话的学习进度详情页
  /// 学习进度从书架移至设置页（设置页区块 + 成长页入口），书架保持纯洁
  /// 批次78：无会话静默 return → 对齐 growth_detail_page 批次77 SnackBar 轻提示
  Future<void> _openProgressDetail() async {
    try {
      final sessionRepo = SessionRepository(ref.read(appDatabaseProvider));
      final sessions = await sessionRepo.listSessions(); // updated_at DESC
      if (sessions.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('还没有写作会话，先写一章吧')),
          );
        }
        return;
      }
      if (!mounted) return;
      final latestId = sessions.first.id;
      if (!mounted) return;
      context.push(
        AppRoutes.progressDetail,
        extra: <String, dynamic>{'sessionId': latestId},
      );
    } catch (_) {
      // 查询失败静默（不进入死页）
    }
  }

  /// 批次 13：打开「选择要诊断的章节」弹层（对齐 RN DiagnosisPickerModal）
  ///
  /// 选章后记录待诊断章节并切到对话 Tab（startDiagnosis 语义），
  /// ChatPage 监听 pendingDiagnosisChapterProvider 自动发起诊断。
  void _openDiagnosisPicker(BuildContext context) {
    showYueModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => DiagnosisPickerSheet(
        onSelect: (manuscriptId, chapter) {
          ref.read(pendingDiagnosisChapterProvider.notifier).state = chapter.id;
          context.go(AppRoutes.writing);
        },
      ),
    );
  }
}

/// 快捷入口（对齐 RN growth.tsx GROWTH_ENTRIES：设置/写作诊断/学习进度）
class _QuickEntries extends StatelessWidget {
  final VoidCallback onSettings;
  final VoidCallback onDiagnosis;
  final VoidCallback onProgress;

  const _QuickEntries({
    required this.onSettings,
    required this.onDiagnosis,
    required this.onProgress,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      decoration: BoxDecoration(
        color: AppColors.surfaceWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          _entry(context, '设置', Icons.settings_outlined, onSettings),
          const Divider(height: 1, color: AppColors.borderSoft),
          _entry(context, '写作诊断', Icons.search, onDiagnosis),
          const Divider(height: 1, color: AppColors.borderSoft),
          // 批次 38：原「敬请期待」占位替换为「学习进度」真实入口
          _entry(context, '学习进度', Icons.trending_up, onProgress),
        ],
      ),
    );
  }

  Widget _entry(
    BuildContext context,
    String label,
    IconData icon,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppColors.textTertiary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const Icon(
              Icons.chevron_right,
              size: 20,
              color: AppColors.disabledText,
            ),
          ],
        ),
      ),
    );
  }
}

class _GrowthContent extends StatelessWidget {
  final GrowthState state;
  final VoidCallback? onOpenDetail;
  final String? sessionId;

  const _GrowthContent({
    required this.state,
    this.onOpenDetail,
    this.sessionId,
  });

  @override
  Widget build(BuildContext context) {
    final profile = state.profile;
    final proficiency = profile?.proficiency ?? ProficiencyLevel.beginner;
    final confidence = profile?.confidence ?? 0;
    final totalSessions = profile?.totalSessions ?? 0;

    // P2-1 修复：新用户 0 会话时显示空状态引导 CTA，而非两张空数据卡片
    if (totalSessions == 0 && state.activeProblems.isEmpty) {
      return _buildEmptyState(context);
    }

    final counts = _countSeverities(state.activeProblems);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 熟练度卡片
        _Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '能力画像',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: ProficiencyRing(
                    level: proficiency,
                    confidence: confidence,
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: Text(
                    '共 $totalSessions 次写作会话',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        // 症候概览卡片
        _Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      '症候概览',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${state.activeProblems.length} 个活跃',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SeverityBar(counts: counts, height: 10),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _Legend(color: AppColors.l1, label: 'L1 ${counts.l1}'),
                    const SizedBox(width: 12),
                    _Legend(color: AppColors.l2, label: 'L2 ${counts.l2}'),
                    const SizedBox(width: 12),
                    _Legend(color: AppColors.l3, label: 'L3 ${counts.l3}'),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        // 详情入口
        if (onOpenDetail != null)
          _Card(
            child: InkWell(
              onTap: onOpenDetail,
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  children: [
                    Text(
                      '查看完整能力画像',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Spacer(),
                    Icon(
                      Icons.chevron_right,
                      size: 20,
                      color: AppColors.textTertiary,
                    ),
                  ],
                ),
              ),
            ),
          ),
        const SizedBox(height: 12),
        // B8：Editor 观察记录审计卡（对齐 RN growth.tsx#L122，折叠展开）
        ObservationAuditCard(sessionId: sessionId),
      ],
    );
  }

  /// 统计症候严重度计数
  SeverityCounts _countSeverities(List<ActiveProblemView> problems) {
    int l1 = 0, l2 = 0, l3 = 0;
    for (final p in problems) {
      switch (p.severity) {
        case 'L1':
          l1++;
          break;
        case 'L2':
          l2++;
          break;
        case 'L3':
          l3++;
          break;
      }
    }
    return SeverityCounts(l1: l1, l2: l2, l3: l3);
  }

  /// P2-1：新用户空状态——引导去写作
  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.edit_note,
              size: 48,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 12),
            const Text(
              '还没有写作记录',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '完成第一次写作后，这里会展示你的能力画像',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => context.go('/bookshelf'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('去写第一篇'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 通用卡片：左侧 4dp 竹青色条（对齐 C3 ManuscriptDetailPage）
///
/// 用 ClipRRect + 内部 Container 实现左侧色条，
/// 规避 Border+borderRadius uniform color 限制
class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
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

class _Legend extends StatelessWidget {
  final Color color;
  final String label;
  const _Legend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
      ],
    );
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
        padding: const EdgeInsets.all(24),
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
                  horizontal: 20,
                  vertical: 10,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
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
