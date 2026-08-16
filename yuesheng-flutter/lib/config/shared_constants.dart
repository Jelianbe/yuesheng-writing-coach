// ─────────────────────────────────────────────────────────────
// 跨组件共享常量 — 复刻 yuesheng-android/src/config/shared-constants.ts
// 仅搬运调度链路所需的常量（LLM / 上下文预算 / 诊断锁定 / Teacher门控等）
// UI 相关常量（素材/头像/时间格式化）暂不搬运，待 UI 批次再补
// ─────────────────────────────────────────────────────────────

/// LLM 客户端配置
class LlmConfig {
  const LlmConfig._();
  static const int testMaxTokens = 5;
  static const int testTimeoutMs = 15000;
  static const double chatTemperature = 0.3;
  static const int chatMaxTokens = 4096;
  static const int chatTimeoutMs = 60000;
  static const double streamTemperature = 0.7;
  static const int streamTimeoutMs =
      180000; // 流式 3 分钟兜底：SSE 大响应深求索服务器可能 40s+ 后主动断
  static const int errorPreviewLength = 100;
  static const int errorPreviewLengthLong = 200;
}

/// 上下文预算（chat-service 引用注入）
class ContextBudget {
  const ContextBudget._();
  static const int totalBudget = 15000;
  static const double primaryRatio = 0.75;
  static const double secondaryRatio = 0.25;
  static const int smartTruncateMinThreshold = 60;
  static const double truncateFrontRatio = 0.6;
  static const int minPerFileBudget = 200;
  static const int manuscriptPreviewChapterCount = 2;
  static const int minPreviewBudget = 200;
}

/// 诊断锁定阈值
class DiagnosisLock {
  const DiagnosisLock._();
  static const double minConfidence = 0.7;
  static const int minEvidenceCount = 2;
  static const int consecutiveFailThreshold = 2;
  static const int disputeThreshold = 2;
}

/// 诊断相关阈值
class DiagnosisLimits {
  const DiagnosisLimits._();
  static const int repeatSyndromeThreshold = 2;
  static const int rewritePreviewLength = 60;
  static const int doubleRejectThreshold = 2;
  static const int discoveryQuestionThreshold = 2;
}

/// UI 列表限制（真源：shared-constants.ts UI_LIMITS 章节选择器部分）
class UILimits {
  const UILimits._();

  /// 章节选择器初始显示章节数（性能优化，避免一次性渲染大量章节）
  static const int chapterListInitial = 50;

  /// 章节选择器每次加载更多章节数
  static const int chapterListLoadMore = 50;

  /// 诊断最短章节字数（<100 字提示先编辑）
  static const int diagnosisWordThreshold = 100;

  /// PhaseSummaryCard 症候变化列表最大展示条数（真源 UI_LIMITS.MAX_SYNDROME_CHANGES）
  static const int maxSyndromeChanges = 5;

  /// DiagnosisFailedCard 显示额外提示的失败次数阈值（真源 UI_LIMITS.FAILURE_WARNING_THRESHOLD）
  static const int failureWarningThreshold = 2;
}

/// 训练调度阈值
class TrainingThresholds {
  const TrainingThresholds._();
  static const int cooldownHours = 24;
  static const int stuckTrainingCount = 3;
  static const int forceUpgradeConsecutivePasses = 3;
  static const int tryUpgradeConsecutivePasses = 2;
  static const int maxDifficultyLevel = 3;
  static const double passRateImproving = 0.8;
  static const double passRateStable = 0.4;
}

/// 评估阈值
class EvaluationThresholds {
  const EvaluationThresholds._();
  static const double passRateImproving = 0.7;
  static const double passRateWorsening = 0.4;
  static const double phasePassRate = 0.7;
  static const double phaseFailRate = 0.4;
  static const double stableSubdivide = 0.5;
}

/// Token 估算与预算
class TokenEstimate {
  const TokenEstimate._();
  static const int maxBudget = 50000;
  static const double charToTokenRatio = 0.4;
  static const double warningRatio = 0.8;
}

