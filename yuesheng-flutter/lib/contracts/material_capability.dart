// ─────────────────────────────────────────────────────────────
// 能力契约层 — 素材能力接口
//
// 架构评审（2026-08-18）选项 A：能力契约层骨架。
// 纯接口定义，不改任何现有实现。
//
// 当前实现映射：
//   formatAttachedFiles → lib/services/chat_context_builder.dart formatAttachedFilesContext
//   formatReferenceCtx  → lib/services/chat_context_builder.dart buildReferenceContext
//   extractWindow       → lib/services/chat_context_builder.dart extractParagraphWindow
//   parseAnchor         → lib/services/chat_context_builder.dart parseParagraphAnchor
//
// ADR: docs/ADR-capability-contracts.md
// ─────────────────────────────────────────────────────────────

import '../services/chat_context_builder.dart';

/// 素材能力契约
///
/// 覆盖「引用素材 → token 预算截断 → 上下文拼装」与「段落锚点解析/窗口提取」链路。
/// UI/编排层经此契约获取注入 LLM 的素材上下文，不直接依赖 context_builder 内部。
abstract class MaterialCapability {
  /// 格式化附加文件列表为 LLM 上下文文本（A-1 token 预算止血后）。
  String? formatAttachedFiles(List<AttachedFileInfo> files);

  /// 段落锚点 JSON 解析（chapterId + startPara + endPara），非法返回 null。
  ParagraphAnchor? parseParagraphAnchor(String? excerptRangeJson);

  /// 从章节内容中按段落锚点提取窗口文本。
  String extractParagraphWindow(
    String content,
    int startPara,
    int endPara,
  );
}
