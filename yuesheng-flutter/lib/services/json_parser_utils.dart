// ─────────────────────────────────────────────────────────────
// JSON 解析容错工具
// 复刻 yuesheng-android/src/services/json-parser-utils.ts
//
// 设计:
// - 零开销路径：原生 jsonDecode 成功时直接返回
// - 容错路径：原生解析失败 + 含中文引号 → 替换后重试
// - 不可容错路径：原生解析失败 + 无中文引号 → 抛出原始异常
//
// 不做的事:
// - 不处理中文逗号/冒号
// - 不做 markdown 代码块标记容错（由各 parser 自行处理）
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

/// 容错 JSON 解析
///
/// 复刻 parseJsonLenient
Object? parseJsonLenient(String jsonStr) {
  try {
    return jsonDecode(jsonStr);
  } catch (originalError) {
    // 容错：LLM 偶发输出中文引号（U+201C 左双引号 / U+201D 右双引号）
    final fixed = jsonStr.replaceAll('\u201C', '"').replaceAll('\u201D', '"');
    if (fixed == jsonStr) {
      // 没有中文引号可替换，无法容错
      rethrow;
    }
    return jsonDecode(fixed);
  }
}

/// 去除 markdown 代码块标记（```json ... ``` 或 ``` ... ```）
///
/// 复刻 editor-parser.ts / reviewer-parser.ts 中的去 fence 逻辑
String stripMarkdownFence(String s) {
  final startIdx = s.indexOf(RegExp(r'^```(?:json)?\s*', multiLine: false));
  String result = s;
  if (startIdx == 0) {
    final firstNl = s.indexOf('\n');
    if (firstNl != -1) {
      result = s.substring(firstNl + 1);
    } else {
      result = s.replaceFirst(RegExp(r'^```(?:json)?\s*'), '');
    }
  }
  // 去尾部 ```
  final endMatch = RegExp(r'\n?\s*```\s*$').firstMatch(result);
  if (endMatch != null) {
    result = result.substring(0, endMatch.start);
  }
  return result.trim();
}
