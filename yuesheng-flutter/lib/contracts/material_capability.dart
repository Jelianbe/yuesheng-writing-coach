// ─────────────────────────────────────────────────────────────
// 能力契约层 — 素材能力接口
//
// 架构评审（2026-08-18）选项 A：能力契约层骨架。
// 选项 B（依赖倒置）：MaterialCapability 自持 DTO（AttachedFileInfo /
// ParagraphAnchor），不 import 任何实现文件，避免契约↔实现的循环依赖（门禁 3）。
//
// 实现映射（Dependency Inversion）：
//   class MaterialCapabilityImpl (lib/services/chat_context_builder.dart)
//   implements MaterialCapability，委托到既有纯函数
//   formatAttachedFilesContext / parseParagraphAnchor / extractParagraphWindow。
//
// ADR: docs/ADR-capability-contracts.md
// ─────────────────────────────────────────────────────────────

/// 附属文件信息（DTO 上移至契约层，原定义于 chat_context_builder.dart）
class AttachedFileInfo {
  final String fileName;
  final String fileRole; // outline | material | normal
  final String content;

  const AttachedFileInfo({
    required this.fileName,
    required this.fileRole,
    required this.content,
  });
}

/// A-3：段落锚点（chapterId + startPara/endPara，0-based 闭区间）
/// 段落以换行 `\n` 分段为基线，编辑漂移从字符级降到段落级。
/// DTO 上移至契约层（选项 B），原定义于 chat_context_builder.dart。
class ParagraphAnchor {
  final String chapterId;
  final int startPara;
  final int endPara;
  const ParagraphAnchor(this.chapterId, this.startPara, this.endPara);
}

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
  String extractParagraphWindow(String content, int startPara, int endPara);
}
