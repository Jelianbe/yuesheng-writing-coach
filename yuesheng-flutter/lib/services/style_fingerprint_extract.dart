// ─────────────────────────────────────────────────────────────
// style_fingerprint 拆分：style_fingerprint_extract.dart（R-019 ≤300 行）
// 文本切分辅助 + extractStyleFingerprint。迁移自 style_fingerprint.dart，行为零变更。
// ─────────────────────────────────────────────────────────────
part of 'style_fingerprint.dart';
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

  // 段落分布（按换行切分）
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
  final paraTotal = paragraphs.isEmpty ? 1 : paragraphs.length;

  // 对话/叙述占比（按行）
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
  final dialogueRatio = dialogueLines / lineTotal;

  // 句式结构 + 句长统计
  var simpleCount = 0;
  for (final s in sentences) {
    if (_commaLike.allMatches(s).length <= 1) simpleCount++;
  }
  final (avgLen, varLen) = _sentenceLengthStats(sentences);

  // 标点特征
  final ellipsisCount = '……'.allMatches(t).length + '…'.allMatches(t).length;
  final exclamationCount = '！'.allMatches(t).length;

  // 修辞频率
  var metaphorCount = 0;
  for (final w in _metaphorWords) {
    metaphorCount += w.allMatches(t).length;
  }
  var rhetoricalCount = 0;
  for (final w in _rhetoricalQuestionWords) {
    rhetoricalCount += w.allMatches(t).length;
  }

  // 高频词指纹（2-gram 近似）
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
  final topWords = <String, int>{
    for (final e in sorted.take(kTopWordsCount)) e.key: e.value,
  };

  return StyleFingerprint(
    avgSentenceLength: avgLen,
    sentenceLengthVariance: varLen,
    shortParaRatio: shortP / paraTotal,
    mediumParaRatio: mediumP / paraTotal,
    longParaRatio: longP / paraTotal,
    dialogueRatio: dialogueRatio,
    narrativeRatio: 1 - dialogueRatio,
    simpleSentenceRatio: simpleCount / sentences.length,
    metaphorDensity: metaphorCount * 1000 / totalChars,
    rhetoricalQuestionDensity: rhetoricalCount * 1000 / totalChars,
    ellipsisDensity: ellipsisCount * 1000 / totalChars,
    exclamationDensity: exclamationCount * 1000 / totalChars,
    topWords: topWords,
    sentencesCount: sentences.length,
  );
}
