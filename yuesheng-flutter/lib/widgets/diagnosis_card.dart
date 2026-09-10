// ─────────────────────────────────────────────────────────────
// DiagnosisCard — 诊断结果卡片
//
// 复刻 RN components/diagnosis/DiagnosisCard.tsx
// 核心职责：
//   1. 展示本次诊断概览（问题数 + 信心）
//   2. 标签行：症候名 + 矿物色严重度（L1/L2/L3）+ 教学状态色点（批次 45：对齐 RN SyndromeTag P0-3）
//   3. 展开/收起：展开后显示症候详情块 + 改写建议块
//   4. 空态：syndromes=0 显示"本次未发现显著问题"
//
// 视觉规范（月色竹青）：
//   - 卡片：#F2F4F2 + 圆角 12 + 左 4dp 竹青色条（ClipRRect 方案）
//   - Header：#F2F4F2 + 深字 #2D3142 + 点分隔问题数/信心
//   - 严重度矿物色：L1=#E8F0EE（竹青淡）/ L2=#F5E6B8（矿物黄）/ L3=#E8C5C5（矿物红）
//   - 症候详情块：左严重度色条 + 证据斜体引用 + 改写建议（品牌竹青条 #E8F0EE）
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_motion.dart';
import '../config/app_theme.dart';
import 'knowledge_card.dart';
import 'thinking_chain.dart';
import 'yue_sheet.dart';
import '../data/repositories/diagnosis_repository.dart';
import '../data/repositories/session_repository.dart';
import '../providers/app_providers.dart';
import '../providers/chat_store.dart';
import '../providers/session_providers.dart';
import '../services/message_card_service.dart';
import '../services/student_profile_compute.dart';
import '../services/syndrome_tracker.dart';
import '../services/teaching_state_cache.dart';
import '../types/teaching_types.dart';
import 'syndrome_detail_modal.dart';

/// 严重度 → 矿物色 + 文字色
class _SeverityConfig {
  final Color bgColor;
  final Color textColor;
  const _SeverityConfig(this.bgColor, this.textColor);
}

const Map<String, _SeverityConfig> _severityMap = {
  'L1': _SeverityConfig(AppColors.l1, AppColors.primary), // 竹青淡
  'L2': _SeverityConfig(AppColors.l2, AppColors.l2Text), // 矿物黄
  'L3': _SeverityConfig(AppColors.l3, AppColors.l3Text), // 矿物红
};

/// 教学状态 → 色点颜色（批次 45：对齐 RN SyndromeTag P0-3，
/// 教学状态存在时色点优先显示教学状态色，否则回退严重度色）
Color _teachingStateDotColor(TeachingState state) => switch (state) {
  TeachingState.identified => AppColors.warning, // 刚识别 → 警告色
  TeachingState.inProgress => AppColors.primaryDeep, // 训练中 → 信息竹青
  TeachingState.consolidating => AppColors.primary, // 趋稳中 → 成功竹青
  TeachingState.mastered => AppColors.disabledText, // 已掌握 → 禁用灰
};

/// 卡片默认文案
/// 注意：不用 record 类型，因为 record 的字段访问不能出现在 const 表达式中
class _CardText {
  static const String headerTitle = '本次诊断';
  static const String problemSuffix = ' 个问题';
  static const String confidenceSuffix = '% 信心';
  static const String evidenceLabel = '证据：';
  static const String rewriteTitle = '改写建议';
  static const String emptyHint = '本次未发现显著问题';
  static const String noEvidence = '（无证据列表）';
  const _CardText._();
}

class DiagnosisCard extends ConsumerStatefulWidget {
  final int syndromeCount;
  final List<DiagnosisSyndromeCard> syndromes;
  final List<String> suggestedActions;
  final double confidence;
  final bool defaultExpanded;

  /// D5-B：所属会话 ID。非空时每个症候详情块底部渲染确认栏
  /// （对齐 RN DiagnosisConfirmationBar：认同/部分认同/不认同）
  final String? sessionId;

  const DiagnosisCard({
    super.key,
    required this.syndromeCount,
    required this.syndromes,
    required this.suggestedActions,
    required this.confidence,
    this.defaultExpanded = false,
    this.sessionId,
  });

