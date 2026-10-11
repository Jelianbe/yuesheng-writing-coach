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
import 'thinking_chain.dart';
import 'yue_sheet.dart';
import '../data/repositories/app_state_repository.dart';
import '../data/repositories/diagnosis_repository.dart';
import '../data/repositories/edit_diff_event_repository.dart';
import '../data/repositories/session_repository.dart';
import '../services/decode_guard.dart';
import '../providers/app_providers.dart';
import '../providers/chat_store.dart';
import '../providers/session_providers.dart';
import '../services/message_card_service.dart';
import '../services/student_profile_compute.dart';
import '../services/syndrome_registry.dart';
import '../services/syndrome_tracker.dart';
import '../services/teaching_state_cache.dart';
import '../types/teaching_types.dart';
import 'syndrome_detail_modal.dart';
import 'm2_recall_bar.dart';
import '../theme/app_typography.dart';
import '../config/app_palette.dart';

/// 严重度 → 矿物色 + 文字色
class _SeverityConfig {
  final Color bgColor;
  final Color textColor;
  const _SeverityConfig(this.bgColor, this.textColor);
}

/// 严重度 → 配色（P1-6：const Map 改 **palette 驱动函数**，随主题翻；
/// 未知 key 回退 L1 配色——与原 `_severityMap[s] ?? L1` 调用方语义一致）。
_SeverityConfig _severityConfigFor(AppPalette p, String s) {
  switch (s) {
    case 'L1':
      return _SeverityConfig(p.l1, p.primary); // 竹青淡
    case 'L2':
      return _SeverityConfig(p.l2, p.l2Text); // 矿物黄
    case 'L3':
      return _SeverityConfig(p.l3, p.l3Text); // 矿物红
  }
  return _SeverityConfig(p.l1, p.primary);
}

/// 教学状态 → 色点颜色（批次 45：对齐 RN SyndromeTag P0-3，
/// 教学状态存在时色点优先显示教学状态色，否则回退严重度色）
Color _teachingStateDotColor(BuildContext context, TeachingState state) =>
    switch (state) {
      TeachingState.identified => context.palette.warning, // 刚识别 → 警告色
      TeachingState.inProgress => context.palette.primaryDeep, // 训练中 → 信息竹青
      TeachingState.consolidating => context.palette.primary, // 趋稳中 → 成功竹青
      TeachingState.mastered => context.palette.disabledText, // 已掌握 → 禁用灰
    };

/// 卡片默认文案
/// 注意：不用 record 类型，因为 record 的字段访问不能出现在 const 表达式中
class _CardText {
  static const String headerTitle = '本次诊断';
  static const String problemSuffix = ' 个问题';
  static const String evidenceLabel = '证据：';

  /// 症候教学解释行标签（批次 N10）。
  static const String whyLabel = '为什么：';
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

  /// 本轮教学焦点理由（teaching_plan.focus_reason，批次 D-B）。
  ///
  /// 数据来源：`DiagnosisResultCardPayload.focusReason` ← `ParsedDiagnosis
  /// .focusReason` ← AI 输出的 `teaching_plan.focus_reason`。
  /// 为空时「诊断依据」链不含「归因」步骤——不编造理由。
  final String? focusReason;

  /// D5-B：所属会话 ID。非空时每个症候详情块底部渲染确认栏
  /// （对齐 RN DiagnosisConfirmationBar：认同/部分认同/不认同）
  final String? sessionId;

  /// ADR-C132 批3（anchor_ack）：诊断所属章节 ID（埋点「确认指认」用）。
  /// 未传时按 sessionId 反查（见 _DiagnosisCardState._chapterId）。
  final String? chapterId;

  /// ADR-C132 批3（anchor_ack）：诊断消息 ID（埋点关联触发反馈用）。
  final String? messageId;

  const DiagnosisCard({
    super.key,
    required this.syndromeCount,
    required this.syndromes,
    required this.suggestedActions,
    required this.confidence,
    this.defaultExpanded = false,
    this.focusReason,
    this.sessionId,
    this.chapterId,
    this.messageId,
  });

