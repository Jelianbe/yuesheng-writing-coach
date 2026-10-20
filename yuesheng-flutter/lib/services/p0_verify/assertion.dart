// P0 验证 · 断言粒度（M17b 唯一真源）
//
// 规格：`.ai/reports/2026-10-20-语文知识体系研究/05-P0规格-断言粒度与锚定.md` §1
// 约束（同文 §6）：纯函数、无 IO、无网络、无 LLM；不改任何既有调用点。
//
// 施工顺序（§0）：本文件先落 → `code_census.dart` 复用其粒度 → `anchor.dart` 复用其句边界。
//
// ⚠️ 三处与规格原文的偏差，均已在此显式标注，不许"实现时顺手抹平"：
//   1. SENT_END 增补半角 `.` `?` `;`。§1.2 只写了 `。！？；…!`，但 §5 的验收样例要求
//      "跨 5 种标点风格：全角句号、半角句号、问号、感叹号、分号"——不补则半角句号切不开。
//      半角 `.` 加一条保护：紧跟数字时视为小数点，不切。
//   2. `transitive_verbs` 实际 93 条，超出 §1.3.1 写的 30–50。方向是"多判断言"
//      ⇒ 分母虚高 ⇒ M17b 偏低 ⇒ 偏否决，与 §1.4 的保守方向同向（可接受）。
//   3. 字符长度用 `String.length`（UTF-16 code unit）。中文 BMP 内 1 字 = 1 unit；
//      含 emoji 时 1 字 = 2 unit，`TOO_SHORT_CHARS` 会把该引文判得更"长"，
//      方向是"少判 too_short" ⇒ 偏严格，不掩盖问题。

import 'dart:convert';

/// 断言粒度判定所用的全部词表（`assertion_lexicon@v1`）。
///
/// 词表是**判据的一部分**，不是辅助数据：换版本 = 换判据 ⇒ 臂间差异不可归因（§1.3.1 约束 4）。
class AssertionLexicon {
  AssertionLexicon({
    required this.version,
    required this.judgmentVerbs,
    required this.transitiveVerbs,
    required this.nouns,
    required this.pronouns,
    required this.aspectMarkers,
    required this.quantityTimePlace,
    required this.segmentTerms,
  });

  final String version;
  final Set<String> judgmentVerbs;
  final Set<String> transitiveVerbs;
  final Set<String> nouns;
  final Set<String> pronouns;
  final Set<String> aspectMarkers;
  final Set<String> quantityTimePlace;

  /// 分词词典。**这不是黑名单**：
  /// 黑名单是"命中后拦截"，词典是"切分依据"——后者让「因为」成为一个词、
  /// 从而不命中 `judgment_verbs` 的「为」，符合 §1.3.1「闭集成员测试、不做子串包含」。
  final Set<String> segmentTerms;

  Set<String> get _predicates => {...judgmentVerbs, ...transitiveVerbs};

  /// 最长匹配所需的词长上限（按 code unit 计）。
  late final int maxTermLength = segmentTerms.fold<int>(
    1,
    (m, t) => t.length > m ? t.length : m,
  );

  /// 从 JSON 文本加载，并校验 `counts` 与各数组实际长度**逐键相等**。
  ///
  /// 不等即抛错（§1.3.1 约束 1：不许只警告）。理由：「词表 40 条」写在文档里、
  /// 实际 120 条，是最常见的规模漂移——规模必须由文件派生，不能靠人记。
  factory AssertionLexicon.fromJsonString(String source) {
    final raw = jsonDecode(source);
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('assertion_lexicon: 根必须是 JSON 对象');
    }
    if (raw['version'] is! String) {
      throw const FormatException('assertion_lexicon: 缺少 version');
    }

    List<String> arr(String key) {
      final v = raw[key];
      if (v is! List) {
        throw FormatException('assertion_lexicon: $key 必须是数组');
      }
      return v.map((e) {
        if (e is! String || e.isEmpty) {
          throw FormatException('assertion_lexicon: $key 含非字符串或空串');
        }
        return e;
      }).toList();
    }

