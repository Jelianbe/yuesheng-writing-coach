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

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/app_palette.dart';
import '../../config/app_theme.dart';
import '../../widgets/yue_sheet.dart';
import '../../data/repositories/diagnosis_repository.dart';
import '../../data/repositories/reflection_question_repository.dart';
import '../../data/database/database.dart';
import '../../providers/app_providers.dart';
import '../../providers/chat_store.dart';
import '../../providers/growth_providers.dart';
import '../../services/focus_card_builder.dart';
import '../../services/growth_narrative.dart';
import 'focus_card.dart';
import 'growth_narrative_card.dart';
import 'pilot_metrics_card.dart';
import '../../router/app_routes.dart';
import '../../types/teaching_types.dart';
import 'diagnosis_picker_sheet.dart';
import 'growth_detail_nav.dart';
import 'growth_diagnosis_prefs_card.dart';
import '../app_settings/coach_settings_page.dart';
import 'observation_audit_card.dart';
import 'proficiency_ring.dart';
import 'severity_bar.dart';
import '../../theme/app_typography.dart';

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
      backgroundColor: context.palette.background,
      appBar: _buildAppBar(context),
      body: _buildBody(context, state, currentSessionId),
    );
  }

  /// 主体三态骨架（T-20261111-01 IA-3 · R-019 职责提取）。
  ///
  /// 快捷入口的**位置随态而变**（舰长 2026-11-11 批，判据见设计稿 §IA-3）：
  /// - **未就绪态**（加载 / 错误）留在顶部 —— 此时没有内容可让位，
  ///   且错误态下它是仅剩的可去去处；
  /// - **就绪态**下沉进内容列表、排在症候概览之后 —— 本 Tab 的任务是
  ///   「看到自己的水平与问题」，三个「去别处」的行不该抢第一屏。
  Widget _buildBody(
    BuildContext context,
    GrowthState state,
    String? currentSessionId,
  ) {
    final pending = state.isLoading || state.error != null;
    return Column(
      children: [
        if (pending) _buildQuickEntries(),
        Expanded(
          child: state.isLoading
              ? Center(
                  child: CircularProgressIndicator(
                    color: context.palette.primary,
                  ),
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
                  // 列表内边距已由 ListView 提供 ⇒ 卡片自身横向外边距归零，
                  // 否则会「双层缩进」（16 + 16）。
                  quickEntries: _buildQuickEntries(margin: EdgeInsets.zero),
                ),
        ),
      ],
    );
  }

  /// 快捷入口卡（批次 11：对齐 RN GROWTH_ENTRIES）；设置入口说明见原注释。
  Widget _buildQuickEntries({EdgeInsetsGeometry? margin}) {
    return _QuickEntries(
      margin: margin,
      onDiagnosis: () => _openDiagnosisPicker(context),
      onProgress: _openProgressDetail,
      onReference: () => context.push(AppRoutes.diagnosticReference),
    );
  }

  /// 顶栏（信息入口）——从 build 抽出（R-019 职责提取）。
  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      title: const Text('成长'),
      backgroundColor: context.palette.background,
      foregroundColor: context.palette.textPrimary,
      toolbarHeight: 48,
      elevation: 0,
      actions: [
        IconButton(
          icon: const Icon(Icons.settings_outlined, size: 22),
          onPressed: () => context.push(AppRoutes.settings),
          tooltip: '设置',
        ),
        IconButton(
          icon: const Icon(Icons.info_outline, size: 22),
          onPressed: widget.onOpenDetail,
          tooltip: '能力画像详情',
        ),
      ],
    );
  }

  /// 批次 38：学习进度入口 → 最新会话的学习进度详情页
  /// 学习进度从书架移至设置页（设置页区块 + 成长页入口），书架保持纯洁
  /// 交互批 #6：实现收敛到 growth_detail_nav.openLatestSessionProgressDetail
  /// （原与详情页导航 helper 是逐字重复的两份 copy，且各自带静默 catch）
  Future<void> _openProgressDetail() =>
      openLatestSessionProgressDetail(context, ref);

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

/// 快捷入口（对齐 RN growth.tsx GROWTH_ENTRIES：写作诊断/学习进度；
/// ADR-C122 追加「教学资料」资料区入口）
class _QuickEntries extends StatelessWidget {
  final VoidCallback onDiagnosis;
  final VoidCallback onProgress;
  final VoidCallback onReference;

