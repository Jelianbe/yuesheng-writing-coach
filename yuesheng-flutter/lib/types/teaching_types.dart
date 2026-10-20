// ─────────────────────────────────────────────────────────────
// 教学类型定义 — 复刻 yuesheng-android/src/types/db.ts（调度链路所需部分）
// ─────────────────────────────────────────────────────────────

/// 教学阶段（P 系）
enum TeachingPhase {
  p0Engage('P0_ENGAGE'),
  p1World('P1_WORLD'),
  p2PracticeLoop('P2_PRACTICE_LOOP'),
  p3Training('P3_TRAINING'),
  p4Review('P4_REVIEW');

  final String value;
  const TeachingPhase(this.value);

  static TeachingPhase? fromString(String? s) {
    if (s == null) return null;
    for (final v in TeachingPhase.values) {
      if (v.value == s) return v;
    }
    return null;
  }
}

/// 零基础等级（N 系）
enum BeginnerLevel {
  n0Engage('N0_ENGAGE'),
  n1Elements('N1_ELEMENTS'),
  n2Scene('N2_SCENE'),
  n3Diagnose('N3_DIAGNOSE'),
  n4Independent('N4_INDEPENDENT');

  final String value;
  const BeginnerLevel(this.value);

  static BeginnerLevel? fromString(String? s) {
    if (s == null) return null;
    for (final v in BeginnerLevel.values) {
      if (v.value == s) return v;
    }
    return null;
  }
}

/// P2 子阶段
enum TeachingSubphase {
  diagnosis('DIAGNOSIS'),
  practice('PRACTICE'),
  feedback('FEEDBACK');

  final String value;
  const TeachingSubphase(this.value);

  static TeachingSubphase? fromString(String? s) {
    if (s == null) return null;
    for (final v in TeachingSubphase.values) {
      if (v.value == s) return v;
    }
    return null;
  }
}

/// 严重度
enum Severity {
  l1('L1'),
  l2('L2'),
  l3('L3');

  final String value;
  const Severity(this.value);

  static Severity? fromString(String? s) {
    if (s == null) return null;
    for (final v in Severity.values) {
      if (v.value == s) return v;
    }
    return null;
  }
}

/// 确认状态
///
/// R-027（治 §4-194 病灶二）：补 [dismissed] 独立态——学员永久关闭/
/// 类型声明「不适用」（绑定 disabledIds），与 [rejected]（质疑）语义分离。
enum ConfirmationStatus {
  suspected('suspected'),
  confirmed('confirmed'),
  rejected('rejected'),
  ignored('ignored'),
  dismissed('dismissed');

  final String value;
  const ConfirmationStatus(this.value);

  static ConfirmationStatus? fromString(String? s) {
    if (s == null) return null;
    for (final v in ConfirmationStatus.values) {
      if (v.value == s) return v;
    }
    return null;
  }
}

/// 教学模式
enum TeachingMode {
  socratic('socratic'),
  mirror('mirror'),
  conflict('conflict'),
  direct('direct');

  final String value;
  const TeachingMode(this.value);

  static TeachingMode? fromString(String? s) {
    if (s == null) return null;
    for (final v in TeachingMode.values) {
      if (v.value == s) return v;
    }
    return null;
  }
}

/// 态度档位
enum AttitudeLevel {
  gentle('gentle'),
  yuesheng('yuesheng'),
  sensei('sensei');

  final String value;
  const AttitudeLevel(this.value);

  static AttitudeLevel? fromString(String? s) {
    if (s == null) return null;
    // legacy 兼容：旧版持久化值 'doubao'（默认温和档）→ gentle。
    // 已有用户的 coach_attitude / persona id / teaching_state 落库值不迁移，
    // 读入时统一映射到默认档（禁止改库结构、禁止清用户数据）。
    if (s == 'doubao') return AttitudeLevel.gentle;
    for (final v in AttitudeLevel.values) {
      if (v.value == s) return v;
    }
    return null;
  }
}

