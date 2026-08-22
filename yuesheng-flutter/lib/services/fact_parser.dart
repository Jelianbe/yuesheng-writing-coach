// ─────────────────────────────────────────────────────────────
// fact_parser — 时序知识图谱事实提取块解析（A6 写入路径）
//
// 从 AI 诊断回复中提取 [YS_FACT]...[/YS_FACT] 块内的 JSON，
// 解析为人物/事件/支线三类结构化事实，schema 校验委托 fact_validator
// （D4 批次9 独立 validator 层），供 upsert 到 TKG 三表。
//
// 与诊断块、大纲块并列独立，解析失败/无块 → 返回 null，
// 调用方降级跳过，不阻断主流程。纯函数，无副作用，不 throw。
// ─────────────────────────────────────────────────────────────

import 'outline_parser.dart'; // 复用 tryParseJsonWithRecovery
import 'fact_validator.dart';

// D4：领域类（CharacterFactUpdate/FactExtraction 等）随 validator 层移动，
// 经 export 保持对既有调用方（chat_service/测试）的兼容。
export 'fact_validator.dart';

/// 事实提取块分隔符
const String kFactStart = '[YS_FACT]';
const String kFactEnd = '[/YS_FACT]';

/// 从完整回复文本中提取事实 JSON
///
/// - 无标记 → null（降级跳过）
/// - 有起始标记无结束标记 → 容错：取到文本末尾（复用 S6 截断恢复）
/// - JSON 截断 → 容错：补全闭合符号后重试
/// - schema 校验 → 宽松：非法条目跳过，保留合法条目（非全有全无）
FactExtraction? parseFactExtraction(String rawText) {
  final startIndex = rawText.indexOf(kFactStart);
  if (startIndex == -1) return null;

  final endIndex = rawText.indexOf(kFactEnd, startIndex + kFactStart.length);

  // S6 容错：有起始标记无结束标记 → 取到文本末尾
  final String jsonStr;
  if (endIndex == -1) {
    jsonStr = rawText.substring(startIndex + kFactStart.length).trim();
  } else {
    jsonStr = rawText
        .substring(startIndex + kFactStart.length, endIndex)
        .trim();
  }

  if (jsonStr.isEmpty) return null;

  final parsed = tryParseJsonWithRecovery(jsonStr);
  if (parsed == null) return null;

  // D4：schema 校验委托独立 validator 层（宽松：三类独立，非法条目跳过）
  final validation = validateFactSchema(parsed);
  return validation.data;
}

/// 从文本中剥离 [YS_FACT]...[/YS_FACT] 块
///
/// 供展示层剥离原始 JSON（AI 输出协议块后不得泄漏给用户）。
/// - 无标记 → 原样返回
/// - 有起始标记无结束标记 → 自标记起截断（保守防泄漏）
/// - 完整块 → 整块移除，前后文本拼接
/// 纯函数，不 throw。
String stripFactBlock(String rawText) {
  final startIndex = rawText.indexOf(kFactStart);
  if (startIndex == -1) return rawText;

  final endIndex = rawText.indexOf(kFactEnd, startIndex + kFactStart.length);
  final before = rawText.substring(0, startIndex).trimRight();
  if (endIndex == -1) return before;

  final after = rawText.substring(endIndex + kFactEnd.length).trimLeft();
  if (before.isEmpty) return after;
  if (after.isEmpty) return before;
  return '$before\n$after';
}