    final counts = raw['counts'];
    if (counts is! Map) {
      throw const FormatException('assertion_lexicon: 缺少 counts');
    }

    final lists = <String, List<String>>{
      'judgment_verbs': arr('judgment_verbs'),
      'transitive_verbs': arr('transitive_verbs'),
      'nouns': arr('nouns'),
      'pronouns': arr('pronouns'),
      'aspect_markers': arr('aspect_markers'),
      'quantity_time_place': arr('quantity_time_place'),
      'segment_terms': arr('segment_terms'),
    };

    for (final entry in lists.entries) {
      final declared = counts[entry.key];
      if (declared != entry.value.length) {
        throw FormatException(
          'assertion_lexicon: counts.${entry.key}=$declared 与数组实际长度 '
          '${entry.value.length} 不等 —— 规模漂移，加载失败',
        );
      }
      if (entry.value.isEmpty) {
        throw FormatException(
          'assertion_lexicon: ${entry.key} 为空表 —— 空表跑出来的是一堆 0，'
          '而评审看不出来（§1.3.1 第 0 步）',
        );
      }
    }

    return AssertionLexicon(
      version: raw['version'] as String,
      judgmentVerbs: lists['judgment_verbs']!.toSet(),
      transitiveVerbs: lists['transitive_verbs']!.toSet(),
      nouns: lists['nouns']!.toSet(),
      pronouns: lists['pronouns']!.toSet(),
      aspectMarkers: lists['aspect_markers']!.toSet(),
      quantityTimePlace: lists['quantity_time_place']!.toSet(),
      segmentTerms: lists['segment_terms']!.toSet(),
    );
  }

  /// 分词：最长匹配优先。
  ///
  /// 不引入 NLP 依赖（§7）。未登录字按单字成词——漏切只会让 A1–A4 少命中，
  /// 最终由 A7 兜底判「断言」，方向偏保守（§1.4）。
  List<VerifiedToken> tokenize(String sentence) {
    final out = <VerifiedToken>[];
    var i = 0;
    while (i < sentence.length) {
      var matched = false;
      final limit = (maxTermLength < sentence.length - i)
          ? maxTermLength
          : sentence.length - i;
      for (var len = limit; len >= 1; len--) {
        final sub = sentence.substring(i, i + len);
        if (segmentTerms.contains(sub)) {
          out.add(VerifiedToken(sub, i));
          i += len;
          matched = true;
          break;
        }
      }
      if (!matched) {
        out.add(VerifiedToken(sentence[i], i));
        i += 1;
      }
    }
    return out;
  }
}

/// 分词结果的一个词元（保留原文下标，供 A2/A3 的"3 字内"判定使用）。
class VerifiedToken {
  const VerifiedToken(this.text, this.start);

  final String text;
  final int start;

  int get end => start + text.length;
}

/// 单个句子在一条规则下的判定结果。
///
/// `rule` 只记录**第一条命中**的规则（规格要求按序短路），便于审计
/// "这句话为什么算/不算断言"。
class SentenceVerdict {
  const SentenceVerdict(this.sentence, this.isAssertion, this.rule);

  final String sentence;
  final bool isAssertion;

  /// 命中的规则编号：`A6` / `A5` / `A1` / `A2` / `A3` / `A4` / `A7`。
  final String rule;

  @override
  String toString() => '[$rule] ${isAssertion ? "断言" : "非"} | $sentence';
}

/// 文本切段结果。
class SegmentSplit {
  const SegmentSplit(this.segments, this.mode);

  /// 段号 = `index + 1`（与诊断输出里引用的段号同源）。
  final List<String> segments;

  /// `blank`（按空行切）或 `line`（整篇零空行的兜底）。
  final String mode;

  bool get isLineFallback => mode == 'line';
}

