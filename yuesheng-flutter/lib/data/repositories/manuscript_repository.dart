// ─────────────────────────────────────────────────────────────
// ManuscriptRepository — 稿件 DAO
// 复刻 yuesheng-android/src/db/dao/basic-dao.ts 的 manuscripts 部分
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:drift/drift.dart';
import '../database/database.dart';
import '../database/utils.dart';

class ManuscriptRepository {
  final AppDatabase _db;
  ManuscriptRepository(this._db);

  /// 创建稿件，返回 id
  /// 复刻 createManuscript(input?)
  ///
  /// [sortOrder] 可选：不传时保持默认 0（与既有行为一致）。
  /// 测试或需要显式排序时传入，避免同一秒插入多条时
  /// listManuscripts（sort_order ASC, updated_at DESC）排序键完全相同
  /// 导致返回顺序不确定（详见 mention_parser_test 的 seed）。
  Future<String> createManuscript({
    String? title,
    String? description,
    String? genre,
    String? language,
    List<String>? tags,
    int? sortOrder,
  }) async {
    final id = generateUuid();
    final now = nowSec();
    await _db
        .into(_db.manuscripts)
        .insert(
          ManuscriptsCompanion.insert(
            id: id,
            title: Value(title ?? ''),
            description: Value(description ?? ''),
            genre: Value(genre ?? ''),
            language: Value(language ?? '中文'),
            status: const Value('active'),
            // 批次94-5：标签落库（JSON string[]）
            tags: Value(tags == null ? '[]' : jsonEncode(tags)),
            sortOrder: Value(sortOrder ?? 0),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
    return id;
  }

  /// 获取单条稿件
  /// 复刻 getManuscript(id)
  Future<Manuscript?> getManuscript(String id) async {
    final result = await (_db.select(
      _db.manuscripts,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return result;
  }

  /// 按 id 集合批量取稿件（A-3 遗留 N+1 消除：引用预加载用）
  /// 语义对齐 getManuscript：仅按 id 过滤，不过滤 status。空列表守卫避免 `IN ()` 非法 SQL。
  Future<List<Manuscript>> getManuscriptsByIds(List<String> ids) async {
    if (ids.isEmpty) return const [];
    return (_db.select(_db.manuscripts)
          ..where((t) => t.id.isIn(ids)))
        .get();
  }

  /// 解析稿件 tags JSON（容错：非法 JSON / 非数组 → 空列表，批次94-5）
  static List<String> parseTags(Manuscript manuscript) {
    try {
      final raw = jsonDecode(manuscript.tags);
      if (raw is List) return raw.whereType<String>().toList();
      return const [];
    } catch (_) {
      return const [];
    }
  }

  /// 列出所有 active 稿件（软删除的不返回）
  /// 复刻 listManuscripts() — 按 sort_order, updated_at DESC 排序
  Future<List<Manuscript>> listManuscripts() async {
    final result =
        await (_db.select(_db.manuscripts)
              ..where((t) => t.status.equals('active'))
              ..orderBy([
                (t) => OrderingTerm(expression: t.sortOrder),
                (t) => OrderingTerm(
                  expression: t.updatedAt,
                  mode: OrderingMode.desc,
                ),
              ]))
            .get();
    return result;
  }

  /// 更新稿件（title/description/genre/tags）
  /// 复刻 updateManuscript(id, input)
  Future<void> updateManuscript(
    String id, {
    String? title,
    String? description,
    String? genre,
    List<String>? tags,
  }) async {
    final companion = ManuscriptsCompanion(
      title: title != null ? Value(title) : const Value.absent(),
      description: description != null
          ? Value(description)
          : const Value.absent(),
      genre: genre != null ? Value(genre) : const Value.absent(),
      // 批次94-5：标签落库（JSON string[]）
      tags: tags != null ? Value(jsonEncode(tags)) : const Value.absent(),
      updatedAt: Value(nowSec()),
    );
    await (_db.update(
      _db.manuscripts,
    )..where((t) => t.id.equals(id))).write(companion);
  }

  /// 批次93-7：更新作品排序值（书架「置顶」用——置为当前最小 sort_order - 1）
  Future<void> updateSortOrder(String id, int sortOrder) async {
    await (_db.update(_db.manuscripts)..where((t) => t.id.equals(id))).write(
      ManuscriptsCompanion(
        sortOrder: Value(sortOrder),
        updatedAt: Value(nowSec()),
      ),
    );
  }

  /// 软删除稿件（置 status='archived'）
  /// 复刻 deleteManuscript(id) — 不是物理删除
  Future<void> deleteManuscript(String id) async {
    await (_db.update(_db.manuscripts)..where((t) => t.id.equals(id))).write(
      ManuscriptsCompanion(
        status: const Value('archived'),
        updatedAt: Value(nowSec()),
      ),
    );
  }

  /// 按 sort_order 获取稿件（解析 @W001 语法用）
  /// 复刻 getManuscriptByOrder(order)
  Future<Manuscript?> getManuscriptByOrder(int order) async {
    final result =
        await (_db.select(_db.manuscripts)
              ..where(
                (t) => t.status.equals('active') & t.sortOrder.equals(order),
              )
              ..limit(1))
            .getSingleOrNull();
    return result;
  }
}
