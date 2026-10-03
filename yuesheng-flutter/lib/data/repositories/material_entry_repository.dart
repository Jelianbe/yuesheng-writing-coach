// ─────────────────────────────────────────────────────────────
// MaterialEntryRepository — 资料条目事件表数据访问（ADR-C143 批C，v44）
//
// 外部参考资料（网页/书目原文），与作者自整理 setting_entry 分开、
// 永不自动升格 canon。
//
// R-009 / 口径（写死在本层）：
//   - saveOriginal **默认存原文不提炼**：original_text 原样落库；
//     key_snippet 为**原样截取**（非 AI 摘要句）；summary 恒 null。
//   - summary **只经 setSummaryOnDemand 写**（作者主动点按钮，on-demand），
//     默认路径绝不生成摘要（本层 saveOriginal 无任何 LLM 调用）。
//   - source_credibility 恒 'unknown'：本层**无评级方法**（AI 不评级 = R-009）；
//     只存 source_name（域名/来源名）供展示。
//   - UNIQUE(manuscript_id, url) 机械去重（非语义去重——不替作者判断同异）。
//
// 本层不进诊断注入链（资料库默认不进诊断 prompt）。
// ─────────────────────────────────────────────────────────────

import 'package:drift/drift.dart';

import '../database/database.dart';
import '../database/utils.dart';
import 'repository_write_guard.dart';

/// 资料条目裁决态常量（与 RecordEntryStatus 同构）
class MaterialEntryStatus {
  static const String pending = 'pending';
  static const String kept = 'kept';
  static const String rejected = 'rejected';
  const MaterialEntryStatus._();
}

/// 来源可信度取值：**恒为 unknown**（裁定⑤：AI 不评级）。
/// 保留为常量唯一真源，禁止在别处引入 'high'/'low' 等评级值。
class SourceCredibility {
  static const String unknown = 'unknown';
  const SourceCredibility._();
}

class MaterialEntryRepository {
  final AppDatabase _db;
  MaterialEntryRepository(this._db);

  /// 作者主动存一条资料条目：默认存原文，**summary=null**（不后台自动总结）。
  ///
  /// [originalText] 原文原样存；[keySnippet] 为原样截取片段；[anchor] 为
  /// 原网页锚点（可空）；[sourceName] 仅域名/来源名。source_credibility
  /// 恒 [SourceCredibility.unknown]（本方法不评级）。
  Future<MaterialEntry> saveOriginal({
    required String manuscriptId,
    String? url,
    String sourceName = '',
    String originalText = '',
    String keySnippet = '',
    String? anchor,
  }) => guardRepoWrite('material_entry', 'saveOriginal', () async {
    final entry = MaterialEntriesCompanion.insert(
      id: generateUuid(),
      manuscriptId: manuscriptId,
      url: Value(url),
      sourceName: Value(sourceName),
      sourceCredibility: const Value(SourceCredibility.unknown),
      originalText: Value(originalText),
      keySnippet: Value(keySnippet),
      anchor: Value(anchor),
      // summary 故意不传（Value.absent → 列默认 NULL）：默认路径不生成摘要。
      status: const Value(MaterialEntryStatus.kept),
    );
    await _db.into(_db.materialEntries).insert(entry);
    return _requireById(entry.id.value);
  });

  /// on-demand：作者主动点按钮才写摘要。
  ///
  /// ★ 本方法是 summary 列的**唯一写入方**。saveOriginal 路径绝不写 summary。
  /// [summary] 由外层（作者点按钮后）经 LLM 生成传入；本层只落库，不自动触发。
  Future<void> setSummaryOnDemand({
    required String id,
    required String summary,
  }) => guardRepoWrite('material_entry', 'setSummaryOnDemand', () async {
    await (_db.update(
      _db.materialEntries,
    )..where((t) => t.id.equals(id))).write(
      MaterialEntriesCompanion(
        summary: Value(summary),
        updatedAt: Value(nowSec()),
      ),
    );
  });

  Future<MaterialEntry> _requireById(String id) async {
    final row = await (_db.select(
      _db.materialEntries,
    )..where((t) => t.id.equals(id))).getSingle();
    return row;
  }

  Future<MaterialEntry?> getById(String id) => (_db.select(
    _db.materialEntries,
  )..where((t) => t.id.equals(id))).getSingleOrNull();

  /// 某作品全部资料条目（按时间升序）。
  Future<List<MaterialEntry>> listByManuscript(String manuscriptId) =>
      (_db.select(_db.materialEntries)
            ..where((t) => t.manuscriptId.equals(manuscriptId))
            ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
          .get();
}
