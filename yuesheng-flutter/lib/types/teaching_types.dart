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
enum ConfirmationStatus {
  suspected('suspected'),
  confirmed('confirmed'),
  rejected('rejected'),
  ignored('ignored');

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
  doubao('doubao'),
  yuesheng('yuesheng'),
  sensei('sensei');

  final String value;
  const AttitudeLevel(this.value);

  static AttitudeLevel? fromString(String? s) {
    if (s == null) return null;
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

  const Syndrome({
    required this.syndromeId,
    required this.name,
    required this.severity,
    required this.evidence,
    required this.explanation,
    this.readerImpact,
  });

  Map<String, dynamic> toJson() => {
    'syndrome_id': syndromeId,
    'name': name,
    'severity': severity.value,
    'evidence': evidence,
    'explanation': explanation,
    if (readerImpact != null) 'reader_impact': readerImpact,
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
    );
  }
}

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

  const FocusProblem({
    required this.syndromeId,
    required this.syndromeName,
    required this.severity,
    required this.confirmationStatus,
    required this.status,
    this.confirmedAt,
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
  const ProfileTextResult({required this.text, required this.profile});
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
