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

/// 解析白名单 —— 枚举一致性（N19）的四份真源之一。
///
/// 四份真源必须**双向相等**，由 test/services/enum_consistency_test.dart 守护：
///   1. 本文件的解析白名单（下两处常量）
///   2. types/teaching_types.dart 的 TeachingPhase / BeginnerLevel 枚举值
///   3. data/database/tables.dart 的 DB CHECK 约束（表重建级变更）
///   4. services/skills_*.dart 里全部注册 skill 正文的声明取值
///
/// 去掉下划线前缀是为了让护栏可引用（N19）；内部仍按只读常量使用，
/// 不要在业务代码里就地增删元素——改枚举、改 DB、改 prompt 要四处同步。
const List<String> _kValidSeverities = ['L1', 'L2', 'L3'];

/// 教学阶段取值白名单（P 系）。与 TeachingPhase / DB CHECK / prompt 声明四向一致。
const List<String> kValidPhases = [
  'P0_ENGAGE',
  'P1_WORLD',
  'P2_PRACTICE_LOOP',
  'P3_TRAINING',
  'P4_REVIEW',
];

/// 零基础等级取值白名单（N 系）。与 BeginnerLevel / DB CHECK / prompt 声明四向一致。
const List<String> kValidBeginnerLevels = [
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

/// 诊断块被拒原因码全集（ADR-C63，N1 / N26）。
///
/// 与下面 12 处 `return ParseResult(rejectReason: ...)` 一一对应。
/// `test/services/diagnosis_reject_reason_test.dart` 断言**每个码都可被触发**——
/// 新增静默点必须同时：① 在此登记 ② 补一条触发测试。
/// 少补任何一样，「静默点」就会重新出现而无人知晓（这正是 N26 的成因）。
const List<String> kDiagnosisRejectReasons = [
  'marker_end_missing', // 有开始标记无结束标记
  'json_decode_failed', // 块内不是合法 JSON
  'root_not_object', // 根不是 JSON 对象
  'syndromes_not_list', // syndromes 不是数组
  'syndrome_item_not_object', // syndromes[i] 不是对象
  'syndrome_id_not_string', // syndrome_id 不是字符串
  'syndrome_name_not_string', // name 不是字符串
  'syndrome_severity_invalid', // severity 不在 L1/L2/L3
  'syndrome_evidence_invalid', // evidence 不是字符串数组
  'syndrome_explanation_not_string', // explanation 不是字符串
  'suggested_actions_invalid', // suggested_actions 不是字符串数组
  'confidence_invalid', // confidence 不是 0-1 数字
];

/// 非阻断观测码全集（ADR-C63，N26-B 组 / N5）。
///
/// 出现这些码时**整块仍然通过**，行为与无码时完全一致——
/// 它们标记的是「此前完全静默、但比整块丢弃更隐蔽」的情形。
const List<String> kDiagnosisParseNotes = [
  'phase_dropped', // suggested_phase 白名单未命中 → 阶段迁移不发生
  'beginner_level_dropped', // suggested_beginner_level 白名单未命中
  'teaching_mode_dropped', // teaching_mode 白名单未命中
  'syndrome_id_format', // syndrome_id 不是 P0xx 格式（N5，只观测不拦截）
];

/// `syndrome_id` 的严格格式（N5）。
///
/// 复用 `diagnosis_validator.dart:17` 的 `kSyndromeCodeRe` 的**模式串**，
/// 但**加锚点**：
///   - 那个正则是为「在正文里找泄漏的编号并替换」设计的
///     （`diagnosis_validator.dart:179`），非锚定是它的正确形态；
///   - 而校验字段值必须锚定，否则 `hasMatch('XP003')` 也会命中
///     → 等于没校验。
/// 因此这里另立一个锚定版本，不复用那个实例。
final RegExp _kSyndromeIdRe = RegExp(r'^P0\d{2}$');

/// 从完整回复文本中提取诊断 JSON
///
/// - 无标记 → displayContent = 原文，diagnosis = null
/// - 标记不完整/JSON 不合法/校验失败 → 降级
///
/// 降级时在 [ParseResult.rejectReason] 说明原因（ADR-C63）。
/// 本函数**仍是纯函数**——不写日志、不落库，只把原因交出去，
/// 由服务层（`chat_service.dart`）决定如何记录。这样既拿到可观测性，
/// 又不破坏本文件头「纯函数，无副作用，不 throw」的既有契约。
ParseResult parseDiagnosis(String rawText) {
  final startIndex = rawText.indexOf(kDiagnosisStart);
  if (startIndex == -1) return _parseNoMarker(rawText);

  final endIndex = rawText.indexOf(
    kDiagnosisEnd,
    startIndex + kDiagnosisStart.length,
  );
  final displayContent = _buildDisplayContent(rawText, startIndex, endIndex);

  if (endIndex == -1) {
    // ADR-C63：此前静默丢弃（无日志）。模型以为有反馈回路，实际没有
    // → 会一直填下去，每一轮都静默失败（N26「永久卡死而非抖动一次」）。
    return ParseResult(
      displayContent: displayContent,
      diagnosis: null,
      rejectReason: 'marker_end_missing',
    );
  }

  final jsonStr = rawText
      .substring(startIndex + kDiagnosisStart.length, endIndex)
      .trim();
  final decoded = _decodeJsonPayload(jsonStr);
  if (!decoded.ok) {
    return ParseResult(
      displayContent: displayContent,
      diagnosis: null,
      rejectReason: 'json_decode_failed',
    );
  }

  final outcome = _validateDiagnosis(decoded.value);
  return ParseResult(
    displayContent: displayContent,
    diagnosis: outcome.diagnosis,
    rejectReason: outcome.rejectReason,
    notes: outcome.notes,
  );
}

/// 组装展示文本：prefix/suffix 各自剥离 ENTITY/FACT 协议块（R-019 拆出）。
String _buildDisplayContent(String rawText, int startIndex, int endIndex) {
  // 批次6（6.12 V8）：prefix 同样剥 ENTITY/FACT 协议块（FACT 块出现在
  // 诊断块之前等顺序错乱场景不泄漏原始 JSON）
  final prefix = stripFactBlock(
    stripOutlineBlock(rawText.substring(0, startIndex)),
  ).trimRight();

  // 批次74：suffix 也做大纲协议块剥离（AI 常把 YS_ENTITY 放诊断块之后、自然语言之前）
  // 批次6（6.12 V8）：suffix 同步剥 FACT 块
  final suffix = endIndex == -1
      ? ''
      : stripFactBlock(
          stripOutlineBlock(rawText.substring(endIndex + kDiagnosisEnd.length)),
        ).trimLeft();

  return _concatDiagnosisDisplay(prefix, suffix);
}

/// 无诊断块：仅剥离协议块后返回（批次74/6 契约）。
ParseResult _parseNoMarker(String rawText) {
  // 批次74：无诊断块也要保证大纲协议块被剥离，避免 100% 非诊断路径出现协议 JSON
  // 批次6（6.12 V8）：FACT 协议块同样剥离（顺序错乱/无诊断时均不泄漏）
  return ParseResult(
    displayContent: stripFactBlock(stripOutlineBlock(rawText)),
    diagnosis: null,
  );
}

/// JSON 载荷安全解码：成功/失败用 record 区分（JSON 值本身可为 null）。
({dynamic value, bool ok}) _decodeJsonPayload(String jsonStr) {
  try {
    return (value: jsonDecode(jsonStr), ok: true);
  } catch (_) {
    return (value: null, ok: false);
  }
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

/// 字段白名单校验的结果（ADR-C63）。
///
/// 改造前 `_validateDiagnosis` 直接返回 `ParsedDiagnosis?`，被拒原因随之丢失——
/// 这正是 N1 / N26「查不到根因」的成因。现在改为返回「结果 + 原因码」，
/// 原因经 `ParseResult.rejectReason` 上浮到服务层日志。
///
/// **纯附加**：[diagnosis] 的取值在任何输入下都与改造前一致（零行为变更）。
class _DiagnosisValidation {
  /// 通过时的诊断结果；被拒时为 null。
  final ParsedDiagnosis? diagnosis;

  /// 被拒原因码（null = 通过）。取值见 [kDiagnosisRejectReasons]。
  final String? rejectReason;

  /// 非阻断观测码。取值见 [kDiagnosisParseNotes]。
  final List<String> notes;

  const _DiagnosisValidation.reject(String reason)
    : diagnosis = null,
      rejectReason = reason,
      notes = const <String>[];

  _DiagnosisValidation.ok(this.diagnosis, List<String> collectedNotes)
    : rejectReason = null,
      notes = List<String>.unmodifiable(collectedNotes);
}

/// 校验 syndromes 数组，命中则填充 [out]，非阻断观测写入 [notes]。
///
/// 返回原因码（null = 通过）。
///
/// 从 `_validateDiagnosis` 抽出的理由：这一段内聚（只管 syndromes），
/// 且含 6 个拒绝点，是全部静默点里最密的一处。为 R-019 服务，
/// 但**不声称已合规**——`_validateDiagnosis` 抽取后仍超 50 行，
/// 如实登记为残留债务（ADR-C63 §4.1）。
String? _validateSyndromes(
  dynamic raw,
  List<Syndrome> out,
  List<String> notes,
) {
  if (raw is! List) return 'syndromes_not_list';
  for (final s in raw) {
    if (s is! Map<String, dynamic>) return 'syndrome_item_not_object';
    final syndromeId = s['syndrome_id'];
    final name = s['name'];
    final severity = s['severity'];
    final evidence = s['evidence'];
    final explanation = s['explanation'];
    if (syndromeId is! String) return 'syndrome_id_not_string';
    if (name is! String) return 'syndrome_name_not_string';
    if (severity is! String || !_kValidSeverities.contains(severity)) {
      return 'syndrome_severity_invalid';
    }
    if (evidence is! List || evidence.any((e) => e is! String)) {
      return 'syndrome_evidence_invalid';
    }
    if (explanation is! String) return 'syndrome_explanation_not_string';

    // N5：格式**只观测不拦截**（ADR-C63 §3.2）。
    // 拦截会让整块诊断被丢弃，反而放大「输出了但不落库」——
    // 与本次要解决的问题同向恶化。先测量发生率，再决定是否升级为拦截。
    if (!_kSyndromeIdRe.hasMatch(syndromeId)) {
      notes.add('syndrome_id_format');
    }

    out.add(
      Syndrome(
        syndromeId: syndromeId,
        name: name,
        severity: Severity.fromString(severity)!,
        evidence: evidence.cast<String>(),
        explanation: explanation,
        // N40：原为 `as String?` 硬 cast，模型填非字符串即抛 TypeError。
        // 改成安全读取——非 String 一律当缺失，与其余可选字段的处理一致。
        readerImpact: s['reader_impact'] is String
            ? s['reader_impact'] as String
            : null,
      ),
    );
  }
  return null;
}

/// 字段白名单校验。
///
/// 与改造前的差异只有一件事：**被拒时说明原因**。
/// [ParsedDiagnosis] 的取值在任何输入下都与改造前一致（零行为变更）。
_DiagnosisValidation _validateDiagnosis(dynamic raw) {
  if (raw is! Map<String, dynamic>) {
    return const _DiagnosisValidation.reject('root_not_object');
  }
  final obj = raw;

  final notes = <String>[];

  // syndromes 必填，数组
  final syndromes = <Syndrome>[];
  final syndromeErr = _validateSyndromes(obj['syndromes'], syndromes, notes);
  if (syndromeErr != null) return _DiagnosisValidation.reject(syndromeErr);

  // suggested_actions 必填，string[]
  final suggestedActionsRaw = obj['suggested_actions'];
  if (suggestedActionsRaw is! List ||
      suggestedActionsRaw.any((a) => a is! String)) {
    return const _DiagnosisValidation.reject('suggested_actions_invalid');
  }
  final suggestedActions = suggestedActionsRaw.cast<String>();

  // confidence 必填，number 0-1
  final confidence = obj['confidence'];
  if (confidence is! num || confidence < 0 || confidence > 1) {
    return const _DiagnosisValidation.reject('confidence_invalid');
  }

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

  // 以下三个可选字段走白名单守卫。白名单未命中时**整块仍然通过**，
  // 只是字段变成 null——这是 N26 的 B 组形态，比整块丢弃更隐蔽：
  // 诊断照常显示、UI 毫无异样，唯独阶段迁移永远不发生（N13 的确切机制）。
  TeachingPhase? suggestedPhase;
  final sp = obj['suggested_phase'];
  if (sp is String && kValidPhases.contains(sp)) {
    suggestedPhase = TeachingPhase.fromString(sp);
  } else if (sp != null) {
    notes.add('phase_dropped');
  }

  BeginnerLevel? suggestedBeginnerLevel;
  final sbl = obj['suggested_beginner_level'];
  if (sbl is String && kValidBeginnerLevels.contains(sbl)) {
    suggestedBeginnerLevel = BeginnerLevel.fromString(sbl);
  } else if (sbl != null) {
    notes.add('beginner_level_dropped');
  }

  TeachingMode? teachingMode;
  final tm = obj['teaching_mode'];
  if (tm is String && _kValidTeachingModes.contains(tm)) {
    teachingMode = TeachingMode.fromString(tm);
  } else if (tm != null) {
    notes.add('teaching_mode_dropped');
  }

  // teaching_plan 子块（设计文档 5.8.4 兼容性策略）
  final teachingPlanRaw = obj['teaching_plan'];
  final teachingPlan = teachingPlanRaw is Map<String, dynamic>
      ? teachingPlanRaw
      : null;

  String? currentTeachingFocusId;
  if (teachingPlan != null) {
    final ctf = teachingPlan['current_teaching_focus_id'];
    if (ctf is String) {
      // N3-a（ADR-C65）：prompt 三处明写「必须从本轮 syndromes 中选取」
      //（skills_l1_core_p2.dart:124 / syndrome_kb_content.dart:77、99）。
      // 越界值置 null → 走 focus-resolver fallback，这是 prompt 自己声明的
      // 既有行为（同 :124「缺失时走 fallback 优先级表」），不是新造路径。
      //
      // 为什么必须拦：越界 id 会绕过诊断锁定。落库后下轮
      // getLatestTeachingFocus 取出它，focus-resolver 校验 1「在池中」只看
      // active_problem 池——而 commitDiagnosis 已把本轮症候 UPSERT 进池，
      // 校验先于落库不成立，拦不住。详见 ADR-C65 §3.3。
      if (syndromes.any((s) => s.syndromeId == ctf)) {
        currentTeachingFocusId = ctf;
      } else {
        notes.add('focus_not_in_syndromes');
      }
    }
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

  return _DiagnosisValidation.ok(
    ParsedDiagnosis(
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
    ),
    notes,
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