/// 症候（诊断结果中的单项）
class Syndrome {
  final String syndromeId;
  final String name;
  final Severity severity;
  final List<String> evidence;
  final String explanation;
  final String? readerImpact;

  /// W-19-A：干预价值档位（'high' | 'medium' | 'low'，null = 未评定）。
  ///
  /// 语义见设计稿 docs/designs/2026-10-15-W19-干预价值门槛-四步原则-设计稿.md：
  /// **≠ severity**（严重程度答「问题多重」，干预价值答「现在教它值不值」，
  /// 两者正交——L3 可 low（需全书重构），L1 可 high（一次练习立竿见影））。
  /// 可选字段：schema 不校验类型，fromJson 安全读取（先例：reader_impact）。
  final String? interventionValue;

  /// W-15-B：跨块因果缺口标记（merge prompt「跨片因果提示」引导 LLM 自标）。
  ///
  /// true = 该条线索的成立依赖未包含在任何分片中的信息（前文伏笔/后文解释/
  /// 分片外人物关系），结论「暂时无法判断」，不得强行下结论。
  /// **引导自标字段，不是代码判定**——禁止代码侧自动推断（会私造语义）；
  /// LLM 未标的漏网场景由 W-21 A4 ②类（证据不足）与用户确认环（W-22）兜底。
  /// 可选字段：schema 不校验类型，fromJson 安全读取（先例：reader_impact）。
  final bool? pendingContext;

  /// ★ 治理续批第二批（2026-10-20 · R-027 批准）：形态要素 (a) —— 成段事实条数。
  ///
  /// 语义与 T-20261014-12 组合⑤判据**逐字同源**：「成段出现的设定/背景事实条数；
  /// 单句带过 = 1」。
  ///
  /// ★ 为什么必须是 **LLM 显式输出**（不得从 evidence.length / severity 派生）：
  ///   W-23 数据实证（脚本实测 2026-10-20）——P002 全库 154 次检出的 evidence 条数
  ///   分布 L2 {1:7,2:50,3:58,4:2} vs L1 {1:9,2:10,3:3} **高度重叠**；
  ///   X01|t03|r2 与 X22|t03|r1 两锚点 P002 的 evidence **均为 3 条**而形态结论相反；
  ///   X01|t07|r1 更是「3 事实旁白但无论文式结构」⇒ 连单值 fact_count 都分不开。
  ///   ⇒ 派生实现必错，只能让 LLM 输出要素态。
  ///
  /// 可选字段：schema 不校验类型，fromJson 安全读取（先例：reader_impact）。
  /// null = 无形态证据 ⇒ 资格闸按 v1 行为处理（存量安全，见 focus_resolver）。
  final int? formFactCount;

  /// ★ 治理续批第二批（2026-10-20 · R-027 批准）：形态要素 (b) —— 结构标记。
  ///
  /// 合法值：`expository`（论文式/说明书结构，「原因有二：其一……」）/
  /// `interruption`（读者关切时刻被打断）/ `narrative`（嵌在叙事流中、无结构标记）。
  /// 与 [formFactCount] **同批输出、缺一不可**（组合⑤双要素）。
  /// 越界值按缺失处理（归一化为 null），不静默纠偏。
  final String? formStructure;

  const Syndrome({
    required this.syndromeId,
    required this.name,
    required this.severity,
    required this.evidence,
    required this.explanation,
    this.readerImpact,
    this.interventionValue,
    this.pendingContext,
    this.formFactCount,
    this.formStructure,
  });