  /// 便利构造：从 Message.content 的 JSON 解析 payload 渲染
  /// 由 MessageList message_type='diagnosis_result' 分支直接调用
  static DiagnosisCard fromMessageContent(
    String content, {
    Key? key,
    String? sessionId,
  }) {
    try {
      final payload = DiagnosisResultCardPayload.fromJson(
        jsonDecode(content) as Map<String, dynamic>,
      );
      return DiagnosisCard(
        key: key,
        syndromeCount: payload.syndromeCount,
        syndromes: payload.syndromes,
        suggestedActions: payload.suggestedActions,
        confidence: payload.confidence,
        sessionId: sessionId,
      );
    } catch (_) {
      // 兜底：空诊断卡
      return DiagnosisCard(
        key: key,
        syndromeCount: 0,
        syndromes: const [],
        suggestedActions: const [],
        confidence: 0.0,
        sessionId: sessionId,
      );
    }
  }

  @override
  ConsumerState<DiagnosisCard> createState() => _DiagnosisCardState();
}

class _DiagnosisCardState extends ConsumerState<DiagnosisCard>
    with SingleTickerProviderStateMixin {
  late bool _expanded = widget.defaultExpanded;
  late final AnimationController _expandAnim;

  /// 症候ID → 教学状态（批次 45：对齐 RN loadSyndromeTeachingStates，
  /// sessionId 非空时加载画像聚合，标签行色点按教学状态着色）
  Map<String, TeachingState> _teachingStates = const {};

  /// 症候ID → 跨轮次追踪（出现次数/趋势；用于「第 N 次出现」角标与好转提示）。
  /// 异步加载，失败静默回退空 map——不阻断卡片渲染。
  Map<String, SyndromeTracked> _trends = const {};

  @override
  void initState() {
    super.initState();
    _loadTeachingStates();
    _loadTrends();
  }

  /// 加载跨轮次症候追踪（复用 SyndromeTracker.loadSyndromeTrends，
  /// 与详情弹层同源；会话级无缓存、量小，直接查库）。
  Future<void> _loadTrends() async {
    final sessionId = widget.sessionId;
    if (sessionId == null) return;
    try {
      final tracker = SyndromeTracker(
        DiagnosisRepository(ref.read(appDatabaseProvider)),
      );
      final trends = await tracker.loadSyndromeTrends(sessionId);
      if (!mounted) return;
      setState(() {
        _trends = {for (final t in trends) t.syndromeId: t};
      });
    } catch (_) {
      // 加载失败静默（角标/趋势行不显示）
    }
  }

  // 批次6（6.1）：prefers-reduced-motion —— 展开动画时长按系统设置归零。
  // controller 在 didChangeDependencies 创建（首次），可安全读取 MediaQuery。
  bool _animControllerInitialized = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_animControllerInitialized) {
      _animControllerInitialized = true;
      _expandAnim = AnimationController(
        vsync: this,
        value: _expanded ? 1.0 : 0.0,
        // 批次69：动效节奏统一——时长收敛到 AppMotion 令牌
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : AppMotion.durationStandard,
      );
    }
  }

  /// 异步加载画像聚合的教学状态（复用 computeSyndromeProfile，与画像页同源）。
  /// 失败静默（色点回退严重度色，不阻断卡片渲染）。
  /// 批次54：会话级缓存——命中直接复用，滚动回收重建不再重复查库；
  /// 新诊断落库时 DiagnosisRepository.commitDiagnosis 已显式失效缓存。
  Future<void> _loadTeachingStates() async {
    final sessionId = widget.sessionId;
    if (sessionId == null) return;
    final cached = readCachedTeachingStates(sessionId);
    if (cached != null) {
      if (!mounted) return;
      setState(() => _teachingStates = cached);
      return;
    }
    try {
      final repo = DiagnosisRepository(ref.read(appDatabaseProvider));
      final entries = await repo.getAllDiagnoses(sessionId: sessionId);
      final profile = computeSyndromeProfile(entries);
      final states = {
        for (final entry in profile.entries)
          entry.key: entry.value.teachingState,
      };
      writeCachedTeachingStates(sessionId, states);
      if (!mounted) return;
      setState(() => _teachingStates = states);
    } catch (_) {
      // 加载失败回退严重度色（静默）
    }
  }

  @override
  void dispose() {
    _expandAnim.dispose();
    super.dispose();
  }

  void _toggleExpanded() {
    setState(() {
      _expanded = !_expanded;
      if (_expanded) {
        _expandAnim.forward();
      } else {
        _expandAnim.reverse();
      }
    });
  }

  _SeverityConfig _sev(String s) =>
      _severityMap[s] ?? const _SeverityConfig(AppColors.l1, AppColors.primary);

  @override
  Widget build(BuildContext context) {
    final confPct = (widget.confidence * 100).round();

    // 卡片：#F2F4F2 + 左 4dp 竹青条
    return Container(
      margin: const EdgeInsets.symmetric(vertical: AppSpacing.xsm),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border.fromBorderSide(BorderSide(color: AppColors.border)),
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 左侧 4dp 竹青主色条
                Container(width: 4, color: AppColors.primary),
                Expanded(child: _buildCardBody(confPct)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 卡片主体：Header + 标签行 + 展开详情（R-019 清偿拆出）。
  Widget _buildCardBody(int confPct) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(confPct),
        _buildTagRow(),
        SizeTransition(
          sizeFactor: CurvedAnimation(
            parent: _expandAnim,
            curve: AppMotion.curveFade,
          ),
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            child: Column(
              children: [
                const Divider(height: 1, color: AppColors.border),
                const SizedBox(height: 12),
                _buildReasoningSection(),
                const SizedBox(height: 12),
                _buildSyndromesDetail(),
                if (widget.suggestedActions.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _buildRewriteBlock(),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── 诊断依据区（批次 C：ConfidenceBar + ThinkingChain 竹青化接入）──
  /// 展开详情顶部：诊断信心置信条 + 诊断依据步骤链（默认折叠）。
  Widget _buildReasoningSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ConfidenceBar(label: '诊断信心', value: widget.confidence),
        const SizedBox(height: AppSpacing.md),
        ThinkingChain(title: '诊断依据', steps: _buildReasoningSteps()),
      ],
    );
  }

  /// 诊断依据步骤链（诚实派生：每一步都来自诊断 payload 真实字段，
  /// 不伪造推理过程；步骤不含置信点——置信只经 ConfidenceBar 展示）。
  List<ThinkingStep> _buildReasoningSteps() {
    final syndromes = widget.syndromes;
    final totalEvidence = syndromes.fold<int>(
      0,
      (sum, s) => sum + s.evidenceCount,
    );
    final names = syndromes.map((s) => s.name).join('、');
    final severitySummary = syndromes
        .map((s) => '${s.name}（${_severityLabel(s.severity)}）')
        .join('；');
    return [
      ThinkingStep(label: '文本分析', detail: '扫描文本，定位 $totalEvidence 处问题片段'),
      ThinkingStep(
        label: '症候匹配',
        detail: syndromes.isEmpty ? '未匹配到已知症候' : '匹配 $names',
      ),
      ThinkingStep(
        label: '严重度评估',
        detail: severitySummary.isEmpty ? '—' : severitySummary,
      ),
      ThinkingStep(
        label: '建议生成',
        detail: '生成 ${widget.suggestedActions.length} 条改写建议',
      ),
    ];
  }

  String _severityLabel(String severity) => switch (severity) {
    'L2' => '中等',
    'L3' => '严重',
    _ => '轻微',
  };
  // ── Header：本次诊断 · N 个问题 · N% 信心 · 展开/收起 ▾ ──
  Widget _buildHeader(int confPct) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _toggleExpanded,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.smx,
          ),
          child: Row(
            children: [
              const Icon(
                Icons.analytics_outlined,
                size: 18,
                color: AppColors.textPrimary,
              ),
              const SizedBox(width: 8),
              const Text(
                _CardText.headerTitle,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              _buildHeaderMeta(confPct),
            ],
          ),
        ),
      ),
    );
  }

  /// Header 尾部：问题数 · 信心 · 展开箭头（R-019 清偿拆出）。
  Widget _buildHeaderMeta(int confPct) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${widget.syndromeCount}${_CardText.problemSuffix}',
          style: AppTextStyles.subBody,
        ),
        const SizedBox(width: 6),
        const Text('·', style: TextStyle(color: AppColors.textTertiary)),
        const SizedBox(width: 6),
        Text(
          '$confPct${_CardText.confidenceSuffix}',
          style: AppTextStyles.subBody,
        ),
        const SizedBox(width: 8),
        RotationTransition(
          turns: Tween(begin: 0.0, end: 0.5).animate(
            CurvedAnimation(parent: _expandAnim, curve: Curves.easeOut),
          ),
          child: const Icon(
            Icons.keyboard_arrow_down,
            size: 20,
            color: AppColors.textTertiary,
          ),
        ),
      ],
    );
  }

  // ── 标签行：症候名 + 矿物色严重度 chip ──
  Widget _buildTagRow() {
    if (widget.syndromes.isEmpty) {
      return _buildEmptyTagHint();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: widget.syndromes.map(_buildSyndromeChip).toList(),
      ),
    );
  }

  /// 空症候提示 chip（R-019 清偿拆出）。
  Widget _buildEmptyTagHint() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.smx,
              vertical: AppSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: AppColors.l1,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: const Text(
              _CardText.emptyHint,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 单个症候 chip：色点 + 名 + 严重度（R-019 清偿拆出）。
  Widget _buildSyndromeChip(DiagnosisSyndromeCard s) {
    final cfg = _sev(s.severity);
    // 批次 45：教学状态存在时色点优先显示教学状态色（对齐 RN SyndromeTag P0-3）
    final teachingState = _teachingStates[s.syndromeId];
    final dotColor = teachingState != null
        ? _teachingStateDotColor(teachingState)
        : cfg.textColor;
    return InkWell(
      // sessionId 非空时可点击打开症候详情弹层（对齐 RN SyndromeTag onPress）
      onTap: widget.sessionId != null ? () => _openSyndromeDetail(s) : null,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.smx,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: cfg.bgColor,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: _buildChipLabel(cfg, dotColor, s),
      ),
    );
  }

  /// chip 内容：色点 + 症候名 + 严重度 + 第 N 次出现角标（R-019 清偿拆出）。
  Widget _buildChipLabel(
    _SeverityConfig cfg,
    Color dotColor,
    DiagnosisSyndromeCard s,
  ) {
    final occurrence = _trends[s.syndromeId]?.occurrenceCount ?? 0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          margin: const EdgeInsets.only(right: AppSpacing.xsm),
          decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
        ),
        Text(
          s.name,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: cfg.textColor,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          s.severity,
          style: TextStyle(
            fontSize: 11,
            color: cfg.textColor.withValues(alpha: 0.85),
          ),
        ),
        // 第 N 次出现角标：仅 N ≥ 2 时显示（首现是常态，不制造噪音）
        if (occurrence >= 2) ...[
          const SizedBox(width: 4),
          Text(
            '×$occurrence',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: cfg.textColor.withValues(alpha: 0.9),
            ),
          ),
        ],
      ],
    );
  }

  /// 症候 chip 点击：加载跨轮次追踪 → 打开详情弹层（对齐 RN debugTriggerSyndromeDetail）
  Future<void> _openSyndromeDetail(DiagnosisSyndromeCard s) async {
    final sessionId = widget.sessionId;
    if (sessionId == null || !mounted) return;
    final tracker = SyndromeTracker(
      DiagnosisRepository(ref.read(appDatabaseProvider)),
    );
    final trends = await tracker.loadSyndromeTrends(sessionId);
    if (!mounted) return;
    final tracked = trends
        .where((t) => t.syndromeId == s.syndromeId)
        .firstOrNull;
    if (tracked == null) {
      // 批次80 M2：新症候无跨轮次追踪数据 → 轻提示而非静默（修复前点击无反应）
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('暂无该症候的追踪记录')));
      }
      return;
    }
    await showYueModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SyndromeDetailModal(syndrome: tracked),
    );
  }

  // ── 症候详情块：每块左色条 + 标签 + 证据 + 说明 ──
  Widget _buildSyndromesDetail() {
    if (widget.syndromes.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Text(_CardText.emptyHint, style: AppTextStyles.subBody),
      );
    }

    return Column(
      children: [
        for (var i = 0; i < widget.syndromes.length; i++) ...[
          _SyndromeBlock(
            syndrome: widget.syndromes[i],
            tracked: _trends[widget.syndromes[i].syndromeId],
          ),
          // D5-B：sessionId 非空时每个症候块底部渲染确认栏（对齐 RN）
          if (widget.sessionId != null) ...[
            const SizedBox(height: 8),
            _SyndromeConfirmationBar(
              syndrome: widget.syndromes[i],
              sessionId: widget.sessionId!,
            ),
          ],
          if (i < widget.syndromes.length - 1) const SizedBox(height: 12),
        ],
      ],
    );
  }

  // ── 改写建议块：品牌竹青 #E8F0EE 底 + 左竹青 #2D5A52 条 ──
  Widget _buildRewriteBlock() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        decoration: const BoxDecoration(color: AppColors.l1),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4, color: AppColors.primary),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        _CardText.rewriteTitle,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      for (var i = 0; i < widget.suggestedActions.length; i++)
                        _buildRewriteAction(i),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 单条改写建议行（序号 + 文本；R-019 清偿拆出）。
  Widget _buildRewriteAction(int index) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: index == widget.suggestedActions.length - 1
            ? 0
            : AppSpacing.xsm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${index + 1}.',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              widget.suggestedActions[index],
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textDeep,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 症候详情块内部组件 ──
class _SyndromeBlock extends StatefulWidget {
  final DiagnosisSyndromeCard syndrome;

