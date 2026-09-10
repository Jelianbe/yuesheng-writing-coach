// ─────────────────────────────────────────────────────────────
// prompt_sanitizer — 用户输入侧 Prompt 注入防御（L2 档）
//
// 背景（设计文档《Prompt模板设计》借鉴 + R-027 人工确认）：
//   用户内容夹带模型指令 token（<system>、[INST] 等）可被用于
//   反向攻击（"忽略以上指令"）。本清洗器只做**已知指令 token 的
//   转义**（全角括号），不替换普通文本——写作场景用户原文必须
//   完整进入模型，任何内容损失都是不可接受的。
//
// 原则：
//   - 只命中白名单内的指令 token（大小写不敏感），普通文本里的
//     <xxx> / [xxx]（如小说对话标记）不受影响 → 零误伤
//   - 转义（全角括号）保留可读性，不删除内容
//   - 行级连续分隔符（整行 ---）转中文破折号，破坏"指令分隔区"
//     的视觉锚点，但保留分隔语义
//   - 纯函数，无 IO，可单测
// ─────────────────────────────────────────────────────────────

/// 已知模型指令 token（小写、无包裹符）。命中即转义。
const List<String> _instructionTokens = [
  'system',
  'user',
  'assistant',
  'im_start',
  'im_end',
  'sys',
  'inst',
  '/inst',
  'human',
  'ai',
  'assistant_response',
];

/// 行级连续短横分隔符（整行 ≥3 个 `-`，markdown 水平线形态）。
final RegExp _lineDashSeparator = RegExp(r'^\s*-{3,}\s*$', multiLine: true);

/// 转义用户内容中的已知指令 token 与行级分隔符。
///
/// 返回清洗后文本。无命中时返回原串（不复制、不变）。
String sanitizeUserContent(String content) {
  if (content.isEmpty) return content;
  var result = _escapeInstructionTokens(content);
  result = result.replaceAll(_lineDashSeparator, '———');
  return result;
}

/// 指令 token 转义：`<system>` / `<|system|>` / `[INST]` / `[/INST]` 等 →
/// 全角括号（`＜system＞` / `［INST］`），斜杠前缀原样保留。
///
/// 覆盖包裹形态：
///   - 尖括号：`<token>`、`<|token|>`、`</token>`、`<|token|/`
///   - 方括号：`[token]`、`[/token]`、`[TOKEN]`
///   - 前后允许空白
String _escapeInstructionTokens(String content) {
  final escaped = RegExp.escape;
  final tokens = _instructionTokens.map(escaped).join('|');
  final pattern = RegExp(
    // 尖括号：<system> | <|system|> | </system>
    r'<\s*\|?\s*(/?)\s*(' +
        tokens +
        r')\s*\|?\s*/?\s*>|' +
        // 方括号：[INST] | [/INST]
        r'\[\s*(/?)\s*(' +
        tokens +
        r')\s*\]',
    caseSensitive: false,
  );
  final buffer = StringBuffer();
  var last = 0;
  for (final m in pattern.allMatches(content)) {
    buffer.write(content.substring(last, m.start));
    if (m.group(0)!.contains('<')) {
      // 尖括号形态 → 全角尖括号（保留斜杠）
      buffer.write('＜${m.group(1) ?? ''}${m.group(2)}＞');
    } else {
      // 方括号形态 → 全角方括号（保留斜杠）
      buffer.write('［${m.group(3) ?? ''}${m.group(4)}］');
    }
    last = m.end;
  }
  if (last == 0) return content;
  buffer.write(content.substring(last));
  return buffer.toString();
}