  /// 卡片外边距。页面级（加载/错误态）用默认值；**放进 ListView 时传
  /// `EdgeInsets.zero`** —— 列表已有 16 内边距，否则横向缩进翻倍。
  final EdgeInsetsGeometry? margin;

  const _QuickEntries({
    required this.onDiagnosis,
    required this.onProgress,
    required this.onReference,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin:
          margin ??
          const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            0,
          ),
      decoration: BoxDecoration(
        color: context.palette.surfaceWhite,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: context.palette.divider),
      ),
      child: Column(
        children: [
          _entry(context, '写作诊断', Icons.search, onDiagnosis),
          Divider(height: 1, color: context.palette.borderSoft),
          // 批次 38：原「敬请期待」占位替换为「学习进度」真实入口
          _entry(context, '学习进度', Icons.trending_up, onProgress),
          Divider(height: 1, color: context.palette.borderSoft),
          // ADR-C122：诊断资料区（症候学员解读库一期）
          _entry(context, '教学资料', Icons.menu_book_outlined, onReference),
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
      child: Container(
        // TC-3：命中区 ≥48dp。原为 12+20+12 = 44dp，差 4dp；这里只抬高
        // 命中区，文字与图标视觉位置不变（Row 默认纵向居中）。
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: context.palette.textTertiary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: context.palette.textPrimary,
                ),
              ),
            ),
            // TK-2：可用入口不该用「禁用色」。`disabledText` 语义是禁用态，
            // 挂在这里等于告诉学员「这行点不动」；换 `textTertiary`（弱化但可读）。
            Icon(
              Icons.chevron_right,
              size: 20,
              color: context.palette.textTertiary,
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

  /// 快捷入口卡（三个「去别处」的行）。就绪态由本组件**排在症候概览之后**
  /// 渲染，不再占首屏第一块（T-20261111-01 IA-3）。
  final Widget quickEntries;

  const _GrowthContent({
    required this.state,
    required this.quickEntries,
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

    // 教学线 P1-4：当前焦点卡（profile + trainingStats 合成，无症候数据时隐藏）
    final focus = _buildFocusData(state);
    // B 议题（T-20261018-03）：「与上次相比」进步叙事卡——纯函数装配
    // （services/growth_narrative.dart），无主锚时返回空叙事 ⇒ 不渲染。
    // 与 FocusCard（前瞻）形成「回望 → 前瞻」对偶，故置于列表首位。
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        ..._buildLeadingSections(
          context,
          state,
          counts,
          proficiency,
          confidence,
          totalSessions,
        ),
        ..._buildNarrativeSection(state),
        _buildPilotSection(),
        GrowthDiagnosisPrefsCard(
          onOpenSettings: () => _openCoachSettings(context),
        ),
        const SizedBox(height: 12),
        // 当前焦点卡（P1-4）
        if (focus != null) ...[
          FocusCard(data: focus),
          const SizedBox(height: 12),
        ],
        if (onOpenDetail != null) _buildDetailEntryCard(context),
        const SizedBox(height: 12),
        // B8：Editor 观察记录审计卡（对齐 RN growth.tsx#L122，折叠展开）
        ObservationAuditCard(sessionId: sessionId),
        const SizedBox(height: 12),
        // E-8：对话思考题回顾（间隔重复）
        const ReflectionQuestionsCard(),
      ],
    );
  }

  /// 首屏最前面三块：能力画像 → 症候概览 → （下沉后的）快捷入口。
  ///
  /// ── IA-3（舰长 2026-11-11 批）：能力画像 + 症候概览上移到首屏第一块 ──
  /// 判据依据：本 Tab 的任务是「看到自己的水平与问题」，不是「去别处」。
  /// 改动前实测（360×740 探针）：能力画像卡内容顶 523 / 卡末行底部 714，
  /// 扣掉 AppBar 48 + NavigationBar 80 后内容区仅 660 ⇒ 老用户必然在 fold 之下。
  /// 改后实测：能力画像文字 81–101、卡末行 253–272 ⇒ 整卡在 fold 内。
  List<Widget> _buildLeadingSections(
    BuildContext context,
    GrowthState state,
    SeverityCounts counts,
    ProficiencyLevel proficiency,
    double confidence,
    int totalSessions,
  ) {
    return [
      _buildProficiencyCard(context, proficiency, confidence, totalSessions),
      const SizedBox(height: 12),
      _buildSeverityCard(context, state, counts),
      const SizedBox(height: 12),
      // 三个「去别处」的行（写作诊断 / 学习进度 / 教学资料）下沉到此处
      quickEntries,
      const SizedBox(height: 12),
    ];
  }

