// ─────────────────────────────────────────────────────────────
// m5_transfer_querier — M5（新题材迁移）三行为测量查询器（DB 装配层）
// （ADR-C139 教学链路补全批 · 子项①）
//
// 职责：读 DB 的现有只读方法，组合出 M5 三行为累计候选计数，再委托
// [aggregateM5Transfer] 纯函数聚合——本类不做任何候选判定（判定全在纯函数）。
//
// 与 M3 的关系：(a) 复用 M3MilestoneEventQuerier.listIndependentDraftingCompletions
// （C134 批3 埋点）；(b) 复用 queryByTimeRange() 全量 diff 的 M3 候选聚合；
// (c) 直接读 anchor_ack 事件，按 payload.kind=='M2_recall' 计数复述。
//
// M5 是「迁移」里程碑，天然跨全学习旅程累计（不按单会话/章节裁剪）——
// 它问的是「这套方法是否已迁移到新题材」，故取全量事件累计。
//
// 纪律：不改 EditDiffEventRepository / M3MilestoneEventQuerier 本身；
// 只记不判（C133 口径）——本查询器不设达标线、不展示学员、不打分。
// ─────────────────────────────────────────────────────────────

import 'package:writingcoach/data/repositories/edit_diff_event_repository.dart';
import 'package:writingcoach/services/m3_milestone_events.dart';
import 'package:writingcoach/services/m5_transfer_report.dart';

/// M5 三行为测量查询器（里程碑证据卡数据源；跨全旅程累计）。
class M5TransferQuerier {
  final EditDiffEventRepository _diffRepo;
  final M3MilestoneEventQuerier _m3;

  const M5TransferQuerier({
    required EditDiffEventRepository diffRepo,
    required M3MilestoneEventQuerier m3,
  }) : _diffRepo = diffRepo,
       _m3 = m3;

  /// M5 三行为累计测量（跨全学习旅程，不按会话/章节裁剪）——只记不判。
  Future<M5TransferReport> report() async {
    // (a) 独立起稿成稿候选（C134 批3 埋点，已按 source 过滤）。
    final independent = await _m3.listIndependentDraftingCompletions();
    // (b) 自主修改命中锚定区域候选（全量 diff 累计；queryByTimeRange 无界=全量）。
    final m3Report = await _m3.queryByTimeRange();
    // (c) M2_recall 复述事件（全量 anchor_ack；纯函数内按 kind 筛出复述）。
    final acks = await _diffRepo.listByType(EditDiffEventTypes.anchorAck);
    return aggregateM5Transfer(
      independentDraftingCompletions: independent,
      anchorAckEvents: acks,
      selfOwnedAnchoredModifications: m3Report,
    );
  }
}
