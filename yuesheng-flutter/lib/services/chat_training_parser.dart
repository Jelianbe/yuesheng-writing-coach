// ─────────────────────────────────────────────────────────────
// ChatTrainingParser — 训练结果解析
// 复刻 yuesheng-android/src/services/chat-training-parser.ts
//
// 从 AI 回复中解析训练结果（passed/partial/failed）。
// 纯函数无 IO 依赖。
// ─────────────────────────────────────────────────────────────

import 'package:writingcoach/types/teaching_types.dart';

import 'decode_guard.dart';
import 'outline_parser.dart' show tryParseJsonWithRecovery;

/// 训练结果协议块分隔符（ADR-C105 A1）。
///
/// prompt（`skills_training_p3.dart:115-125`）要求模型在 FEEDBACK 子阶段末尾
/// 输出 `[YS_TRAINING]{...}[/YS_TRAINING]`，其 `result` 为**模型自主判定**
/// （`:128` 明写「由你自主判断，不受代码数据绑架」）。
/// 与 `kFactStart`（`fact_parser.dart:20`）、`kGenuiStart`（`genui_parser.dart:22`）同构。
const String kTrainingStart = '[YS_TRAINING]';
const String kTrainingEnd = '[/YS_TRAINING]';

/// 训练结果解析的关键词模式
///
/// 真源：chat-training-parser.ts TRAINING_RESULT_PATTERNS
/// 批次2（2.4）：Map 遍历顺序 partial → failed → passed（保守偏置：
/// 宁可多练一轮不虚报达标）。混合表述（如"完成度不错，但还需要重新处理"）
/// 同时含 partial 与 passed 关键词时，partial 优先命中，避免虚报达标。
///
/// ADR-C100（2026-09-25）：新增「否定式归一 + 判定顺序前移」，消除
/// "没通过 / 不达标 / 没有完成" 被裸 `达标`/`通过` 截胡误判为 passed 的类。
///
/// ADR-C105（2026-09-30）：本表降级为**协议缺失时的回退路径** ——
/// `[YS_TRAINING]` 块存在且 `result` 合法时以模型判定为准（见 [parseTrainingResult]）。
const Map<TrainingResult, List<String>> _kTrainingResultPatterns = {
  TrainingResult.partial: ['部分正确', '方向对了', '还需要'],
  TrainingResult.failed: ['需要重新', '不太对'],
  TrainingResult.passed: ['达标', '通过', '很好', '完成', '成功'],
};

/// 否定标记前缀（ADR-C100；ADR-C105 A2 扩充 `无` / `难`）。
///
/// ⚠️ 本列表**顺序无关**（ADR-C105 C12 更正）：判定是整串子串判断
/// `content.contains('$prefix$gap$stem')`，不存在「先匹配谁消耗谁」的语义。
/// 但 `没有` 必须是**列表成员**（载荷项）——删掉它后 `没有完成` / `没有通过`
/// 会落到序 5 的 passed 词被判成 passed（实测 `'没完成' in '没有完成'` == false）。
/// 原注释声称「`没有` 必须排在 `没` 之前，否则会漏判」为**错误理由**，
/// 且与实际列表顺序自相矛盾（`没有` 恰在 `没` 之后），故本批改写。
const List<String> _kNegationPrefixes = ['未', '不', '没', '没有', '无', '难'];

/// 否定前缀与正向词干之间的**修饰中缀**（ADR-C105 A2）。
///
/// 只收录实测确认的四例中缀（能/法/以/太），**不放开为任意通配** ——
/// 否则 `不要通过抄袭完成` 这类**指令句**会被误判为 failed
/// （`要` 不在本表内 ⇒ 前缀与词干不相邻 ⇒ 不命中）。
/// 首项 `''` 使「前缀紧邻词干」（`未达标`）与旧实现逐字节等价 ⇒ 本扩充为**纯增量**。
/// 新增中缀须附实测用例。
const List<String> _kNegationGaps = ['', '能', '法', '以', '太'];

/// 正向社会词（ADR-C100）：与否定前缀组合即判 failed。
const List<String> _kPositiveStems = ['达标', '通过', '完成', '成功'];

