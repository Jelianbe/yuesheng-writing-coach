// ─────────────────────────────────────────────────────────────
// volume_group — 章节按卷分组纯函数（批次89-2 章节树分组）
//
// 规则：
//   - 卷按 sort_order 排序展示
//   - 未分卷章节（volume_id 为 null 或指向已删卷）归入末尾「未分卷」组
//   - 组内章节按 sort_order 排序
//   - volumes 为空（作品还没有卷）→ 返回空列表，UI 层走扁平列表
//
// 批次96-4：UI 平铺展示改用 buildChapterSections——散落章节不再有
// 「未分卷」组头，直接平铺并与卷组按全局顺序自然穿插；本函数保留给
// 导出等「未分卷置末」的旧场景使用。
// ─────────────────────────────────────────────────────────────

import '../data/database/database.dart';

/// 一个卷分组：volume 为 null 表示「未分卷」组
class VolumeGroup {
  final Volume? volume;
  final List<Chapter> chapters;

  const VolumeGroup({this.volume, required this.chapters});
}

/// 按卷分组（卷序 + 未分卷排最后）
List<VolumeGroup> groupChaptersByVolume(
  List<Volume> volumes,
  List<Chapter> chapters,
) {
  if (volumes.isEmpty) return const [];

  final sortedVolumes = [...volumes]
    ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  final volumeIds = volumes.map((v) => v.id).toSet();
  // volumeId 指向不存在卷的章节按未分卷处理（脏数据兜底）
  bool isUnassigned(Chapter c) =>
      c.volumeId == null || !volumeIds.contains(c.volumeId);

  final groups = <VolumeGroup>[];
  for (final v in sortedVolumes) {
    final inVolume = chapters
        .where((c) => c.volumeId == v.id)
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    groups.add(VolumeGroup(volume: v, chapters: inVolume));
  }

  final unassigned = chapters.where(isUnassigned).toList()
    ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  if (unassigned.isNotEmpty) {
    groups.add(VolumeGroup(volume: null, chapters: unassigned));
  }
  return groups;
}

/// 批次96-4：渲染段——散落章节（无卷头，直接平铺）或 卷组（卷头 + 卷内章节）
class ChapterSection {
  /// 非空 = 散落章节平铺段（不显示任何组头）
  final Chapter? looseChapter;

  /// 非空 = 卷组段（卷头 + chapters）
  final Volume? volume;

  final List<Chapter> chapters;

  const ChapterSection.loose(Chapter this.looseChapter)
      : volume = null,
        chapters = const [];

  ChapterSection.volume(this.volume, this.chapters)
      : looseChapter = null;
}

/// 批次96-4：按「全局顺序」构建渲染段——散落章节直接平铺（无卷头），
/// 卷组出现在其卷内第一个章节的全局位置，卷内章节按 sort_order 排序。
/// 空卷（无章节）按卷序追加到末尾。
///
/// 效果（用户示例）：
///   第一章（散落）→ 第二章（散落）→ 第一卷[…] → 第二卷[…] → 第三章（散落）
List<ChapterSection> buildChapterSections(
  List<Volume> volumes,
  List<Chapter> chapters,
) {
  final volumeById = {for (final v in volumes) v.id: v};
  // 全局序：sort_order 为主，createdAt 兜底（移动章节后可能局部重排导致同序）
  final sorted = [...chapters]
    ..sort((a, b) {
      final c = a.sortOrder.compareTo(b.sortOrder);
      return c != 0 ? c : a.createdAt.compareTo(b.createdAt);
    });

  final sections = <ChapterSection>[];
  final started = <String>{};
  for (final ch in sorted) {
    final vid = ch.volumeId;
    if (vid == null || !volumeById.containsKey(vid)) {
      // 散落章节（含指向已删卷的脏数据）→ 平铺
      sections.add(ChapterSection.loose(ch));
      continue;
    }
    if (!started.contains(vid)) {
      started.add(vid);
      sections.add(ChapterSection.volume(volumeById[vid]!, [ch]));
    } else {
      sections.last.chapters.add(ch);
    }
  }

  // 空卷追尾（按卷序）
  final emptyVolumes = volumes
      .where((v) => !started.contains(v.id))
      .toList()
    ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  for (final v in emptyVolumes) {
    sections.add(ChapterSection.volume(v, const []));
  }
  return sections;
}