  /// 便利构造：从 Message.content 的 JSON 解析 payload 渲染
  /// 由 MessageList message_type='diagnosis_result' 分支直接调用
  static DiagnosisCard fromMessageContent(
    String content, {
    Key? key,
    String? sessionId,
    String? messageId,
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
        focusReason: payload.focusReason,
        sessionId: sessionId,
        messageId: messageId,
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
        messageId: messageId,
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

  /// ADR-C132 批3（anchor_ack）：诊断所属章节 ID（未显式传入时按
  /// sessionId 反查）；空 = 埋点不可用（卡片渲染不受影响）。
  String _chapterId = '';

  /// 已确认指认的证据文本集合（会话级确认态，只读内存，不跨轮次）。
  final Set<String> _acknowledgedEvidence = {};

  @override
  void initState() {
    super.initState();
    _loadTeachingStates();
    _loadTrends();
    _resolveChapterId();
  }

  /// ADR-C132 批3：章节 ID 反查（session → chapter）。失败静默留 ''。
  Future<void> _resolveChapterId() async {
    if (widget.chapterId != null && widget.chapterId!.isNotEmpty) {
      _chapterId = widget.chapterId!;
      return;
    }
    final sid = widget.sessionId;
    if (sid == null || sid.isEmpty) return;
    try {
      final db = ref.read(appDatabaseProvider);
      final row = await (db.select(
        db.sessions,
      )..where((t) => t.id.equals(sid))).getSingleOrNull();
      if (!mounted) return;
      _chapterId = row?.chapterId ?? '';
    } catch (_) {
      // 反查失败不阻断卡片渲染（埋点降级为不可用）。
    }
  }

  /// ADR-C132 批3（anchor_ack）：确认指认一条证据 → 记录事件。
  /// 失败仅 debugPrint 留痕，绝不阻断 UI。
  Future<void> _acknowledgeEvidence(String evidenceText) async {
    final sid = widget.sessionId;
    if (sid == null || sid.isEmpty || _chapterId.isEmpty) return;
    setState(() => _acknowledgedEvidence.add(evidenceText));
    try {
      await EditDiffEventRepository(
        ref.read(appDatabaseProvider),
      ).recordAnchorAcknowledged(
        sessionId: sid,
        chapterId: _chapterId,
        messageId: widget.messageId,
        anchorText: evidenceText,
      );
    } catch (e) {
      debugPrint('[edit_diff] anchor_ack 埋点失败（不阻断）: $e');
    }
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

  _SeverityConfig _sev(String s) => _severityConfigFor(context.palette, s);

  @override
  Widget build(BuildContext context) {
    // 卡片：#F2F4F2 + 左 4dp 竹青条
    return Container(
      margin: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          decoration: BoxDecoration(
            color: context.palette.surface,
            border: Border.fromBorderSide(
              BorderSide(color: context.palette.border),
            ),
          ),
          child: Row(children: [Expanded(child: _buildCardBody())]),
        ),
      ),
    );
  }

  /// 卡片主体：Header + 标签行 + 展开详情（R-019 清偿拆出）。
  Widget _buildCardBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(),
        _buildTagRow(),
        // P1-7：常驻弱提示——条目≠总评（prompt 里只写给模型听，UI 反而渲染成
        // 「严重度评估」让学员当成整篇总评）。
        _buildNotOverallHint(),
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
                Divider(height: 1, color: context.palette.border),
                const SizedBox(height: 12),
                _buildReasoningSection(),
                const SizedBox(height: 12),
                _buildSyndromesDetail(),
                if (widget.suggestedActions.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _buildRewriteBlock(),
                ],
                // 读者层弱提示：题材/受众/可读性超出文本诊断范围，恒显在详情末尾。
                _buildReaderLayerHint(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── 诊断依据区（批次 C：ConfidenceBar + ThinkingChain 竹青化接入）──
  /// 展开详情顶部：归因（焦点理由）+ 诊断信心置信条 + 诊断依据步骤链（默认折叠）。
  ///
  /// 批次 N10：`focus_reason` 原埋在「卡片展开 + 诊断依据链展开」两重折叠内，
  /// 走查实测需 **2 次点击**才可见（`.ai/reports/2026-09-18-N10-走查.md` §2.8）。
  /// 现提到展开区首行直接渲染 ⇒ 折叠层数归零（展开卡片即见）。
  Widget _buildReasoningSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_focusReasonText != null) ...[
          _buildFocusReasonBlock(),
          const SizedBox(height: AppSpacing.md),
        ],
        ThinkingChain(title: '诊断依据', steps: _buildDiagnosisSteps()),
      ],
    );
  }

  /// 归因块：本轮教学焦点理由（`teaching_plan.focus_reason`）。
  ///
  /// 语义：AI 定义为「为什么**选这个 focus**（一句话）」——是教学焦点的
  /// **选择**理由，而非「该症候为何被判定存在」（后者由每症候 `explanation`
  /// 承担）。故它独立于「诊断依据」推理链渲染，不再充当链的首步
  /// （原挂法属语义借用，见走查报告 §2.5）。文案仍沿用「归因」不引入新术语。
  Widget _buildFocusReasonBlock() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '归因',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: context.palette.textDeep,
          ),
        ),
        const SizedBox(height: 4),
        Text(_focusReasonText!, style: context.text.caption),
      ],
    );
  }

  /// focus_reason 的展示文本（null = 不渲染归因步骤）。
  ///
  /// 长度上限 160 字：该字段由 AI 自由生成，实测偶有长段落，
  /// 在折叠步骤行里会撑爆一行。截断而非改写——保留原文前 160 字
  /// 加省略号，不做摘要（R-009：不替用户改写 AI 的原话）。
  String? get _focusReasonText {
    final raw = widget.focusReason?.trim();
    if (raw == null || raw.isEmpty) return null;
    return raw.length <= 160 ? raw : '${raw.substring(0, 160)}…';
  }

  /// 依据链主干 4 步（全部派生自 payload 既有字段，R-019 拆出）。
  List<ThinkingStep> _buildDiagnosisSteps() {
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
        label: '各问题相对轻重',
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
  Widget _buildHeader() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _toggleExpanded,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.sm,
          ),
          child: Row(
            children: [
              Icon(
                Icons.analytics_outlined,
                size: 18,
                color: context.palette.textPrimary,
              ),
              const SizedBox(width: 8),
              Text(
                _CardText.headerTitle,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: context.palette.textPrimary,
                ),
              ),
              const Spacer(),
              _buildHeaderMeta(),
            ],
          ),
        ),
      ),
    );
  }

  /// Header 尾部：问题数 · 信心 · 展开箭头（R-019 清偿拆出）。
  Widget _buildHeaderMeta() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${widget.syndromeCount}${_CardText.problemSuffix}',
          style: context.text.subBody,
        ),
        const SizedBox(width: 8),
        RotationTransition(
          turns: Tween(begin: 0.0, end: 0.5).animate(
            CurvedAnimation(parent: _expandAnim, curve: Curves.easeOut),
          ),
          child: Icon(
            Icons.keyboard_arrow_down,
            size: 20,
            color: context.palette.textTertiary,
          ),
        ),
      ],
    );
  }

  /// P1-7：常驻弱提示——「逐条问题点，不是整篇总评」。
  Widget _buildNotOverallHint() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 4, AppSpacing.lg, 0),
      child: Text(
        '以下是逐条问题点，不是对整篇的总评',
        style: context.text.caption.copyWith(
          color: context.palette.textTertiary,
          fontSize: 11,
        ),
      ),
    );
  }

  // ── 读者层弱提示：题材选择/受众匹配/可读性不在文本诊断覆盖内 ──
  /// 视觉刻意做弱（灰字、小一号、Divider 隔开），不与正常症候条目抢注意力。
  Widget _buildReaderLayerHint() {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Divider(height: 1, color: context.palette.border),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '读者层 · 需自行判断',
            style: context.text.caption.copyWith(
              color: context.palette.textTertiary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '以上是文本层面的问题。题材选择、受众匹配、读者会不会想读下去——这部分我覆盖不了，请自行判断。',
            style: context.text.caption.copyWith(
              color: context.palette.textTertiary,
              fontSize: 11,
              height: 1.4,
            ),
          ),
        ],
      ),
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
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: context.palette.l1,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Text(
              _CardText.emptyHint,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: context.palette.primary,
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
        ? _teachingStateDotColor(context, teachingState)
        : cfg.textColor;
    return InkWell(
      // sessionId 非空时可点击打开症候详情弹层（对齐 RN SyndromeTag onPress）
      onTap: widget.sessionId != null ? () => _openSyndromeDetail(s) : null,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
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
          margin: const EdgeInsets.only(right: AppSpacing.xs),
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
              fontSize: 11,
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
      return Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Text(_CardText.emptyHint, style: context.text.subBody),
      );
    }

    // ADR-C146：按呈现分组（描写/剧情/角色/逻辑）分组展示，替换原先
    // 「按 severity 粗分」（L2/L3=结构层、L1=笔误/用词层）的伪分类。
    // 分组由 syndrome_id 静态反查 presentationGroup，模型不输出此字段。
    // 未收录号（反查 null）兜底归入「描写」组，保证不丢条目。
    final groups = <PresentationGroup, List<DiagnosisSyndromeCard>>{
      for (final g in PresentationGroup.values) g: [],
    };
    for (final s in widget.syndromes) {
      final g =
          presentationGroupOf(s.syndromeId) ?? PresentationGroup.description;
      groups[g]!.add(s);
    }

    final children = <Widget>[];
    // 展示顺序：逻辑 → 剧情 → 角色 → 描写（逻辑链最该先修，描写最轻）
    const order = [
      PresentationGroup.logic,
      PresentationGroup.plot,
      PresentationGroup.character,
      PresentationGroup.description,
    ];
    for (var i = 0; i < order.length; i++) {
      final items = groups[order[i]]!;
      if (items.isEmpty) continue;
      if (children.isNotEmpty) {
        children.add(_buildSectionDivider(order[i].label));
      }
      _appendBlocks(children, items);
    }

    return Column(children: children);
  }

  Widget _buildSyndromeBlock(DiagnosisSyndromeCard s) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      _SyndromeBlock(
        syndrome: s,
        tracked: _trends[s.syndromeId],
        // ADR-C132 批3（anchor_ack）：确认指认交互下传（无诊断上下文
        // 时 onAcknowledge = null，证据块不渲染确认入口）。
        acknowledgedEvidence: _acknowledgedEvidence,
        onAcknowledgeEvidence:
            (widget.sessionId != null && _chapterId.isNotEmpty)
            ? _acknowledgeEvidence
            : null,
      ),
      if (widget.sessionId != null) ...[
        const SizedBox(height: 8),
        _SyndromeConfirmationBar(syndrome: s, sessionId: widget.sessionId!),
      ],
      // ADR-C133 批2（M2）：复述根因入口。仅在有诊断上下文（sessionId +
      // chapterId）且该症候有「为什么」根因解释时渲染——无解释不编造根因。
      if (widget.sessionId != null &&
          _chapterId.isNotEmpty &&
          (s.explanation?.trim().isNotEmpty ?? false)) ...[
        const SizedBox(height: 8),
        M2RecallBar(
          syndromeId: s.syndromeId,
          syndromeName: s.name,
          rootCauseText: s.explanation!.trim(),
          sessionId: widget.sessionId!,
          chapterId: _chapterId,
          messageId: widget.messageId,
        ),
      ],
    ],
  );

  Widget _buildSectionDivider(String label) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: Divider(height: 1, color: context.palette.border),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: context.palette.textTertiary,
                  ),
                ),
              ),
              Expanded(
                child: Divider(height: 1, color: context.palette.border),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  void _appendBlocks(List<Widget> out, List<DiagnosisSyndromeCard> items) {
    for (var i = 0; i < items.length; i++) {
      out.add(_buildSyndromeBlock(items[i]));
      if (i < items.length - 1) out.add(const SizedBox(height: 12));
    }
  }

  // ── 改写建议块：品牌竹青 #E8F0EE 底 + 左竹青 #2D5A52 条 ──
  Widget _buildRewriteBlock() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        decoration: BoxDecoration(color: context.palette.l1),
        child: Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _CardText.rewriteTitle,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: context.palette.textPrimary,
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
    );
  }

  /// 单条改写建议行（序号 + 文本；R-019 清偿拆出）。
  Widget _buildRewriteAction(int index) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: index == widget.suggestedActions.length - 1 ? 0 : AppSpacing.xs,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${index + 1}.',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: context.palette.primary,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              widget.suggestedActions[index],
              style: TextStyle(
                fontSize: 13,
                color: context.palette.textDeep,
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

  /// ADR-C132 批3（anchor_ack）：已确认指认的证据集合 + 确认回调
  ///（null = 无诊断上下文，不渲染确认入口）。
  final Set<String> acknowledgedEvidence;
  final ValueChanged<String>? onAcknowledgeEvidence;

  const _SyndromeBlock({
    required this.syndrome,
    this.tracked,
    this.acknowledgedEvidence = const {},
    this.onAcknowledgeEvidence,
  });

  @override
  State<_SyndromeBlock> createState() => _SyndromeBlockState();
}