/// 解析 `[YS_TRAINING]` 协议块（ADR-C105 A1）。
///
/// - 无起始标记 → null
/// - 有起始标记无结束标记 → 容错：取到文本末尾（同 `parseFactExtraction`）
/// - JSON 截断 → 委托 `tryParseJsonWithRecovery` 补全后重试
/// - `result` 非法/缺失 → 该字段为 null（调用方回退关键词表）
///
/// 纯函数，不 throw；JSON 解码失败经 `logDecodeFailure` 留痕（R-028）。
({
  TrainingResult? result,
  String? reason,
  List<String> evidence,
  String? nextStep,
  String? stateSuggestion,
})?
parseTrainingProtocol(String content) {
  final start = content.indexOf(kTrainingStart);
  if (start == -1) return null;
  final end = content.indexOf(kTrainingEnd, start + kTrainingStart.length);
  final raw =
      (end == -1
              ? content.substring(start + kTrainingStart.length)
              : content.substring(start + kTrainingStart.length, end))
          .trim();
  if (raw.isEmpty) return null;

  Object? decoded;
  try {
    decoded = tryParseJsonWithRecovery(raw);
  } catch (e, st) {
    logDecodeFailure(
      field: 'training_protocol',
      error: e,
      stack: st,
      category: 'api',
    );
    return null;
  }
  if (decoded is! Map) return null;

  final Object? rawResult = decoded['result'];
  final Object? rawEvidence = decoded['evidence'];
  final Object? rawReason = decoded['reason'];
  final Object? rawNext = decoded['next_step'];
  final Object? rawState = decoded['state_suggestion'];
  return (
    result: rawResult is String ? TrainingResult.fromString(rawResult) : null,
    reason: rawReason is String ? rawReason : null,
    evidence: rawEvidence is List
        ? rawEvidence.whereType<String>().toList()
        : const <String>[],
    nextStep: rawNext is String ? rawNext : null,
    stateSuggestion: rawState is String ? rawState : null,
  );
}

/// 从文本中剥离 `[YS_TRAINING]...[/YS_TRAINING]` 块（ADR-C105 A1）。
///
/// 与 `stripFactBlock`（`fact_parser.dart:62`）同款容错：
/// - 无标记 → 原样返回
/// - 有起始标记无结束标记 → 自标记起截断（保守防泄漏）
/// - 完整块 → 整块移除，前后文本拼接
/// 纯函数，不 throw。
String stripTrainingBlock(String rawText) {
  final startIndex = rawText.indexOf(kTrainingStart);
  if (startIndex == -1) return rawText;
  final endIndex = rawText.indexOf(
    kTrainingEnd,
    startIndex + kTrainingStart.length,
  );
  final before = rawText.substring(0, startIndex).trimRight();
  if (endIndex == -1) return before;
  final after = rawText.substring(endIndex + kTrainingEnd.length).trimLeft();
  if (before.isEmpty) return after;
  if (after.isEmpty) return before;
  return '$before\n$after';
}

/// 从 AI 回复中解析训练结果
///
/// 真源：chat-training-parser.ts parseTrainingResult
///
/// **两级判定（ADR-C105 A1/A2）**：
///   Tier 1：`[YS_TRAINING]` 协议块 `result` 合法 ⇒ **以模型判定为准**
///           （prompt `:128` 明写「由你自主判断，不受代码数据绑架」）
///   Tier 2：无协议块 / `result` 非法 ⇒ 回退关键词表，**且扫描对象先剥协议块**
///           （否则模型自述里的「完成」二字会反过来污染判定：
///            模型判 failed、reason 写「学员没能完成这次改写」→ 旧实现记 passed）
///
/// Tier 2 判定顺序（ADR-C100 成果，原样保留）：
///   1. 含 `部分达标` → partial（精确短语优先）
///   2. 含 partial 关键词 → partial（保守偏置，防虚报达标）
///   3. 含否定式（未/不/没/没有/无/难 + [能/法/以/太]? + 达标|通过|完成|成功）→ failed
///   4. 含 failed 关键词 → failed
///   5. 含 passed 关键词 → passed
///   6. 无匹配 → null（= 不计通过、不写 history、不触发 FSM 重评估）
TrainingResult? parseTrainingResult(String content) {
  // Tier 1：协议优先（模型自主判定）
  final protocol = parseTrainingProtocol(content);
  if (protocol?.result != null) return protocol!.result;

  // Tier 2：关键词回退（扫描对象先剥协议块，防自污染）
  final text = stripTrainingBlock(content);

  // 1. 精确短语：部分达标 必须在一切之前判定
  if (text.contains('部分达标')) return TrainingResult.partial;

  // 2. partial 关键词（保守偏置，混合表述不虚报达标）
  for (final kw in _kTrainingResultPatterns[TrainingResult.partial]!) {
    if (text.contains(kw)) return TrainingResult.partial;
  }

  // 3. 否定式归一：前缀 × 中缀 × 词干（ADR-C100 + ADR-C105 A2）
  for (final prefix in _kNegationPrefixes) {
    for (final gap in _kNegationGaps) {
      for (final stem in _kPositiveStems) {
        if (text.contains('$prefix$gap$stem')) return TrainingResult.failed;
      }
    }
  }

  // 4. failed 关键词
  for (final kw in _kTrainingResultPatterns[TrainingResult.failed]!) {
    if (text.contains(kw)) return TrainingResult.failed;
  }

  // 5. passed 关键词
  for (final kw in _kTrainingResultPatterns[TrainingResult.passed]!) {
    if (text.contains(kw)) return TrainingResult.passed;
  }

  // 6. 无匹配：null 语义即「不计通过」—— 报告要求的「解析失败不计通过」
  //    现状已满足，无需新增 unknown 态（该语义在 ADR-C100 中明确为有意设计）。
  return null;
}
