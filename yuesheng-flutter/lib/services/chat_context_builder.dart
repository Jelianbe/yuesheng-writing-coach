/// Chat 上下文构建工具
///
/// 从 chat-service.ts 拆出，负责构建注入 system prompt 的各类上下文：
/// - 引用内容（作品/章节/文件）预算分配与截断
/// - 附属文件上下文格式化
/// - 活跃症候上下文格式化（分级注入）
/// - 智能截断工具
///
/// 真源：yuesheng-android/src/services/chat-context-builder.ts
library;

import 'dart:convert';

import 'package:writingcoach/config/shared_constants.dart';
import 'package:writingcoach/data/repositories/reference_repository.dart';
import 'package:writingcoach/services/conflict_detector.dart';
import 'package:writingcoach/services/dialogue_tag_detector.dart';
import 'package:writingcoach/services/event_causality_detector.dart';
import 'package:writingcoach/services/grammar_lexical_detector.dart';
import 'package:writingcoach/services/subplot_closure_detector.dart';
import 'package:writingcoach/services/syndrome_knowledge_base.dart';
import 'package:writingcoach/services/technique_knowledge_base.dart';
import 'package:writingcoach/types/teaching_types.dart';

// ─── 智能截断 ─────────────────────────────────────────────────

/// 智能截断：保留首尾，中间省略
///
/// 当文本超过 maxChars 时，保留前 [ContextBudget.truncateFrontRatio] 比例和尾部，
/// 中间用省略标记替代。maxChars 过小时直接截断。
String smartTruncate(String text, int maxChars) {
  if (text.length <= maxChars) return text;
  if (maxChars <= ContextBudget.smartTruncateMinThreshold) {
    return text.substring(0, maxChars);
  }

  final omittedEstimate = text.length - maxChars;
  final ellipsis = '\n...（省略 $omittedEstimate 字）\n';
  final ellipsisLen = ellipsis.length;
  final available = maxChars - ellipsisLen;

  final frontLen = (available * ContextBudget.truncateFrontRatio).floor();
  final backLen = available - frontLen;
  final actualOmitted = text.length - frontLen - backLen;
  final finalEllipsis = '\n...（省略 $actualOmitted 字）\n';

  return text.substring(0, frontLen) +
      finalEllipsis +
      text.substring(text.length - backLen);
}

// ─── 附属文件上下文 ───────────────────────────────────────────

/// 附属文件信息
class AttachedFileInfo {
  final String fileName;
  final String fileRole; // outline | material | normal
  final String content;

  const AttachedFileInfo({
    required this.fileName,
    required this.fileRole,
    required this.content,
  });
}

