// ─────────────────────────────────────────────────────────────
// 完整章完成候选·证据卡查询器（ADR-C137 批3；M4 第二格证据卡对接）
//
// 定位（与 M3MilestoneEventQuerier 平级、职责正交）：
//   M3MilestoneEventQuerier —— M3 里程碑候选（diff/adopt/anchor/普通 completion）。
//   本查询器              —— M4 第二格「独立成完整章」完成候选（批1 聚合器的异步装配层）。
//
// 证据卡输入（ADR §4.2）：沿用 C133「按章节 / 按会话聚合」查询形态。
//   - queryByChapter(chapterId)：证据卡按章节取该章的完成候选（含 independent_drafting 标记筛选）；
//   - queryBySession(sessionId)：证据卡按会话取该会话命中章节的完成候选。
//
// 装配两张上下文 map 喂给纯函数 aggregateChapterCompletionCandidates：
//   - goalWordsByChapter：app_state `chapter_goal:<chapterId>`（0=未设目标）；
//   - wordCountByChapter：该章当前草稿字数（chapter.content.length）。
//
// R-009：本层**只记不判**——装配事实 + 调用纯函数，不做任何成败判定 / 打分 / 处方。
// 各排除原因计数由纯函数给出，证据卡只读展示。
//
// R-028：仓储读取属边界层，读失败按「未设目标 / 零字数」降级并留痕
//   （不阻断证据卡、不空 catch）。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/foundation.dart';

import '../data/repositories/app_state_repository.dart';
import '../data/repositories/chapter_repository.dart';
import '../data/repositories/chapter_scoped_keys.dart';
import '../data/repositories/edit_diff_event_repository.dart';
import 'chapter_completion_aggregator.dart';

/// M4 第二格完成候选证据卡查询器（按章节 / 会话聚合）。
class ChapterCompletionQuerier {
  final EditDiffEventRepository _diffRepo;
  final AppStateRepository _appStateRepo;
  final ChapterRepository _chapterRepo;

  const ChapterCompletionQuerier(
    this._diffRepo,
    this._appStateRepo,
    this._chapterRepo,
  );

  /// 按章节聚合该章全部事件 → 完成候选报告（证据卡章节视图）。
  ///
  /// 上下文：该章当前目标字数 + 当前草稿字数。
  Future<ChapterCompletionReport> queryByChapter(String chapterId) async {
    final events = await _diffRepo.listByChapter(chapterId);
    return aggregateChapterCompletionCandidates(
      events: events,
      goalWordsByChapter: {chapterId: await _goalWordsOf(chapterId)},
      wordCountByChapter: {chapterId: await _wordCountOf(chapterId)},
    );
  }

  /// 按会话聚合该会话命中章节的事件 → 完成候选报告（证据卡会话视图）。
  ///
  /// 一个会话通常落在单一章节；若事件跨章，逐章装配 goal/wordCount 上下文。
  Future<ChapterCompletionReport> queryBySession(String sessionId) async {
    final events = await _diffRepo.listBySession(sessionId);
    final chapterIds = events.map((e) => e.chapterId).toSet().toList();
    final goalBy = <String, int>{};
    final wordsBy = <String, int>{};
    for (final cid in chapterIds) {
      goalBy[cid] = await _goalWordsOf(cid);
      wordsBy[cid] = await _wordCountOf(cid);
    }
    return aggregateChapterCompletionCandidates(
      events: events,
      goalWordsByChapter: goalBy,
      wordCountByChapter: wordsBy,
    );
  }

  /// 读章节目标字数（app_state `chapter_goal:<id>`）；未设 / 读失败 → 0。
  /// 0=未设目标：按 ADR §4.2 现场裁定，goal=0 的章节不产出完整章候选（不替用户猜阈值）。
  Future<int> _goalWordsOf(String chapterId) async {
    try {
      final raw = await _appStateRepo.getValue(chapterGoalKey(chapterId));
      final g = int.tryParse(raw ?? '') ?? 0;
      return g < 0 ? 0 : g;
    } catch (e) {
      debugPrint('[ChapterCompletionQuerier] 读 goal 失败($chapterId)→按未设目标: $e');
      return 0;
    }
  }

  /// 读章节当前草稿字数（chapter.content.length）；章不存在 / 读失败 → 0。
  Future<int> _wordCountOf(String chapterId) async {
    try {
      final ch = await _chapterRepo.getChapter(chapterId);
      return ch?.content.length ?? 0;
    } catch (e) {
      debugPrint('[ChapterCompletionQuerier] 读字数失败($chapterId)→0: $e');
      return 0;
    }
  }
}
