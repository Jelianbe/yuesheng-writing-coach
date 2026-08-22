// ─────────────────────────────────────────────────────────────
// Style Fingerprint — 写作风格定量指纹（B62f，A5/F10 落地）
//
// 真源参考：V2.0 §3.2 Layer3「定量指标（自动从文本提取）」8 类：
//   平均句子长度+方差 / 段落长度分布 / 对话占比 / 描写占比 /
//   高频词TOP指纹 / 句式结构 / 修辞手法频率 / 标点特征
//
// 用途：
//   1. L2→L3 沉淀：诊断章节文本时提取定量指纹，存 student_model.style_fingerprint
//   2. L3→L1 实时反馈：当前指纹 vs 基线指纹偏差超阈值 → 生成「声线漂移」
//      例证式提示（F10），由 AI 以提问方式温和指出（软引导，非硬拦截）
//
// 纯函数、无外部依赖，便于单测。
// ─────────────────────────────────────────────────────────────

part 'style_fingerprint_extract.dart';
part 'style_fingerprint_drift.dart';

/// 声线漂移检测阈值（保守，避免过度触发）
const double kDriftSentenceLengthRatio = 0.4; // 句长均值偏离 ≥40%
const double kDriftDialogueRatioAbs = 0.15; // 对话占比偏离 ≥0.15
const double kDriftSimpleRatioAbs = 0.20; // 简单句占比偏离 ≥0.20
const double kDriftExclamationMin = 5.0; // 感叹号密度（/千字）
const double kDriftExclamationBaselineMax = 2.0;
const double kDriftEllipsisMin = 8.0; // 省略号密度（/千字）
const double kDriftEllipsisBaselineMax = 3.0;

/// 指纹有效性的最小样本量
const int kFingerprintMinChars = 60;
const int kFingerprintMinSentences = 5;

/// 高频词指纹保留条目数（2-gram 近似词频）
const int kTopWordsCount = 30;

/// 写作风格定量指纹
///
/// JSON 字段（snake_case）：
///   avg_sentence_length / sentence_length_variance
///   short_para_ratio / medium_para_ratio / long_para_ratio
///   dialogue_ratio / narrative_ratio
///   simple_sentence_ratio
///   metaphor_density / rhetorical_question_density
///   ellipsis_density / exclamation_density
///   top_words / sentences_count
class StyleFingerprint {
  /// 平均句子长度（字）
  final double avgSentenceLength;

  /// 句长方差（总体方差，字²）
  final double sentenceLengthVariance;

  /// 段落分布：短（<50 字）
  final double shortParaRatio;

  /// 段落分布：中（50-200 字）
  final double mediumParaRatio;

  /// 段落分布：长（>200 字）
  final double longParaRatio;

  /// 对话占比（含引号行 / 总行数）
  final double dialogueRatio;

  /// 叙述占比（非对话行 / 总行数，描写占比的规则近似）
  final double narrativeRatio;

  /// 简单句占比（句内逗号组 ≤1 → 简单句）
  final double simpleSentenceRatio;

  /// 比喻密度（像/仿佛/如同…，每千字次数）
  final double metaphorDensity;

  /// 反问密度（难道/岂不…，每千字次数）
  final double rhetoricalQuestionDensity;

  /// 省略号密度（……/…，每千字次数）
  final double ellipsisDensity;

  /// 感叹号密度（！，每千字次数）
  final double exclamationDensity;

  /// 高频词指纹（2-gram 近似，top [kTopWordsCount]）
  final Map<String, int> topWords;

  /// 样本句数（指纹有效性判定用）
  final int sentencesCount;

  const StyleFingerprint({
    required this.avgSentenceLength,
    required this.sentenceLengthVariance,
    required this.shortParaRatio,
    required this.mediumParaRatio,
    required this.longParaRatio,
    required this.dialogueRatio,
    required this.narrativeRatio,
    required this.simpleSentenceRatio,
    required this.metaphorDensity,
    required this.rhetoricalQuestionDensity,
    required this.ellipsisDensity,
    required this.exclamationDensity,
    required this.topWords,
    required this.sentencesCount,
  });

  Map<String, dynamic> toJson() => {
    'avg_sentence_length': avgSentenceLength,
    'sentence_length_variance': sentenceLengthVariance,
    'short_para_ratio': shortParaRatio,
    'medium_para_ratio': mediumParaRatio,
    'long_para_ratio': longParaRatio,
    'dialogue_ratio': dialogueRatio,
    'narrative_ratio': narrativeRatio,
    'simple_sentence_ratio': simpleSentenceRatio,
    'metaphor_density': metaphorDensity,
    'rhetorical_question_density': rhetoricalQuestionDensity,
    'ellipsis_density': ellipsisDensity,
    'exclamation_density': exclamationDensity,
    'top_words': topWords,
    'sentences_count': sentencesCount,
  };

  /// 宽松解析：非法/缺字段时返回 null（不抛出，由调用方兜底）
  static StyleFingerprint? tryFromJson(Map<String, dynamic> json) {
    try {
      final avg = (json['avg_sentence_length'] as num?)?.toDouble();
      if (avg == null) return null;
      final topRaw = json['top_words'];
      final topWords = <String, int>{};
      if (topRaw is Map) {
        for (final e in topRaw.entries) {
          if (e.value is num) {
            topWords[e.key.toString()] = (e.value as num).toInt();
          }
        }
      }
      return StyleFingerprint(
        avgSentenceLength: avg,
        sentenceLengthVariance:
            (json['sentence_length_variance'] as num?)?.toDouble() ?? 0,
        shortParaRatio: (json['short_para_ratio'] as num?)?.toDouble() ?? 0,
        mediumParaRatio: (json['medium_para_ratio'] as num?)?.toDouble() ?? 0,
        longParaRatio: (json['long_para_ratio'] as num?)?.toDouble() ?? 0,
        dialogueRatio: (json['dialogue_ratio'] as num?)?.toDouble() ?? 0,
        narrativeRatio: (json['narrative_ratio'] as num?)?.toDouble() ?? 0,
        simpleSentenceRatio:
            (json['simple_sentence_ratio'] as num?)?.toDouble() ?? 0,
        metaphorDensity: (json['metaphor_density'] as num?)?.toDouble() ?? 0,
        rhetoricalQuestionDensity:
            (json['rhetorical_question_density'] as num?)?.toDouble() ?? 0,
        ellipsisDensity: (json['ellipsis_density'] as num?)?.toDouble() ?? 0,
        exclamationDensity:
            (json['exclamation_density'] as num?)?.toDouble() ?? 0,
        topWords: topWords,
        sentencesCount: (json['sentences_count'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }
}