  /// 跨轮次追踪（可能为 null：新症候无历史/加载失败时不显示趋势行）
  final SyndromeTracked? tracked;
  const _SyndromeBlock({required this.syndrome, this.tracked});

  @override
  State<_SyndromeBlock> createState() => _SyndromeBlockState();
}

class _SyndromeBlockState extends State<_SyndromeBlock> {
  /// 证据原文展开状态（点击「展开证据」切换）。
  bool _evidenceExpanded = false;

  @override
  Widget build(BuildContext context) {
    final sev = _SeverityConfig(AppColors.l1, AppColors.primary);
    final cfg = _severityMap[widget.syndrome.severity] ?? sev;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 左侧严重度色条
        Container(
          width: 4,
          height: 44,
          decoration: BoxDecoration(
            color: cfg.bgColor,
            borderRadius: BorderRadius.circular(AppRadius.xs),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 症候名小 chip
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xxs,
                ),
                decoration: BoxDecoration(
                  color: cfg.bgColor,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Text(
                  widget.syndrome.name,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: cfg.textColor,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _buildTrendRow(),
              const SizedBox(height: 4),
              _buildEvidenceRow(),
            ],
          ),
        ),
      ],
    );
  }

  /// 趋势行：仅 improving/worsening 显示（stable 不制造噪音；
  /// 诚实派生自跨轮次严重度差分，无数据时不显示）。
  Widget _buildTrendRow() {
    final tracked = widget.tracked;
    if (tracked == null) return const SizedBox.shrink();
    final (icon, text, color) = switch (tracked.trend) {
      'improving' => ('↗', '较上次诊断好转', AppColors.primary),
      'worsening' => ('↘', '较上次诊断加重', AppColors.danger),
      _ => (null, null, null),
    };
    if (text == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            icon!,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(width: 3),
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  /// 证据行：无证据 / 有原文可展开 / 仅计数（旧数据无原文时如实展示）。
  Widget _buildEvidenceRow() {
    final evidence = widget.syndrome.evidence;
    final count = widget.syndrome.evidenceCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 证据
        const Text(
          _CardText.evidenceLabel,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textDeep,
          ),
        ),
        const SizedBox(height: 4),
        if (count == 0)
          const Text(_CardText.noEvidence, style: AppTextStyles.noteCaption)
        else if (evidence.isNotEmpty)
          _buildEvidenceToggle(evidence, count)
        else
          // 旧版数据仅有计数、无证据原文：不承诺可查看（批次80 M1 教训延续）
          Text(
            '（共 $count 处证据）',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textDeep,
              fontStyle: FontStyle.italic,
            ),
          ),
        if (_evidenceExpanded && evidence.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final e in evidence) _EvidenceQuote(text: e),
        ],
      ],
    );
  }

  /// 证据展开/收起开关（有原文时显示可点击入口）。
  Widget _buildEvidenceToggle(List<String> evidence, int count) {
    return GestureDetector(
      onTap: () => setState(() => _evidenceExpanded = !_evidenceExpanded),
      behavior: HitTestBehavior.opaque,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _evidenceExpanded ? '▾ 收起证据（$count 处）' : '▸ 展开证据（$count 处）',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 4),
          const Icon(
            Icons.keyboard_arrow_down,
            size: 14,
            color: AppColors.primary,
          ),
        ],
      ),
    );
  }
}

