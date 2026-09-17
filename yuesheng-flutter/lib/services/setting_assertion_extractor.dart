// ─────────────────────────────────────────────────────────────
// setting_assertion_extractor — 从正文提炼设定断言（创建体验 A2）
//
// 「用户写正文，机器提炼结构」的显式桥：把条目的设定正文交给 LLM
// 提炼为断言（pending 待确认，source=ai），走 upsertCharacter 增量合并
// （不覆盖既有断言；用户裁决走 replaceAssertions，R-009 不受影响）。
//
// 克制边界：
//   - 不自动提炼（详情页显式按钮触发）
//   - 提炼结果一律 pending（AI 协议写入，用户裁决后才成为事实）
//   - 失败由调用方降级（无 key / 网络异常 → SnackBar，不阻塞）
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import '../types/character_types.dart';
import 'llm_client.dart';

/// 提炼服务：正文 → 断言（pending）。
class SettingAssertionExtractor {
  final LlmClient _llmClient;

  SettingAssertionExtractor(this._llmClient);

  /// 调用 LLM 提炼；失败向上抛，由调用方降级提示。
  Future<List<CharacterAssertion>> extractFromText({
    required String entityName,
    required String text,
    int? chapter,
  }) async {
    final completion = await _llmClient.chatCompletionWithContinuation(
      _buildMessages(entityName, text),
      maxTokens: 2048,
    );
    return parseExtractedAssertions(completion.content, chapter: chapter);
  }

  List<ChatMessage> _buildMessages(String entityName, String text) {
    return [
      const ChatMessage(
        role: 'system',
        content:
            '你是设定资料整理助手。从用户给出的设定正文中提炼出独立的设定断言，'
            '每条断言是一个属性-取值对。只输出 JSON 数组，不要输出任何其他文字。',
      ),
      ChatMessage(
        role: 'user',
        content:
            '设定主体：「$entityName」\n正文：\n$text\n\n'
            '输出格式（严格 JSON 数组，每项含 attribute 与 value 两个字符串字段）：\n'
            '[{"attribute": "身份", "value": "守夜人"}]',
      ),
    ];
  }
}

/// 解析 LLM 输出为断言列表（纯函数，可单测）。
///
/// 容错：```json 围栏 / 前导说明文字 / 缺字段项跳过 / 空数组返回空。
/// 全部失败（非 JSON）返回空列表——调用方按「提炼出 0 条」处理，不抛。
List<CharacterAssertion> parseExtractedAssertions(String raw, {int? chapter}) {
  final jsonText = _extractJsonArray(raw);
  if (jsonText == null) return const [];
  final Object? decoded;
  try {
    decoded = jsonDecode(jsonText);
  } catch (_) {
    return const [];
  }
  if (decoded is! List) return const [];
  final result = <CharacterAssertion>[];
  for (final item in decoded) {
    if (item is! Map) continue;
    final attribute = item['attribute'];
    final value = item['value'];
    if (attribute is! String || attribute.trim().isEmpty) continue;
    if (value is! String || value.trim().isEmpty) continue;
    result.add(
      CharacterAssertion(
        attribute: attribute.trim(),
        value: value.trim(),
        chapter: chapter,
        timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        status: 'pending',
        source: 'ai',
      ),
    );
  }
  return result;
}

/// 从 LLM 输出中截取 JSON 数组子串（容错围栏与前导文本）。
String? _extractJsonArray(String raw) {
  final start = raw.indexOf('[');
  final end = raw.lastIndexOf(']');
  if (start < 0 || end < 0 || end <= start) return null;
  return raw.substring(start, end + 1);
}