/// Reviewer 门控配置（默认关闭）
class ReviewerGate {
  const ReviewerGate._();
  static const bool enabled = false;
  static const int minTextLength = 500;
  static const double reviewerTemperature = 0.2;
  static const int reviewerMaxTokens = 800;
}

/// Teacher 门控配置（已启用）
class TeacherGate {
  const TeacherGate._();
  static const bool enabled = true;
  static const double teacherTemperature = 0.2;
  static const int teacherMaxTokens = 1500;
  static const int editorPronouncedThreshold = 1;
  static const int editorAgainstThreshold = 2;
  static const int diagnosisSyndromeCountThreshold = 3;
}

/// 焦点切换阈值
class FocusSwitch {
  const FocusSwitch._();
  static const int threshold = 3;
}

/// 文件解析阈值（真源：shared-constants.ts FILE_PARSER_LIMITS）
class FileParserLimits {
  const FileParserLimits._();

  /// 章节标题最大长度（txt 正则匹配模式）
  static const int chapterTitleMaxLength = 50;

  /// 一级标题最大长度（markdown # 模式）
  static const int heading1MaxLength = 80;
}

/// 学员画像：能力等级判定阈值
/// 真源：shared-constants.ts PROFICIENCY_THRESHOLDS
class ProficiencyThresholds {
  const ProficiencyThresholds._();
  // 初级判定
  static const int beginnerL3CountThreshold = 3;
  static const int beginnerL2CountThreshold = 5;
  static const double maxBeginnerL3Confidence = 0.9;
  static const double baseBeginnerL3Confidence = 0.4;
  static const double maxBeginnerL2Confidence = 0.8;
  static const double baseBeginnerL2Confidence = 0.3;
  // 高级判定
  static const int advancedRecentWindow = 5;
  static const int advancedRecentMin = 3;
  static const double advancedConfidence = 0.8;
  // 中级判定（样本数 → 置信度）
  static const int intermediateLowSampleThreshold = 3;
  static const int intermediateMidSampleThreshold = 10;
  static const double lowSampleConfidence = 0.4;
  static const double midSampleConfidence = 0.7;
  static const double highSampleConfidence = 0.9;
  // 停滞检测
  static const int stagnationMinSessions = 3;
  static const int stagnationMinDiagnoses = 5;
  static const int stagnationMinSeverityHistory = 4;
}

/// 学员画像：症候优先级评分权重
/// 真源：shared-constants.ts SYNDROME_PRIORITY_WEIGHTS
class SyndromePriorityWeights {
  const SyndromePriorityWeights._();
  static const double frequencyFactor = 1.5;
  static const double severityFactor = 3;
  static const double trendWorsening = 2;
  static const double trendImproving = -1;
  static const double stateInProgress = 3;
  static const double stateIdentified = 1;
  static const double stateMastered = -5;
}

/// 学员画像：认知风格阈值
/// 真源：shared-constants.ts COGNITIVE_STYLE_THRESHOLDS
class CognitiveStyleThresholds {
  const CognitiveStyleThresholds._();
  static const double analyticalRatio = 2;
  static const double intuitiveRatio = 0.5;
  static const double analyticalMaxConfidence = 0.9;
  static const double analyticalBaseConfidence = 0.4;
  static const double analyticalStepFactor = 0.05;
  static const double mixedMaxConfidence = 0.6;
  static const double mixedBaseConfidence = 0.3;
  static const double mixedStepFactor = 0.03;
}

/// 态度切换阈值
class AttitudeThresholds {
  const AttitudeThresholds._();
  static const int suggestionCooldownMs = 10 * 60 * 1000;
  static const int minMessageCount = 5;
  static const double upgradeSeverityThreshold = 2.2;
  static const double upgradeSeverityThresholdHigh = 1.8;
  static const int upgradeSyndromeCount = 2;
  // 对齐教学策略（skill_registry §态度档位切换）：用户挫败/负反馈 → 降档；积极跟上 → 升档
  static const int negativeFeedbackDowngradeCount = 3;
  static const int upgradeMessageCountHigh = 15;
  static const int positiveFeedbackUpgradeCount = 4;
  static const int downgradeMessageCount = 10;
  static const double downgradeSeverityThreshold = 1.2;
  static const int downgradeSyndromeCount = 1;
}

