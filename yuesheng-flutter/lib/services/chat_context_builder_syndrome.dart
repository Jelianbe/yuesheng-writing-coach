// ─────────────────────────────────────────────────────────────
// chat_context_builder 主题分组拆分：chat_context_builder_syndrome.dart（R-019 ≤300 行）
// 活跃症候上下文：ActiveFocusContext/FocusSource/SyndromeEvidence/ActiveSyndromeView/buildStructuredSyndromeContext。逐字迁移自 chat_context_builder.dart，零行为变更。
// ─────────────────────────────────────────────────────────────
part of 'chat_context_builder.dart';
// ─── 活跃症候上下文（分级注入） ──────────────────────────────

/// 教学焦点上下文（focus-resolver 输出）
class ActiveFocusContext {
  final String? focusId;
  final FocusSource source;
  final String reason;

  const ActiveFocusContext({
    required this.focusId,
    required this.source,
    required this.reason,
  });
}

/// 焦点来源
enum FocusSource {
  aiSuggested('ai_suggested'),
  userOverride('user_override'),
  fallback('fallback'),
  none('none');

  final String value;
  const FocusSource(this.value);
}

/// 症候证据信息
class SyndromeEvidence {
  final List<String> evidence;
  final String explanation;
  final int diagnosedAt;

  const SyndromeEvidence({
    required this.evidence,
    required this.explanation,
    required this.diagnosedAt,
  });
}

/// 活跃症候视图（用于上下文构建）
class ActiveSyndromeView {
  final String syndromeId;
  final String syndromeName;
  final Severity severity;
  final ConfirmationStatus? confirmationStatus;

  const ActiveSyndromeView({
    required this.syndromeId,
    required this.syndromeName,
    required this.severity,
    this.confirmationStatus,
  });
}

