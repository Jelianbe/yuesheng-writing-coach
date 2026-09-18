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
//
// 章号口径（`N12-F3c`）：提炼协议里**不含章号** ⇒ 本模块不产生章号，只把宿主给的
// 实体首见章节作为**身份**落到 `chapterSortOrder`（旧列 `chapter` 留空）。
// 展示侧只吃身份（`utils/chapter_number.dart` 文件头）。
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import '../types/character_types.dart';
import 'llm_client.dart';

/// 提炼服务：正文 → 断言（pending）。
class SettingAssertionExtractor {
  final LlmClient _llmClient;

  SettingAssertionExtractor(this._llmClient);

  /// 调用 LLM 提炼；失败向上抛，由调用方降级提示。
  ///
  /// [chapterIdentity] 是**身份键**（`chapters.sort_order`），不是展示号 ——
  /// 宿主传的是该实体的首见章节（`first_seen_chapter`，写侧已归一为身份）。
  Future<List<CharacterAssertion>> extractFromText({
    required String entityName,
    required String text,
    int? chapterIdentity,
  }) async {
    final completion = await _llmClient.chatCompletionWithContinuation(
      _buildMessages(entityName, text),
      maxTokens: 2048,
    );
    return parseExtractedAssertions(
      completion.content,
      chapterIdentity: chapterIdentity,
    );
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
///
/// `N12-F3c`：[chapterIdentity] 落**新载体** `chapterSortOrder`。
/// 此前它落旧列 `chapter` —— 而该列装的是「用户原写的数 / AI 标称号」，
/// 我们却往里塞了一个**身份键**；`N12-F3b` phase 2 之后后果可见
/// （瓦片只读新载体 ⇒ 章号其实已知却显示成「章节未知」）。
/// 旧列此处**不写**：没有任何一方上报过它（提炼协议里不含章号）。
List<CharacterAssertion> parseExtractedAssertions(
  String raw, {
  int? chapterIdentity,
}) {
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
        chapterSortOrder: chapterIdentity,
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