class _SyndromeBlockState extends State<_SyndromeBlock> {
  /// 证据原文展开状态（点击「展开证据」切换）。
  bool _evidenceExpanded = false;

  @override
  Widget build(BuildContext context) {
    final cfg = _severityConfigFor(context.palette, widget.syndrome.severity);

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
              _buildNameChip(cfg),
              const SizedBox(height: 8),
              _buildWhyRow(),
              _buildTrendRow(),
              const SizedBox(height: 4),
              _buildEvidenceRow(),
            ],
          ),
        ),
      ],
    );
  }

  /// 症候名小 chip（R-019 清偿：批次 N10 由 build 拆出，为「为什么」行腾额）。
  Widget _buildNameChip(_SeverityConfig cfg) {
    return Container(
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
    );
  }

  /// 教学解释行（批次 N10）：`syndromes[].explanation` —— 该症候
  /// **为什么被判定存在**（AI 定义为「问题描述 + 判断理由」）。
  ///
  /// 该字段此前从未进入卡片 payload，故恒不渲染；接线后**默认展示、不需额外点击**，
  /// 与同块内「证据」行（指出位置）共同构成用户诉求的「指出位置 + 为什么」。
  /// null / 空串时不渲染（数据诚实：不编造理由）。
  ///
  /// 视觉提档（批次 N11，2026-09-18）：原与「证据」正文**同级同色**
  /// （`caption` = 12px + textSecondary）⇒ 独立验证判断「长卡片里易被当作
  /// 辅助说明略过，有重演『接出来了但用户仍不看』的风险」。
  /// 现提为 13px + `textDeep`（深青）+ `height: 1.5`，成为症候块内的**视觉次强项**
  /// （仅弱于严重度 chip），且 13px 与本卡片既有次级档一致
  /// （header meta / 改写建议 / 本文件 1087 行的 13px textDeep 散文行）。
  Widget _buildWhyRow() {
    final why = widget.syndrome.explanation?.trim();
    if (why == null || why.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _CardText.whyLabel,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: context.palette.textDeep,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            why,
            style: context.text.subBody.copyWith(
              color: context.palette.textDeep,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  /// 趋势行：仅 improving/worsening 显示（stable 不制造噪音；
  /// 诚实派生自跨轮次严重度差分，无数据时不显示）。
  Widget _buildTrendRow() {
    final tracked = widget.tracked;
    if (tracked == null) return const SizedBox.shrink();
    final (icon, text, color) = switch (tracked.trend) {
      'improving' => ('↗', '较上次诊断好转', context.palette.primary),
      'worsening' => ('↘', '较上次诊断加重', context.palette.danger),
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
        Text(
          _CardText.evidenceLabel,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: context.palette.textDeep,
          ),
        ),
        const SizedBox(height: 4),
        if (count == 0)
          Text(_CardText.noEvidence, style: context.text.caption)
        else if (evidence.isNotEmpty)
          _buildEvidenceToggle(evidence, count)
        else
          // 旧版数据仅有计数、无证据原文：不承诺可查看（批次80 M1 教训延续）
          Text(
            '（共 $count 处证据）',
            style: TextStyle(
              fontSize: 12,
              color: context.palette.textDeep,
              fontStyle: FontStyle.italic,
            ),
          ),
        if (_evidenceExpanded && evidence.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final e in evidence)
            _EvidenceQuote(
              text: e,
              // ADR-C132 批3（anchor_ack）：确认指认 = 学员确认教练
              // 指认的片段位置（埋点；无诊断上下文时静默不可用）。
              acknowledged: widget.acknowledgedEvidence.contains(e),
              onAcknowledge: widget.onAcknowledgeEvidence == null
                  ? null
                  : () => widget.onAcknowledgeEvidence!(e),
            ),
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
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: context.palette.primary,
            ),
          ),
          const SizedBox(width: 4),
          Icon(
            Icons.keyboard_arrow_down,
            size: 14,
            color: context.palette.primary,
          ),
        ],
      ),
    );
  }
}

