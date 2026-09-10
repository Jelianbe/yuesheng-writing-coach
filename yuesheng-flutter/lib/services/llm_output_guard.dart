// ─────────────────────────────────────────────────────────────
// llm_output_guard — AI 输出轻量校验 + extractJSON 容错（入档批次）
//
// 对齐外来《AI小说写作工具_安全设计.md》§12.2 OutputValidator 与
// 《中间件管道完整实现.md》§七 extractJSON，适配月笙形态：
//
// 一、assessLlmOutput 三判据（空输出 / 重复 loop / 元文本）：
//   只做「评估 + 可观测留痕」，**不截断不改行为**——写作教练场景下
//   误拦正常创作的风险高于模型抽风，阈值校准后再决定是否截断。
//   - 空输出：trim 后为空
//   - 重复 loop：连续相同行 ≥ [minRepeatLines]（默认 5，对齐
//     `\n(.+)\n(\1\n){5,}` 语义；仅行级连续重复，防止误拦正常段落）
//   - 元文本：模型身份声明短语白名单（精确匹配，不泛化）
//
// 二、extractJsonObject：从任意 LLM 输出提取第一个顶层 JSON
//   （对象或数组）。比 progressive_diagnosis 既有 extractJson 更强：
//   - 代码块围栏支持 json / 任意语言标签
//   - 括号平衡支持嵌套 + 字符串内括号（\ " 转义）
//   - 顶层数组（[]）与对象（{}）都支持
//   - 尾逗号清理
// ─────────────────────────────────────────────────────────────

/// 模型身份声明短语（命中即元文本，精确包含匹配，不泛化防误拦）
const List<String> _kModelMetaPhrases = [
  '我是一个AI',
  '我是AI',
  '我是一个AI助手',
  '我作为语言模型',
  '作为AI语言模型',
  '作为一个AI',
  '我是人工智能',
  '我不能作为',
  '我不能直接',
];

/// 输出评估结果（只描述，不干预）
class LlmOutputAssessment {
  final bool isBlank;
  final bool hasRepetition;
  final bool hasMetaText;

  /// 首个命中的说明（定位用）
  final String? detail;

  const LlmOutputAssessment({
    required this.isBlank,
    required this.hasRepetition,
    required this.hasMetaText,
    this.detail,
  });

  bool get isProblematic => isBlank || hasRepetition || hasMetaText;
}

/// 三判据评估（空输出 / 重复 loop / 元文本）
LlmOutputAssessment assessLlmOutput(String content, {int minRepeatLines = 5}) {
  final trimmed = content.trim();
  if (trimmed.isEmpty) {
    return const LlmOutputAssessment(
      isBlank: true,
      hasRepetition: false,
      hasMetaText: false,
      detail: 'blank_output',
    );
  }

  // 重复 loop：连续相同行 ≥ minRepeatLines（行级连续重复）
  final lines = trimmed.split('\n');
  String? repeatDetail;
  if (lines.length >= minRepeatLines) {
    var run = 1;
    for (var i = 1; i < lines.length; i++) {
      if (lines[i].trim() == lines[i - 1].trim() &&
          lines[i].trim().isNotEmpty) {
        run++;
        if (run >= minRepeatLines) {
          repeatDetail = 'repetition_line_${i + 1}_x$run="${_clip(lines[i])}"';
          break;
        }
      } else {
        run = 1;
      }
    }
  }

  // 元文本：身份声明短语
  String? metaDetail;
  for (final phrase in _kModelMetaPhrases) {
    if (trimmed.contains(phrase)) {
      metaDetail = 'meta_phrase="$phrase"';
      break;
    }
  }

  return LlmOutputAssessment(
    isBlank: false,
    hasRepetition: repeatDetail != null,
    hasMetaText: metaDetail != null,
    detail: repeatDetail ?? metaDetail,
  );
}

/// 从 LLM 输出提取第一个顶层 JSON（对象或数组）的原始文本。
/// 提取失败返回 null（不抛异常）。
String? extractJsonObject(String raw) {
  // 1. 优先代码块围栏（json / 任意语言标签）
  final fence = RegExp(
    r'```[a-zA-Z0-9_]*\s*\n?([\[{][\s\S]*?[\]}])\s*\n?```',
  ).firstMatch(raw);
  if (fence != null && fence.groupCount >= 1) {
    final candidate = fence.group(1)!;
    if (_isBalanced(candidate)) return candidate;
  }

  // 2. 括号平衡：从第一个 { 或 [ 到匹配的结束括号
  final start = _firstJsonStart(raw);
  if (start == -1) return null;
  final end = _matchingEnd(raw, start);
  if (end == -1) return null;
  return _stripTrailingComma(raw.substring(start, end + 1));
}

bool _isBalanced(String s) {
  return _matchingEnd(s, 0) == s.length - 1;
}

int _firstJsonStart(String s) {
  var inString = false;
  var escape = false;
  for (var i = 0; i < s.length; i++) {
    final ch = s[i];
    if (inString) {
      if (escape) {
        escape = false;
      } else if (ch == r'\') {
        escape = true;
      } else if (ch == '"') {
        inString = false;
      }
      continue;
    }
    if (ch == '"') {
      inString = true;
    } else if (ch == '{' || ch == '[') {
      return i;
    }
  }
  return -1;
}

/// 从 [start]（必须是 { 或 [）找匹配结束下标；字符串内括号不计。
int _matchingEnd(String s, int start) {
  final open = s[start];
  final close = open == '{' ? '}' : ']';
  var depth = 0;
  var inString = false;
  var escape = false;
  for (var i = start; i < s.length; i++) {
    final ch = s[i];
    if (inString) {
      if (escape) {
        escape = false;
      } else if (ch == r'\') {
        escape = true;
      } else if (ch == '"') {
        inString = false;
      }
      continue;
    }
    if (ch == '"') {
      inString = true;
    } else if (ch == open) {
      depth++;
    } else if (ch == close) {
      depth--;
      if (depth == 0) return i;
    }
  }
  return -1;
}

/// 剥尾逗号（对象/数组最后一个元素后的逗号，JSON5 常见）
String _stripTrailingComma(String s) {
  final trimmed = s.trim();
  if (trimmed.length < 2) return trimmed;
  final beforeClose = trimmed[trimmed.length - 2];
  if (beforeClose == ',') {
    return trimmed.substring(0, trimmed.length - 2) +
        trimmed[trimmed.length - 1];
  }
  return trimmed;
}

String _clip(String s) {
  if (s.length <= 24) return s;
  return '${s.substring(0, 24)}…';
}