  /// B 议题（T-20261018-03）：「与上次相比」进步叙事卡段——纯函数装配
  /// （services/growth_narrative.dart），置于列表首位，与 FocusCard（前瞻）
  /// 形成「回望 → 前瞻」对偶。
  ///
  /// 无主锚（少于两次带能力快照的评估）时返回空列表 ⇒ 整段不渲染，
  /// 对齐设计批 §二 显隐规则（全空不出卡，不造死卡）。
  List<Widget> _buildNarrativeSection(GrowthState state) {
    final narrative = buildGrowthNarrative(
      evaluationHistory: state.evaluationHistory,
      recurrences: state.syndromeRecurrences,
    );
    if (narrative.isEmpty) return const <Widget>[];
    return <Widget>[
      GrowthNarrativeCard(narrative: narrative),
      const SizedBox(height: 12),
    ];
  }

  /// D 议题（T-20261018-06）：「引文锚定」卡段——anchor_probe 聚合读数
  /// （services/pilot_metrics_summary.dart 经 pilotMetricsSummaryProvider）。
  ///
  /// 显隐规则（设计批 §二）：零 anchor_probe 记录 / loading / 读失败
  /// （R-028 降级返回 null）⇒ 不渲染；有记录零引文由卡内出空态文案。
  /// 置于叙事卡（回望）之后，不破坏「回望 → 前瞻」对偶。
  /// `_GrowthContent` 是 StatelessWidget ⇒ 用 Consumer 局部 watch
  /// （不为此改类形态，最小侵入）。
  Widget _buildPilotSection() {
    return Consumer(
      builder: (context, ref, _) {
        final summary = ref.watch(pilotMetricsSummaryProvider).valueOrNull;
        if (summary == null) return const SizedBox.shrink();
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PilotMetricsCard(summary: summary),
            const SizedBox(height: 12),
          ],
        );
      },
    );
  }

  /// 教学线 P1-4：当前焦点卡数据（profile + trainingStats 合成；
  /// profile 缺失或无症候数据时 buildFocusCardData 返回 null ⇒ 不渲染）。
  FocusCardData? _buildFocusData(GrowthState state) {
    final profile = state.profile;
    if (profile == null) return null;
    return buildFocusCardData(
      profile: profile,
      trainingStats: state.trainingStats,
      phase: state.overview?.currentPhase,
      beginnerLevel: state.beginnerLevel,
    );
  }

  /// ADR-C110：折叠态「教学设置」入口行 → 教练设置二级页。
  ///
  /// 该导航**原本写在卡片内部**，使卡片反向 import 二级页、与二级页内嵌卡片
  /// 形成循环依赖（门禁 3 全量卡口）。改为由调用方注入 Action，依赖单向化。
  void _openCoachSettings(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const CoachSettingsPage()));
  }

  /// 熟练度卡片：能力画像 + 熟练度环 + 总会话数
  Widget _buildProficiencyCard(
    BuildContext context,
    ProficiencyLevel proficiency,
    double confidence,
    int totalSessions,
  ) {
    return _Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '能力画像',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: context.palette.textSecondary,
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
                style: context.text.subBody,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 症候概览卡片：活跃数 + 严重度条 + 图例
  Widget _buildSeverityCard(
    BuildContext context,
    GrowthState state,
    SeverityCounts counts,
  ) {
    return _Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '症候概览',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: context.palette.textSecondary,
                  ),
                ),
                const Spacer(),
                Text(
                  '${state.activeProblems.length} 个活跃',
                  style: TextStyle(
                    fontSize: 12,
                    color: context.palette.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SeverityBar(counts: counts, height: 10),
            const SizedBox(height: 8),
            _buildSeverityLegend(context, counts),
          ],
        ),
      ),
    );
  }

  /// 症候概览图例（L1/L2/L3 计数）
  Widget _buildSeverityLegend(BuildContext context, SeverityCounts counts) {
    return Row(
      children: [
        _Legend(color: context.palette.l1, label: 'L1 ${counts.l1}'),
        const SizedBox(width: 12),
        _Legend(color: context.palette.l2, label: 'L2 ${counts.l2}'),
        const SizedBox(width: 12),
        _Legend(color: context.palette.l3, label: 'L3 ${counts.l3}'),
      ],
    );
  }

  /// 详情入口卡片（查看完整能力画像）
  Widget _buildDetailEntryCard(BuildContext context) {
    return _Card(
      child: InkWell(
        onTap: onOpenDetail,
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.lg),
          child: Row(
            children: [
              Text(
                '查看完整能力画像',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: context.palette.textPrimary,
                ),
              ),
              Spacer(),
              Icon(
                Icons.chevron_right,
                size: 20,
                color: context.palette.textTertiary,
              ),
            ],
          ),
        ),
      ),
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
    return SingleChildScrollView(
      child: Column(
        children: [
          // 与 _QuickEntries 同款外边距，避免「教学设置」行通栏贴边（问题②修复）
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              0,
            ),
            child: GrowthDiagnosisPrefsCard(
              onOpenSettings: () => _openCoachSettings(context),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: _buildEmptyStateBody(context),
          ),
          // IA-3 的**空态对齐**：快捷入口在空态里仍然可达 —— 新用户的第一次
          // 写作诊断正是从这里进的（若空态不给，「能力画像先行」就会误伤新人）。
          // 位置放在空态 CTA 之后：第一眼仍应是「你还没有写作记录」。
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.xl,
            ),
            child: quickEntries,
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyStateBody(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.edit_note, size: 48, color: context.palette.textSecondary),
        const SizedBox(height: 12),
        Text(
          '还没有写作记录',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: context.palette.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '完成第一次写作后，这里会展示你的能力画像',
          style: context.text.subBody,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () => context.go('/bookshelf'),
          style: FilledButton.styleFrom(
            backgroundColor: context.palette.primary,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xl,
              vertical: AppSpacing.md,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
          ),
          child: const Text('去写第一篇'),
        ),
      ],
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
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        decoration: BoxDecoration(
          color: context.palette.surface,
          border: Border.all(color: context.palette.border),
        ),
        child: Row(children: [Expanded(child: child)]),
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
            borderRadius: BorderRadius.circular(AppRadius.xs),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: context.palette.textSecondary),
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
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 32, color: context.palette.danger),
            const SizedBox(height: 8),
            Text('加载失败', style: context.text.body),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onRetry,
              style: FilledButton.styleFrom(
                backgroundColor: context.palette.primary,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.sm,
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

/// E-8：对话思考题回顾卡片（间隔重复）
///
/// 从 reflection_question 表读取待回顾思考题，用户可标记「已想过」推延下次回顾。
class ReflectionQuestionsCard extends ConsumerStatefulWidget {
  const ReflectionQuestionsCard({super.key});

  @override
  ConsumerState<ReflectionQuestionsCard> createState() =>
      _ReflectionQuestionsCardState();
}

class _ReflectionQuestionsCardState
    extends ConsumerState<ReflectionQuestionsCard> {
  late Future<List<ReflectionQuestion>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<ReflectionQuestion>> _load() {
    final db = ref.read(appDatabaseProvider);
    return ReflectionQuestionRepository(db).listPending();
  }

  Future<void> _markReviewed(String id) async {
    final db = ref.read(appDatabaseProvider);
    await ReflectionQuestionRepository(db).markReviewed(id);
    if (mounted) setState(() => _future = _load());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ReflectionQuestion>>(
      future: _future,
      builder: _buildContent,
    );
  }

  Widget _buildContent(
    BuildContext context,
    AsyncSnapshot<List<ReflectionQuestion>> snap,
  ) {
    final items = snap.data ?? const [];
    if (items.isEmpty) return _buildEmpty(context);
    return _buildList(context, items);
  }

  Widget _buildEmpty(BuildContext context) {
    return _Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '思考题回顾',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: context.palette.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            Text('暂无待回顾的思考题', style: context.text.subBody),
          ],
        ),
      ),
    );
  }

  Widget _buildList(BuildContext context, List<ReflectionQuestion> items) {
    return _Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '思考题回顾（${items.length}）',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: context.palette.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            ...items.take(5).map((q) => _buildQuestionItem(q)),
          ],
        ),
      ),
    );
  }

  Widget _buildQuestionItem(ReflectionQuestion q) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              q.question,
              style: TextStyle(
                fontSize: 13,
                color: context.palette.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () => _markReviewed(q.id),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              // TC-5（舰长 2026-11-11 批 §4-490 ⑤）：命中区 ≥44dp。
              // 不取 48：该卡一屏最多 5 条，48 会多占 ≈145dp 把「思考题回顾」
              // 整块推下 fold；44 是 Material 允许的次优值。
              minimumSize: const Size(0, 44),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              '已想过',
              style: TextStyle(
                fontSize: 12,
                color: context.palette.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
