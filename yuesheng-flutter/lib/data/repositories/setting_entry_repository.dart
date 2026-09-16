// ─────────────────────────────────────────────────────────────
// SettingEntryRepository — 「其他」开放容器 DAO（设定资料库第二批）
//
// 作品级（manuscript_id 维度）通用设定条目：用户自建类别标签 + 名称 + 自由正文。
// 与 character/world 的关键差异：
//   ① **无 AI 写入**（E1-b-3 裁定同源冻结）——纯用户主权区，无 pending 状态机
//   ② **无 assertions**——不做矛盾检测，参与诊断 = 整条注入（用户勾选）
//   ③ participate 为专列开关（默认 false：不注入诊断，勾选后进上下文）
// ─────────────────────────────────────────────────────────────

import 'package:drift/drift.dart';

import '../database/database.dart';
import '../database/utils.dart';
import 'repository_write_guard.dart';

class SettingEntryRepository {
  final AppDatabase _db;

  SettingEntryRepository(this._db);

  /// 新建条目（用户主权区：类别自建、正文自由，无 AI 参与）。
  Future<String> createEntry({
    required String manuscriptId,
    required String category,
    required String name,
    String description = '',
  }) => guardRepoWrite('setting_entry', 'createEntry', () async {
    final now = nowSec();
    final id = generateUuid();
    await _db
        .into(_db.settingEntries)
        .insert(
          SettingEntriesCompanion.insert(
            id: id,
            manuscriptId: manuscriptId,
            category: Value(category),
            name: name,
            description: Value(description),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
    return id;
  });

  /// 更新条目正文/类别/名称（用户主权区，专列更新；行不存在静默跳过）。
  Future<void> updateEntry(
    String id, {
    String? category,
    String? name,
    String? description,
  }) => guardRepoWrite('setting_entry', 'updateEntry', () async {
    final existing = await (_db.select(
      _db.settingEntries,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (existing == null) return;
    await (_db.update(_db.settingEntries)..where((t) => t.id.equals(id))).write(
      SettingEntriesCompanion(
        category: category == null ? Value.absent() : Value(category),
        name: name == null ? Value.absent() : Value(name),
        description: description == null ? Value.absent() : Value(description),
        updatedAt: Value(nowSec()),
      ),
    );
  });

  /// 勾选/取消「参与诊断」（用户主权区，独立开关）。
  Future<void> setParticipate(String id, bool participate) =>
      guardRepoWrite('setting_entry', 'setParticipate', () async {
        await (_db.update(
          _db.settingEntries,
        )..where((t) => t.id.equals(id))).write(
          SettingEntriesCompanion(
            participate: Value(participate),
            updatedAt: Value(nowSec()),
          ),
        );
      });

  /// 删除条目（级联仅限自身行；作品删除走 manuscript 级联）。
  Future<void> deleteEntry(String id) =>
      guardRepoWrite('setting_entry', 'deleteEntry', () async {
        await (_db.delete(
          _db.settingEntries,
        )..where((t) => t.id.equals(id))).go();
      });

  /// 作品全部条目（按 updatedAt 倒序，列表主查询）。
  Future<List<SettingEntry>> listEntries(String manuscriptId) async {
    return (_db.select(_db.settingEntries)
          ..where((t) => t.manuscriptId.equals(manuscriptId))
          ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]))
        .get();
  }

  /// 作品已勾选「参与诊断」的条目（注入用：只取 participate==1）。
  Future<List<SettingEntry>> listParticipating(String manuscriptId) async {
    return (_db.select(_db.settingEntries)
          ..where(
            (t) =>
                t.manuscriptId.equals(manuscriptId) &
                t.participate.equals(true),
          )
          ..orderBy([
            (t) => OrderingTerm.asc(t.category),
            (t) => OrderingTerm.asc(t.name),
          ]))
        .get();
  }

  /// 作品现有类别（chips 建议：SELECT DISTINCT category，空串排除）。
  Future<List<String>> listCategories(String manuscriptId) async {
    final rows =
        await (_db.selectOnly(_db.settingEntries)
              ..addColumns([_db.settingEntries.category])
              ..where(_db.settingEntries.manuscriptId.equals(manuscriptId))
              ..groupBy([_db.settingEntries.category]))
            .get();
    return rows
        .map((r) => r.read(_db.settingEntries.category))
        .whereType<String>()
        .map((c) => c.trim())
        .where((c) => c.isNotEmpty)
        .toList();
  }
}
