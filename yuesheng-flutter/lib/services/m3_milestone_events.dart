// ─────────────────────────────────────────────────────────────
// m3_milestone_events — M3 门槛事件查询工具
// （ADR-C133 北极星测量协议批 · 批1 子任务 M3）
//
// 职责：读 DB（EditDiffEventRepository + DiagnosisRepository 的**现有只读**
// 方法），构建章节→已学症候锚定上下文，再委托 [aggregateM3Candidates]
// 纯函数聚合 —— 本类自己不做任何候选判定（判定全在纯函数里，可单测）。
//
// 与聚合器**分文件**的理由（任务要求二选一并写明）：
//   聚合器是零 DB 依赖的纯函数（import 只到 drift 数据类），查询器是
//   async 的仓储装配层。拆开后聚合器单测无需起内存库；若合并，纯函数
//   形态会被仓储 import 污染，单测成本上升。故分文件。
//
// 纪律：
//   - 不修改 EditDiffEventRepository / DiagnosisRepository 本身
//     （C132/C133 边界，另一批次活跃施工）；
//   - 时间段过滤在内存做（listByType(diff) 取回后按 createdAt 区间裁剪）
//     —— 事件表为 append-only 小流水，暂不为过滤加 SQL 重载；
//   - 畸形 syndromes JSON 按 decode_guard 留痕降级为空（R-028，禁空 catch）。
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/diagnosis_repository.dart';
import 'package:writingcoach/data/repositories/edit_diff_event_repository.dart';
import 'package:writingcoach/services/decode_guard.dart';
import 'package:writingcoach/services/m3_candidate_aggregator.dart';

/// M3 门槛候选事件查询器（里程碑证据卡数据源）。
class M3MilestoneEventQuerier {
  final EditDiffEventRepository _diffRepo;
  final DiagnosisRepository _diagRepo;
  const M3MilestoneEventQuerier(this._diffRepo, this._diagRepo);

  /// 按章节查询门槛候选事件（事件时间升序已由 repo 保证）。
  Future<M3CandidateReport> queryByChapter(String chapterId) async {
    final events = await _diffRepo.listByChapter(chapterId);
    return _aggregate(events);
  }

  /// 按会话查询门槛候选事件。
  Future<M3CandidateReport> queryBySession(String sessionId) async {
    final events = await _diffRepo.listBySession(sessionId);
    return _aggregate(events);
  }

  /// 按时间段查询（createdAt unix 秒闭区间；fromSec/toSec 均可空 = 开端）。
  Future<M3CandidateReport> queryByTimeRange({int? fromSec, int? toSec}) async {
    final events = await _diffRepo.listByType(EditDiffEventTypes.diff);
    final filtered = events.where((e) {
      if (fromSec != null && e.createdAt < fromSec) return false;
      if (toSec != null && e.createdAt > toSec) return false;
      return true;
    }).toList();
    return _aggregate(filtered);
  }

  /// ADR-C134 批3（M4a）：列出「独立起稿模式下触发的成稿事件」——
  /// 里程碑证据卡的可观测输入。只记不判（C133 四硬隔离）：
  /// 本方法只做事实过滤（eventType==completion 且 payload.source==independent_drafting），
  /// 不设达标线、不展示学员、不打分、不自动加码；是否计入 M4a 由用户在证据卡裁决。
  Future<List<EditDiffEvent>> listIndependentDraftingCompletions() async {
    final completions = await _diffRepo.listByType(
      EditDiffEventTypes.completion,
    );
    return completions.where((e) {
      final payload = CompletionPayload.tryDecode(e.payload);
      return payload?.source == CompletionSource.independentDrafting;
    }).toList();
  }

  Future<M3CandidateReport> _aggregate(List<EditDiffEvent> events) async {
    final anchors = await buildChapterAnchors();
    return aggregateM3Candidates(diffEvents: events, anchorsByChapter: anchors);
  }

  /// 构建章节→已学症候锚定映射：
  ///   ① diagnosis_results 中 targetRefType=='chapter' 且 status=='confirmed'
  ///      的行，syndromes JSON 解析为症候 id/name（同章多行累加）；
  ///   ② anchor_ack 事件（afterText = 指认片段）按章节归入 anchorTexts。
  Future<Map<String, M3ChapterAnchor>> buildChapterAnchors() async {
    final anchors = <String, M3ChapterAnchor>{};
    final rows = await _diagRepo.getAllDiagnosisRows();
    for (final r in rows) {
      if (r.targetRefType != 'chapter' || r.status != 'confirmed') continue;
      final chapterId = r.targetRefId;
      if (chapterId == null || chapterId.isEmpty) continue;
      final entry = anchors.putIfAbsent(
        chapterId,
        () => M3ChapterAnchor(chapterId: chapterId),
      );
      entry.syndromes.addAll(_parseAnchorSyndromes(r.syndromes));
    }
    final acks = await _diffRepo.listByType(EditDiffEventTypes.anchorAck);
    for (final a in acks) {
      final text = a.afterText;
      if (text == null || text.isEmpty) continue;
      final entry = anchors.putIfAbsent(
        a.chapterId,
        () => M3ChapterAnchor(chapterId: a.chapterId),
      );
      entry.anchorTexts.add(text);
    }
    return anchors;
  }

  /// 解析 confirmed 诊断行的 syndromes JSON（[{syndrome_id,name,...}]）。
  List<M3AnchorSyndrome> _parseAnchorSyndromes(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final out = <M3AnchorSyndrome>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        final id = item['syndrome_id']?.toString() ?? '';
        if (id.isEmpty) continue;
        out.add(
          M3AnchorSyndrome(
            syndromeId: id,
            syndromeName: item['name']?.toString() ?? '',
          ),
        );
      }
      return out;
    } catch (e, st) {
      logDecodeFailure(field: 'm3.syndromes', error: e, stack: st);
      return const [];
    }
  }
}
