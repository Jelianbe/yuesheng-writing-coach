// ─────────────────────────────────────────────────────────────
// SettingLinkRepository — 条目互链 DAO（设定资料库·Codex 式互链第一批，v36）
//
// 四类设定实体（character / world / outline / setting）之间的跨实体引用。
// 与 character/world/entry 的关键差异：
//   ① **软引用**：source_id / target_id 跨表无 FK（类型由 kind 决定），
//      目标行被删后展示容错（「已删除的条目」不可点）
//   ② **方向性**：link(A→B) 与 link(B→A) 是两行——用户自定义方向与关系名；
//      listForEntity 返回「涉及本实体的全部互链」（出链 + 入链）
//   ③ **本批不参与诊断注入**：仅管理 / 展示 / 详情页互跳
// ─────────────────────────────────────────────────────────────

import 'package:drift/drift.dart';

import '../database/database.dart';
import '../database/utils.dart';
import 'repository_write_guard.dart';

/// 互链实体类型（四类设定实体）。
enum SettingEntityKind {
  character,
  world,
  outline,
  setting;

  static SettingEntityKind parse(String v) =>
      SettingEntityKind.values.firstWhere(
        (k) => k.name == v,
        orElse: () => SettingEntityKind.character,
      );

  /// 详情页跳转友好标签。
  String get label => switch (this) {
    SettingEntityKind.character => '角色',
    SettingEntityKind.world => '世界观',
    SettingEntityKind.outline => '大纲',
    SettingEntityKind.setting => '其他',
  };
}

/// 详情页展示视图：一条互链 + 对方实体解析结果。
class SettingLinkView {
  final SettingLink link;
  final SettingEntityKind otherKind;
  final String otherId;
  final String otherName;

  /// 目标行是否仍存在（被删后展示容错，不可跳转）。
  final bool targetExists;

  const SettingLinkView({
    required this.link,
    required this.otherKind,
    required this.otherId,
    required this.otherName,
    required this.targetExists,
  });

  bool get isJumpable =>
      targetExists &&
      (otherKind == SettingEntityKind.character ||
          otherKind == SettingEntityKind.world);
}

class SettingLinkRepository {
  final AppDatabase _db;

  SettingLinkRepository(this._db);

  /// 新建互链（幂等：同 (source,target) 唯一键冲突返回既有 id，不重复建）。
  Future<String?> createLink({
    required String manuscriptId,
    required SettingEntityKind sourceKind,
    required String sourceId,
    required SettingEntityKind targetKind,
    required String targetId,
    String label = '',
  }) => guardRepoWrite('setting_link', 'createLink', () async {
    final existing = await _findLink(
      manuscriptId,
      sourceKind.name,
      sourceId,
      targetKind.name,
      targetId,
    );
    if (existing != null) return existing.id;
    final now = nowSec();
    final id = generateUuid();
    await _db
        .into(_db.settingLinks)
        .insert(
          SettingLinksCompanion.insert(
            id: id,
            manuscriptId: manuscriptId,
            sourceKind: sourceKind.name,
            sourceId: sourceId,
            targetKind: targetKind.name,
            targetId: targetId,
            label: Value(label),
            createdAt: Value(now),
          ),
        );
    return id;
  });

  /// 按唯一键查既有互链（幂等 create 的前置读）。
  Future<SettingLink?> _findLink(
    String manuscriptId,
    String sourceKind,
    String sourceId,
    String targetKind,
    String targetId,
  ) async {
    return (_db.select(_db.settingLinks)..where(
          (t) =>
              t.manuscriptId.equals(manuscriptId) &
              t.sourceKind.equals(sourceKind) &
              t.sourceId.equals(sourceId) &
              t.targetKind.equals(targetKind) &
              t.targetId.equals(targetId),
        ))
        .getSingleOrNull();
  }

  /// 删除互链（级联仅限自身行；作品删除走 manuscript 级联）。
  Future<void> deleteLink(String id) => guardRepoWrite(
    'setting_link',
    'deleteLink',
    () async {
      await (_db.delete(_db.settingLinks)..where((t) => t.id.equals(id))).go();
    },
  );

  /// 涉及某实体的全部互链（出链 + 入链），对方实体名解析。
  Future<List<SettingLinkView>> listForEntity(
    String manuscriptId,
    SettingEntityKind kind,
    String id,
  ) async {
    final rows =
        await (_db.select(_db.settingLinks)..where(
              (t) =>
                  t.manuscriptId.equals(manuscriptId) &
                  ((t.sourceKind.equals(kind.name) & t.sourceId.equals(id)) |
                      (t.targetKind.equals(kind.name) & t.targetId.equals(id))),
            ))
            .get();
    final views = <SettingLinkView>[];
    for (final link in rows) {
      final isSource = link.sourceKind == kind.name && link.sourceId == id;
      final otherKind = isSource
          ? SettingEntityKind.parse(link.targetKind)
          : SettingEntityKind.parse(link.sourceKind);
      final otherId = isSource ? link.targetId : link.sourceId;
      final name = await _resolveName(manuscriptId, otherKind, otherId);
      views.add(
        SettingLinkView(
          link: link,
          otherKind: otherKind,
          otherId: otherId,
          otherName: name ?? '已删除的条目',
          targetExists: name != null,
        ),
      );
    }
    views.sort((a, b) => a.otherName.compareTo(b.otherName));
    return views;
  }

  /// 按 kind 解析对方实体名（不存在返回 null）。
  Future<String?> _resolveName(
    String manuscriptId,
    SettingEntityKind kind,
    String id,
  ) async {
    switch (kind) {
      case SettingEntityKind.character:
        final row =
            await (_db.select(_db.characterFacts)..where(
                  (t) => t.id.equals(id) & t.manuscriptId.equals(manuscriptId),
                ))
                .getSingleOrNull();
        return row?.name;
      case SettingEntityKind.world:
        final row =
            await (_db.select(_db.worldFacts)..where(
                  (t) => t.id.equals(id) & t.manuscriptId.equals(manuscriptId),
                ))
                .getSingleOrNull();
        return row?.name;
      case SettingEntityKind.outline:
        final row =
            await (_db.select(_db.outlineEntities)..where(
                  (t) => t.id.equals(id) & t.manuscriptId.equals(manuscriptId),
                ))
                .getSingleOrNull();
        return row?.entityKey;
      case SettingEntityKind.setting:
        final row =
            await (_db.select(_db.settingEntries)..where(
                  (t) => t.id.equals(id) & t.manuscriptId.equals(manuscriptId),
                ))
                .getSingleOrNull();
        return row?.name;
    }
  }

  /// 作品全部互链（后续批：标签 / 注入 / Progressions 用）。
  Future<List<SettingLink>> listAll(String manuscriptId) async {
    return (_db.select(_db.settingLinks)
          ..where((t) => t.manuscriptId.equals(manuscriptId))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
  }
}
