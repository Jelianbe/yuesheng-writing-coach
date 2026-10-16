// ─────────────────────────────────────────────────────────────
// diagnosis_signal_monitor_test — V3 诊断信号埋点（ADR-0005 · 2026-10-12）
//
// 口径真源：`.ai/reports/2026-10-05-诊断架构外部评审.md` §4.3 V3
//   判读 = 质疑数 / 出块条数，按症候 ID 分组。
//   任何 ID 质疑率进 top-3 ⇒ 触发该 ID 判据复审。
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/diagnosis_signal_monitor.dart';

void main() {
  setUp(() => kSharedDiagnosisSignalMonitor.reset());

  test('#1 出块事件累计轮数/条数 + 按 ID 分布（同 ID 重复计条数）', () {
    kSharedDiagnosisSignalMonitor.recordBlockEmitted(
      itemCount: 2,
      syndromeIds: ['P005', 'P009'],
    );
    kSharedDiagnosisSignalMonitor.recordBlockEmitted(
      itemCount: 1,
      syndromeIds: ['P005'],
    );
    final t = kSharedDiagnosisSignalMonitor.totals;
    expect(t.blocksEmitted, 2);
    expect(t.blockItems, 3);
    expect(t.emittedBySyndrome['P005'], 2);
    expect(t.emittedBySyndrome['P009'], 1);
    expect(t.emittedBySyndrome['P999'], isNull);
  });

  test('#2 确认/质疑事件按 ID 累计', () {
    kSharedDiagnosisSignalMonitor.recordSyndromeConfirmed('P005');
    kSharedDiagnosisSignalMonitor.recordSyndromeDisputed('P005');
    kSharedDiagnosisSignalMonitor.recordSyndromeDisputed('P009');
    final t = kSharedDiagnosisSignalMonitor.totals;
    expect(t.confirmed, 1);
    expect(t.disputed, 2);
    expect(t.confirmedBySyndrome['P005'], 1);
    expect(t.disputedBySyndrome['P005'], 1);
    expect(t.disputedBySyndrome['P009'], 1);
  });

  test('#3 质疑率口径 = 质疑数 / 出块条数（按 ID；零分母不除零）', () {
    kSharedDiagnosisSignalMonitor.recordBlockEmitted(
      itemCount: 4,
      syndromeIds: ['P005', 'P005', 'P005', 'P005'],
    );
    kSharedDiagnosisSignalMonitor.recordSyndromeDisputed('P005');
    final t = kSharedDiagnosisSignalMonitor.totals;
    expect(t.disputeRate('P005'), closeTo(0.25, 1e-9));
    // 未出块的 ID 不除零（未出块无所谓质疑率，不得产出 Infinity/NaN）
    expect(t.disputeRate('P999'), 0.0);
  });

  test('#4 reset 清零（测试隔离前提）', () {
    kSharedDiagnosisSignalMonitor.recordBlockEmitted(
      itemCount: 1,
      syndromeIds: ['P005'],
    );
    kSharedDiagnosisSignalMonitor.recordSyndromeDisputed('P005');
    kSharedDiagnosisSignalMonitor.reset();
    final t = kSharedDiagnosisSignalMonitor.totals;
    expect(t.blocksEmitted, 0);
    expect(t.blockItems, 0);
    expect(t.disputed, 0);
    expect(t.emittedBySyndrome, isEmpty);
    expect(t.disputedBySyndrome, isEmpty);
  });

  test('#5 totals 快照不可变（外部改写不得回流累计器）', () {
    kSharedDiagnosisSignalMonitor.recordBlockEmitted(
      itemCount: 1,
      syndromeIds: ['P005'],
    );
    final t = kSharedDiagnosisSignalMonitor.totals;
    expect(() => t.emittedBySyndrome['P005'] = 99, throwsUnsupportedError);
    // 原累计器不受快照侧失败操作影响
    expect(kSharedDiagnosisSignalMonitor.totals.emittedBySyndrome['P005'], 1);
  });

  // ── W-22 G2 档 A：disputeRateTopK（V3 判读口径的读尺出口）──────────
  // 设计批验收 V5：回流探针读数正确。零持久化（ADR-0005 边界不变）。

  test('#6 W22 topK 按质疑率降序（同率使出块多者优先）', () {
    // P005：3 出块 2 质疑 = 0.667；P009：3 出块 1 质疑 = 0.333；
    // P011：3 出块 2 质疑 = 0.667（与 P005 同率，出块数也同 3 ⇒ 并列任序，
    // 但必须都排在 P009 前）。
    for (final id in ['P005', 'P009', 'P011']) {
      kSharedDiagnosisSignalMonitor.recordBlockEmitted(
        itemCount: 3,
        syndromeIds: [id, id, id],
      );
    }
    kSharedDiagnosisSignalMonitor.recordSyndromeDisputed('P005');
    kSharedDiagnosisSignalMonitor.recordSyndromeDisputed('P005');
    kSharedDiagnosisSignalMonitor.recordSyndromeDisputed('P011');
    kSharedDiagnosisSignalMonitor.recordSyndromeDisputed('P011');
    kSharedDiagnosisSignalMonitor.recordSyndromeDisputed('P009');

    final top = kSharedDiagnosisSignalMonitor.totals.disputeRateTopK(3);
    expect(top.length, 3);
    expect(top[2].syndromeId, 'P009', reason: '质疑率最低者垫底');
    expect(top[2].rate, closeTo(1 / 3, 1e-9));
    expect({top[0].syndromeId, top[1].syndromeId}, {'P005', 'P011'});
    expect(top[0].rate, closeTo(2 / 3, 1e-9));
  });

  test('#7 W22 minEmitted 过滤薄样本（1/1 的 100% 不得盖过 2/3）', () {
    kSharedDiagnosisSignalMonitor.recordBlockEmitted(
      itemCount: 3,
      syndromeIds: ['P005', 'P005', 'P005'],
    );
    kSharedDiagnosisSignalMonitor.recordSyndromeDisputed('P005');
    kSharedDiagnosisSignalMonitor.recordSyndromeDisputed('P005');
    kSharedDiagnosisSignalMonitor.recordBlockEmitted(
      itemCount: 1,
      syndromeIds: ['P009'],
    );
    kSharedDiagnosisSignalMonitor.recordSyndromeDisputed('P009');

    final t = kSharedDiagnosisSignalMonitor.totals;
    // 无过滤：P009 的 1/1 = 100% 排第一（薄样本噪声原样呈现）
    expect(t.disputeRateTopK(2)[0].syndromeId, 'P009');
    // minEmitted=2：薄样本出局，P005 的 2/3 升第一
    final filtered = t.disputeRateTopK(2, minEmitted: 2);
    expect(filtered.length, 1);
    expect(filtered[0].syndromeId, 'P005');
    expect(filtered[0].rate, closeTo(2 / 3, 1e-9));
    expect(filtered[0].emitted, 3);
    expect(filtered[0].disputed, 2);
  });

  test('#8 W22 k<=0 返回空；空排行 format 返回空串（调用方据此不打日志）', () {
    final t = kSharedDiagnosisSignalMonitor.totals;
    expect(t.disputeRateTopK(0), isEmpty);
    expect(t.disputeRateTopK(-1), isEmpty);
    expect(t.formatDisputeRateTopK(3), isEmpty);
    kSharedDiagnosisSignalMonitor.recordBlockEmitted(
      itemCount: 1,
      syndromeIds: ['P005'],
    );
    final line = kSharedDiagnosisSignalMonitor.totals.formatDisputeRateTopK(3);
    expect(line, contains('P005'));
    expect(line, contains('top-3'));
  });

  test('#9 W22 零质疑 ID 也进排行（率 0，排名垫底）——尺子要能量全貌', () {
    kSharedDiagnosisSignalMonitor.recordBlockEmitted(
      itemCount: 2,
      syndromeIds: ['P005', 'P009'],
    );
    kSharedDiagnosisSignalMonitor.recordSyndromeConfirmed('P009');
    final top = kSharedDiagnosisSignalMonitor.totals.disputeRateTopK(3);
    expect(top.length, 2);
    for (final r in top) {
      expect(r.rate, 0.0, reason: '无质疑 ⇒ 率 0（不是缺席）');
    }
  });
}