/// 判决词黑名单（editor-validator / teacher-validator 共享）
const List<String> verdictDangerousWords = [
  '应该',
  '必须',
  '务必',
  '应当',
  '你要',
  '你可以试着',
  '需要修改',
  '需要重写',
  '需要调整',
  '需要增加',
  '需要删除',
  '需要补充',
  '重写',
  '不好',
  '失败',
  '糟糕',
  '拖沓',
  '平庸',
  '缺陷',
  '建议你',
  '修改成',
  '改成',
];

/// 批次4（4.6）：诊断 V-02 判定句词表——"你+指令动词"句式（AI 不应替学员做决定）。
/// 与 [verdictDangerousWords] 同源语义，按角色策略引用：
///   - diagnosis_validator V-02：仅记录（warning 级）
///   - editor_validator / teacher_validator：hard-limit 拦截（verdictDangerousWords）
/// 抽为共享常量防双份维护漂移。
const List<String> diagnosisVerdictPhrases = [
  '你应该',
  '你务必',
  '你必须',
  '你要',
  '你可以试着',
];

/// 批次4（4.4）：学员负反馈关键词——"太深奥/听不懂/太快了"类挫败信号，
/// 用于代码层识别态度降档触发（补充 suggestAttitudeAdjustment 的负反馈计数）。
const List<String> negativeFeedbackPhrases = [
  '太深奥',
  '听不懂',
  '太快了',
  '换个说法',
  '看不懂',
  '太复杂',
  '不明白',
  '跟不上了',
  '你说慢点',
];

/// 批次4（4.4）：负反馈检测——文本命中负反馈关键词即视为一次挫败信号。
/// 仅做关键词包含判断（纯函数），供态度判定链路统计连续负反馈次数。
bool containsNegativeFeedback(String text) {
  for (final phrase in negativeFeedbackPhrases) {
    if (text.contains(phrase)) return true;
  }
  return false;
}

/// 批次4（4.4）：安全词「轻一点」降档请求检测（带上下文判断）。
/// 以下情况不视为态度降档请求：
///   - 引号内引用（如 她说了"轻一点"）——是转述而非请求
///   - 写作示例（如 这句改成"轻一点"更合适）——是教学内容
///   - 含「语气措辞」术语（如 用"轻一点"这个语气措辞）——是术语讨论
bool isSafetyWordRequest(String text) {
  if (!text.contains('轻一点')) return false;
  // 剥离引号包裹的「轻一点」后仍有裸命中 → 才是降档请求
  final stripped = text
      .replaceAll('"轻一点"', '')
      .replaceAll('「轻一点」', '')
      .replaceAll("'轻一点'", '');
  if (!stripped.contains('轻一点')) return false;
  if (text.contains('语气措辞') || text.contains('措辞')) return false;
  return true;
}

/// 字数格式化（真源：shared-constants.ts WORD_COUNT_FORMAT + formatWordCount）
class WordCountFormat {
  const WordCountFormat._();
  static const int wanThreshold = 10000;
  static const int wanDecimals = 1;
}

/// 字数格式化：>=10000 → "1.2万字"，否则 → "3,256字"（千位分隔符）
String formatWordCount(int n) {
  if (n >= WordCountFormat.wanThreshold) {
    return '${(n / WordCountFormat.wanThreshold).toStringAsFixed(WordCountFormat.wanDecimals)}万字';
  }
  return '${_thousandSeparate(n)}字';
}

String _thousandSeparate(int n) {
  final s = n.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    buf.write(s[i]);
    final remaining = s.length - 1 - i;
    if (remaining > 0 && remaining % 3 == 0) buf.write(',');
  }
  return buf.toString();
}
