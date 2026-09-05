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

// ─── 文本切分辅助 ─────────────────────────────────────────────
/// 句末标点（中文句号/问号/感叹号）
final RegExp _sentenceSplit = RegExp(r'[。！？!?]+');

/// 对话引号
final RegExp _dialogueQuote = RegExp(r'[「」“”"]');

/// 逗号类（判定句式复杂度）
final RegExp _commaLike = RegExp(r'[，、；,;]');

/// 比喻词
const List<String> _metaphorWords = ['像', '仿佛', '如同', '犹如', '似乎', '宛如', '好像'];

/// 反问词
const List<String> _rhetoricalQuestionWords = [
  '难道',
  '岂不',
  '怎么会',
  '怎么能',
  '哪能',
  '何尝',
];

/// 句内切分句子（按句末标点，过滤空白段）
List<String> _splitSentences(String text) {
  return text
      .split(_sentenceSplit)
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
}

/// 句长均值 + 总体方差
(double avg, double variance) _sentenceLengthStats(List<String> sentences) {
  if (sentences.isEmpty) return (0, 0);
  final lens = sentences.map((s) => s.length.toDouble()).toList();
  final avg = lens.reduce((a, b) => a + b) / lens.length;
  var sumSq = 0.0;
  for (final l in lens) {
    sumSq += (l - avg) * (l - avg);
  }
  return (avg, sumSq / lens.length);
}

/// 从文本提取定量指纹；样本不足（字数 < [kFingerprintMinChars] 或
/// 句数 < [kFingerprintMinSentences]）返回 null。
StyleFingerprint? extractStyleFingerprint(String text) {
  final t = text.trim();
  if (t.length < kFingerprintMinChars) return null;

  final sentences = _splitSentences(t);
  if (sentences.length < kFingerprintMinSentences) return null;

  final totalChars = t.length.toDouble();

  final pdist = _paragraphDistribution(t);
  final dialogueRatio = _dialogueRatio(t);
  final (avgLen, varLen) = _sentenceLengthStats(sentences);
  final simpleCount = _countSimpleSentences(sentences);
  final punc = _punctuationCounts(t);
  final rhet = _rhetoricCounts(t);
  final topWords = _bigramFingerprint(sentences);

  return StyleFingerprint(
    avgSentenceLength: avgLen,
    sentenceLengthVariance: varLen,
    shortParaRatio: pdist.short / pdist.total,
    mediumParaRatio: pdist.medium / pdist.total,
    longParaRatio: pdist.long / pdist.total,
    dialogueRatio: dialogueRatio,
    narrativeRatio: 1 - dialogueRatio,
    simpleSentenceRatio: simpleCount / sentences.length,
    metaphorDensity: rhet.metaphor * 1000 / totalChars,
    rhetoricalQuestionDensity: rhet.rhetorical * 1000 / totalChars,
    ellipsisDensity: punc.ellipsis * 1000 / totalChars,
    exclamationDensity: punc.exclamation * 1000 / totalChars,
    topWords: topWords,
    sentencesCount: sentences.length,
  );
}

/// 段落分布（R-019 拆出：extractStyleFingerprint）。
({int short, int medium, int long, int total}) _paragraphDistribution(
  String t,
) {
  final paragraphs = t
      .split('\n')
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty)
      .toList();
  var shortP = 0, mediumP = 0, longP = 0;
  for (final p in paragraphs) {
    if (p.length < 50) {
      shortP++;
    } else if (p.length <= 200) {
      mediumP++;
    } else {
      longP++;
    }
  }
  final total = paragraphs.isEmpty ? 1 : paragraphs.length;
  return (short: shortP, medium: mediumP, long: longP, total: total);
}

/// 对话行占比（R-019 拆出：extractStyleFingerprint）。
double _dialogueRatio(String t) {
  final lines = t
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();
  var dialogueLines = 0;
  for (final l in lines) {
    if (_dialogueQuote.hasMatch(l)) dialogueLines++;
  }
  final lineTotal = lines.isEmpty ? 1 : lines.length;
  return dialogueLines / lineTotal;
}

/// 简单句计数（逗号类分隔 ≤1 视为简单句，R-019 拆出）。
int _countSimpleSentences(List<String> sentences) {
  var simpleCount = 0;
  for (final s in sentences) {
    if (_commaLike.allMatches(s).length <= 1) simpleCount++;
  }
  return simpleCount;
}

/// 省略号 / 感叹号计数（R-019 拆出）。
({int ellipsis, int exclamation}) _punctuationCounts(String t) {
  final ellipsisCount = '……'.allMatches(t).length + '…'.allMatches(t).length;
  final exclamationCount = '！'.allMatches(t).length;
  return (ellipsis: ellipsisCount, exclamation: exclamationCount);
}