/// 附属文件上下文格式化（V3）。
///
/// 在 15K 字符预算内，将书籍下所有文件的完整内容注入 system prompt。
/// 超过预算时按文件数均分截断。
String? formatAttachedFilesContext(List<AttachedFileInfo> files) {
  if (files.isEmpty) return null;

  const budget = ContextBudget.totalBudget;
  const header = '\n## 当前书籍文件\n\n以下是你所关联书籍下的参考文件。你可以直接参考这些内容来更好地帮助用户。\n\n';
  // 取 max(minPerFileBudget, 均分预算)；files 非空已在上方 return
  final evenShare = (budget - header.length) ~/ files.length;
  final actualPerFile = evenShare > ContextBudget.minPerFileBudget
      ? evenShare
      : ContextBudget.minPerFileBudget;

  final body = StringBuffer();
  for (final f in files) {
    final roleLabel = f.fileRole == 'outline'
        ? '大纲'
        : f.fileRole == 'material'
        ? '素材'
        : '常规';
    final truncated = f.content.length > actualPerFile
        ? '${f.content.substring(0, actualPerFile)}\n...(内容已截断)'
        : f.content;
    body.writeln('### ${f.fileName}（$roleLabel）');
    body.writeln('```');
    body.writeln(truncated);
    body.writeln('```');
    body.writeln();
    if (header.length + body.length > budget) break;
  }

  final bodyStr = body.toString();
  return bodyStr.isNotEmpty ? '$header$bodyStr' : null;
}

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
String buildStructuredSyndromeContext(
  List<ActiveSyndromeView> problems, {
  Map<String, SyndromeEvidence>? evidenceMap,
  ActiveFocusContext? activeFocus,
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

  return '$header\n\n---\n\n${sections.join('\n\n---\n\n')}';
}

/// 将文本截断为一行（按句号/分号分割取第一句，超长时追加省略号）
String _truncateToOneLine(String text, int maxLen) {
  final firstSentence = RegExp(r'[。；;\n]').firstMatch(text);
  final first = firstSentence != null
      ? text.substring(0, firstSentence.start)
      : text;
  if (first.length <= maxLen) return first;
  return '${first.substring(0, maxLen)}...';
}

/// 关键词首现片段摘录（O11，批次6 6.5）
///
/// 在正文中定位 keyword 首次出现，返回含前后 padding 上下文的单行片段。
/// 未命中 / 关键词为空 / 正文为空 → 返回 null（降级安全，调用方不输出摘录）。
String? findKeywordExcerpt(
  String content,
  String keyword, {
  int padding = 12,
}) {
  if (keyword.isEmpty || content.isEmpty) return null;
  final start = content.indexOf(keyword);
  if (start < 0) return null;
  final from = (start - padding).clamp(0, content.length);
  final to = (start + keyword.length + padding).clamp(0, content.length);
  final snippet = content.substring(from, to);
  return _truncateAroundKeyword(snippet, keyword, 48);
}

/// 以关键词为锚截断为一行：保留关键词及其所在句（到句末分隔符）。
/// 跨行/跨句时不被关键词之前的句号/换行截断（防摘录不含关键词）；
/// 超长时从句头截断并加省略号。
String _truncateAroundKeyword(String snippet, String keyword, int maxLen) {
  final keyIndex = snippet.indexOf(keyword);
  if (keyIndex < 0) return _truncateToOneLine(snippet, maxLen);
  final tail = snippet.substring(keyIndex + keyword.length);
  final tailEnd = RegExp(r'[。；;\n]').firstMatch(tail);
  final clippedTail = tailEnd != null ? tail.substring(0, tailEnd.start) : tail;
  final head = snippet.substring(0, keyIndex);
  final total = head.length + keyword.length + clippedTail.length;
  if (total > maxLen) {
    final headBudget = maxLen - keyword.length - clippedTail.length;
    if (headBudget <= 0) return keyword; // 极端：仅保留关键词
    if (head.length > headBudget) {
      final trimmedHead = head.substring(head.length - headBudget);
      return '…$trimmedHead$keyword$clippedTail';
    }
  }
  return '$head$keyword$clippedTail';
}

/// 摘录后缀（O11，批次6 6.5）：excerpt 非空 → 「（原文：「…」）」，否则空串
/// （正文反查不可得时安全降级，不输出摘录）
String _excerptSuffix(String? excerpt) {
  if (excerpt == null || excerpt.isEmpty) return '';
  return '（原文：「$excerpt」）';
}

/// 时序矛盾观察上下文（批次66 B62i，A6 首步，挂 F05/P018 补充）
///
/// 输入 conflict_detector 输出的观察项（同属性不同值，带章节/时间维度）。
/// 无观察项 → 返回 null（调用方不注入，零 token 成本）。
/// 注入措辞遵循 A1 约束：只定位不代改、温和提问、软引导非硬拦截。
String? buildConflictObservationsContext(
  List<ConflictObservation> observations,
) {
  if (observations.isEmpty) return null;

  final lines = observations
      .map(
        (o) =>
            '- ${o.characterName}「${o.attribute}」：${o.description}'
            '${_excerptSuffix(o.excerpt)}',
      )
      .join('\n');

  return '## 时序矛盾观察（F05 补充）\n\n'
      '以下是作品中已记录的人物属性前后不一致（同属性不同值，按出现章节标注）。'
      '若这些矛盾确属事实性错误（而非角色刻意隐瞒或剧情转折），请结合 P018 人设崩塌症'
      '的判断原则提示学员，温和指出矛盾位置与前后差异（只定位，不代改正文）。\n\n'
      '$lines';
}

/// 因果链断裂观察上下文（批次67 B62j，A6 第二迭代 F07，挂 P021/P016 补充）
///
/// 输入 event_causality_detector 输出的观察项（关键事件缺前因，带章节维度）。
/// 无观察项 → 返回 null（调用方不注入，零 token 成本）。
/// 注入措辞遵循 A1 约束：只定位不代改、温和提问、软引导非硬拦截。
String? buildCausalityBreakContext(
  List<CausalityBreakObservation> observations,
) {
  if (observations.isEmpty) return null;

  final lines = observations
      .map((o) => '- ${o.description}${_excerptSuffix(o.excerpt)}')
      .join('\n');

  return '## 因果链断裂观察（F07 补充）\n\n'
      '以下是作品中已记录的关键事件（决定/转折/突发类）缺少触发事件（因果前驱缺失）。'
      '若确属「突然发生」而读者无法理解动机（而非有意留白或后续章节揭示），请结合 P021 跳跃叙事'
      '/ P016 情节巧合的判断原则提示学员，温和指出事件位置与缺位的前因（只定位，不代改正文）。\n\n'
      '$lines';
}

/// 情节闭环观察上下文（批次67 B62j，A6 第二迭代 F11，挂 P014/P017 补充）
///
/// 输入 subplot_closure_detector 输出的观察项（引入多章未回收的支线）。
/// 无观察项 → 返回 null（调用方不注入，零 token 成本）。
/// 注入措辞遵循 A1 约束：只定位不代改、温和提问、软引导非硬拦截。
String? buildSubplotClosureContext(
  List<UnclosedSubplotObservation> observations,
) {
  if (observations.isEmpty) return null;

  final lines = observations
      .map((o) => '- ${o.description}${_excerptSuffix(o.excerpt)}')
      .join('\n');
  final summary = observations.length >= 2
      ? '\n\n共 ${observations.length} 条支线收束滞后。'
      : '';

  return '## 情节闭环观察（F11 补充）\n\n'
      '以下是作品中已引入多章但至今未回收的支线。若这些支线并非有意留待后续收束，'
      '请结合 P014 结尾仓促 / P017 伏笔埋设回收问题的判断原则提示学员，'
      '温和指出各支线的引入位置与未回收现状（只定位，不代改正文）。\n\n'
      '$lines$summary';
}

/// 基础文法观察上下文（批次70 F12，挂 P022 重复用词/基础语病 补充）
///
/// 输入 grammar_lexical_detector 输出的观察项（相邻重复字/连续标点/
/// 句首重复/高频词密度，带原文证据）。
/// 无观察项 → 返回 null（调用方不注入，零 token 成本）。
/// 注入措辞遵循 A1 约束：只定位不代改、温和提问、软引导非硬拦截。
String? buildGrammarLexicalContext(List<GrammarLexicalIssue> issues) {
  if (issues.isEmpty) return null;

  final lines = issues
      .map((o) => '- ${o.description}：「${o.evidence}」')
      .join('\n');

  return '## 基础文法观察（F12 补充）\n\n'
      '以下是文本中检出的重复用词 / 基础文法问题（纯规则精确匹配，可能包含刻意修辞，'
      '请结合 P022 重复用词/基础语病的判断原则甄别）。'
      '若确属语病（而非刻意排比/口语习惯），温和指出位置与原文片段（只定位，不代改正文）。\n\n'
      '$lines';
}

/// 对话标签观察上下文（批次71 F02，挂 P011 对话疲劳症 增强补充）
///
/// 输入 dialogue_tag_detector 输出的观察项（同一修饰性对话标签重复，
/// 带原文证据）。无观察项 → 返回 null（调用方不注入，零 token 成本）。
/// 注入措辞遵循 A1 约束：只定位不代改、温和提问、软引导非硬拦截。
String? buildDialogueTagContext(List<DialogueTagIssue> issues) {
  if (issues.isEmpty) return null;

  final lines = issues
      .map((o) => '- ${o.description}：「${o.evidence}」')
      .join('\n');

  return '## 对话标签观察（F02 补充）\n\n'
      '以下是文本中重复出现的修饰性对话标签（纯规则精确匹配，'
      '可能属于刻意修辞或人物特征，请结合 P011 对话疲劳症的判断原则甄别）。'
      '若确属标签过度（而非低声密语场景的功能性需要 / 人物固定的口头式说话方式），'
      '温和指出位置与原文片段，提示可尝试用动作/表情替代标签（只定位，不代改正文）。\n\n'
      '$lines';
}

// ─── 引用内容上下文 ───────────────────────────────────────────

/// 引用项（buildReferencesContext 的输入）
class ReferenceItem {
  final String refType; // 'manuscript' | 'chapter' | 'file'
  final String refId;
  final String title;
  final int isPrimary; // 0 | 1
  final String? manuscriptId;

  /// 批次5（5.5）：选段范围 JSON（如 {"start":100,"end":320}），chapter 引用专用
  final String? excerptRange;

  const ReferenceItem({
    required this.refType,
    required this.refId,
    required this.title,
    required this.isPrimary,
    this.manuscriptId,
    this.excerptRange,
  });
}

/// 批次5（5.5）：解析选段范围 JSON（{"start":..,"end":..}），非法返回 null
({int start, int end})? parseExcerptRange(String? json) {
  if (json == null || json.isEmpty) return null;
  try {
    final decoded = jsonDecode(json);
    if (decoded is! Map<String, dynamic>) return null;
    final start = decoded['start'];
    final end = decoded['end'];
    if (start is! num || end is! num || start < 0 || end < start) {
      return null;
    }
    return (start: start.toInt(), end: end.toInt());
  } catch (_) {
    return null;
  }
}

/// 批次5（5.5）：截取选段±上下文（start/end 为字符偏移，前后各补 50 字符）
String extractExcerpt(String content, ({int start, int end}) range) {
  if (content.isEmpty) return content;
  const ctx = 50;
  final start = (range.start - ctx).clamp(0, content.length);
  final end = (range.end + ctx).clamp(0, content.length);
  if (start >= end) {
    final capped = range.end.clamp(0, content.length);
    return content.substring(0, capped);
  }
  return content.substring(start, end);
}

/// 引用内容解析后的详情（manuscript 类型需要聚合章节信息）
class ManuscriptDetail {
  final String genre;
  final String? description;
  final List<ChapterBrief> chapters;

  const ManuscriptDetail({
    required this.genre,
    required this.description,
    required this.chapters,
  });
}

class ChapterBrief {
  final String id;
  final String title;
  final int wordCount;
  final int sortOrder;
  final String content;

  const ChapterBrief({
    required this.id,
    required this.title,
    required this.wordCount,
    required this.sortOrder,
    required this.content,
  });
}

/// 构建引用内容上下文（注入 system prompt）
///
/// 真源：yuesheng-android/src/services/chat-context-builder.ts L221-338
///
/// 输入：
///   refs: 该会话的所有引用项（listReferencesOfSession 返回值）
///   resolvers: 引用内容解析器（注入式依赖，避免在纯函数里直接调用 DAO）
///
/// 简化项（与 RN 原版偏差）：
///   - resolvers.fileResolver 直接返回 AttachedFileRow（合并 getAttachedFile 到一条路径）
///   - resolvers.manuscriptResolver 返回聚合后的 _ManuscriptDetail（包含章节列表）
///   - 没用 `__DEV__` 日志（Flutter 无对应宏）
String buildReferencesContext(
  List<ReferenceItem> refs, {
  required ReferenceResolvers resolvers,
}) {
  if (refs.isEmpty) return '';

  final totalBudget = ContextBudget.totalBudget;
  final primaryRatio = ContextBudget.primaryRatio;
  final secondaryRatio = ContextBudget.secondaryRatio;

  final primaryRefs = refs.where((r) => r.isPrimary == 1).toList();
  final secondaryRefs = refs.where((r) => r.isPrimary != 1).toList();

  int primaryBudget;
  int secondaryBudget;
  if (primaryRefs.isEmpty) {
    primaryBudget = 0;
    secondaryBudget =
        (totalBudget / (secondaryRefs.isNotEmpty ? secondaryRefs.length : 1))
            .floor();
  } else {
    primaryBudget = (totalBudget * primaryRatio / primaryRefs.length).floor();
    secondaryBudget =
        (totalBudget *
                secondaryRatio /
                (secondaryRefs.isNotEmpty ? secondaryRefs.length : 1))
            .floor();
  }

  final parts = <String>[];
  parts.add('## 内容位置判断');
  parts.add(
    '请先判断以下引用内容在原文中的位置（开头/中段/结尾/全局），然后仅对 position_sensitivity 匹配的症候进行诊断。',
  );
  parts.add('');
  parts.add('## 引用内容');
  parts.add('以下是用户当前引用的作品和章节内容。');
  parts.add('');
  parts.add('**优先级规则**：标注【主引用】的是用户主要希望分析的目标，请以主引用为核心分析对象；');
  parts.add('标注【次要引用】的仅作为辅助参考，用于理解上下文和写作风格，不应作为诊断的主要依据。');
  parts.add('如果预算不足以完整呈现内容，主引用的完整性优先于次要引用。');
  parts.add('');

  for (final ref in refs) {
    final budget = ref.isPrimary == 1 ? primaryBudget : secondaryBudget;
    final tag = ref.isPrimary == 1 ? '【主引用】' : '【次要引用】';

    if (ref.refType == 'file') {
      final file = resolvers.fileResolver(ref.refId);
      if (file != null) {
        const fileBudget = 50 * 1024; // 50KB
        final content = file.content.length > fileBudget
            ? '${file.content.substring(0, fileBudget)}\n...(内容已截断，超过50KB)'
            : file.content;
        parts.add('### 【素材文件】${file.fileName}（${file.fileRole}）');
        parts.add('```');
        parts.add(content);
        parts.add('```');
        parts.add('');
      }
    } else if (ref.refType == 'chapter') {
      final chapter = resolvers.chapterResolver(ref.refId);
      if (chapter != null) {
        parts.add('### $tag 章节：${ref.title}（${chapter.wordCount}字）');
        // 批次5（5.5）：主引用带选段范围 → 优先展开选段±上下文（替代整章）
        final range = parseExcerptRange(ref.excerptRange);
        if (ref.isPrimary == 1 && range != null) {
          parts.add('【选段诊断】以下为主引用章节中的选中片段（含前后文）');
          parts.add('```');
          parts.add(smartTruncate(extractExcerpt(chapter.content, range), budget));
          parts.add('```');
          parts.add('');
        } else {
          parts.add('【位置提示】请根据内容判断这是原文章节的开头/中段/结尾');
          parts.add('```');
          parts.add(smartTruncate(chapter.content, budget));
          parts.add('```');
          parts.add('');
        }
      }
    } else if (ref.refType == 'manuscript') {
      final detail = resolvers.manuscriptResolver(ref.refId);
      if (detail == null) continue;

      final totalWords = detail.chapters.fold<int>(
        0,
        (sum, ch) => sum + ch.wordCount,
      );

      final metaLines = <String>[];
      metaLines.add('### $tag 作品：${ref.title}');
      metaLines.add('- 类型：${detail.genre.isEmpty ? "未指定" : detail.genre}');
      metaLines.add('- 章节数：${detail.chapters.length}');
      metaLines.add('- 总字数：$totalWords');
      if (detail.description != null && detail.description!.isNotEmpty) {
        metaLines.add('- 简介：${detail.description}');
      }
      metaLines.add('');
      metaLines.add('**目录概览：**');
      for (final ch in detail.chapters) {
        metaLines.add('  ${ch.sortOrder}. ${ch.title}（${ch.wordCount}字）');
      }
      metaLines.add('');
      metaLines.add('【位置提示】以下预览章节可能位于作品的不同位置，请根据内容判断每段的位置');

      final metaLength = metaLines.join('\n').length;
      final previewBudget = budget - metaLength;
      final previewCount =
          detail.chapters.length < ContextBudget.manuscriptPreviewChapterCount
          ? detail.chapters.length
          : ContextBudget.manuscriptPreviewChapterCount;
      if (previewCount > 0 && previewBudget > ContextBudget.minPreviewBudget) {
        final chBudget = (previewBudget / previewCount).floor();
        for (int i = 0; i < previewCount; i++) {
          final ch = detail.chapters[i];
          metaLines.add('#### ${ch.title}');
          metaLines.add('```');
          metaLines.add(smartTruncate(ch.content, chBudget));
          metaLines.add('```');
          metaLines.add('');
        }
      }

      parts.addAll(metaLines);
    }
  }

  return parts.join('\n');
}

/// 引用内容解析器（依赖注入，避免纯函数直接调 DAO）
class ReferenceResolvers {
  final AttachedFileRow? Function(String fileId) fileResolver;
  final ChapterBrief? Function(String chapterId) chapterResolver;
  final ManuscriptDetail? Function(String manuscriptId) manuscriptResolver;

  const ReferenceResolvers({
    required this.fileResolver,
    required this.chapterResolver,
    required this.manuscriptResolver,
  });
}
