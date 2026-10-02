// ─────────────────────────────────────────────────────────────
// m3_candidate_aggregator — M3 门槛候选事件聚合纯函数
// （ADR-C133 北极星测量协议批 · 批1 子任务 M3）
//
// 背景（ADR-C133 §4.1）：M3 门槛事件 = 「学员在无教练提示下，自己修改了
// 一个已学症候位置」。本聚合器只做「候选事件绝对值」的事实聚合，
// 严禁任何「改对/改好/达标」成败判定（R-009 红线 / ADR §7 验收⑥）——
// 是否真的改对，由用户在里程碑证据卡环节裁决。
//
// 操作化三要素：
//   ① 非采纳链路的自主修改 diff：eventType=='diff' 且 messageId==null
//     且 payload.source!='adopt'（现成语义 = 无关联反馈的自主修改）。
//     采纳链路两种形态均排除、计入 adoptedChainDiffCount：
//       · messageId 非空（UI 链路由触发采纳的教练消息 id 透传）；
//       · messageId 为 null 但 payload.source='adopt'（provider 包装层/
//         旧调用拿不到 messageId 的形态，见 ChapterRepository.adoptContentToChapter）。
//   ② 修改位置命中已学症候诊断锚定区域（章节级为主判据）：
//     diff.chapterId 命中「已有 confirmed 章节级诊断（syndromes 非空）」
//     的章节。
//   ③ 只记不判：输出候选事实列表 + 绝对值计数，无成败布尔。
//
// 片段级增强（附加事实，不参与候选主判据）：
//   diff 变化段 afterText 与同章 anchor_ack 指认文本几何重叠
//   （互相包含，或 ≥2 字的非空交集）。中文散文单字交集噪声过大
//   （如「的」「了」），故交集下限取 2 字——这是保守几何事实判定，
//   不构成质量评价；片段不重叠也不影响「章节级候选」成立。
//
// 纯函数纪律：不 import 任何 Repository / DB 连接；输入输出驱动，可单测。
// EditDiffEvent 是 drift 生成的不可变数据类（const 构造，可脱离 DB 实例化），
// 直接作为输入行类型，避免手写镜像 DTO 与表结构漂移。
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/edit_diff_event_repository.dart';

/// 已学症候锚定条目（事实快照：id + 名称；来自 confirmed 诊断 syndromes JSON）。
class M3AnchorSyndrome {
  final String syndromeId;
  final String syndromeName;
  const M3AnchorSyndrome({
    required this.syndromeId,
    required this.syndromeName,
  });
}

/// 章节级诊断锚定上下文（由查询工具从 diagnosis_results + anchor_ack 构建，
/// 聚合器只消费，不构建）。syndromes 为空列表 = 该章节无已学症候锚定。
class M3ChapterAnchor {
  final String chapterId;
  final List<M3AnchorSyndrome> syndromes;
  final List<String> anchorTexts; // 同章 anchor_ack 指认片段文本
  M3ChapterAnchor({
    required this.chapterId,
    List<M3AnchorSyndrome>? syndromes,
    List<String>? anchorTexts,
  }) : syndromes = syndromes ?? <M3AnchorSyndrome>[],
       anchorTexts = anchorTexts ?? <String>[];
}

/// 锚定命中层级（事实描述，非质量档位）。
enum M3AnchorHitLevel {
  /// 仅章节级命中（主判据成立）。
  chapter,

  /// 章节级命中 + 变化段与同章指认文本几何重叠（附加事实）。
  chapterWithFragment,
}

/// M3 门槛候选事件（只记事实，不判成败）。
class M3CandidateEvent {
  final String diffEventId;
  final String chapterId;
  final String sessionId;
  final int createdAt;

  /// 要素①事实留痕：候选构造时恒为 null（自主修改）。
  /// 仅作「messageId==null」的事实确认快照，不表达任何成败语义。
  final String? messageId;

  /// 变化段后文本快照（事件事实，供里程碑证据卡展示改了什么）。
  final String? afterText;

  /// 命中章节的已学症候快照（事实：该章节当时被诊断出哪些症候）。
  final List<M3AnchorSyndrome> anchoredSyndromes;

  /// 锚定命中层级（章节级主判据 + 可选片段重叠事实）。
  final M3AnchorHitLevel hitLevel;

  const M3CandidateEvent({
    required this.diffEventId,
    required this.chapterId,
    required this.sessionId,
    required this.createdAt,
    required this.messageId,
    this.afterText,
    required this.anchoredSyndromes,
    required this.hitLevel,
  });
}

