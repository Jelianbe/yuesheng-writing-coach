// ─────────────────────────────────────────────────────────────
// dialogue_tag_detector — F02 对话标签过度检测（批次71）
//
// 规格（V2.0 §3.3 F02）：对话行/非"说"类标签比例，Lv1。
// 观察项挂 P011 对话疲劳症增强补充（不新建症候）。
// 纯函数、无 IO，规则保守精确（避免误报）：
//   1. 提取对话行（「」/『』/双引号包裹的对话片段）
//   2. 检测对话后紧跟的修饰性标签（词根 + 说/道/问/喊/答 等后缀）
//   3. 同一词根标签重复 ≥2 次 → 观察项（对齐 V2.0 示例「12 个'低声'」）
// 刻意不做「修饰标签密度比例」规则：词库覆盖敏感、误报风险高，
// 先验证同标签重复稳定后再增强（保守铁律）。
// ─────────────────────────────────────────────────────────────

/// 对话标签过度问题类型
enum DialogueTagIssueKind {
  /// 同一修饰性对话标签重复（如「低声说」出现 ≥2 次）
  tagRepeat,
}

/// 对话标签过度观察项（挂 P011 增强补充输入）
class DialogueTagIssue {
  final DialogueTagIssueKind kind;
  final String evidence; // 原文片段（5-20 字）
  final String description; // 人类可读描述

  const DialogueTagIssue({
    required this.kind,
    required this.evidence,
    required this.description,
  });
}

/// 修饰性对话标签词根（非中性「说/道/问」，带修饰成分的副词/拟声）
const Set<String> _adverbTagRoots = {
  '低声',
  '轻声',
  '细声',
  '悄声',
  '小声',
  '呢喃',
  '低语',
  '喃喃',
  '嘟囔',
  '嘀咕',
  '冷冷',
  '淡淡',
  '缓缓',
  '沉声',
  '厉声',
  '急切',
  '温柔',
  '平静',
  '机械',
  '没好气',
};

/// 对话标签后缀（词根 + 可选中缀「的」 + 后缀 = 修饰性标签）
const Set<String> _tagSuffixes = {'说', '道', '问', '喊', '应', '答', '开口', '出声'};

/// 启用检测的最少对话行数（低于此数量不做判定，避免短文本误报）
const int _minDialogueLines = 3;

/// 同词根标签重复阈值（出现 ≥ 此次数 → 观察项）
const int _tagRepeatThreshold = 2;

/// 对话片段结束后的标签候选窗口长度（字）
const int _labelWindow = 10;

/// 对话片段正则（中文「」/『』与英文双引号）
final RegExp _dialoguePattern = RegExp(r'[「『"]([^」』"]*)[」』"]');

/// 检测文本的对话标签过度问题
///
/// 规则（保守，纯字符串精确比较）：
///   1. 提取对话片段，统计对话行数；
///   2. 对话行数 ≥3 时启用检测；
///   3. 对每个对话片段，取其后 [_labelWindow] 字窗口，匹配
///      「词根（的）?后缀」标签模式；
///   4. 同一词根标签出现 ≥2 次 → 观察项。
/// 输出按词根出现顺序（不排序），无问题返回空列表。
List<DialogueTagIssue> detectDialogueTagIssues(String text) {
  final issues = <DialogueTagIssue>[];
  if (text.trim().isEmpty) return issues;

  final dialogueMatches = _dialoguePattern.allMatches(text).toList();
  if (dialogueMatches.length < _minDialogueLines) return issues;

  final rootCount = <String, int>{};
  final rootEvidence = <String, String>{};
  for (final match in dialogueMatches) {
    final dialogueEnd = match.end;
    final window = _window(text, dialogueEnd, _labelWindow);
    for (final root in _adverbTagRoots) {
      if (_hasTag(window, root)) {
        rootCount[root] = (rootCount[root] ?? 0) + 1;
        rootEvidence.putIfAbsent(root, () => _clip(window, 20));
      }
    }
  }

  for (final entry in rootCount.entries) {
    if (entry.value >= _tagRepeatThreshold) {
      issues.add(
        DialogueTagIssue(
          kind: DialogueTagIssueKind.tagRepeat,
          evidence: rootEvidence[entry.key]!,
          description: '「${entry.key}」类对话标签出现 ${entry.value} 次',
        ),
      );
    }
  }
  return issues;
}

/// 判断 [window] 内是否含「[root]（的）?后缀」标签模式
bool _hasTag(String window, String root) {
  final pattern = RegExp('${RegExp.escape(root)}(的)?(${_suffixPattern()})');
  return pattern.hasMatch(window);
}

/// 拼接后缀选择模式（按长度降序避免「开口」被「开」截断）
String _suffixPattern() {
  final sorted = _tagSuffixes.toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  return sorted.map(RegExp.escape).join('|');
}

/// 取 [start] 起最多 [len] 字的窗口
String _window(String text, int start, int len) {
  final end = start + len > text.length ? text.length : start + len;
  if (start >= text.length) return '';
  return text.substring(start, end);
}

/// 截断到 [maxLen] 字（超长加省略号）
String _clip(String s, int maxLen) {
  if (s.length <= maxLen) return s;
  return '${s.substring(0, maxLen)}…';
}
