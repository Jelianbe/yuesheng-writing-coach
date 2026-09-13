// ─────────────────────────────────────────────────────────────
// WorldEditorService — 世界观手动录入的写入服务（批次 W1）
//
// 职责：主题详情页/列表页的写入动作——追加断言 + 归档 + 恢复。
// 刻意独立成类（真分解，非 part/extension）：与 CharacterEditorService
// 同模式——持 AppDatabase 直读仓储，**不新建 provider**（承架构 §1.2 口径：
// character 四件套用「局部 state + 直读仓储」，本批照搬）。
//
// 「追加」唯一写路径 = WorldFactRepository.upsertWorld 的增量合并
// （UNIQUE(manuscript_id, name) 命中即合并，历史断言不被覆盖）——
// **严禁**为「追加」新增仓储写方法。
//
// R-009 边界：全部字段为**纯手动输入**（属性 / 取值 / 章节 / 原文依据全由
// 用户填），本服务不提供任何「建议值」，不代写、不代决定。
//
// 指纹口径（承架构 §8-N4）：手动录入多属设计态（章节可能尚未写），
// 追加断言**不计 chapterHash** ⇒ chapterHash/chapterNo 均不传，
// upsertWorld 的 mergeAssertions 退化为纯三元组去重（历史断言不被覆盖）。
// ─────────────────────────────────────────────────────────────

import '../data/database/database.dart';
import '../data/database/utils.dart';
import '../data/repositories/world_fact_repository.dart';
import '../types/character_types.dart';

/// 世界观设定的人工写入服务（追加断言 / 归档 / 恢复）。
class WorldEditorService {
  WorldEditorService(this._db);

  final AppDatabase _db;

  WorldFactRepository get _repo => WorldFactRepository(_db);

  /// 追加一条用户断言到既有主题：读行 → 构造 `source='user'` /
  /// `status='confirmed'` 的断言 → 经 [WorldFactRepository.upsertWorld]
  /// 增量合并（历史断言不被覆盖）。
  ///
  /// [evidence] 去首尾空格；空串归一为 null（= 不进一致性检查；
  /// `conflict_detector._hasEvidence` 判 `(a.evidence ?? '').isNotEmpty`，
  /// 空串与 null 语义等价，但**存储应统一为 null**）。
  ///
  /// 属性 / 取值去空格后为空 → 返回 false（不写，防 `parseAssertions`
  /// 静默丢弃空条目）；主题不存在 → 返回 false。
  Future<bool> appendAssertion({
    required String worldId,
    required String attribute,
    required String value,
    int? chapter,
    String? evidence,
  }) async {
    final attr = attribute.trim();
    final val = value.trim();
    if (attr.isEmpty || val.isEmpty) return false;
    final row = await _repo.getWorldById(worldId);
    if (row == null) return false;
    await _repo.upsertWorld(
      manuscriptId: row.manuscriptId,
      name: row.name,
      assertions: [
        CharacterAssertion(
          attribute: attr,
          value: val,
          chapter: chapter,
          timestamp: nowSec(),
          status: 'confirmed',
          source: 'user',
          evidence: _normalizeEvidence(evidence),
        ),
      ],
    );
    return true;
  }

  /// 归档主题（软归档，委派仓储；**非物理删除**）。
  Future<bool> archiveWorld(String worldId) => _repo.archiveWorld(worldId);

  /// 恢复已归档主题（委派仓储）。
  Future<bool> restoreWorld(String worldId) => _repo.restoreWorld(worldId);

  /// 依据文本归一：去首尾空格；null / 空串 → null（存储统一口径）。
  String? _normalizeEvidence(String? raw) {
    final trimmed = raw?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }
}