/// M3 候选聚合报告（绝对值计数；无达标/阈值语义）。
class M3CandidateReport {
  final List<M3CandidateEvent> candidates;

  /// 要素①计数：eventType=='diff' 且 messageId==null 的事件总数
  /// （含未命中锚定章节者——事实全量，不裁剪）。
  final int selfOwnedDiffCount;

  /// 被排除的采纳链路 diff 数：eventType=='diff' 且（messageId!=null
  /// 或 payload.source=='adopt'）——含 UI 透传 messageId 的形态，与
  /// 拿不到 messageId 但 payload.source='adopt' 的调用形态。
  final int adoptedChainDiffCount;

  const M3CandidateReport({
    required this.candidates,
    required this.selfOwnedDiffCount,
    required this.adoptedChainDiffCount,
  });

  /// 候选事件绝对值（= 章节级命中数；章节级即主判据，候选必命中）。
  int get candidateCount => candidates.length;
}

/// 聚合 M3 门槛候选事件（纯函数）。
///
/// [diffEvents] 待审事件行（调用方已按章节/会话/时间段预筛）；
/// [anchorsByChapter] 章节→已学症候锚定上下文（键为 chapterId）。
M3CandidateReport aggregateM3Candidates({
  required List<EditDiffEvent> diffEvents,
  required Map<String, M3ChapterAnchor> anchorsByChapter,
}) {
  final candidates = <M3CandidateEvent>[];
  var selfOwned = 0;
  var adopted = 0;
  for (final e in diffEvents) {
    if (e.eventType != EditDiffEventTypes.diff) {
      continue; // ack/completion 非 diff，不参与候选判定
    }
    if (e.messageId != null || _payloadSourceIsAdopt(e.payload)) {
      adopted++;
      continue; // 要素①：采纳链路（messageId 透传 / payload.source=adopt）
    }
    selfOwned++;
    final anchor = anchorsByChapter[e.chapterId];
    if (anchor == null || anchor.syndromes.isEmpty) {
      continue; // 要素②：该章节无已学症候锚定区域
    }
    final fragmentHit = _fragmentTextOverlap(e.afterText, anchor.anchorTexts);
    candidates.add(
      M3CandidateEvent(
        diffEventId: e.id,
        chapterId: e.chapterId,
        sessionId: e.sessionId,
        createdAt: e.createdAt,
        messageId: e.messageId, // 恒 null，事实留痕
        afterText: e.afterText, // 变化段事实快照
        anchoredSyndromes: List.unmodifiable(anchor.syndromes),
        hitLevel: fragmentHit
            ? M3AnchorHitLevel.chapterWithFragment
            : M3AnchorHitLevel.chapter,
      ),
    );
  }
  return M3CandidateReport(
    candidates: List.unmodifiable(candidates),
    selfOwnedDiffCount: selfOwned,
    adoptedChainDiffCount: adopted,
  );
}

/// 判定 diff 行是否来自采纳链路（payload.source=='adopt'）。
///
/// 采纳链路存在「拿不到 messageId」的调用形态（provider 包装层/旧调用），
/// 其 diff 行 message_id=null 但 payload 带 source='adopt'（见
/// ChapterRepository.adoptContentToChapter 写入）。本函数安全解析 payload：
/// 空串 / 损坏 JSON / 无 source 字段一律返回 false（按自主修改处理），
/// 绝不抛错（解析外部 JSON 须兜底；不引入任何成败语义）。
bool _payloadSourceIsAdopt(String payload) {
  if (payload.isEmpty) return false;
  try {
    final map = jsonDecode(payload) as Map<String, dynamic>;
    return map['source'] == 'adopt';
  } catch (_) {
    return false;
  }
}

/// 片段几何重叠（纯事实）：[afterText] 与 [anchorTexts] 任一条
/// 互相包含，或存在 ≥2 字的非空交集。空文本/空表 → false。
bool _fragmentTextOverlap(String? afterText, List<String> anchorTexts) {
  final after = afterText?.trim() ?? '';
  if (after.isEmpty || anchorTexts.isEmpty) return false;
  for (final t in anchorTexts) {
    final anchor = t.trim();
    if (anchor.isEmpty) continue;
    if (anchor.contains(after) || after.contains(anchor)) return true;
    if (_sharesBigram(after, anchor)) return true;
  }
  return false;
}

/// 双向 ≥2 字非空交集（任一 2-字 bigram 互相出现）。
bool _sharesBigram(String a, String b) {
  if (a.length < 2 || b.length < 2) return false;
  for (var i = 0; i < a.length - 1; i++) {
    if (b.contains(a.substring(i, i + 2))) return true;
  }
  return false;
}