/// 修辞词频（R-019 拆出）。
({int metaphor, int rhetorical}) _rhetoricCounts(String t) {
  var metaphorCount = 0;
  for (final w in _metaphorWords) {
    metaphorCount += w.allMatches(t).length;
  }
  var rhetoricalCount = 0;
  for (final w in _rhetoricalQuestionWords) {
    rhetoricalCount += w.allMatches(t).length;
  }
  return (metaphor: metaphorCount, rhetorical: rhetoricalCount);
}

/// 2-gram 高频词指纹（R-019 拆出：extractStyleFingerprint）。
Map<String, int> _bigramFingerprint(List<String> sentences) {
  final bigrams = <String, int>{};
  for (final s in sentences) {
    final cleaned = s.replaceAll(RegExp(r'[^\u4e00-\u9fa5]'), '');
    if (cleaned.length < 2) continue;
    for (int i = 0; i < cleaned.length - 1; i++) {
      final bg = cleaned.substring(i, i + 2);
      bigrams[bg] = (bigrams[bg] ?? 0) + 1;
    }
  }
  final sorted = bigrams.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return <String, int>{
    for (final e in sorted.take(kTopWordsCount)) e.key: e.value,
  };
}

/// 声线漂移检测：当前指纹 vs 基线指纹。
///
/// 返回例证式提示列表（最多 3 条，按显著性排序）；无偏差返回空列表。
/// 文案对齐报告 L3→L1 触发示例（"你的句子长度通常 15-20 词，但这章平均 8 词——
/// 是刻意加速还是无意识变化？"）——提问式、软引导、带具体数字。
List<String> detectVoiceDrift(
  StyleFingerprint baseline,
  StyleFingerprint current,
) {
  final hints = <String>[];
  final sentence = _sentenceLengthDriftHint(baseline, current);
  if (sentence != null) hints.add(sentence);
  final dialogue = _dialogueRatioDriftHint(baseline, current);
  if (dialogue != null) hints.add(dialogue);
  final structure = _structureRatioDriftHint(baseline, current);
  if (structure != null) hints.add(structure);
  hints.addAll(_punctuationDriftHints(baseline, current));
  return hints.take(3).toList();
}

/// 句长均值偏离提示（R-019 拆出：detectVoiceDrift）。
String? _sentenceLengthDriftHint(
  StyleFingerprint baseline,
  StyleFingerprint current,
) {
  if (baseline.avgSentenceLength <= 0) return null;
  final ratio =
      (current.avgSentenceLength - baseline.avgSentenceLength).abs() /
      baseline.avgSentenceLength;
  if (ratio < kDriftSentenceLengthRatio) return null;
  return '你的句子长度通常约 ${baseline.avgSentenceLength.round()} 字，'
      '但这段平均只有 ${current.avgSentenceLength.round()} 字——'
      '是刻意加速，还是无意识的变化？';
}

/// 对话/叙述配比偏离提示（R-019 拆出：detectVoiceDrift）。
String? _dialogueRatioDriftHint(
  StyleFingerprint baseline,
  StyleFingerprint current,
) {
  if ((current.dialogueRatio - baseline.dialogueRatio).abs() <
      kDriftDialogueRatioAbs) {
    return null;
  }
  final bPct = (baseline.dialogueRatio * 100).round();
  final cPct = (current.dialogueRatio * 100).round();
  return '你通常对话约占 $bPct%，但这段到了 $cPct%——'
      '对话和叙述的配比变化，是有意为之吗？';
}

/// 句式结构（简单句占比）偏离提示（R-019 拆出：detectVoiceDrift）。
String? _structureRatioDriftHint(
  StyleFingerprint baseline,
  StyleFingerprint current,
) {
  if ((current.simpleSentenceRatio - baseline.simpleSentenceRatio).abs() <
      kDriftSimpleRatioAbs) {
    return null;
  }
  final bPct = (baseline.simpleSentenceRatio * 100).round();
  final cPct = (current.simpleSentenceRatio * 100).round();
  return '你惯用的句式偏${baseline.simpleSentenceRatio >= 0.5 ? '简短' : '绵长'}'
      '（简单句约 $bPct%），这段到了 $cPct%——'
      '是情绪需要，还是节奏不自觉地变了？';
}

/// 标点特征偏离（感叹号/省略号激增）提示列表（R-019 拆出）。
List<String> _punctuationDriftHints(
  StyleFingerprint baseline,
  StyleFingerprint current,
) {
  final hints = <String>[];
  if (current.exclamationDensity >= kDriftExclamationMin &&
      baseline.exclamationDensity < kDriftExclamationBaselineMax) {
    hints.add(
      '这段感叹号比平时多不少（每千字 ${current.exclamationDensity.round()} 个）——'
      '是情绪强烈，还是语气不自觉地变急了？',
    );
  }
  if (current.ellipsisDensity >= kDriftEllipsisMin &&
      baseline.ellipsisDensity < kDriftEllipsisBaselineMax) {
    hints.add(
      '这段省略号用得比平时密（每千字 ${current.ellipsisDensity.round()} 次）——'
      '是留白的刻意安排吗？',
    );
  }
  return hints;
}
