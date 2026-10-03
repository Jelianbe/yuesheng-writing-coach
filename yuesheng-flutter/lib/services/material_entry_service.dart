// ─────────────────────────────────────────────────────────────
// MaterialEntryService — 资料条目写入与 on-demand 摘要编排（ADR-C143 批C）
//
// 与 WorldEditorService 同模式：持 AppDatabase 直读仓储，不新建 provider。
//
// R-009 / R-027 边界（写死）：
//   - saveOriginal 是默认路径：存原文、不提炼、summary=null。
//   - summary **只经 requestSummaryOnDemand 生成**——作者主动点按钮才调 LLM，
//     本服务**不后台自动总结**。summarizer 由调用方注入（按钮点击后），
//     本层不持有 LLM client、不在任何自动流程里调用它。
//   - buildMaterialSummaryPrompt 是 ADR-C142 §4 停线4 已批的**唯一**摘要 prompt
//     （本批零其它新增 prompt）。它**只能**经 requestSummaryOnDemand 这条
//     按钮路径触达，不得被自动诊断/提炼链引用。
// ─────────────────────────────────────────────────────────────

import '../data/database/database.dart';
import '../data/repositories/material_entry_repository.dart';

/// ADR-C142 §4 停线4 已批的 on-demand 资料摘要 prompt（最小口径）。
///
/// ★ 本批已批文档未落定具体 prompt 文本，此处按**最小口径**实现并如实登记：
///   只要求「客观概括要点」，明确「不替作者做设定判断」（R-009）。
///   用途被钉死在「作者主动点按钮看这段资料讲了什么」，不扩展为
///   自动总结 / 诊断注入 / 设定升格。若未来要改文本，须走 R-027 停线批准。
String buildMaterialSummaryPrompt(String originalText) {
  return '请客观概括以下资料原文的要点（2-3 句即可；'
      '只复述原文内容，不替作者判断它对作品是否有用、不做设定提炼）：\n\n'
      '原文：\n$originalText';
}

/// 资料条目写入与 on-demand 摘要服务。
class MaterialEntryService {
  MaterialEntryService(this._db);

  final AppDatabase _db;

  MaterialEntryRepository get _repo => MaterialEntryRepository(_db);

  /// 作者主动存一条资料（默认路径：存原文，不生成摘要）。
  Future<MaterialEntry> saveOriginal({
    required String manuscriptId,
    String? url,
    String sourceName = '',
    String originalText = '',
    String keySnippet = '',
    String? anchor,
  }) => _repo.saveOriginal(
    manuscriptId: manuscriptId,
    url: url,
    sourceName: sourceName,
    originalText: originalText,
    keySnippet: keySnippet,
    anchor: anchor,
  );

  /// on-demand：作者点按钮才生成摘要。
  ///
  /// [summarize] 由按钮调用方注入（内部用 [buildMaterialSummaryPrompt] 调 LLM，
  /// 返回摘要文本）。本方法只：载入条目 → 调一次 summarizer → 落库 summary。
  /// ★ 默认保存路径绝不调用本方法（测试断言 summary 默认 null）。
  Future<String?> requestSummaryOnDemand({
    required String entryId,
    required Future<String> Function(String originalText) summarize,
  }) async {
    final entry = await _repo.getById(entryId);
    if (entry == null) return null;
    final summary = await summarize(entry.originalText);
    await _repo.setSummaryOnDemand(id: entryId, summary: summary);
    return summary;
  }
}