/// 构建结构化的 L3 症候详情上下文（按症候组织，合并症候定义+证据+技法）
///
/// P2-v3 B4：按 focus 分级注入（设计文档 5.6）：
/// - focus 症候：完整 L3 定义 + 完整技法 + evidence
/// - 非 focus 症候：ID + 名称 + severity + 确认状态 + 一句诊断理由（无 evidence、无 L3、无技法）
/// - activeFocus 为 null：向后兼容，全部完整注入（旧调用方）
/// - activeFocus.focusId 为 null：无激活 focus，全部简化注入
///
/// 注意：批次 22 已接入症候/技法知识库（syndrome_knowledge_base / technique_knowledge_base），
/// focus 症候的 L3 定义和技法内容由 `_getSyndromeContent` / `_getTechniqueContent` 真实注入。
///
/// 2026-08-18 批次（文笔画像→技法旁路路由）：新增可选 [styleTechniqueSection]，
/// 由调用方经 style_technique_router 产出后传入，追加在症候段之后（null=不注入）。
String buildStructuredSyndromeContext(
  List<ActiveSyndromeView> problems, {
  Map<String, SyndromeEvidence>? evidenceMap,
  ActiveFocusContext? activeFocus,
  String? styleTechniqueSection,
}) {
  const severityRank = {Severity.l3: 3, Severity.l2: 2, Severity.l1: 1};

  final sortedProblems = List<ActiveSyndromeView>.from(problems)
    ..sort(
      (a, b) =>
          (severityRank[b.severity] ?? 0) - (severityRank[a.severity] ?? 0),
    );

  // 判定是否启用分级注入
  final hasActiveFocus = activeFocus != null;
  final focusId = hasActiveFocus ? activeFocus.focusId : null;
  final focusEnabled = focusId != null;

  // focus 症候排在最前（若启用分级注入）
  if (focusEnabled) {
    final fid = focusId;
    sortedProblems.sort((a, b) {
      final aFocus = a.syndromeId == fid ? 1 : 0;
      final bFocus = b.syndromeId == fid ? 1 : 0;
      if (aFocus != bFocus) return bFocus - aFocus;
      return (severityRank[b.severity] ?? 0) - (severityRank[a.severity] ?? 0);
    });
  }

  final sections = <String>[];

  for (final p in sortedProblems) {
    final confirmLabel = p.confirmationStatus == ConfirmationStatus.confirmed
        ? '已确认'
        : '待确认';
    final isFocus = focusEnabled && p.syndromeId == focusId;

    if (isFocus) {
      // focus 症候：完整 L3 定义 + 完整技法 + evidence
      // 2026-08-08 批次 22 步骤②：接入症候/技法知识库
      // 真源：syndrome-diagnosis.ts getSyndromeContent / technique-library.ts getTechniquesBySyndrome
      // 训练侧完整教学知识（training-templates-v2 getTrainingContent）由 chat_service
      // 按当前教学焦点在 L3 阶段单独注入（chat_service.dart ~L917），此处不重复
      final syndromeContent = getSyndromeContent([p.syndromeId]);
      final techniqueSection = getTechniquesBySyndrome([p.syndromeId]);

      final evidence = evidenceMap?[p.syndromeId];
      String evidenceText = '';
      if (evidence != null && evidence.evidence.isNotEmpty) {
        final truncated = evidence.evidence
            .take(2)
            .map((e) => e.length > 60 ? '${e.substring(0, 60)}...' : e)
            .join(' / ');
        evidenceText = '\n> 文本证据："$truncated"\n';
      }

      sections.add(
        '### ★ 当前教学焦点 ${p.syndromeId} ${p.syndromeName} [${p.severity.value}] [$confirmLabel]\n$evidenceText\n$syndromeContent$techniqueSection',
      );
    } else if (hasActiveFocus) {
      // 非 focus 症候（分级注入模式）：简化呈现
      // ID + 名称 + severity + 确认状态 + 一句诊断理由（无 evidence、无 L3、无技法）
      final evidence = evidenceMap?[p.syndromeId];
      final reason = evidence?.explanation != null
          ? _truncateToOneLine(evidence!.explanation, 80)
          : '';
      final reasonText = reason.isNotEmpty ? '：$reason' : '';
      sections.add(
        '- ${p.syndromeId} ${p.syndromeName} [${p.severity.value}] [$confirmLabel]$reasonText',
      );
    } else {
      // 向后兼容（未传 activeFocus）：完整注入（旧逻辑）
      // 2026-08-08 批次 22 步骤②：接入症候/技法知识库（训练知识由 chat_service L3 单独注入）
      final syndromeContent = getSyndromeContent([p.syndromeId]);
      final techniqueSection = getTechniquesBySyndrome([p.syndromeId]);

      final evidence = evidenceMap?[p.syndromeId];
      String evidenceText = '';
      if (evidence != null && evidence.evidence.isNotEmpty) {
        final truncated = evidence.evidence
            .take(2)
            .map((e) => e.length > 60 ? '${e.substring(0, 60)}...' : e)
            .join(' / ');
        evidenceText = '\n> 文本证据："$truncated"\n';
      }

      sections.add(
        '### ${p.syndromeId} ${p.syndromeName} [${p.severity.value}] [$confirmLabel]\n$evidenceText\n$syndromeContent$techniqueSection',
      );
    }
  }

  // 构建头部说明
  String header;
  if (focusEnabled) {
    final af = activeFocus!;
    final sourceLabel = {
      FocusSource.aiSuggested: 'AI 建议',
      FocusSource.userOverride: '学员选择',
      FocusSource.fallback: '系统兜底',
      FocusSource.none: '无',
    }[af.source]!;
    header =
        '## 活跃症候详情（教学焦点：$focusId，来源：$sourceLabel）\n\n'
        '当前教学焦点已激活，下方★标记的症候注入完整定义、技法与证据，请围绕该症候展开教学。\n'
        '其余症候仅提供概览（无完整定义、无证据、无技法），供你了解全局，不要主动展开。\n\n'
        '学员确认状态标注在方括号中：[待确认] 或 [已确认]。';
  } else if (hasActiveFocus) {
    header =
        '## 活跃症候概览（未激活教学焦点）\n\n'
        '本轮未激活教学焦点，仅提供症候概览（无完整定义、无证据、无技法）。\n'
        '请在下一轮 teaching_plan.current_teaching_focus_id 中明确教学重点。';
  } else {
    header =
        '## 活跃症候详情（按严重度排序）\n\n'
        '以下是本会话中已识别的文本特征及详细说明。每条特征包含证据、定义和对应教学方法。\n'
        '学员确认状态标注在方括号中：[待确认] 或 [已确认]。';
  }

  final body = '$header\n\n---\n\n${sections.join('\n\n---\n\n')}';

  // 2026-08-18 批次：文笔画像→技法旁路段（无候选时调用方传 null，零成本）
  if (styleTechniqueSection == null || styleTechniqueSection.isEmpty) {
    return body;
  }
  return '$body\n\n---\n\n$styleTechniqueSection';
}