/// 段：**只以空行分段**；段内单换行并入同段（§1.1）。
///
/// 整篇一个空行都没有时退化为按 `\n` 切，并返回 `mode='line'`。
/// 该模式下 `M17` 的目标校验必须记 `undecidable`（§1.1 第 62–65 行），
/// 由调用方负责——本函数只如实报出 `mode`，不替调用方决定。
SegmentSplit splitSegments(String text) {
  final blocks = text
      .split(RegExp(r'\n[ \t]*\n+'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
  if (blocks.length == 1 && text.contains('\n')) {
    final lines = text
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    return SegmentSplit(lines, 'line');
  }
  return SegmentSplit(blocks, 'blank');
}

/// 句末标点（§1.2 + 偏差 1 的半角补充）。
final RegExp _sentEnd = RegExp(r'[。！？；…!?;]|\.(?!\d)');

/// 次级切分标点：**仅对不含任何 SENT_END 的句子启用**，且作用域是"句子"不是"整段"。
final RegExp _subClauseSep = RegExp(r'[，、：,]');

/// 引号字符（由外向内剥离；剥离不影响切分，切分在剥离之后做）。
const List<String> _quoteChars = [
  '「',
  '」',
  '『',
  '』',
  '“',
  '”',
  '‘',
  '’',
  '"',
  "'",
];

/// 剥引号：由外向内剥到无引号为止。
String stripQuotes(String s) {
  var out = s.trim();
  var changed = true;
  while (changed && out.isNotEmpty) {
    changed = false;
    for (final q in _quoteChars) {
      if (out.length >= 2 && out.startsWith(q) && out.endsWith(q)) {
        out = out.substring(1, out.length - 1).trim();
        changed = true;
        break;
      }
    }
    if (!changed && out.isNotEmpty && _quoteChars.contains(out[0])) {
      // 只有一侧带引号的半包情况：剥掉那一侧
      out = out.substring(1).trim();
      changed = true;
    }
    if (!changed &&
        out.isNotEmpty &&
        _quoteChars.contains(out[out.length - 1])) {
      out = out.substring(0, out.length - 1).trim();
      changed = true;
    }
  }
  return out;
}

/// 切句（§1.2）。
///
/// - `SENT_END` 为唯一主切分依据；引号与括号**不阻断**切分（对白与叙述同一把尺子）。
/// - 次级切分 `，、：` 只在"该句不含任何 SENT_END"时逐句启用。
List<String> splitSentences(String text) {
  final out = <String>[];
  for (final seg in splitSegments(text).segments) {
    // 先在 SENT_END 处切开（保留标点），再逐句决定是否次级切分
    var start = 0;
    final pieces = <String>[];
    for (var i = 0; i < seg.length; i++) {
      final ch = seg[i];
      var isEnd = _sentEnd.hasMatch(ch);
      if (ch == '.') {
        final next = (i + 1 < seg.length) ? seg[i + 1] : '';
        final isDigit = next.isNotEmpty && RegExp(r'\d').hasMatch(next);
        isEnd = !isDigit;
      }
      if (isEnd) {
        pieces.add(seg.substring(start, i + 1));
        start = i + 1;
      }
    }
    if (start < seg.length) pieces.add(seg.substring(start));

    for (final p in pieces) {
      final t = p.trim();
      if (t.isEmpty) continue;
      final body = t.replaceAll(_sentEnd, '');
      if (_subClauseSep.hasMatch(body)) {
        // 无 SENT_END 才次级切分（此处 body 已无 SENT_END，等价成立）
        for (final sub in t.split(_subClauseSep)) {
          final s = sub.trim();
          if (s.isNotEmpty) out.add(s);
        }
      } else {
        out.add(t);
      }
    }
  }
  return out;
}

/// 判定一句话是否为**断言**，返回命中的规则编号（§1.3 七条规则，按序短路）。
///
/// 顺序写死：`A6 → A5 → A1 → A2 → A3 → A4 → A7`。
///
/// ⚠️ A6 必须在 A1 之前：A1 只要含「是」就判断言，若 A1 先跑，
/// 「你是谁？」「谁是对的？」「这不就是你？」全部变成断言 ⇒ 反问进分子 ⇒ `M17b` 虚高。
SentenceVerdict classifySentence(String sentence, AssertionLexicon lex) {
  final body = stripQuotes(
    sentence,
  ).replaceAll(_sentEnd, '').replaceAll(_subClauseSep, '').trim();
  if (body.isEmpty) {
    return SentenceVerdict(sentence, false, 'A6');
  }
  final tokens = lex.tokenize(body);
  final texts = tokens.map((t) => t.text).toList();

  // A6：整句为疑问/感叹/呼语，且**不含陈述性子句**
  if (_isPureQuestionOrExclaim(sentence, lex)) {
    return SentenceVerdict(sentence, false, 'A6');
  }

  // A5：仅名词/形容词堆叠、无谓词
  if (!_hasPredicate(tokens, texts, lex)) {
    return SentenceVerdict(sentence, false, 'A5');
  }

  // A1：判断词（闭集成员测试，不做子串包含）
  if (_hasJudgment(texts, lex)) return SentenceVerdict(sentence, true, 'A1');

  // A2：及物动词 + 后 3 字内有名词/代词
  if (_hasTransitiveWithObject(tokens, lex)) {
    return SentenceVerdict(sentence, true, 'A2');
  }

  // A3：体标记 + 标记前有名词/代词（不含「得」）
  if (_hasAspectWithSubject(tokens, lex)) {
    return SentenceVerdict(sentence, true, 'A3');
  }

  // A4：数量/时间/地点 + 谓词
  if (_hasQuantityWithPredicate(body, texts, lex)) {
    return SentenceVerdict(sentence, true, 'A4');
  }

  // A7：兜底判「断言」（§1.4：把"掉出分母"这条路堵死）
  return SentenceVerdict(sentence, true, 'A7');
}

/// A6：整句为疑问/感叹/呼语，且**不含陈述性子句**。
///
/// ⚠️ 不能写成"含判断词就不算 A6"：`你是谁？` 含「是」，若因此落回 A1，
/// 反问句就进了分子 ⇒ `M17b` 虚高（这正是 A6 要排在 A1 前面的原因）。
/// 判据用「前面的子句里有没有陈述性的」——`他不是学生，怎么办？` 有，
/// 所以整句不是纯疑问句，A6 不该吃掉它。
bool _isPureQuestionOrExclaim(String sentence, AssertionLexicon lex) {
  final trimmed = sentence.trim();
  if (trimmed.isEmpty) return false;
  if (!'？?!！'.contains(trimmed[trimmed.length - 1])) return false;

  final clauses = trimmed
      .split(_subClauseSep)
      .map((c) => c.trim())
      .where((c) => c.isNotEmpty)
      .toList();
  if (clauses.length <= 1) return true;
  return !clauses.sublist(0, clauses.length - 1).any((c) {
    final bodyC = stripQuotes(
      c,
    ).replaceAll(_sentEnd, '').replaceAll(_subClauseSep, '').trim();
    if (bodyC.isEmpty) return false;
    return lex.tokenize(bodyC).any((t) => lex._predicates.contains(t.text));
  });
}

/// A5 的否命题：句中有谓词。
///
/// ⚠️ "无谓词"必须把**体标记要件**算进来，否则 `A3` 在「名词+不及物动词+了」
/// 这一大类上不可达：`剑断了` 的「断」按 A4 的谓词定义不算谓词，
/// 于是 A5 先把它判成非断言，A3 永远轮不到。规格的原始顺序（A5 在 A3 前）
/// 与 §1.5 期望（`剑断了` → 断言）在此冲突，按"期望优先"修 A5 的判定条件。
bool _hasPredicate(
  List<VerifiedToken> tokens,
  List<String> texts,
  AssertionLexicon lex,
) => texts.any(lex._predicates.contains) || _hasAspectWithSubject(tokens, lex);

/// A1：判断词（闭集成员测试，不做子串包含）。
bool _hasJudgment(List<String> texts, AssertionLexicon lex) =>
    texts.any(lex.judgmentVerbs.contains);

/// A2：及物动词 + 其后 3 字内有名词/代词。
bool _hasTransitiveWithObject(
  List<VerifiedToken> tokens,
  AssertionLexicon lex,
) {
  for (final t in tokens) {
    if (!lex.transitiveVerbs.contains(t.text)) continue;
    for (final u in tokens) {
      if (u.start < t.end || u.start - t.end > 3) continue;
      if (lex.nouns.contains(u.text) || lex.pronouns.contains(u.text)) {
        return true;
      }
    }
  }
  return false;
}

/// A3：体标记 + 标记前有名词/代词（不含「得」）。
bool _hasAspectWithSubject(List<VerifiedToken> tokens, AssertionLexicon lex) {
  for (final t in tokens) {
    if (!lex.aspectMarkers.contains(t.text)) continue;
    for (final u in tokens) {
      if (u.end > t.start) continue;
      if (lex.nouns.contains(u.text) || lex.pronouns.contains(u.text)) {
        return true;
      }
    }
  }
  return false;
}

/// A4：数量/时间/地点 + 谓词。
bool _hasQuantityWithPredicate(
  String body,
  List<String> texts,
  AssertionLexicon lex,
) {
  if (!lex.quantityTimePlace.any(body.contains)) return false;
  // 谓词 := judgment_verbs ∪ transitive_verbs（引用，不新增概念 —— §1.3 A4）
  return texts.any(lex.judgmentVerbs.contains) ||
      texts.any(lex.transitiveVerbs.contains);
}

/// 统计一段文本里的断言数（`M17b` 的分子/分母基础）。
///
/// 主口径 = **计入对白**（`m17b_exclude_dialogue = false`，预注册写死）。
/// 两个数都报，但判定只走主口径（§1.3）。要看去掉对白后的敏感性，
/// 用 [countAssertionsDetailed] 的 `dialogueAssertions`。
AssertionCount countAssertions(String text, AssertionLexicon lex) {
  final verdicts = <SentenceVerdict>[];
  var dialogueAssertions = 0;
  var dialogueChars = 0;
  var totalChars = 0;

  for (final seg in splitSegments(text).segments) {
    totalChars += seg.length;
    for (final s in splitSentences(seg)) {
      final v = classifySentence(s, lex);
      verdicts.add(v);
      final inDialogue = _isDialogue(s);
      if (inDialogue) {
        dialogueChars += s.length;
        if (v.isAssertion) dialogueAssertions++;
      }
    }
  }

  return AssertionCount(
    total: verdicts.where((v) => v.isAssertion).length,
    dialogueAssertions: dialogueAssertions,
    verdicts: verdicts,
    dialogueShare: totalChars == 0 ? 0 : dialogueChars / totalChars,
  );
}

bool _isDialogue(String s) {
  final t = s.trim();
  if (t.isEmpty) return false;
  return t.startsWith('「') || t.startsWith('“') || t.startsWith('"');
}

/// 断言计数结果。
class AssertionCount {
  const AssertionCount({
    required this.total,
    required this.dialogueAssertions,
    required this.verdicts,
    required this.dialogueShare,
  });

  /// 主口径断言数（计入对白）。
  final int total;
  final int dialogueAssertions;
  final List<SentenceVerdict> verdicts;

  /// 引号内字数 / 总字数。`> 0.6` 的篇目标 `dialogue_heavy`，
  /// **进敏感性分析，不从主口径删除**（§1.3）。
  final double dialogueShare;

  bool get isDialogueHeavy => dialogueShare > 0.6;
}
