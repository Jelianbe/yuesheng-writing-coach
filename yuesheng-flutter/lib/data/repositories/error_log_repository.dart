// ─────────────────────────────────────────────────────────────
// ErrorLogRepository — 错误日志 DAO
// 复刻 yuesheng-android/src/db/dao/error-log-dao.ts
// 唯一实现了分页查询的 DAO
// ─────────────────────────────────────────────────────────────

import 'dart:convert';
import 'package:drift/drift.dart';
import '../database/database.dart';
import '../database/utils.dart';

/// 错误日志查询条件（复刻 ErrorLogQuery）
class ErrorLogQuery {
  final String? level;
  final String? category;
  final int? limit;
  final int? offset;
  final int? since;

  ErrorLogQuery({
    this.level,
    this.category,
    this.limit,
    this.offset,
    this.since,
  });
}

/// 错误日志条目（复刻 ErrorLogEntry）
class ErrorLogEntry {
  final String id;
  final String level;
  final String category;
  final String message;
  final String? stack;
  final Map<String, dynamic>? context;
  final Map<String, dynamic>? deviceInfo;
  final int createdAt;

  ErrorLogEntry({
    required this.id,
    required this.level,
    required this.category,
    required this.message,
    this.stack,
    this.context,
    this.deviceInfo,
    required this.createdAt,
  });
}

class ErrorLogRepository {
  final AppDatabase _db;
  ErrorLogRepository(this._db);

  /// 插入错误日志
  /// 复刻 insertErrorLog(entry)
  /// ID 格式：err_`<timestamp>`_`<random>`（不走 uuid）
  Future<String> insertErrorLog({
    required String level,
    required String category,
    required String message,
    String? stack,
    Map<String, dynamic>? context,
    Map<String, dynamic>? deviceInfo,
  }) async {
    final now = nowSec();
    final id = 'err_${now}_${generateUuid().substring(0, 8)}';

    await _db
        .into(_db.errorLogs)
        .insert(
          ErrorLogsCompanion.insert(
            id: id,
            level: Value(level),
            category: Value(category),
            message: message,
            stack: Value(stack),
            context: Value(context != null ? jsonEncode(context) : null),
            deviceInfo: Value(
              deviceInfo != null ? jsonEncode(deviceInfo) : null,
            ),
            createdAt: Value(now),
          ),
        );
    return id;
  }

  /// 查询错误日志（支持分页 + 条件过滤）
  /// 复刻 queryErrorLogs(query?)
  /// 默认 limit=100, offset=0
  Future<List<ErrorLogEntry>> queryErrorLogs({ErrorLogQuery? query}) async {
    final q = query ?? ErrorLogQuery();
    final stmt = _db.select(_db.errorLogs);

    // 动态 WHERE
    stmt.where((t) {
      final conditions = <Expression<bool>>[];
      if (q.level != null) conditions.add(t.level.equals(q.level!));
      if (q.category != null) conditions.add(t.category.equals(q.category!));
      if (q.since != null) {
        conditions.add(t.createdAt.isBiggerOrEqualValue(q.since!));
      }
      if (conditions.isEmpty) return const Constant(true);
      return conditions.reduce((a, b) => a & b);
    });

    // 排序 + 分页
    stmt.orderBy([
      (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
    ]);
    stmt.limit(q.limit ?? 100, offset: q.offset ?? 0);

    final rows = await stmt.get();
    return rows.map(_rowToEntry).toList();
  }

  /// 统计各级别日志数量
  /// 复刻 getErrorLogStats(since?)
  Future<List<({String level, int count})>> getErrorLogStats({
    int? since,
  }) async {
    final stmt = _db.selectOnly(_db.errorLogs)
      ..addColumns([_db.errorLogs.level, _db.errorLogs.id.count()])
      ..groupBy([_db.errorLogs.level]);

    if (since != null) {
      stmt.where(_db.errorLogs.createdAt.isBiggerOrEqualValue(since));
    }

    final rows = await stmt.get();
    return rows.map((r) {
      return (
        level: r.read(_db.errorLogs.level)!,
        count: r.read(_db.errorLogs.id.count())!,
      );
    }).toList();
  }

  /// 删除旧日志（按天数）
  /// 复刻 deleteOldErrorLogs(olderThanDays?)
  /// 默认 30 天
  Future<int> deleteOldErrorLogs({int olderThanDays = 30}) async {
    const secondsPerDay = 86400;
    final cutoff = nowSec() - (olderThanDays * secondsPerDay);
    return (_db.delete(
      _db.errorLogs,
    )..where((t) => t.createdAt.isSmallerThanValue(cutoff))).go();
  }

  /// 清空所有日志
  /// 复刻 clearAllErrorLogs()
  Future<int> clearAllErrorLogs() async {
    return _db.delete(_db.errorLogs).go();
  }

  // ── 内部辅助 ──

  ErrorLogEntry _rowToEntry(ErrorLog row) {
    Map<String, dynamic>? parseJsonField(String? raw) {
      if (raw == null || raw.isEmpty) return null;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) return decoded;
      } catch (_) {}
      return null;
    }

    return ErrorLogEntry(
      id: row.id,
      level: row.level,
      category: row.category,
      message: row.message,
      stack: row.stack,
      context: parseJsonField(row.context),
      deviceInfo: parseJsonField(row.deviceInfo),
      createdAt: row.createdAt,
    );
  }
}
