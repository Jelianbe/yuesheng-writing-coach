// ─────────────────────────────────────────────────────────────
// 能力契约层 — 引用能力接口
//
// 架构评审（2026-08-18）选项 A：能力契约层骨架。
// 纯接口定义，不改任何现有实现。
//
// 当前实现映射：
//   listReferences    → lib/data/repositories/reference_repository.dart
//   addReference      → 同上
//   removeReference   → 同上
//   setPrimary        → 同上
//   updateExcerpt     → 同上
//   parseMentions     → lib/services/mention_parser.dart MentionParser.parseMentions
//
// ADR: docs/ADR-capability-contracts.md
// ─────────────────────────────────────────────────────────────

import '../data/repositories/reference_repository.dart';
import '../services/mention_parser.dart';

/// 引用能力契约
///
/// 覆盖「会话引用 CRUD + 主引用管理 + 选段锚点 + @提及解析」链路。
/// UI 层经此契约操作引用，不直接依赖具体仓库实现。
abstract class ReferenceCapability {
  /// 列出会话的所有引用。
  Future<List<ReferencedItem>> listReferences(String sessionId);

  /// 添加引用（可选设主、可选携带选段锚点）。
  Future<String> addReference(
    String sessionId,
    String refType,
    String refId, {
    bool isPrimary,
    ({String chapterId, int startPara, int endPara})? excerptRange,
  });

  /// 移除引用（若删主引用则自动另选）。
  Future<void> removeReference(
    String sessionId,
    String refType,
    String refId,
  );

  /// 设主引用。
  Future<void> setPrimaryReference(
    String sessionId,
    String refType,
    String refId,
  );

  /// 写入/清除选段锚点。返回是否命中并更新了行。
  Future<bool> updateExcerptRange(
    String sessionId,
    String refType,
    String refId,
    ({String chapterId, int startPara, int endPara})? anchor,
  );

  /// 解析输入文本中的 @提及（标题反查 refId），返回解析结果（mentions + cleanedText）。
  Future<ParseResult> parseMentions(String text);
}
