// ─────────────────────────────────────────────────────────────
// manuscript_providers — 书架/作品状态管理
// 复刻 yuesheng-android/src/store/book-store.ts
//
// 管理状态：
//   - manuscripts：作品列表（active 状态）
//   - isLoading：加载中
//   - error：最近一次错误
//
// 状态转换：
//   - loadManuscripts()：从 DB 拉取列表
//   - createManuscript()：DB 写入 + 乐观更新列表
//   - deleteManuscript()：软删除 + 从列表移除
//   - updateManuscript()：更新标题/简介/类型
//
// MVP 范围：
//   - 不实现 chaptersCache / filesCache / chapterDiagnoses
//   - 不实现 version 全局版本号
//   - 后续批次 B/C 扩展
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database/database.dart';
import '../data/repositories/chapter_repository.dart';
import '../data/repositories/manuscript_repository.dart';
import '../data/repositories/outline_repository.dart';
import '../data/repositories/volume_repository.dart';
import '../services/error_handler.dart';
import 'chapter_providers.dart';
import 'app_providers.dart';

/// 书架状态（不可变）
class ManuscriptState {
  final List<Manuscript> manuscripts;
  final bool isLoading;
  final String? error;

  const ManuscriptState({
    this.manuscripts = const [],
    this.isLoading = false,
    this.error,
  });

