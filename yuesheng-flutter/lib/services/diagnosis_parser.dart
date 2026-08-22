// ─────────────────────────────────────────────────────────────
// 诊断块解析 — 复刻 services/diagnosis-parser.ts
// 从 AI 完整回复中提取 [YS_DIAGNOSIS]...[/YS_DIAGNOSIS] 块内的 JSON
// 纯函数，无副作用，不 throw
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import '../types/teaching_types.dart';
import 'fact_parser.dart';
import 'outline_parser.dart';
import 'diagnosis_validator.dart';
import 'chat_training_parser.dart';

export 'package:writingcoach/contracts/diagnosis_capability.dart';

/// 诊断块分隔符
const String kDiagnosisStart = '[YS_DIAGNOSIS]';
const String kDiagnosisEnd = '[/YS_DIAGNOSIS]';

/// 解析结果（DTO 已上移至 contracts/diagnosis_capability.dart）

const List<String> _kValidSeverities = ['L1', 'L2', 'L3'];
const List<String> _kValidPhases = [
  'P0_ENGAGE',
  'P1_WORLD',
  'P2_PRACTICE_LOOP',
  'P3_TRAINING',
  'P4_REVIEW',
];
const List<String> _kValidBeginnerLevels = [
  'N0_ENGAGE',
  'N1_ELEMENTS',
  'N2_SCENE',
  'N3_DIAGNOSE',
  'N4_INDEPENDENT',
];
const List<String> _kValidTeachingModes = [
  'socratic',
  'mirror',
  'conflict',
  'direct',
];

/// 从完整回复文本中提取诊断 JSON
///
/// - 无标记 → displayContent = 原文，diagnosis = null
/// - 标记不完整/JSON 不合法/校验失败 → 降级
ParseResult parseDiagnosis(String rawText) {
  final startIndex = rawText.indexOf(kDiagnosisStart);
  if (startIndex == -1) {
    // 批次74：无诊断块也要保证大纲协议块被剥离，避免 100% 非诊断路径出现协议 JSON
    // 批次6（6.12 V8）：FACT 协议块同样剥离（顺序错乱/无诊断时均不泄漏）
    return ParseResult(
      displayContent: stripFactBlock(stripOutlineBlock(rawText)),
      diagnosis: null,
    );
  }

  // 批次6（6.12 V8）：prefix 同样剥 ENTITY/FACT 协议块（FACT 块出现在
  // 诊断块之前等顺序错乱场景不泄漏原始 JSON）
  final prefix = stripFactBlock(
    stripOutlineBlock(rawText.substring(0, startIndex)),
  ).trimRight();

  final endIndex = rawText.indexOf(
    kDiagnosisEnd,
    startIndex + kDiagnosisStart.length,
  );
  // 批次74：suffix 也做大纲协议块剥离（AI 常把 YS_ENTITY 放诊断块之后、自然语言之前）
  // 批次6（6.12 V8）：suffix 同步剥 FACT 块
  final suffix = endIndex == -1
      ? ''
      : stripFactBlock(
          stripOutlineBlock(rawText.substring(endIndex + kDiagnosisEnd.length)),
        ).trimLeft();

  final displayContent = _concatDiagnosisDisplay(prefix, suffix);

  if (endIndex == -1) {
    return ParseResult(displayContent: displayContent, diagnosis: null);
  }

  final jsonStr = rawText
      .substring(startIndex + kDiagnosisStart.length, endIndex)
      .trim();

  dynamic parsed;
  try {
    parsed = jsonDecode(jsonStr);
  } catch (_) {
    return ParseResult(displayContent: displayContent, diagnosis: null);
  }

  final diagnosis = _validateDiagnosis(parsed);
  if (diagnosis == null) {
    return ParseResult(displayContent: displayContent, diagnosis: null);
  }

  return ParseResult(displayContent: displayContent, diagnosis: diagnosis);
}

String _concatDiagnosisDisplay(String prefix, String suffix) {
  if (prefix.isEmpty) return suffix;
  if (suffix.isEmpty) return prefix;
  final pEnd = prefix.endsWith('\n');
  final sStart = suffix.startsWith('\n');
  if (pEnd && sStart) return '$prefix$suffix';
  if (pEnd || sStart) return '$prefix$suffix';
  return '$prefix\n\n$suffix';
}