/// 证据原文引用块：左侧竹青色竖线 + 斜体弱色文本。
class _EvidenceQuote extends StatelessWidget {
  final String text;
  const _EvidenceQuote({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 3,
            height: 16,
            margin: const EdgeInsets.only(top: 2, right: 8),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(AppRadius.xs),
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12,
                height: 1.5,
                color: AppColors.textDeep,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── D5-B：症候确认栏（对齐 RN DiagnosisConfirmationBar）──
//
// 状态机：pending → (confirmed | partial | disputed)
// 点击后调用 DiagnosisService.confirmDiagnosis/disputeDiagnosis 落库，
// 并立即切换本地状态展示（即时反馈）。
class _SyndromeConfirmationBar extends ConsumerStatefulWidget {
  final DiagnosisSyndromeCard syndrome;
  final String sessionId;

  const _SyndromeConfirmationBar({
    required this.syndrome,
    required this.sessionId,
  });

  @override
  ConsumerState<_SyndromeConfirmationBar> createState() =>
      _SyndromeConfirmationBarState();
}

class _SyndromeConfirmationBarState
    extends ConsumerState<_SyndromeConfirmationBar> {
  /// 当前确认状态（本地内存态；落库到 active_problems）
  String _status = 'pending';
  bool _submitting = false;

  Future<void> _confirm(String level) async {
    if (_submitting) return;
    setState(() => _submitting = true);
    final service = ref.read(diagnosisServiceProvider);
    try {
      await service.confirmDiagnosis(
        widget.sessionId,
        widget.syndrome.syndromeId,
        widget.syndrome.name,
        Severity.fromString(widget.syndrome.severity) ?? Severity.l1,
        level: level,
      );
      if (mounted) setState(() => _status = level);
      // B1：部分认同 → 插入 PartialAgreementCard（反馈表单），让学员补充具体差异。
      // 按钮点击后即切到 _buildStatus，仅能触发一次，无需去重。
      if (level == 'partial' && mounted) {
        try {
          await insertPartialAgreementCard(
            SessionRepository(ref.read(appDatabaseProvider)),
            widget.sessionId,
            widget.syndrome.syndromeId,
            widget.syndrome.name,
            widget.syndrome.severity,
          );
          final messages = await SessionRepository(
            ref.read(appDatabaseProvider),
          ).listMessages(widget.sessionId);
          ref.read(chatStoreProvider.notifier).setMessages(messages);
        } catch (_) {
          // 部分认同卡片写入失败不阻断确认主流程
        }
      }
    } catch (_) {
      // 落库失败不切换状态（保持 pending，用户可重试）
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _dispute() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    final service = ref.read(diagnosisServiceProvider);
    try {
      await service.disputeDiagnosis(
        widget.sessionId,
        widget.syndrome.syndromeId,
        widget.syndrome.name,
      );
      if (mounted) setState(() => _status = 'disputed');
    } catch (_) {
      // 落库失败保持 pending
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: _status == 'pending' ? _buildPending() : _buildStatus(),
    );
  }

  /// pending：提问 + 三个操作按钮
  Widget _buildPending() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '这个诊断符合你的实际情况吗？',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: AppColors.textDeep),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildActionButton(
              label: '认同',
              bg: AppColors.primary,
              fg: AppColors.onPrimary,
              onTap: () => _confirm('confirmed'),
            ),
            const SizedBox(width: 8),
            _buildActionButton(
              label: '部分认同',
              bg: AppColors.background,
              fg: AppColors.l2Text,
              border: AppColors.l2,
              onTap: () => _confirm('partial'),
            ),
            const SizedBox(width: 8),
            _buildActionButton(
              label: '不认同',
              bg: AppColors.background,
              fg: AppColors.l3Text,
              border: AppColors.l3,
              onTap: _dispute,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required String label,
    required Color bg,
    required Color fg,
    Color? border,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      height: 36,
      child: OutlinedButton(
        onPressed: _submitting ? null : onTap,
        style: OutlinedButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          side: border != null ? BorderSide(color: border) : null,
          minimumSize: const Size(70, 36),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        child: _submitting && label == '认同'
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.onPrimary,
                ),
              )
            : Text(label),
      ),
    );
  }

  /// 已确认/质疑：状态行 + 提示文案
  Widget _buildStatus() {
    final (icon, statusText, hint, color) = switch (_status) {
      'confirmed' => (
        Icons.check_circle_outline,
        '已认同',
        '可以开始针对「${widget.syndrome.name}」的练习',
        AppColors.primary,
      ),
      'partial' => (
        Icons.change_circle_outlined,
        '部分认同',
        '建议继续沟通确认',
        AppColors.l2Text,
      ),
      'disputed' => (
        Icons.cancel_outlined,
        '已质疑',
        '诊断已标记为不适用',
        AppColors.l3Text,
      ),
      _ => (Icons.help_outline, '', '', AppColors.textSecondary),
    };

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 6),
            Text(
              statusText,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          hint,
          textAlign: TextAlign.center,
          style: AppTextStyles.noteCaption,
        ),
      ],
    );
  }
}
