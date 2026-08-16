// ─────────────────────────────────────────────────────────────
// outline_parser — 大纲提取块解析（批次72 大纲层）
//
// 从 AI 完整回复中提取 [YS_ENTITY]...[/YS_ENTITY] 块内的 JSON，
// schema 校验委托 outline_validator（D4 批次9 独立 validator 层）。
// 与诊断块并列独立（不并入诊断协议），解析失败/无块 → 返回 null，
// 调用方降级跳过，不阻断主流程（沿用 diagnosis_parser 惯例）。
// 纯函数，无副作用，不 throw。
//
// 批次74：标记由 [YS_OUTLINE] 改名为 [YS_ENTITY]——原标记已被批次17
// 的旧「大纲诊断」skill（outline-diagnosis，schema 为 diagnosis/nodes）
// 占用，同标记两套 schema 会令 AI 混淆，新协议独立改名以隔离。
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import 'outline_validator.dart';

// D4：领域类（OutlineEntityUpdate/OutlineExtraction 等）随 validator 层移动，
// 经 export 保持对既有调用方（outline_service/chat_service/测试）的兼容。
export 'outline_validator.dart';

/// 大纲提取块分隔符（[YS_ENTITY] = 大纲实体记忆协议，区别于旧大纲诊断的 [YS_OUTLINE]）
const String kOutlineStart = '[YS_ENTITY]';
const String kOutlineEnd = '[/YS_ENTITY]';

/// 从完整回复文本中提取大纲 JSON
///
/// - 无标记 → null（降级跳过）
/// - 有起始标记无结束标记 → S6 容错：取到文本末尾，尝试解析（流式截断场景）
/// - JSON 截断（缺闭合符号） → S6 容错：补全 `]}` 后重试
/// - JSON 语法错误（非截断） / schema 校验失败 → null（严格：任一实体非法整体丢弃）
OutlineExtraction? parseOutlineExtraction(String rawText) {
  final startIndex = rawText.indexOf(kOutlineStart);
  if (startIndex == -1) return null;

  final endIndex = rawText.indexOf(
    kOutlineEnd,
    startIndex + kOutlineStart.length,
  );

  // S6 容错：有起始标记无结束标记 → 取到文本末尾（而非返回 null）
  // 场景：流式输出中途截断、AI 输出未闭合
  final String jsonStr;
  if (endIndex == -1) {
    jsonStr = rawText.substring(startIndex + kOutlineStart.length).trim();
  } else {
    jsonStr = rawText
        .substring(startIndex + kOutlineStart.length, endIndex)
        .trim();
  }

  if (jsonStr.isEmpty) return null;

  final parsed = tryParseJsonWithRecovery(jsonStr);
  if (parsed == null) return null;

  // D4：schema 校验委托独立 validator 层（严格：任一非法整体 null）
  final validation = validateOutlineSchema(parsed);
  if (!validation.valid) return null;
  return validation.data;
}

/// 从文本中剥离 [YS_ENTITY]...[/YS_ENTITY] 块（批次74）
///
/// 供展示层剥离原始 JSON（AI 输出协议块后不得泄漏给用户）。
/// - 无标记 → 原样返回
/// - 有起始标记无结束标记 → 自标记起截断（保守防泄漏）
/// - 完整块 → 整块移除，前后文本拼接
/// 纯函数，不 throw。
String stripOutlineBlock(String rawText) {
  final startIndex = rawText.indexOf(kOutlineStart);
  if (startIndex == -1) return rawText;

  final endIndex = rawText.indexOf(
    kOutlineEnd,
    startIndex + kOutlineStart.length,
  );
  final before = rawText.substring(0, startIndex).trimRight();
  if (endIndex == -1) return before;

  final after = rawText.substring(endIndex + kOutlineEnd.length).trimLeft();
  if (before.isEmpty) return after;
  if (after.isEmpty) return before;
  return '$before\n$after';
}

/// S6：带截断容错的 JSON 解析
///
/// 策略：
///   1. 直接 jsonDecode
///   2. 失败 → 用栈跟踪未闭合的 `{` `[` `"`，按嵌套逆序补全后重试
///   3. 仍失败 → 返回 null（非截断性语法错误，不强行恢复）
///
/// 只处理"截断"（缺尾部的闭合符号），不处理其他语法错误（如 `{not-json}`）。
/// 正确识别字符串内的字符，不误判字符串内的 `{}[]"`。
dynamic tryParseJsonWithRecovery(String jsonStr) {
  try {
    return jsonDecode(jsonStr);
  } catch (_) {
    // 继续尝试容错恢复
  }

  // 用栈跟踪未闭合的括号（记录需要的闭合符号）
  final stack = <String>[];
  bool inString = false;
  bool escape = false;

  for (var i = 0; i < jsonStr.length; i++) {
    final c = jsonStr[i];
    if (escape) {
      escape = false;
      continue;
    }
    if (c == r'\') {
      escape = true;
      continue;
    }
    if (c == '"') {
      inString = !inString;
      continue;
    }
    if (inString) continue;
    if (c == '{') {
      stack.add('}');
    } else if (c == '[') {
      stack.add(']');
    } else if (c == '}' || c == ']') {
      if (stack.isNotEmpty) stack.removeLast();
    }
  }

  // 按嵌套逆序补全（先闭合字符串 → 再从内到外闭合括号）
  final buffer = StringBuffer(jsonStr);
  if (inString) buffer.write('"');
  while (stack.isNotEmpty) {
    buffer.write(stack.removeLast());
  }

  // 未补全任何符号 → 非截断性错误，不强行恢复
  if (buffer.length == jsonStr.length) return null;

  try {
    return jsonDecode(buffer.toString());
  } catch (_) {
    return null;
  }
}
