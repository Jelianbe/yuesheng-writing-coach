// ─────────────────────────────────────────────────────────────
// archive_export_service — 教学档案导出 · **web 侧 stub**
// （T-20261031-03 §九 #4 · 编译期门控）
//
// web 首发面 = 单次诊断 + 整体教学 + 资料库（`T-20261024-03` U4）；
// 「教学档案导出」属**内容编辑侧**，首发**不接** ⇒ web 侧一律抛
// `UnsupportedError`（**不静默成功**：返回成功会让调用方以为文件已分享）。
//
// ★ 与 io 侧的差异仅此一处：纯逻辑（DTO 组装 / JSON 拼装 / 文件名生成）
//   在门面 `archive_export_service.dart` 里，**两侧共用**（不复制）。
// ─────────────────────────────────────────────────────────────

/// web 首发不支持「教学档案导出」（内容编辑侧未接）⇒ 显式不支持。
Future<void> shareArchiveExport({
  required String json,
  required String fileName,
  String? subject,
}) async {
  throw UnsupportedError('web 首发不支持教学档案导出（内容编辑侧未接入）');
}