  Map<String, dynamic> toJson() => {
    'syndrome_id': syndromeId,
    'name': name,
    'severity': severity.value,
    'evidence': evidence,
    'explanation': explanation,
    if (readerImpact != null) 'reader_impact': readerImpact,
    if (interventionValue != null) 'intervention_value': interventionValue,
    // W-15-B：null 不落 key，fromJson→toJson 往返稳定（同 reader_impact 约定）。
    if (pendingContext != null) 'pending_context': pendingContext,
    // 治理续批第二批：形态两要素同款约定（null 不落 key，往返稳定）。
    if (formFactCount != null) 'form_fact_count': formFactCount,
    if (formStructure != null) 'form_structure': formStructure,
  };

  factory Syndrome.fromJson(Map<String, dynamic> json) {
    // ⚠️ 前 5 处 cast 依赖 validateDiagnosisSchema 的必填校验
    // （diagnosis_validator.dart:80-137）。schema 当前保证：syndromes 是非空
    // List、元素是 Map、syndrome_id/name 非空 String、severity ∈ L1/L2/L3、
    // evidence 是 List、explanation 是 String。
    // 若未来放宽 schema 的必填校验，这 5 处会变成崩溃点——放宽时须同步
    // 改为安全读取。见 ADR-C64 §2.3。
    //
    // reader_impact 是可选字段，schema 不校验其类型（ADR-C64 §2.2 #9），
    // 故此字段必须安全读取：非 String 按缺失处理。硬 cast 会抛 TypeError，
    // 而抛错点在 validateDiagnosisOutput 返回之前，会连带丢掉已经算好的
    // NL 清洗结果——后果是 V-03 编号泄漏拦截失效（ADR-C64 §1.2 实测）。
    final readerImpact = json['reader_impact'];
    return Syndrome(
      syndromeId: json['syndrome_id'] as String,
      name: json['name'] as String,
      severity: Severity.fromString(json['severity'] as String?) ?? Severity.l2,
      evidence:
          (json['evidence'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      explanation: json['explanation'] as String? ?? '',
      readerImpact: readerImpact is String ? readerImpact : null,
      // W-19-A：intervention_value 同 reader_impact 口径——可选、类型不校验、
      // 安全读取；档位越界（非 high/medium/low）按缺失处理（归一化为 null）。
      interventionValue: normalizeInterventionValue(json['intervention_value']),
      // W-15-B：pending_context 同 reader_impact 口径——可选、类型不校验、
      // 安全读取；非 bool 按缺失处理（归一化为 null）。
      pendingContext: normalizePendingContext(json['pending_context']),
      // 治理续批第二批：形态两要素同款口径——可选、类型不校验、安全读取。
      formFactCount: normalizeFormFactCount(json['form_fact_count']),
      formStructure: normalizeFormStructure(json['form_structure']),
    );
  }
}

/// ★ 治理续批第二批（2026-10-20 · R-027 批准）：形态要素 (a) 归一化。
///
/// 合法形态 = 非负整数（num→int 容差：JSON 里 3.0 读成 double 属正常）。
/// 非法（负数 / 非数值 / null）一律返回 null（= 无形态证据），不静默纠偏。
int? normalizeFormFactCount(Object? raw) {
  if (raw is int) return raw >= 0 ? raw : null;
  if (raw is num) {
    if (raw.isNaN || raw.isInfinite) return null;
    final v = raw.toInt();
    return v >= 0 ? v : null;
  }
  return null;
}

/// ★ 治理续批第二批（2026-10-20 · R-027 批准）：形态要素 (b) 合法值集合。
const List<String> kFormStructures = [
  'expository',
  'interruption',
  'narrative',
];

/// 形态结构标记归一化：合法值原样返回；其余（越界/非字符串/null）返回 null。
/// 与 [normalizeInterventionValue] 同款口径（不静默纠偏）。
String? normalizeFormStructure(Object? raw) {
  if (raw is String && kFormStructures.contains(raw)) {
    return raw;
  }
  return null;
}

/// W-15-B：归一化 pending_context——bool 原样返回；其余（越界/非 bool/null）
/// 一律返回 null（= 未标记）。不做静默纠偏（同 normalizeInterventionValue 口径）。
bool? normalizePendingContext(Object? raw) => raw is bool ? raw : null;

/// intervention_value 的合法档位（W-19-A）。
const List<String> kInterventionValues = ['high', 'medium', 'low'];

/// 归一化 intervention_value：合法档位原样返回；其余（越界/非字符串/null）
/// 一律返回 null（= 未评定）。不做静默纠偏——模型输出越界值时由解析侧
/// notes 留痕，字段本身按缺失处理。
String? normalizeInterventionValue(Object? raw) {
  if (raw is String && kInterventionValues.contains(raw)) {
    return raw;
  }
  return null;
}

/// 干预价值排序权重（W-19-A 消费侧）：high > medium > low > null。
/// 仅用于**同 severity 档内**的次序（主序仍是 severity，见
/// intervention_value.dart 的 sortSyndromesForDiagnosisCard）。
int interventionValueRank(String? value) {
  if (value == null) return -1;
  return switch (value) {
    'high' => 2,
    'medium' => 1,
    'low' => 0,
    _ => -1,
  };
}

/// 整体判定（ADR-0006 顶层 `overall` 块的解析产物）。
///
/// 定位 = **结构完整度诊断**，不是文学打分（R-009 用户主权：「好不好」的
/// 最终判断权在学员）。⇒ 无任何数字字段；[verdict] 仅三档字符串。
///
/// H-3（ADR-0006 §C-3）：[coverage] 非空才有效——缺覆盖度复述的整体判定
/// 宁可整块作废（解析层拒绝或降级），不许呈现「局部冒充整体」。
class OverallDiagnosis {
  final String verdict; // kOverallVerdicts 三档之一
  final List<String> reasons; // 核心理由（1-3 条）
  final String? keep; // 最值得保持的一点
  final List<String> priority; // 建议先改顺序（1-3 条）
  final String coverage; // 覆盖度复述，非空才有效

  const OverallDiagnosis({
    required this.verdict,
    required this.reasons,
    this.keep,
    required this.priority,
    required this.coverage,
  });

  Map<String, dynamic> toJson() => {
    'verdict': verdict,
    'reasons': reasons,
    if (keep != null) 'keep': keep,
    'priority': priority,
    'coverage': coverage,
  };

  factory OverallDiagnosis.fromJson(Map<String, dynamic> json) {
    final keep = json['keep'];
    return OverallDiagnosis(
      verdict: json['verdict'] as String? ?? '',
      reasons:
          (json['reasons'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      keep: keep is String && keep.isNotEmpty ? keep : null,
      priority:
          (json['priority'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      // 空串按缺失处理（H-3：缺 coverage 的整体判定无效，交由调用方丢弃）。
      coverage: json['coverage'] is String ? json['coverage'] as String : '',
    );
  }
}

/// 整体判定三档（协议与呈现层共用，单一真源）。
const List<String> kOverallVerdicts = ['结构完整', '基本完整', '存在结构性缺口'];

/// 诊断结果（解析后的结构化对象，不含 session_id / message_id）
class ParsedDiagnosis {
  final List<Syndrome> syndromes;
  final List<String> suggestedActions;
  final double confidence;
  final String? rootCauseAnalysis;
  final String? nextFocus;
  final String? feedbackSummary;
  final TeachingPhase? suggestedPhase;
  final BeginnerLevel? suggestedBeginnerLevel;
  final TeachingMode? teachingMode;
  final String? currentTeachingFocusId;
  final String? focusReason;
  final WritingStyleProfile? styleProfile; // 可选：写作风格画像（批次53）

  /// ADR-0006：整体判定（结构完整度诊断，非文学打分）。
  ///
  /// 可选顶层字段——解析失败（含 H-3 coverage 缺失 ⇒ 置 null）不影响
  /// 其余字段路径，与 styleProfile 同型。
  final OverallDiagnosis? overall;

  const ParsedDiagnosis({
    required this.syndromes,
    required this.suggestedActions,
    required this.confidence,
    this.rootCauseAnalysis,
    this.nextFocus,
    this.feedbackSummary,
    this.suggestedPhase,
    this.suggestedBeginnerLevel,
    this.teachingMode,
    this.currentTeachingFocusId,
    this.focusReason,
    this.styleProfile,
    this.overall,
  });
}

/// 活跃症候视图（focus-resolver 用）
class FocusProblem {
  final String syndromeId;
  final String syndromeName;
  final Severity severity;
  final ConfirmationStatus confirmationStatus;
  final String status; // 'active' | 'resolved'
  final int? confirmedAt;

  /// ★ 治理续批第二批（2026-10-20 · R-027 批准）：形态要素 (a) —— 成段事实条数。
  /// null = 无形态证据（存量行 / 非量形式症候 / LLM 未输出）⇒ 资格闸按 v1 行为。
  final int? formFactCount;

  /// ★ 治理续批第二批（2026-10-20 · R-027 批准）：形态要素 (b) —— 结构标记。
  final String? formStructure;

  const FocusProblem({
    required this.syndromeId,
    required this.syndromeName,
    required this.severity,
    required this.confirmationStatus,
    required this.status,
    this.confirmedAt,
    this.formFactCount,
    this.formStructure,
  });
}

/// 教学状态（training-evaluator FSM）
/// 真源：yuesheng-android/src/types/profile.ts
enum TeachingState {
  identified('identified'),
  inProgress('in_progress'),
  consolidating('consolidating'),
  mastered('mastered');

  final String value;
  const TeachingState(this.value);

  static TeachingState? fromString(String? s) {
    if (s == null) return null;
    for (final v in TeachingState.values) {
      if (v.value == s) return v;
    }
    return null;
  }
}

/// 趋势判断
enum TrendJudgment {
  improving('improving'),
  stable('stable'),
  worsening('worsening'),
  insufficientData('insufficient_data');

  final String value;
  const TrendJudgment(this.value);
}

/// 综合判断结果
enum ComprehensiveJudgment {
  significantImprovement('significant_improvement'),
  improving('improving'),
  stable('stable'),
  possibleWorsening('possible_worsening'),
  worsening('worsening'),
  worseningTrend('worsening_trend'),
  insufficientData('insufficient_data');

  final String value;
  const ComprehensiveJudgment(this.value);
}

/// 恶化信号
enum DeteriorationSignal {
  relapse('relapse'),
  worsening('worsening'),
  newConcurrent('new_concurrent'),
  rebound('rebound'),
  consolidationFail('consolidation_fail');

  final String value;
  const DeteriorationSignal(this.value);
}

/// 训练结果（passed/partial/failed）
/// 真源：yuesheng-android/src/services/chat-training-parser.ts
enum TrainingResult {
  passed('passed'),
  partial('partial'),
  failed('failed');

  final String value;
  const TrainingResult(this.value);

  static TrainingResult? fromString(String? s) {
    if (s == null) return null;
    for (final v in TrainingResult.values) {
      if (v.value == s) return v;
    }
    return null;
  }
}

/// 训练自评（教学线 P0-1：mastery_evidence 三维证据的采集载体）
///
/// 对齐 `mastery_evidence.dart` 契约：
/// - confidenceRating → ConfidenceEvidence.rating（1-5，阈值 3）
/// - explanationText → ExplanationEvidence.validCount（按句切分，阈值 2）
/// - transferText → NearTransferEvidence.scenarioCount（非空 = 1，阈值 1）
///
/// 三个字段**全部可空**（R-009 用户主权：自评不强制，跳过 = null）。
class TrainingSelfAssessment {
  /// 信心评分（1-5，5 为最高）
  final int? confidenceRating;

  /// 解释文本：为什么这样改（学员思路）
  final String? explanationText;

  /// 近迁移文本：换个写法/场景会怎么做
  final String? transferText;

  /// FSRS 回忆难度自评（批1·N2，v38）：'again'|'hard'|'good'|'easy'。
  ///
  /// ★ 与上面三维证据**语义不同**，勿混用：三维 = 掌握证据（供 mastery_evidence
  /// 门控）；本字段 = 回忆难度（供 FSRS 间隔调度）。
  ///
  /// 取值的枚举真源是 `FsrsRating`（`services/spaced_repetition.dart`）；
  /// 此处刻意用裸 `String?` 而非该 enum —— **types 层不依赖 services 层**，
  /// 保持依赖方向单向（与 `result` 列用 String 同一惯例）。
  final String? userRating;

  const TrainingSelfAssessment({
    this.confidenceRating,
    this.explanationText,
    this.transferText,
    this.userRating,
  });
}

// ─────────────────────────────────────────────────────────────
// 学员画像类型 — 复刻 yuesheng-android/src/types/profile.ts
// ─────────────────────────────────────────────────────────────

/// 趋势（症候严重度演化方向）
enum Trend {
  improving('improving'),
  worsening('worsening'),
  stable('stable'),
  unknown('unknown');

  final String value;
  const Trend(this.value);

  static Trend fromString(String s) {
    for (final v in Trend.values) {
      if (v.value == s) return v;
    }
    return Trend.unknown;
  }
}

/// 能力等级
/// 真源：yuesheng-android/src/types/profile.ts
/// 补齐 elementary（映射 N1_ELEMENTS）— 批次1-8 波6
enum ProficiencyLevel {
  beginner('beginner'),
  elementary('elementary'),
  intermediate('intermediate'),
  advanced('advanced');

  final String value;
  const ProficiencyLevel(this.value);

  static ProficiencyLevel fromString(String s) {
    for (final v in ProficiencyLevel.values) {
      if (v.value == s) return v;
    }
    return ProficiencyLevel.beginner;
  }
}

/// 认知风格
enum CognitiveStyle {
  analytical('analytical'),
  intuitive('intuitive'),
  mixed('mixed');

  final String value;
  const CognitiveStyle(this.value);

  static CognitiveStyle fromString(String s) {
    for (final v in CognitiveStyle.values) {
      if (v.value == s) return v;
    }
    return CognitiveStyle.mixed;
  }
}

// ─────────────────────────────────────────────────────────────
// 写作风格画像 — 五维风格坐标（批次53 新增）
// 维度真源：yuesheng-android/src/assets/skills/writing-style.ts（五维风格坐标）
// 与症候诊断互补：诊断找"哪里不对"，风格找"哪里特别对"
// 注意：RN 端无画像层风格字段，本批 Flutter 先行（日志已标注 RN 待同步）
// ─────────────────────────────────────────────────────────────

/// 维度1：感官偏好（视觉型/听觉型/体感型/均衡型）
enum SensoryPreference {
  visual('visual'), // 视觉型：颜色/光影/形状/空间关系占主导
  auditory('auditory'), // 听觉型：大量对话/声音描写/节奏感强
  kinesthetic('kinesthetic'), // 体感型：温度/重量/触觉/身体感受优先
  balanced('balanced'); // 均衡型：多种感官自然轮换

  final String value;
  const SensoryPreference(this.value);

  static SensoryPreference fromString(String s) {
    for (final v in SensoryPreference.values) {
      if (v.value == s) return v;
    }
    return SensoryPreference.balanced;
  }
}

/// 维度2：节奏偏好（长句型/短句型/错落型/重复型）
enum RhythmPreference {
  long('long'), // 长句型：平均句长 >25 字，多从句嵌套
  short('short'), // 短句型：平均句长 <15 字，多用句号分隔
  alternating('alternating'), // 错落型：长短句有意交替
  repetitive('repetitive'); // 重复型：排比/对仗/重复结构频繁

  final String value;
  const RhythmPreference(this.value);

  static RhythmPreference fromString(String s) {
    for (final v in RhythmPreference.values) {
      if (v.value == s) return v;
    }
    return RhythmPreference.alternating;
  }
}

/// 维度3：叙事距离（贴身型/观察型/评述型/游移型）
enum NarrativeDistance {
  intimate('intimate'), // 贴身型：大量内心独白/自由间接引语
  observational('observational'), // 观察型：像摄影机客观记录
  editorial('editorial'), // 评述型：叙述者有自己的声音，会评价/感叹
  fluid('fluid'); // 游移型：距离灵活切换

  final String value;
  const NarrativeDistance(this.value);

  static NarrativeDistance fromString(String s) {
    for (final v in NarrativeDistance.values) {
      if (v.value == s) return v;
    }
    return NarrativeDistance.observational;
  }
}

/// 维度4：语气质地（诗意型/冷峻型/口语型/文雅型）
enum ToneTexture {
  poetic('poetic'), // 诗意型：修辞丰富，意象密集
  spare('spare'), // 冷峻型：简洁、克制、不修饰
  colloquial('colloquial'), // 口语型：大量口语化表达
  elegant('elegant'); // 文雅型：语言规范、用词考究

  final String value;
  const ToneTexture(this.value);

  static ToneTexture fromString(String s) {
    for (final v in ToneTexture.values) {
      if (v.value == s) return v;
    }
    return ToneTexture.spare;
  }
}

/// 维度5：结构本能（线性型/碎片型/回环型/发散型）
enum StructureInstinct {
  linear('linear'), // 线性型：按时间顺序，从头到尾
  fragmented('fragmented'), // 碎片型：跳跃、碎片化、多时间线
  circular('circular'), // 回环型：首尾呼应、反复回到核心意象
  divergent('divergent'); // 发散型：从一个点发散，联想丰富

  final String value;
  const StructureInstinct(this.value);

  static StructureInstinct fromString(String s) {
    for (final v in StructureInstinct.values) {
      if (v.value == s) return v;
    }
    return StructureInstinct.linear;
  }
}

/// 写作风格画像（五维坐标 + 一句话总结 + 置信度 + 更新时间）
///
/// 序列化 JSON 字段：
///   sensory / rhythm / narrative_distance / tone_texture / structure
///   summary / confidence / updated_at
/// 由诊断链路从 AI 输出解析并落库到 student_model.style_profile（v13）。
class WritingStyleProfile {
  final SensoryPreference sensory;
  final RhythmPreference rhythm;
  final NarrativeDistance narrativeDistance;
  final ToneTexture toneTexture;
  final StructureInstinct structure;
  final String summary; // 一句话风格描述（对齐 writing-style.ts「用学员自己的文本」）
  final double? confidence; // 识别置信度 0-1
  final int? updatedAt; // 更新时间（unix epoch）

  const WritingStyleProfile({
    required this.sensory,
    required this.rhythm,
    required this.narrativeDistance,
    required this.toneTexture,
    required this.structure,
    required this.summary,
    this.confidence,
    this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
    'sensory': sensory.value,
    'rhythm': rhythm.value,
    'narrative_distance': narrativeDistance.value,
    'tone_texture': toneTexture.value,
    'structure': structure.value,
    'summary': summary,
    if (confidence != null) 'confidence': confidence,
    if (updatedAt != null) 'updated_at': updatedAt,
  };

  /// 宽松解析：未知维度值降级为默认；缺 summary 视为非法（抛 FormatException，由调用方兜底）
  factory WritingStyleProfile.fromJson(Map<String, dynamic> json) {
    final summary = json['summary'];
    if (summary is! String) {
      throw const FormatException('style_profile 缺少 summary');
    }
    return WritingStyleProfile(
      sensory: SensoryPreference.fromString(json['sensory'] as String? ?? ''),
      rhythm: RhythmPreference.fromString(json['rhythm'] as String? ?? ''),
      narrativeDistance: NarrativeDistance.fromString(
        json['narrative_distance'] as String? ?? '',
      ),
      toneTexture: ToneTexture.fromString(
        json['tone_texture'] as String? ?? '',
      ),
      structure: StructureInstinct.fromString(
        json['structure'] as String? ?? '',
      ),
      summary: summary,
      confidence: (json['confidence'] as num?)?.toDouble(),
      updatedAt: (json['updated_at'] as num?)?.toInt(),
    );
  }
}

/// 症候聚合（多次诊断的统计）
class SyndromeAggregation {
  final String syndromeId;
  final String syndromeName;
  final int occurrenceCount;
  final List<Severity> severityHistory;
  final Severity latestSeverity;
  final Trend trend;
  final int lastSeenAt;
  final int sessionCount;
  final TeachingState teachingState;

  const SyndromeAggregation({
    required this.syndromeId,
    required this.syndromeName,
    required this.occurrenceCount,
    required this.severityHistory,
    required this.latestSeverity,
    required this.trend,
    required this.lastSeenAt,
    required this.sessionCount,
    required this.teachingState,
  });
}

/// 认知风格推断结果
class CognitiveStyleInference {
  final CognitiveStyle style;
  final double confidence;
  const CognitiveStyleInference({
    required this.style,
    required this.confidence,
  });
}

/// 学员画像（结构化）
class StudentProfile {
  final ProficiencyLevel proficiency;
  final double confidence;
  final CognitiveStyleInference? cognitiveStyle;
  final Map<String, SyndromeAggregation> syndromeProfile;
  final int totalSessions;

  const StudentProfile({
    required this.proficiency,
    required this.confidence,
    this.cognitiveStyle,
    required this.syndromeProfile,
    required this.totalSessions,
  });
}

/// 画像文本构建结果
class ProfileTextResult {
  final String text;
  final StudentProfile profile;

  /// A-1c：本次构建是否命中有效 onboarding（决定认知风格是否单独注入）
  final bool hasOnboarding;

  const ProfileTextResult({
    required this.text,
    required this.profile,
    this.hasOnboarding = false,
  });
}

/// 能力等级推断结果
class ProficiencyInference {
  final ProficiencyLevel level;
  final double confidence;
  const ProficiencyInference({required this.level, required this.confidence});
}

/// 停滞检测结果
class StagnationResult {
  final bool stagnated;
  final String? reason;
  const StagnationResult({this.stagnated = false, this.reason});
}

/// 新手引导数据
class OnboardingData {
  final ProficiencyLevel proficiency;
  final List<String> focusAreas;
  final CognitiveStyle cognitiveStyle;
  final String writingGoal;
  final int completedAt;
  final bool skipped;

  const OnboardingData({
    required this.proficiency,
    required this.focusAreas,
    required this.cognitiveStyle,
    required this.writingGoal,
    required this.completedAt,
    this.skipped = false,
  });

  factory OnboardingData.fromJson(Map<String, dynamic> json) {
    return OnboardingData(
      proficiency: ProficiencyLevel.fromString(
        json['proficiency'] as String? ?? 'beginner',
      ),
      focusAreas:
          (json['focusAreas'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      cognitiveStyle: CognitiveStyle.fromString(
        json['cognitiveStyle'] as String? ?? 'mixed',
      ),
      writingGoal: json['writingGoal'] as String? ?? '',
      completedAt: (json['completedAt'] as num?)?.toInt() ?? 0,
      skipped: json['skipped'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'proficiency': proficiency.value,
    'focusAreas': focusAreas,
    'cognitiveStyle': cognitiveStyle.value,
    'writingGoal': writingGoal,
    'completedAt': completedAt,
    'skipped': skipped,
  };
}
