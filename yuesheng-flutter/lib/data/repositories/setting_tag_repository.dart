// ─────────────────────────────────────────────────────────────
// setting_tag_repository — 条目标签（设定资料库·标签批次，第二批）
//
// Codex 式自由多标签：覆盖 character / world / setting（「其他」）三类实体，
// 多对多自由字符串，UNIQUE 幂等。**不参与诊断注入**（克制清单），纯管理/展示。
//
// 与 setting_entry.category 的关系：category 是「其他」的单值类别且参与诊断
// （AI 上下文）；tag 是自由多标签，两条线并存互不干扰（AI 写入链路零改动）。
// outline 不纳入（大纲实体无直接写入路径，AI 沉淀）。
// ─────────────────────────────────────────────────────────────

import 'package:drift/drift.dart';

import '../database/database.dart';
import 'setting_link_repository.dart' show SettingEntityKind;

/// 条目标签仓储：增删查 + 重建（「其他」弹窗保存用）。
///
/// 实体类型复用互链仓储的 [SettingEntityKind]；标签实际仅支持
/// character / world / setting 三类（outline 无直接写入路径，克制不纳入）。
class SettingTagRepository {
  SettingTagRepository(this._db);

  final AppDatabase _db;

  /// 某实体的全部标签（按 tag 字典序）。
  Future<List<String>> listForEntity(
    SettingEntityKind kind,
    String entityId,
  ) async {
    final rows =
        await (_db.select(_db.settingTags)
              ..where(
                (t) =>
                    t.entityKind.equals(kind.name) &
                    t.entityId.equals(entityId),
              )
              ..orderBy([(t) => OrderingTerm.asc(t.tag)]))
            .get();
    return [for (final r in rows) r.tag];
  }

  /// 幂等添加（先查后插，避开 UniqueConstraintViolationException 路径）。
  Future<void> addTag(
    String manuscriptId,
    SettingEntityKind kind,
    String entityId,
    String tag,
  ) async {
    final normalized = tag.trim();
    if (normalized.isEmpty) return;
    final existing =
        await (_db.select(_db.settingTags)..where(
              (t) =>
                  t.manuscriptId.equals(manuscriptId) &
                  t.entityKind.equals(kind.name) &
                  t.entityId.equals(entityId) &
                  t.tag.equals(normalized),
            ))
            .get();
    if (existing.isNotEmpty) return;
    await _db
        .into(_db.settingTags)
        .insert(
          SettingTagsCompanion.insert(
            id: _uuid(),
            manuscriptId: manuscriptId,
            entityKind: kind.name,
            entityId: entityId,
            tag: normalized,
          ),
        );
  }

  /// 删除一个标签（不存在则静默）。
  Future<void> removeTag(
    String manuscriptId,
    SettingEntityKind kind,
    String entityId,
    String tag,
  ) async {
    await (_db.delete(_db.settingTags)..where(
          (t) =>
              t.manuscriptId.equals(manuscriptId) &
              t.entityKind.equals(kind.name) &
              t.entityId.equals(entityId) &
              t.tag.equals(tag),
        ))
        .go();
  }

  /// 重建某实体的全部标签（事务：DELETE 全部 + batch insert）。
  /// 「其他」编辑弹窗保存时用（内存 list 增删后整体提交，避免 diff 成本）。
  Future<void> replaceTags(
    String manuscriptId,
    SettingEntityKind kind,
    String entityId,
    List<String> tags,
  ) async {
    final normalized = <String>{
      for (final t in tags)
        if (t.trim().isNotEmpty) t.trim(),
    }.toList()..sort();
    await _db.transaction(() async {
      await (_db.delete(_db.settingTags)..where(
            (t) => t.entityKind.equals(kind.name) & t.entityId.equals(entityId),
          ))
          .go();
      for (final tag in normalized) {
        await _db
            .into(_db.settingTags)
            .insert(
              SettingTagsCompanion.insert(
                id: _uuid(),
                manuscriptId: manuscriptId,
                entityKind: kind.name,
                entityId: entityId,
                tag: tag,
              ),
            );
      }
    });
  }

  static var _seq = 0;

  String _uuid() {
    _seq++;
    return 'tg-${DateTime.now().microsecondsSinceEpoch}-$_seq';
  }
}
