// ─────────────────────────────────────────────────────────────
// 能力契约层 — 引用能力接口
//
// 架构评审（2026-08-18）选项 A 骨架；选项 B（依赖倒置）首落：N+1 样板。
//
// 真正的依赖倒置：契约层自持 DTO（ReferencedItem），不再 import 任何实现
// 文件，消除「契约 ↔ 实现」的 import 环（满足门禁 3：循环依赖扫描）。
//
// 方法映射（实现：lib/data/repositories/reference_repository.dart）：
//   listReferences      → listReferencesOfSession（别名）
//   addReference        → 同名
//   removeReference     → 同名
//   setPrimaryReference → 同名
//   updateExcerptRange  → 同名
//
// 注：parseMentions 属 @提及解析关注点，且其实现 MentionParser 反向依赖
//     本仓库（取附属文件），若并入本接口会使契约层与实现成环，故独立为
//     MentionCapability（见 mention_capability.dart）。
//
// ADR: docs/ADR-capability-contracts.md
// ─────────────────────────────────────────────────────────────

/// 引用项（UNION ALL 查询结果）
///
/// DTO 定义于契约层：依赖倒置要求实现依赖契约，而非契约依赖实现。
/// 实现文件 reference_repository.dart 通过 re-export 维持旧有导入可见性。
class ReferencedItem {
  final String refId;
  final String refType; // 'manuscript' | 'chapter' | 'file'
  final int isPrimary;
  final String title;
  final String? manuscriptId;

  /// 选段范围 JSON（如 {"start":100,"end":320}），chapter 引用专用
  final String? excerptRange;

  const ReferencedItem({
    required this.refId,
    required this.refType,
    required this.isPrimary,
    required this.title,
    this.manuscriptId,
    this.excerptRange,
  });
}

/// 引用能力契约
///
/// 覆盖「会话引用 CRUD + 主引用管理 + 选段锚点」链路。
/// UI 层经此契约操作引用，不直接依赖具体仓库实现。
abstract class ReferenceCapability {
  /// 列出会话的所有引用。
  Future<List<ReferencedItem>> listReferences(String sessionId);

  /// 添加引用（可选设主、可选携带选段锚点）。
  Future<String> addReference(
    String sessionId,
    String refType,
    String refId, {
    bool isPrimary = false,
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
}
