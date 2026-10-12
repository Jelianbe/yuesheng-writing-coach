// ─────────────────────────────────────────────────────────────
// diagnosis_signal_monitor — 诊断假报/漏报信号埋点（V3 · ADR-0005）
//
// 口径真源：`.ai/reports/2026-10-05-诊断架构外部评审.md` §4.3 V3
// （2026-10-12 舰长批准实施，范围 = 只做静默事件记录）。
//
// 三个事件：
//   1. `diagnosis_block_emitted`     本轮出 [YS_DIAGNOSIS] 块（条数 + 症候 ID）
//   2. `syndrome_confirmed_by_user`  学员点「确认 / 认同」
//   3. `syndrome_disputed_by_user`   学员点「质疑 / 不认同」
//      —— **假报的唯一直接信号**
//
// 判读口径：**质疑数 / 出块条数，按症候 ID 分组**。任何 ID 的质疑率进入
// top-3，即为该 ID 判据需复审的触发条件（阈值由 V1 跑完后校准，不先拍）。
//
// ★ R-027 边界（评审报告明文 + 舰长 2026-10-12 批准）：
//   **只做静默事件记录** —— 进程内累计 + kDebugMode 日志；
//   **不持久化、无 UI、不弹窗、不主动探测学员写作过程**。
//   持久化属另一议题（涉 PHI / 隐私），须单独裁定，不得顺手加。
//
// 形态：仿 `llm_usage_monitor.dart`（kSharedLlmUsageMonitor）——
// 全局单例 + record **永不抛出**（观测是旁路，失败不得阻断主流程）。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/foundation.dart'
    show debugPrint, kDebugMode, visibleForTesting;

/// 累计读数快照（不可变）
class DiagnosisSignalTotals {
  /// 出块轮数（分母之一：轮次维度）
  final int blocksEmitted;

  /// 出块症候条数合计（判读口径的分母：条数维度）
  final int blockItems;

  /// 学员确认条数合计
  final int confirmed;

  /// 学员质疑条数合计
  final int disputed;

  /// 按症候 ID 的出块条数分布（判读口径分母）
  final Map<String, int> emittedBySyndrome;

  /// 按症候 ID 的确认条数分布
  final Map<String, int> confirmedBySyndrome;

  /// 按症候 ID 的质疑条数分布（分子）
  final Map<String, int> disputedBySyndrome;

  const DiagnosisSignalTotals({
    required this.blocksEmitted,
    required this.blockItems,
    required this.confirmed,
    required this.disputed,
    required this.emittedBySyndrome,
    required this.confirmedBySyndrome,
    required this.disputedBySyndrome,
  });

  /// 按症候 ID 的质疑率 = 质疑数 / 出块条数（V3 判读口径）。
  /// 该 ID 零出块 ⇒ 0.0（不除零；未出块无所谓质疑率）。
  double disputeRate(String syndromeId) {
    final emitted = emittedBySyndrome[syndromeId] ?? 0;
    if (emitted <= 0) return 0.0;
    return (disputedBySyndrome[syndromeId] ?? 0) / emitted;
  }

  @override
  String toString() =>
      'blocks: $blocksEmitted, items: $blockItems, '
      'confirmed: $confirmed, disputed: $disputed';
}

/// 进程内累计器。不持久化 —— 重启即清零（定位是「尺子」不是「报表」）。
class DiagnosisSignalMonitor {
  int _blocksEmitted = 0;
  int _blockItems = 0;
  int _confirmed = 0;
  int _disputed = 0;
  final Map<String, int> _emittedBySyndrome = {};
  final Map<String, int> _confirmedBySyndrome = {};
  final Map<String, int> _disputedBySyndrome = {};

  /// 事件 1：本轮出 [YS_DIAGNOSIS] 块。
  ///
  /// [itemCount] = 本条数（症候条数，非轮数）；[syndromeIds] = 各条症候 ID
  /// （可重复 —— 同一条症候在一轮里报两次就记两次，与「条数」口径一致）。
  ///
  /// **永不抛出** —— 观测失败不得影响诊断主链路。
  void recordBlockEmitted({
    required int itemCount,
    required List<String> syndromeIds,
  }) {
    try {
      _blocksEmitted++;
      _blockItems += itemCount;
      for (final id in syndromeIds) {
        _emittedBySyndrome[id] = (_emittedBySyndrome[id] ?? 0) + 1;
      }
      if (kDebugMode) {
        debugPrint(
          '[V3 诊断信号] 出块 itemCount=$itemCount '
          'ids=${syndromeIds.join(',')}（仅观测）',
        );
      }
    } catch (_) {
      // 观测是旁路：任何异常都不得冒泡
    }
  }

  /// 事件 2：学员确认/认同某条症候。**永不抛出**。
  void recordSyndromeConfirmed(String syndromeId) {
    try {
      _confirmed++;
      _confirmedBySyndrome[syndromeId] =
          (_confirmedBySyndrome[syndromeId] ?? 0) + 1;
      if (kDebugMode) {
        debugPrint('[V3 诊断信号] 学员确认 $syndromeId（仅观测）');
      }
    } catch (_) {
      // 同上
    }
  }

  /// 事件 3：学员质疑/不认同某条症候（**假报的唯一直接信号**）。
  /// **永不抛出**。
  void recordSyndromeDisputed(String syndromeId) {
    try {
      _disputed++;
      _disputedBySyndrome[syndromeId] =
          (_disputedBySyndrome[syndromeId] ?? 0) + 1;
      if (kDebugMode) {
        debugPrint('[V3 诊断信号] 学员质疑 $syndromeId（仅观测）');
      }
    } catch (_) {
      // 同上
    }
  }

  /// 当前累计读数
  DiagnosisSignalTotals get totals => DiagnosisSignalTotals(
    blocksEmitted: _blocksEmitted,
    blockItems: _blockItems,
    confirmed: _confirmed,
    disputed: _disputed,
    emittedBySyndrome: Map.unmodifiable(_emittedBySyndrome),
    confirmedBySyndrome: Map.unmodifiable(_confirmedBySyndrome),
    disputedBySyndrome: Map.unmodifiable(_disputedBySyndrome),
  );

  /// 清零（测试隔离 / 会话边界用）
  @visibleForTesting
  void reset() {
    _blocksEmitted = 0;
    _blockItems = 0;
    _confirmed = 0;
    _disputed = 0;
    _emittedBySyndrome.clear();
    _confirmedBySyndrome.clear();
    _disputedBySyndrome.clear();
  }
}

/// 应用级共享累计器（生产默认上报目标，零组装改动即生效）
final DiagnosisSignalMonitor kSharedDiagnosisSignalMonitor =
    DiagnosisSignalMonitor();