/// 字段白名单校验。校验失败返回 null
ParsedDiagnosis? _validateDiagnosis(dynamic raw) {
  if (raw is! Map<String, dynamic>) return null;
  final obj = raw;

  // syndromes 必填，数组
  final syndromesRaw = obj['syndromes'];
  if (syndromesRaw is! List) return null;
  final syndromes = <Syndrome>[];
  for (final s in syndromesRaw) {
    if (s is! Map<String, dynamic>) return null;
    final syndromeId = s['syndrome_id'];
    final name = s['name'];
    final severity = s['severity'];
    final evidence = s['evidence'];
    final explanation = s['explanation'];
    if (syndromeId is! String) return null;
    if (name is! String) return null;
    if (severity is! String || !_kValidSeverities.contains(severity)) {
      return null;
    }
    if (evidence is! List || evidence.any((e) => e is! String)) return null;
    if (explanation is! String) return null;
    syndromes.add(
      Syndrome(
        syndromeId: syndromeId,
        name: name,
        severity: Severity.fromString(severity)!,
        evidence: evidence.cast<String>(),
        explanation: explanation,
        readerImpact: s['reader_impact'] as String?,
      ),
    );
  }

  // suggested_actions 必填，string[]
  final suggestedActionsRaw = obj['suggested_actions'];
  if (suggestedActionsRaw is! List ||
      suggestedActionsRaw.any((a) => a is! String)) {
    return null;
  }
  final suggestedActions = suggestedActionsRaw.cast<String>();

  // confidence 必填，number 0-1
  final confidence = obj['confidence'];
  if (confidence is! num || confidence < 0 || confidence > 1) return null;

  // 可选字段
  String? rootCauseAnalysis;
  final rca = obj['root_cause_analysis'];
  if (rca is String) {
    rootCauseAnalysis = rca;
  }

  String? nextFocus;
  final nf = obj['next_focus'];
  if (nf is String) {
    nextFocus = nf;
  }

  String? feedbackSummary;
  final fs = obj['feedback_summary'];
  if (fs is String) {
    feedbackSummary = fs;
  }

  TeachingPhase? suggestedPhase;
  final sp = obj['suggested_phase'];
  if (sp is String && _kValidPhases.contains(sp)) {
    suggestedPhase = TeachingPhase.fromString(sp);
  }

  BeginnerLevel? suggestedBeginnerLevel;
  final sbl = obj['suggested_beginner_level'];
  if (sbl is String && _kValidBeginnerLevels.contains(sbl)) {
    suggestedBeginnerLevel = BeginnerLevel.fromString(sbl);
  }

  TeachingMode? teachingMode;
  final tm = obj['teaching_mode'];
  if (tm is String && _kValidTeachingModes.contains(tm)) {
    teachingMode = TeachingMode.fromString(tm);
  }

  // teaching_plan 子块（设计文档 5.8.4 兼容性策略）
  final teachingPlanRaw = obj['teaching_plan'];
  final teachingPlan = teachingPlanRaw is Map<String, dynamic>
      ? teachingPlanRaw
      : null;

  String? currentTeachingFocusId;
  if (teachingPlan != null) {
    final ctf = teachingPlan['current_teaching_focus_id'];
    if (ctf is String) currentTeachingFocusId = ctf;
  }

  String? focusReason;
  if (teachingPlan != null) {
    final fr = teachingPlan['focus_reason'];
    if (fr is String) focusReason = fr;
  }

  String? teachingPlanNextStep;
  if (teachingPlan != null) {
    final ns = teachingPlan['next_step'];
    if (ns is String) teachingPlanNextStep = ns;
  }

  // 兼容性策略（设计 5.8.4）：
  // teaching_plan.next_step 有值时优先；为 null 时回退到 next_focus
  final finalNextFocus = teachingPlanNextStep ?? nextFocus;

  // 可选：style_profile 写作风格画像（批次53，缺失/非法不阻断诊断）
  WritingStyleProfile? styleProfile;
  final styleRaw = obj['style_profile'];
  if (styleRaw is Map<String, dynamic>) {
    try {
      styleProfile = WritingStyleProfile.fromJson(styleRaw);
    } catch (_) {
      styleProfile = null; // 缺 summary 等非法结构 → 忽略
    }
  }

  return ParsedDiagnosis(
    syndromes: syndromes,
    suggestedActions: suggestedActions,
    confidence: confidence.toDouble(),
    rootCauseAnalysis: rootCauseAnalysis,
    nextFocus: finalNextFocus,
    feedbackSummary: feedbackSummary,
    suggestedPhase: suggestedPhase,
    suggestedBeginnerLevel: suggestedBeginnerLevel,
    teachingMode: teachingMode,
    currentTeachingFocusId: currentTeachingFocusId,
    focusReason: focusReason,
    styleProfile: styleProfile,
  );
}

/// 检查 fullContent 尾部是否匹配 [YS_DIAGNOSIS] 的某个前缀
/// 返回匹配的前缀长度（0 = 不匹配，>0 = 可能正在到达）
/// 用于流式拦截，防止分隔符跨 chunk 到达时误转发
int getPendingMarkerPrefix(String fullContent) {
  const marker = kDiagnosisStart;
  // 从最长前缀开始检查（排除完整匹配）
  for (var len = marker.length - 1; len > 0; len--) {
    final prefix = marker.substring(0, len);
    if (fullContent.endsWith(prefix)) {
      return len;
    }
  }
  return 0;
}

// ─── 诊断能力实现（选项 B 依赖倒置）────────────────────────────
//
// 委托到既有纯函数 parseDiagnosis / validateDiagnosisOutput /
// parseTrainingResult，自身无状态；UI 经 DiagnosisCapability 消费，
// 不直接依赖具体解析器。
//
// 三个方法名与顶层纯函数同名——方法体内同名标识符优先解析为实例成员，
// 故必须用私有别名委托到顶层函数，否则会无限自递归（Stack Overflow）。
// 见 2026-08-19 修复（GenUi 同款坑）。

/// 顶层实现别名：parseDiagnosis 委托
ParseResult _parseDiagnosisImpl(String rawText) => parseDiagnosis(rawText);

/// 顶层实现别名：validateDiagnosisOutput 委托
FullValidationResult _validateDiagnosisOutputImpl(
  String displayContent,
  Map<String, dynamic> rawJson, {
  AttitudeLevel? attitude,
}) => validateDiagnosisOutput(displayContent, rawJson, attitude: attitude);

/// 顶层实现别名：parseTrainingResult 委托
TrainingResult? _parseTrainingResultImpl(String content) =>
    parseTrainingResult(content);

class DiagnosisCapabilityImpl implements DiagnosisCapability {
  const DiagnosisCapabilityImpl();

  @override
  ParseResult parseDiagnosis(String rawText) => _parseDiagnosisImpl(rawText);

  @override
  FullValidationResult validateDiagnosisOutput(
    String displayContent,
    Map<String, dynamic> rawJson, {
    AttitudeLevel? attitude,
  }) =>
      _validateDiagnosisOutputImpl(displayContent, rawJson, attitude: attitude);

  @override
  TrainingResult? parseTrainingResult(String content) =>
      _parseTrainingResultImpl(content);
}
