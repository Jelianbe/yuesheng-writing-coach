// ─────────────────────────────────────────────────────────────
// m5_transfer_report — M5（新题材迁移）三行为测量纯函数
// （ADR-C139 教学链路补全批 · 子项①）
//
// M5 = 三可观察迁移行为（裁决三件套 §1.5）：
//   (a) 新题材无提示独立写开头 → 独立起稿成稿候选计数；
//   (b) 过程中主动指认已学症候的应用点/复发点 → 自主修改命中锚定区域候选
//       （复用 M3 候选聚合，candidateCount）；
//   (c) 事后用自己的话说出根因通用/需变 → M2_recall 复述事件计数。
//
// C133 口径「只记不判」：本纯函数只输出候选计数，无达标/成败/迁移成功布尔；
// 是否达 M5 由北极星裁决框架在证据卡环节外部判定（本批不触发外部裁判）。
//
// 纯函数纪律（同 m3_candidate_aggregator）：不 import Repository/DB 连接；
// EditDiffEvent 为 drift 数据类，直接作输入行，避免镜像 DTO 与表结构漂移。
// ─────────────────────────────────────────────────────────────

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/edit_diff_event_repository.dart';
import 'package:writingcoach/services/m3_candidate_aggregator.dart';

/// M5（新题材迁移）三行为测量报告——只记不判（ADR-C139 / C133 口径）。
///
/// 三个计数分别对应三可观察迁移行为；无达标线、无成败布尔。
/// [selfOwnedAnchoredModifications] 复用 M3 候选报告（其 candidateCount 即
/// (b) 自主修改命中锚定区域候选数）。
class M5TransferReport {
  /// (a) 独立起稿成稿候选数（eventType==completion 且 payload.source==
  /// independent_drafting 的事件数；C134 批3 埋点）。
  final int independentDraftingCompletionCount;

  /// (b) 自主修改命中已学症候锚定区域候选（复用 M3 候选报告）。
  final M3CandidateReport selfOwnedAnchoredModifications;

  /// (c) M2_recall 复述「复述到位」候选数（verdict==confirmed；C133 批2 埋点）。
  final int recallConfirmedCount;

  /// (c) M2_recall 复述「需修正」留痕数（verdict==corrected；非候选，仍落库留证据）。
  final int recallCorrectedCount;

  const M5TransferReport({
    required this.independentDraftingCompletionCount,
    required this.selfOwnedAnchoredModifications,
    required this.recallConfirmedCount,
    required this.recallCorrectedCount,
  });

  /// (b) 便捷访问：自主修改命中锚定区域候选数（= M3 candidateCount）。
  int get selfOwnedAnchoredModificationCount =>
      selfOwnedAnchoredModifications.candidateCount;

  /// 空报告（无任何事件）。
  static final M5TransferReport empty = M5TransferReport(
    independentDraftingCompletionCount: 0,
    selfOwnedAnchoredModifications: M3CandidateReport(
      candidates: const [],
      selfOwnedDiffCount: 0,
      adoptedChainDiffCount: 0,
    ),
    recallConfirmedCount: 0,
    recallCorrectedCount: 0,
  );
}

/// 聚合 M5 三行为候选计数（纯函数）。
///
/// [independentDraftingCompletions] 已过滤的独立起稿成稿事件（调用方经
/// M3MilestoneEventQuerier.listIndependentDraftingCompletions 取得）；
/// [anchorAckEvents] 全部 anchor_ack 事件（含纯指认 + M2_recall，本函数内按
/// payload.kind=='M2_recall' 筛出复述事件）；
/// [selfOwnedAnchoredModifications] 复用 M3 候选聚合结果（(b)）。
M5TransferReport aggregateM5Transfer({
  required List<EditDiffEvent> independentDraftingCompletions,
  required List<EditDiffEvent> anchorAckEvents,
  required M3CandidateReport selfOwnedAnchoredModifications,
}) {
  var recallConfirmed = 0;
  var recallCorrected = 0;
  for (final e in anchorAckEvents) {
    final p = M2RecallPayload.tryDecode(e.payload);
    if (p == null) continue; // 纯指认 anchor_ack，非 M2_recall，不计入 (c)
    if (p.verdict == M2RecallVerdict.confirmed) {
      recallConfirmed++;
    } else if (p.verdict == M2RecallVerdict.corrected) {
      recallCorrected++;
    }
  }
  return M5TransferReport(
    independentDraftingCompletionCount: independentDraftingCompletions.length,
    selfOwnedAnchoredModifications: selfOwnedAnchoredModifications,
    recallConfirmedCount: recallConfirmed,
    recallCorrectedCount: recallCorrected,
  );
}
