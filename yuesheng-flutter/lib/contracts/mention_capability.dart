// ─────────────────────────────────────────────────────────────
// 能力契约层 — @提及解析能力接口
//
// 选项 B（依赖倒置）首落样板（随 N+1 / ReferenceCapability 拆分而出）。
//
// 为何独立成契约：parseMentions 原属 ReferenceCapability，但其实现
// MentionParser 反向依赖 ReferenceRepository（取附属文件列表/单文件），
// 若并入 ReferenceCapability 会让契约层与实现成环（违反门禁 3）。
// 故独立为 MentionCapability，契约层自持 DTO（ParseResult / ParsedMention），
// 不 import 任何实现文件。
//
// 实现映射：lib/services/mention_parser.dart MentionParser
// ADR: docs/ADR-capability-contracts.md
// ─────────────────────────────────────────────────────────────

/// 解析出的单条引用
class ParsedMention {
  final String raw;
  final String refType; // 'manuscript' | 'chapter' | 'file'
  final String refId;
  final String title;

  /// 所属作品 ID（manuscript/chapter/file 均填；@ 引用可视化跳转用）
  final String? manuscriptId;

  const ParsedMention({
    required this.raw,
    required this.refType,
    required this.refId,
    required this.title,
    this.manuscriptId,
  });
}

/// 解析结果
class ParseResult {
  final List<ParsedMention> mentions;

  /// 清理后的文本（移除已解析成功的 @ 引用）
  final String cleanedText;

  const ParseResult({required this.mentions, required this.cleanedText});
}

/// @提及解析能力契约
///
/// 覆盖「文本 @提及 → 标题反查 refId → 结构化结果」链路。
/// UI/编排层经此契约消费解析能力，不直接依赖具体解析器。
abstract class MentionCapability {
  /// 解析输入文本中的 @提及（标题反查 refId），返回解析结果（mentions + cleanedText）。
  Future<ParseResult> parseMentions(String text);
}
