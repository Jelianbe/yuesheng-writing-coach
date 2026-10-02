// ─────────────────────────────────────────────────────────────
// chapter_completion_aggregator — M4 第二格「独立成完整章」完成候选聚合纯函数
//   （ADR-C137 批1；复用 C133/C134 只记不判范式）
//
// 背景（ADR-C137 §4.2）：完成候选 = 「学员独立声明下、无教练采纳链路介入、
// 且字数达到单章目标」的成稿事件。本聚合器只做「候选事件事实」的聚合，
// 严禁任何「成稿/写好/达标/通过」成败判定（R-009 红线 / ADR §6 验收6）——
// 是否真的「完整」，由用户在里程碑证据卡环节裁决。
//
// 操作化三要素（缺一即不候选，各计排除原因——事实全量留痕，不裁剪）：
//   ① 成稿 + 自主声明：eventType=='completion' 且 payload.source
//      == CompletionSource.independentDrafting（C134 已埋，M4a 与完整章共用）。
//      普通成稿事件（无该 source）不进独立候选。
//   ② 自主性（非采纳链路）：该 completion 所属会话（sessionId；空则回退
//      chapterId）在事件范围内**无任何 adopt 链路 diff**。采纳链路两种形态
//      （沿用 M3 口径）：diff.messageId!=null，或 diff.payload.source=='adopt'。
//   ③ 长度达标：goalWordsByChapter[chapterId] > 0 且
//      wordCountByChapter[chapterId] >= goalWords。
//      · goalWords<=0（未设目标）→ 不计「完整章」候选（现场裁定见下）；
//      · wordCount<goal → 不计候选（事实计入 belowGoalCount）。
//
// 现场裁定（setGoalWords=0 语义）：
//   ADR §4.2「字数 ≥ 单章目标（setGoalWords，0=未设置时如何处理按 ADR 语义裁定）」。
//   裁定：goalWords==0 = 学员未给「这一章多长才算完整」下过定义。M4 第二格的
//   「完整章」**正是以达到自设字数目标来操作化的**；没有目标就没有「完整」的
//   定义，代码不得替学员猜一个默认长度阈值（那等于替用户做决定，违反 R-009）。
//   故 goalWords<=0 的 completion **不产出完整章候选**（计入 noGoalTargetCount
//   留痕，交证据卡由用户裁决）。这与事件产生路径自洽：completion 埋点本就只在
//   goalWords>0 且 wordCount>=goalWords 时触发（writing_page_document_controller），
//   goalWords=0 时现实中不会有 completion 行；本函数的 goal<=0 分支是对历史/
//   异常数据的防御性事实记录，不改变生产路径语义。
//
// 纯函数纪律：不 import 任何 Repository / DB 连接；输入输出驱动，可单测。
// EditDiffEvent 是 drift 生成的不可变数据类（const 构造，可脱离 DB 实例化）。
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/edit_diff_event_repository.dart';

/// 「独立成完整章」完成候选（只记事实，不判成败）。
///
/// goalWords / wordCount 是**评估当下的事实快照**（该章目标 + 当时字数），
/// 供证据卡展示「目标多少、写到多少」；本类不含任何 passed/success/reached
/// 等成败布尔——是否完整由用户裁决。
///
/// sessionId 与表 schema 对齐：非空 String；'' = 无法确定会话（章节级事件）。
class ChapterCompletionCandidate {
  final String completionEventId;
  final String chapterId;
  final String sessionId;
  final int createdAt;

  /// 评估该章单章目标字数（事实快照；>0，候选成立的前提）。
  final int goalWords;

  /// 评估该章当前字数（事实快照；>= goalWords）。
  final int wordCount;

  const ChapterCompletionCandidate({
    required this.completionEventId,
    required this.chapterId,
    required this.sessionId,
    required this.createdAt,
    required this.goalWords,
    required this.wordCount,
  });
}

/// 完成候选聚合报告（绝对值计数；无达标/通过语义）。
class ChapterCompletionReport {
  final List<ChapterCompletionCandidate> candidates;

  /// 要素①事实全量：eventType==completion 且 source==independent_drafting
  /// 的事件总数（含被②③排除者——事实不裁剪）。
  final int independentCompletionCount;

  /// 要素②排除：自主声明成稿，但所属会话/章节存在 adopt 链路介入。
  final int adoptIntervenedCount;

  /// 要素③a 排除：自主声明成稿，但该章未设字数目标（goalWords<=0）。
  final int noGoalTargetCount;

  /// 要素③b 排除：自主声明成稿、有目标，但字数未达目标。
  final int belowGoalCount;

