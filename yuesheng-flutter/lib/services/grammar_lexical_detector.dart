// ─────────────────────────────────────────────────────────────
// grammar_lexical_detector — F12 文法与重复用词检测（批次70）
//
// 规格（V2.0 §3.3 F12）：基础语法 + 重复用词检测，Lv1（初学段价值高）。
// 观察项挂 P022 重复用词/基础语病症候补充（新建症候，批次70）。
// 纯函数、无 IO，规则保守精确（避免误报）：
//   1. 相邻重复虚词（的了很是不和在把被着过也就都又再你我他她们）
//   2. 连续重复标点（，，。。！！？？）
//   3. 连续多句同一词起头（≥3 句）
//   4. 高频连接词密度（短篇幅内 ≥3 次）
// ─────────────────────────────────────────────────────────────

/// 基础文法问题类型
enum GrammarIssueKind {
  /// 相邻重复虚词（如「的了了」）
  dupChar,

  /// 连续重复标点（如「。。」）
  dupPunct,

  /// 连续多句同一词起头
  sentenceStartRepeat,

  /// 高频连接词密度
  frequentWord,
}

/// 基础文法观察项（挂 P022 补充输入）
class GrammarLexicalIssue {
  final GrammarIssueKind kind;
  final String evidence; // 原文片段（5-20 字）
  final String description; // 人类可读描述

  const GrammarLexicalIssue({
    required this.kind,
    required this.evidence,
    required this.description,
  });
}

/// 相邻重复即视为语病的虚词集合（实词叠词如「人人/天天」合法，不检测）
const Set<String> _dupSensitiveChars = {
  '的',
  '了',
  '很',
  '是',
  '不',
  '和',
  '在',
  '把',
  '被',
  '着',
  '过',
  '也',
  '就',
  '都',
  '又',
  '再',
  '你',
  '我',
  '他',
  '她',
  '们',
  '将',
  '向',
  '从',
  '与',
  '或',
};

/// 高频连接词集合（短篇幅内反复出现 → 机械感）
const Set<String> _frequentConnectives = {
  '然后',
  '但是',
  '可是',
  '忽然',
  '突然',
  '终于',
  '这时',
  '此时',
};

/// 高频词判定的最短文本长度（低于此长度不做词频判定，避免误报）
const int _minTextForFrequency = 200;

/// 高频词判定阈值（该词出现 ≥ 此次数 → 观察项）
const int _frequentWordThreshold = 3;

/// 句首重复判定阈值（连续 ≥ 此句数同一起头词 → 观察项）
const int _sentenceStartRepeatThreshold = 3;

/// 检测文本的基础文法与重复用词问题
///
/// 规则（保守，纯字符串精确比较）：
///   1. 相邻重复虚词：连续两个相同汉字且属于 [_dupSensitiveChars]；
///   2. 连续重复标点：`，，` `。。` `！！` `？？`；
///   3. 句首重复：连续 ≥3 句以同一词（前 2 字）起头；
///   4. 高频连接词：文本 ≥200 字且某连接词出现 ≥3 次。
/// 输出按出现顺序（不排序），无问题返回空列表。
List<GrammarLexicalIssue> detectGrammarLexicalIssues(String text) {
  final issues = <GrammarLexicalIssue>[];
  if (text.trim().isEmpty) return issues;

  _detectDupChars(text, issues);
  _detectDupPuncts(text, issues);
  _detectSentenceStartRepeats(text, issues);
  _detectFrequentConnectives(text, issues);
  return issues;
}

/// 1. 相邻重复虚词
void _detectDupChars(String text, List<GrammarLexicalIssue> issues) {
  for (int i = 0; i + 1 < text.length; i++) {
    final a = text[i];
    final b = text[i + 1];
    if (a == b && _dupSensitiveChars.contains(a)) {
      final evidence = _around(text, i, 6);
      issues.add(
        GrammarLexicalIssue(
          kind: GrammarIssueKind.dupChar,
          evidence: evidence,
          description: '相邻重复字「$a」',
        ),
      );
      // 跳过重复位置，避免同一处连报（如「了了了」只报一次）
      i += 1;
    }
  }
}

/// 2. 连续重复标点
void _detectDupPuncts(String text, List<GrammarLexicalIssue> issues) {
  final pattern = RegExp(r'([，。！？])\1+');
  for (final match in pattern.allMatches(text)) {
    final punct = match.group(0)!;
    final evidence = _around(text, match.start, 6);
    issues.add(
      GrammarLexicalIssue(
        kind: GrammarIssueKind.dupPunct,
        evidence: evidence,
        description: '连续重复标点「$punct」',
      ),
    );
  }
}

/// 3. 连续多句同一词起头
void _detectSentenceStartRepeats(
  String text,
  List<GrammarLexicalIssue> issues,
) {
  final sentences = text
      .split(RegExp(r'[。！？]'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
  if (sentences.length < _sentenceStartRepeatThreshold) return;

  var runStart = 0;
  var runWord = _startWord(sentences[0]);
  for (int i = 1; i <= sentences.length; i++) {
    final word = i < sentences.length ? _startWord(sentences[i]) : null;
    if (word != null && word == runWord) continue;

    // 一段同起头运行结束：runStart..i-1
    final runLength = i - runStart;
    if (runLength >= _sentenceStartRepeatThreshold && runWord.isNotEmpty) {
      final evidence = '${sentences[runStart]}…${sentences[i - 1]}';
      issues.add(
        GrammarLexicalIssue(
          kind: GrammarIssueKind.sentenceStartRepeat,
          evidence: _clip(evidence, 20),
          description: '连续 $runLength 句以「$runWord」开头',
        ),
      );
    }
    if (i < sentences.length) {
      runStart = i;
      runWord = _startWord(sentences[i]);
    }
  }
}

/// 4. 高频连接词密度
void _detectFrequentConnectives(String text, List<GrammarLexicalIssue> issues) {
  if (text.length < _minTextForFrequency) return;
  for (final word in _frequentConnectives) {
    final count = _countOccurrences(text, word);
    if (count >= _frequentWordThreshold) {
      final idx = text.indexOf(word);
      final evidence = _around(text, idx, 6);
      issues.add(
        GrammarLexicalIssue(
          kind: GrammarIssueKind.frequentWord,
          evidence: evidence,
          description: '「$word」出现 $count 次（${text.length} 字）',
        ),
      );
    }
  }
}

/// 取句子的起头词（前 2 个字符）
String _startWord(String sentence) {
  if (sentence.length >= 2) return sentence.substring(0, 2);
  return sentence;
}

/// 取 [index] 附近 ±[radius] 字的片段
String _around(String text, int index, int radius) {
  final start = index - radius < 0 ? 0 : index - radius;
  final end = index + radius > text.length ? text.length : index + radius;
  return _clip(text.substring(start, end), 20);
}

/// 截断到 [maxLen] 字（超长加省略号）
String _clip(String s, int maxLen) {
  if (s.length <= maxLen) return s;
  return '${s.substring(0, maxLen)}…';
}

/// 统计 [word] 在 [text] 中的非重叠出现次数
int _countOccurrences(String text, String word) {
  var count = 0;
  var idx = text.indexOf(word);
  while (idx != -1) {
    count++;
    idx = text.indexOf(word, idx + word.length);
  }
  return count;
}