  ManuscriptState copyWith({
    List<Manuscript>? manuscripts,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) {
    return ManuscriptState(
      manuscripts: manuscripts ?? this.manuscripts,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// 作品状态管理器
///
/// 数据库通过构造函数注入（StateNotifier 无 ref 访问，遵循 ChatStore 模式）
class ManuscriptStore extends StateNotifier<ManuscriptState> {
  final AppDatabase _db;
  ManuscriptStore(this._db) : super(const ManuscriptState());

  /// 持久化失败留痕（CR-43）
  ///
  /// `debugPrint` 在 release 构建不输出 = 生产环境零留痕。作品 CRUD 是主链路
  /// 操作，失败表现为用户「点了没反应」且无从归因，故落 error_logs。
  /// 与 evaluation_providers 的 `_logPersistFailure` 同形（故意保持同构，
  /// 便于后续统一），level 取 error —— 评估是旁路用 warn，这里是主链路。
  void _logFailure(String op, Object e, StackTrace s) {
    debugPrint('[ManuscriptStore] $op 失败: $e');
    ErrorHandler.instance.captureError(
      level: 'error',
      category: 'database',
      message: '[ManuscriptStore] $op 失败: $e',
      stack: s.toString(),
    );
  }

  /// 从 DB 加载作品列表
  Future<void> loadManuscripts() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final repo = ManuscriptRepository(_db);
      final manuscripts = await repo.listManuscripts();
      state = state.copyWith(
        manuscripts: manuscripts,
        isLoading: false,
        clearError: true,
      );
    } catch (e, s) {
      _logFailure('loadManuscripts', e, s);
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// 创建作品：DB 写入 + 乐观更新到列表头部
  Future<String?> createManuscript({
    required String title,
    String? description,
    String? genre,
    List<String>? tags,
  }) async {
    try {
      final repo = ManuscriptRepository(_db);
      final id = await repo.createManuscript(
        title: title,
        description: description,
        genre: genre,
        tags: tags,
      );
      // CR-42：回读 DB 真实记录，不在内存里按默认值重造一个 Manuscript。
      // 原写法把 language / status / sortOrder 的默认值在此又抄了一份，
      // repository 侧改默认值时本处不会同步（P1-13 同源分歧）。
      final newMs = await repo.getManuscript(id);
      if (newMs == null) {
        // 回读失败（理论不可达）：重拉全量，保证内存与 DB 一致
        await loadManuscripts();
        return id;
      }
      state = state.copyWith(
        manuscripts: [newMs, ...state.manuscripts],
        clearError: true,
      );
      debugPrint('[ManuscriptStore] createManuscript 成功: id=$id');
      return id;
    } catch (e, s) {
      _logFailure('createManuscript', e, s);
      state = state.copyWith(error: e.toString());
      return null;
    }
  }

  /// 更新作品信息（批次94-5：tags 落库透传）
  Future<void> updateManuscript(
    String id, {
    String? title,
    String? description,
    String? genre,
    List<String>? tags,
  }) async {
    try {
      final repo = ManuscriptRepository(_db);
      await repo.updateManuscript(
        id,
        title: title,
        description: description,
        genre: genre,
        tags: tags,
      );
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      state = state.copyWith(
        manuscripts: state.manuscripts.map((m) {
          // CR-42：改 copyWith —— 表新增列时不会在此被静默丢弃
          // （原写法逐字段列举，漏一个就重置成默认值）
          return m.id == id
              ? m.copyWith(
                  title: title,
                  description: description,
                  genre: genre,
                  tags: tags != null ? jsonEncode(tags) : null,
                  updatedAt: now,
                )
              : m;
        }).toList(),
        clearError: true,
      );
    } catch (e, s) {
      _logFailure('updateManuscript', e, s);
      state = state.copyWith(error: e.toString());
    }
  }

  /// 软删除作品：DB 置 archived + 从列表移除
  Future<void> deleteManuscript(String id) async {
    try {
      final repo = ManuscriptRepository(_db);
      await repo.deleteManuscript(id);
      state = state.copyWith(
        manuscripts: state.manuscripts.where((m) => m.id != id).toList(),
        clearError: true,
      );
      debugPrint('[ManuscriptStore] deleteManuscript 成功: id=$id');
    } catch (e, s) {
      _logFailure('deleteManuscript', e, s);
      state = state.copyWith(error: e.toString());
    }
  }

  /// 清除错误
  void clearError() {
    state = state.copyWith(clearError: true);
  }
}

final manuscriptStoreProvider =
    StateNotifierProvider<ManuscriptStore, ManuscriptState>((ref) {
      final db = ref.watch(appDatabaseProvider);
      return ManuscriptStore(db);
    });

/// 批次93-3：书架刷新信号（详情页/写作页返回前 +1，书架 listen 后刷新）。
/// go_router StatefulShellRoute 下 RouteAware/routerDelegate/push-future 均
/// 无法可靠感知「branch 内页面从 root push 的页面返回」，用显式信号兜底。
final bookshelfRefreshSignalProvider = StateProvider<int>((ref) => 0);

/// 章节列表（ADR-C90 收敛：派生自 chapterStoreProvider，不再直读 DB）
///
/// 原为 FutureProvider 直读 DB；写操作经 store 后本视图自动同步，
/// 消费方不再需要手工 invalidate。类型为同步 List（非 AsyncValue）。
final chapterListProvider = Provider.family<List<Chapter>, String>((
  ref,
  manuscriptId,
) {
  return ref.watch(chapterStoreProvider(manuscriptId)).chapters;
});

/// 批次92：按作品加载卷列表（章节树抽屉分组用；无卷时为空列表）
final volumeListProvider = FutureProvider.family<List<Volume>, String>((
  ref,
  manuscriptId,
) async {
  final db = ref.watch(appDatabaseProvider);
  final repo = VolumeRepository(db);
  return repo.listVolumes(manuscriptId);
});

/// 批次93-1：作品章节统计（章节数 + 总字数，书架卡片信息加厚用）
class ManuscriptStats {
  final int chapterCount;
  final int totalWords;
  const ManuscriptStats({required this.chapterCount, required this.totalWords});
}

/// 批次93-1（B27 修复）：一次性批量统计所有作品的章节数 + 总字数。
/// 监听 manuscriptStoreProvider，作品列表变化时自动重算；以单条 GROUP BY
/// 查询替代原先每张卡片单独 manuscriptStatsProvider 的 N+1 查询。
final allManuscriptStatsProvider = FutureProvider<Map<String, ManuscriptStats>>(
  (ref) async {
    // CR-45：只订阅 manuscripts，不订阅整个 store。store 的 isLoading /
    // error 每次变化都会让整个 provider 重建——loadManuscripts 一轮就触发两次
    // 统计查询（isLoading=true 一次、false 一次），且第一次拿到的还是旧列表。
    final manuscripts = ref.watch(
      manuscriptStoreProvider.select((s) => s.manuscripts),
    );
    final ids = manuscripts.map((m) => m.id).toList();
    final db = ref.watch(appDatabaseProvider);
    final stats = await ChapterRepository(db).statsForManuscripts(ids);
    return {
      for (final e in stats.entries)
        e.key: ManuscriptStats(
          chapterCount: e.value.chapterCount,
          totalWords: e.value.totalWords,
        ),
    };
  },
);

/// 批次83：大纲边写边看——一次加载作品全部实体 + 各自印象
/// entityId → impressions 映射；读取失败由 repo 保守降级返回空
class OutlineView {
  final List<OutlineEntity> entities;
  final Map<String, List<OutlineImpression>> impressionsByEntity;

  const OutlineView({
    this.entities = const [],
    this.impressionsByEntity = const {},
  });
}

final outlineViewProvider = FutureProvider.family<OutlineView, String>((
  ref,
  manuscriptId,
) async {
  final db = ref.watch(appDatabaseProvider);
  final repo = OutlineRepository(db);
  final entities = await repo.listEntities(manuscriptId);
  final impressions = <String, List<OutlineImpression>>{};
  for (final e in entities) {
    impressions[e.id] = await repo.listImpressions(e.id);
  }
  return OutlineView(entities: entities, impressionsByEntity: impressions);
});
