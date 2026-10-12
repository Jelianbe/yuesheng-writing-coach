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
}