  const ChapterCompletionReport({
    required this.candidates,
    required this.independentCompletionCount,
    required this.adoptIntervenedCount,
    required this.noGoalTargetCount,
    required this.belowGoalCount,
  });

  /// 候选事件绝对值（三要素齐备者）。
  int get candidateCount => candidates.length;
}

/// 聚合「独立成完整章」完成候选（纯函数）。
///
/// [events] 待审事件行（调用方已按章节/会话预筛；completion 与 diff 都传入——
///   diff 用于判定 adopt 链路介入）；
/// [goalWordsByChapter] 章节→单章目标字数（键为 chapterId；缺省按 0=未设置）；
/// [wordCountByChapter] 章节→评估当下字数（键为 chapterId；缺省按 0）。
ChapterCompletionReport aggregateChapterCompletionCandidates({
  required List<EditDiffEvent> events,
  required Map<String, int> goalWordsByChapter,
  required Map<String, int> wordCountByChapter,
}) {
  final adopt = _scanAdoptedContext(events);
  final candidates = <ChapterCompletionCandidate>[];
  var independentTotal = 0;
  var adoptIntervened = 0;
  var noGoal = 0;
  var belowGoal = 0;

  for (final e in events) {
    if (e.eventType != EditDiffEventTypes.completion) continue;
    final payload = CompletionPayload.tryDecode(e.payload);
    if (payload?.source != CompletionSource.independentDrafting) continue;
    independentTotal++;

    final goal = goalWordsByChapter[e.chapterId] ?? 0;
    final words = wordCountByChapter[e.chapterId] ?? 0;
    switch (_verdict(e, adopt, goal, words)) {
      case _Verdict.adopted:
        adoptIntervened++;
      case _Verdict.noGoal:
        noGoal++;
      case _Verdict.belowGoal:
        belowGoal++;
      case _Verdict.candidate:
        candidates.add(
          ChapterCompletionCandidate(
            completionEventId: e.id,
            chapterId: e.chapterId,
            sessionId: e.sessionId,
            createdAt: e.createdAt,
            goalWords: goal,
            wordCount: words,
          ),
        );
    }
  }

  return ChapterCompletionReport(
    candidates: List.unmodifiable(candidates),
    independentCompletionCount: independentTotal,
    adoptIntervenedCount: adoptIntervened,
    noGoalTargetCount: noGoal,
    belowGoalCount: belowGoal,
  );
}

/// adopt 链路介入的事实集：被采纳链路介入的会话与章节（要素②判据输入）。
class _AdoptedContext {
  final Set<String> sessions;
  final Set<String> chapters;
  const _AdoptedContext(this.sessions, this.chapters);
}

/// 扫 diff 行，标记被 adopt 链路介入的会话与章节（自主性判据的事实集）。
_AdoptedContext _scanAdoptedContext(List<EditDiffEvent> events) {
  final sessions = <String>{};
  final chapters = <String>{};
  for (final e in events) {
    if (e.eventType != EditDiffEventTypes.diff) continue;
    if (e.messageId != null || _payloadSourceIsAdopt(e.payload)) {
      if (e.sessionId.isNotEmpty) sessions.add(e.sessionId);
      chapters.add(e.chapterId);
    }
  }
  return _AdoptedContext(sessions, chapters);
}

/// 单个独立成稿事件的三要素判定结果（②③；①已在主循环筛过）。
enum _Verdict { adopted, noGoal, belowGoal, candidate }

/// 判定单个独立成稿事件归哪一桶（自主性 + 长度达标）。
_Verdict _verdict(EditDiffEvent e, _AdoptedContext adopt, int goal, int words) {
  final intervened = e.sessionId.isNotEmpty
      ? adopt.sessions.contains(e.sessionId)
      : adopt.chapters.contains(e.chapterId);
  if (intervened) return _Verdict.adopted;
  if (goal <= 0) return _Verdict.noGoal;
  if (words < goal) return _Verdict.belowGoal;
  return _Verdict.candidate;
}

/// 判定 diff 行是否来自采纳链路（payload.source=='adopt'）。
///
/// 口径沿用 M3 聚合器（见 m3_candidate_aggregator._payloadSourceIsAdopt）：
/// 空串 / 损坏 JSON / 无 source 字段一律返回 false（按自主修改处理），绝不抛错。
bool _payloadSourceIsAdopt(String? payload) {
  if (payload == null || payload.isEmpty) return false;
  try {
    final map = jsonDecode(payload) as Map<String, dynamic>;
    return map['source'] == 'adopt';
  } catch (_) {
    return false;
  }
}