/// 证据原文引用块：左侧竹青色竖线 + 斜体弱色文本。
/// ADR-C132 批3（anchor_ack）：可选「确认指认」动作（学员确认教练
/// 指认的片段 → 埋点；已确认态显示勾选，不重复记录）。
class _EvidenceQuote extends StatelessWidget {
  final String text;
  final bool acknowledged;
  final VoidCallback? onAcknowledge;

  const _EvidenceQuote({
    required this.text,
    this.acknowledged = false,
    this.onAcknowledge,
  });

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
              color: context.palette.primary,
              borderRadius: BorderRadius.circular(AppRadius.xs),
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: context.palette.textDeep,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
          if (onAcknowledge != null) ...[
            const SizedBox(width: 8),
            _buildAcknowledgeAction(context),
          ],
        ],
      ),
    );
  }

  /// R-019 拆出：「确认指认」动作（未确认态可点；已确认态显示勾选，不重复记录）。
  Widget _buildAcknowledgeAction(BuildContext context) {
    return InkWell(
      onTap: acknowledged ? null : onAcknowledge,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: acknowledged
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.check_circle,
                    size: 14,
                    color: context.palette.primary,
                  ),
                  const SizedBox(width: 2),
                  Text(
                    '已确认',
                    style: TextStyle(
                      fontSize: 11,
                      color: context.palette.primary,
                    ),
                  ),
                ],
              )
            : Text(
                '确认指认',
                style: TextStyle(fontSize: 11, color: context.palette.primary),
              ),
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

  @override
  void initState() {
    super.initState();
    _hydrateStatusFromDb();
  }

  /// 交互批 #8：从 active_problems.confirmation_status **回灌裁决态**。
  /// 缺陷本体 = `_status` 硬编码 pending、重建后已裁决的症候会再次提问并允许
  /// 重复裁决；重复质疑累积 `shouldUnlockSyndrome` 的「≥2 质疑」计数 ⇒ 是
  /// 教学状态机的数据污染，不只是 UX。
  /// 已知近似：「部分认同」落库同为 'confirmed'（区分仅存于留痕字段 level）
  /// ⇒ 重进后 partial 显示为「已认同」——比重新提问诚实，登记为边界。
  Future<void> _hydrateStatusFromDb() async {
    try {
      final problems = await DiagnosisRepository(
        ref.read(appDatabaseProvider),
      ).listActiveProblems(widget.sessionId);
      // 查询期间用户已点击 ⇒ 以本次真实操作优先，不回收
      if (!mounted || _status != 'pending') return;
      final dbStatus = problems
          .where((p) => p.syndromeId == widget.syndrome.syndromeId)
          .firstOrNull
          ?.confirmationStatus;
      final mapped = switch (dbStatus) {
        'confirmed' => 'confirmed',
        'rejected' => 'disputed',
        _ => null, // suspected / ignored / 无行 ⇒ 维持 pending，照常提问
      };
      if (mapped != null) setState(() => _status = mapped);
    } catch (e, st) {
      // hydrate 失败 = 退回旧行为（多问一次，不崩不猜）——留痕可追溯
      logSilentDegrade(
        operation: 'hydrateConfirmationStatus',
        error: e,
        stack: st,
      );
    }
  }

  /// 失败反馈单一出口（R-019 真分解：确认/质疑/插入三路降级共用）。
  /// 纪律 = NN/g「点了就要被告知为什么没成」+ 文案必须与「状态未切换、可重试」
  /// 的真实行为一致，不制造「已生效」假象。
  void _showFailureSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

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
        } catch (e, st) {
          // 部分认同卡片插入失败**不阻断确认主流程**（确认本身已落库成功）——
          // 但必须留痕 + 告知用户降级去向（否则「部分认同」看起来像只生效了一半）。
          logSilentDegrade(
            operation: 'insertPartialAgreementCard',
            error: e,
            stack: st,
          );
          _showFailureSnack('部分认同已记录；反馈卡片暂不可用，可在对话中直接补充差异');
        }
      }
    } catch (e, st) {
      // 落库失败不切换状态（保持 pending，可重试）。R-028：静默降级必须留痕；
      // NN/g《Disabled/失败》判据：用户点了就要告诉他为什么没成——否则与「死按钮」不可分。
      logSilentDegrade(operation: 'confirmDiagnosis', error: e, stack: st);
      _showFailureSnack('确认失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// 质疑前置（2026-09-29 反馈修复）：必须先说明"哪里不对"再提交异议。
  /// 裸"有异议"一键即拒会被想逃训练的学员滥用，绕开结构层诊断；
  /// 要求补充信息能逼出具体判断，也留痕。
  Future<void> _dispute() async {
    if (_submitting) return;
    final reason = await _showDisputeReasonDialog();
    if (reason == null || reason.trim().isEmpty) return; // 取消或不填 ⇒ 不提交
    // P0-3：最小长度校验——「不对」二字即过等于没填，逼不出具体判断也无留痕价值。
    if (reason.trim().length < 5) {
      _showFailureSnack('请写具体一些（至少 5 个字），说明哪里不对');
      return;
    }
    await _commitDispute(reason.trim());
  }

  Future<String?> _showDisputeReasonDialog() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('提交异议'),
        content: TextField(
          controller: controller,
          maxLines: 3,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '说明你觉得哪里不对（具体到哪一句 / 哪个判断）',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('提交异议'),
          ),
        ],
      ),
    );
  }

  Future<void> _commitDispute(String reason) async {
    if (_submitting) return;
    setState(() => _submitting = true);
    final service = ref.read(diagnosisServiceProvider);
    try {
      await service.disputeDiagnosis(
        widget.sessionId,
        widget.syndrome.syndromeId,
        widget.syndrome.name,
        reason: reason,
      );
      if (mounted) setState(() => _status = 'disputed');
    } catch (e, st) {
      // 质疑落库失败保持 pending（可重试）——留痕 + 用户可见失败反馈（同确认栏判据）。
      logSilentDegrade(operation: 'disputeDiagnosis', error: e, stack: st);
      _showFailureSnack('提交异议失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// P1-1：二次确认弹窗——明示永久静音语义 + 恢复路径（成长页）。
  /// 此前是零理由一键暗门，现加确认；定位为「类型声明」操作，不需要理由。
  Future<bool> _confirmDismissForever() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('永久静音此问题？'),
        content: const Text(
          '将不再主动报这个问题（跨会话生效）。\n'
          '这是你的写作类型声明，不需要写理由。\n'
          '以后想恢复，可在「成长」页重新开启。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('以后都别报'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  /// 诊断编辑器：「不适用，以后别报」——把症候 ID 写入全局 disabledIds，
  /// 同时把当前这条标 disputed。用户不是惩罚症候，是声明自己的写作类型。
  Future<void> _dismissForever() async {
    if (_submitting) return;
    final confirmed = await _confirmDismissForever();
    if (!confirmed) return;
    setState(() => _submitting = true);
    try {
      final repo = AppStateRepository(ref.read(appDatabaseProvider));
      final prefs = await repo.getDiagnosisPrefs() ?? DiagnosisPrefs();
      final updated = prefs.copyWith(
        disabledIds: {...prefs.disabledIds, widget.syndrome.syndromeId},
      );
      await repo.setDiagnosisPrefs(updated);
      // 同时把当前这条标 disputed（别留在 active_problems）
      await ref
          .read(diagnosisServiceProvider)
          .disputeDiagnosis(
            widget.sessionId,
            widget.syndrome.syndromeId,
            widget.syndrome.name,
          );
      if (mounted) setState(() => _status = 'dismissed');
    } catch (e, st) {
      logSilentDegrade(
        operation: 'dismissSyndromeForever',
        error: e,
        stack: st,
      );
      _showFailureSnack('操作失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.palette.background,
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
        Text(
          '这个诊断符合你的实际情况吗？',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: context.palette.textDeep),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildActionButton(
              label: '认同',
              bg: context.palette.primary,
              fg: context.palette.onPrimary,
              onTap: () => _confirm('confirmed'),
            ),
            const SizedBox(width: 8),
            _buildActionButton(
              label: '部分认同',
              bg: context.palette.background,
              fg: context.palette.l2Text,
              border: context.palette.l2,
              onTap: () => _confirm('partial'),
            ),
            const SizedBox(width: 8),
            _buildActionButton(
              label: '不认同',
              bg: context.palette.background,
              fg: context.palette.l3Text,
              border: context.palette.l3,
              onTap: _dispute,
            ),
          ],
        ),
        const SizedBox(height: 4),
        _buildDismissLink(),
      ],
    );
  }

  Widget _buildDismissLink() {
    return TextButton(
      onPressed: _submitting ? null : _dismissForever,
      style: TextButton.styleFrom(
        foregroundColor: context.palette.l3Text,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: const Text('这个问题不适用我，以后别报', style: TextStyle(fontSize: 12)),
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
            ? SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: context.palette.onPrimary,
                ),
              )
            : Text(label),
      ),
    );
  }

  /// 已确认/质疑：状态行 + 提示文案
  (IconData, String, String, Color) _statusDisplay() {
    return switch (_status) {
      'confirmed' => (
        Icons.check_circle_outline,
        '已认同',
        '可以开始针对「${widget.syndrome.name}」的练习',
        context.palette.primary,
      ),
      'partial' => (
        Icons.change_circle_outlined,
        '部分认同',
        '建议继续沟通确认',
        context.palette.l2Text,
      ),
      'disputed' => (
        Icons.cancel_outlined,
        '已质疑',
        '诊断已标记为不适用',
        context.palette.l3Text,
      ),
      'dismissed' => (
        Icons.do_not_disturb_on_outlined,
        '已关闭',
        '以后不再提示（成长页可恢复）',
        context.palette.l3Text,
      ),
      _ => (Icons.help_outline, '', '', context.palette.textSecondary),
    };
  }

  Widget _buildStatus() {
    final (icon, statusText, hint, color) = _statusDisplay();
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
        Text(hint, textAlign: TextAlign.center, style: context.text.caption),
      ],
    );
  }
}
