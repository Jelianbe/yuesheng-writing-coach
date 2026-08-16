// ─────────────────────────────────────────────────────────────
// VolumeRepository — 卷 DAO（批次89 卷分组）
// 卷是作品下章节的顶层分组（第一卷/第二卷…），卷内章节顺序仍由
// chapters.sort_order 决定（同卷内连续）。
// 设计：
//   - volume_id 可空 = 章节「未分卷」（兼容存量章节）
//   - 删卷时外键 ON DELETE SET NULL → 卷内章节自动回「未分卷」
// ─────────────────────────────────────────────────────────────

import 'package:drift/drift.dart';
import '../database/database.dart';
import '../database/utils.dart';
import '../../utils/chapter_title.dart';

class VolumeRepository {
  final AppDatabase _db;
  VolumeRepository(this._db);

  /// 创建卷（title 空则自动命名「第一卷/第二卷…」），返回 id
  Future<String> createVolume(
    String manuscriptId, {
    String? title,
    int? sortOrder,
  }) async {
    final id = generateUuid();
    final now = nowSec();
    int order = sortOrder ?? 0;
    if (sortOrder == null) {
      final maxOrder = await (_db.selectOnly(_db.volumes)
            ..addColumns([_db.volumes.sortOrder.max()])
            ..where(_db.volumes.manuscriptId.equals(manuscriptId)))
          .getSingleOrNull();
      order = (maxOrder?.read(_db.volumes.sortOrder.max()) ?? -1) + 1;
    }
    final resolvedTitle = title?.trim().isNotEmpty == true
        ? title!.trim()
        : nextVolumeTitle(await listVolumes(manuscriptId));
    await _db.into(_db.volumes).insert(
          VolumesCompanion.insert(
            id: id,
            manuscriptId: manuscriptId,
            title: Value(resolvedTitle),
            sortOrder: Value(order),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
    return id;
  }

  /// 读取作品全部卷（按 sort_order）
  Future<List<Volume>> listVolumes(String manuscriptId) async {
    return (_db.select(_db.volumes)
          ..where((t) => t.manuscriptId.equals(manuscriptId))
          ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
        .get();
  }

  /// 批次95-4：读取单卷（写作页面包屑按 volumeId 取卷名）
  Future<Volume?> getVolume(String volumeId) async {
    return (_db.select(_db.volumes)..where((t) => t.id.equals(volumeId)))
        .getSingleOrNull();
  }

  /// 删除卷（批次96-4：事务内先软删卷内全部章节进回收站，再删卷）
  /// 不再散落到「散落」组——卷内章节一并删除（回收站可恢复，语义与单章删除一致）。
  /// 外键 ON DELETE SET NULL 仍作兜底：软删章节的 volume_id 随卷删除被置空，
  /// 恢复后落入「散落」组，符合「卷已删除」的事实。
  Future<void> deleteVolume(String volumeId) async {
    await _db.transaction(() async {
      await (_db.update(_db.chapters)
            ..where(
              (t) => t.volumeId.equals(volumeId) & t.status.equals('draft'),
            ))
          .write(
            ChaptersCompanion(
              status: const Value('archived'),
              updatedAt: Value(nowSec()),
            ),
          );
      await (_db.delete(_db.volumes)..where((t) => t.id.equals(volumeId))).go();
    });
  }

  /// 设置章节所属卷（volumeId null = 移出卷 → 未分卷）
  Future<void> setChapterVolume(String chapterId, String? volumeId) async {
    await (_db.update(_db.chapters)..where((t) => t.id.equals(chapterId)))
        .write(ChaptersCompanion(
          volumeId: Value(volumeId),
          updatedAt: Value(nowSec()),
        ));
  }

  /// 批次96-1：移动章节到目标卷末尾（跨卷归属调整）
  /// 事务内：
  ///   ① 计算目标卷内最大 sort_order + 1 作为新顺序（null = 未分卷组内）
  ///   ② 设置 volumeId + 更新 sort_order
  /// 与 setChapterVolume 的区别：后者保持原 sort_order（章节会按原全局序
  /// 插入目标卷任意位置），本方法保证落到目标卷末位，顺序语义直观。
  Future<void> moveChapterToVolumeEnd(
    String chapterId,
    String? volumeId,
  ) async {
    await _db.transaction(() async {
      final maxOrder = await (_db.selectOnly(_db.chapters)
            ..addColumns([_db.chapters.sortOrder.max()])
            ..where(
              volumeId == null
                  ? _db.chapters.volumeId.isNull()
                  : _db.chapters.volumeId.equals(volumeId),
            ))
          .getSingleOrNull();
      final order = (maxOrder?.read(_db.chapters.sortOrder.max()) ?? -1) + 1;
      await (_db.update(_db.chapters)..where((t) => t.id.equals(chapterId)))
          .write(ChaptersCompanion(
            volumeId: Value(volumeId),
            sortOrder: Value(order),
            updatedAt: Value(nowSec()),
          ));
    });
  }

  /// 批次92-2：重命名卷（鱼写作长按驱动模型——长按卷头 → 重命名）
  Future<void> updateVolumeTitle(String volumeId, String title) async {
    await (_db.update(_db.volumes)..where((t) => t.id.equals(volumeId)))
        .write(VolumesCompanion(
          title: Value(title.trim().isEmpty ? '未命名卷' : title.trim()),
          updatedAt: Value(nowSec()),
        ));
  }

  /// 计算新建卷的自动标题（「第X卷」，按当前卷数 +1）
  String nextVolumeTitle(List<Volume> volumes) {
    return '第${intToChineseNumber(volumes.length + 1)}卷';
  }
}
