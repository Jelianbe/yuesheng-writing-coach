// pilot_metrics_summary_test — 「引文锚定」聚合读数纯函数测试
// （T-20261018-06 · D 议题 · 设计批 §六 测试计划 1~8）
//
// 覆盖（fail-closed 阶梯 + AER 现算口径 + 隐私边界「拿不到原文」）：
//   #T1 零 anchor_probe 记录 ⇒ null（不出卡）
//   #T2 合法 payload ⇒ AER 分子分母正确（手算对照）
//   #T3 坏 JSON ⇒ 跳过不崩
//   #T4 items 为空（n=0）⇒ 无 AER（空态④由卡出，不出 0%）
//   #T5 skip（未测）payload ⇒ 无 AER
//   #T6 未知 v 版本 ⇒ fail-closed 跳过
//   #T7 多事件聚合 + 空串混入 ⇒ 聚合正确、不崩
//   #T8 隐私边界：payload 含引文原文片段，装配结果结构上不含它

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/pilot_metrics_summary.dart';

/// 一条合法 anchor_probe payload（协议 = anchor_probe.dart toPayload()）。
/// [items] = (状态码, 原文片段) 列表；原文片段用哨兵串（隐私边界断言用）。
String _payload({int version = 1, required List<(String, String)> items}) {
  final encoded = items
      .map(
        (e) =>
            '{"s":"syn_1","k":"${e.$1}","o":1,"l":${e.$2.length},"h":"${e.$2}"}',
      )
      .join(',');
  return '{"v":$version,"src":100,"syn":1,"emp":0,"n":${items.length},'
      '"items":[$encoded]}';
}

void main() {
  group('T-20261018-06「引文锚定」聚合读数（纯函数）', () {
    test('#T1 零 anchor_probe 记录 ⇒ null（调用方据此不挂载，不出死卡）', () {
      expect(buildPilotMetricsSummary(const [], version: 1), isNull);
    });

    test('#T2 合法 payload ⇒ AER 分子分母正确（2/4 = 50%，手算对照）', () {
      // anchored = ok_exact + ambiguous（kAnchoredStatusCodes 同口径）
      // 非 anchored = fail + too_short（进分母不进分子）
      final payloads = [
        _payload(
          items: [
            ('ok_exact', '__SENTINEL_RAW__'),
            ('ambiguous', '另一段引文'),
            ('fail', '第三段'),
            ('too_short', '短'),
          ],
        ),
      ];
      final summary = buildPilotMetricsSummary(payloads, version: 1);
      expect(summary, isNotNull);
      expect(summary!.aerPercent, 50);
      expect(summary.evidenceCount, 4);
    });

    test('#T3 坏 JSON ⇒ 跳过不崩（该条不计入，其余照算）', () {
      final payloads = [
        '{"v":1,"items":[坏JSON',
        _payload(items: [('ok_exact', '引文一'), ('fail', '引文二')]),
      ];
      final summary = buildPilotMetricsSummary(payloads, version: 1);
      expect(summary, isNotNull);
      expect(summary!.evidenceCount, 2);
      expect(summary.aerPercent, 50); // 1/2
    });

    test('#T4 items 为空（测了但 0 条引文）⇒ 无 AER、空态④不出 0%', () {
      final payloads = [_payload(items: const [])];
      final summary = buildPilotMetricsSummary(payloads, version: 1);
      expect(summary, isNotNull);
      expect(summary!.aerPercent, isNull);
      expect(summary.evidenceCount, 0);
    });

    test('#T5 skip（未测）payload ⇒ 无 AER（aer:null ≠ aer:0 纪律）', () {
      // 未测 = 无 items 键，只有 skip 字段（toPayload 同构）
      const payloads = ['{"v":1,"src":0,"syn":0,"emp":0,"skip":"读不到原文"}'];
      final summary = buildPilotMetricsSummary(payloads, version: 1);
      expect(summary, isNotNull);
      expect(summary!.aerPercent, isNull);
    });

    test('#T6 未知 v 版本 ⇒ fail-closed 跳过（不猜未来结构）', () {
      final payloads = [
        _payload(version: 99, items: [('ok_exact', '未来版本的引文')]),
      ];
      final summary = buildPilotMetricsSummary(payloads, version: 1);
      expect(summary, isNotNull);
      expect(summary!.aerPercent, isNull); // 整条被跳过 ⇒ 零引文
      expect(summary.evidenceCount, 0);
    });

    test('#T7 多事件聚合 + 空串混入 ⇒ 聚合正确、不崩', () {
      final payloads = [
        '', // app_opened 的 payload 形态（空串）混入：jsonDecode 抛 ⇒ 跳过
        _payload(items: [('ok_exact', '甲'), ('fail', '乙')]),
        _payload(items: [('ok_ws', '丙'), ('ok_width', '丁'), ('fail', '戊')]),
      ];
      final summary = buildPilotMetricsSummary(payloads, version: 1);
      expect(summary, isNotNull);
      expect(summary!.evidenceCount, 5);
      expect(summary.aerPercent, 60); // 3/5
    });

    test('#T8 隐私边界：payload 含引文原文，装配结果结构上不含它', () {
      const sentinel = '__SENTINEL_RAW__';
      final payloads = [
        _payload(items: [('ok_exact', sentinel), ('fail', sentinel)]),
      ];
      final summary = buildPilotMetricsSummary(payloads, version: 1);
      expect(summary, isNotNull);
      // 聚合结果只有两个数字 ⇒ 原文哨兵串在 toString 里也不可能出现
      expect(summary.toString(), isNot(contains(sentinel)));
      expect(summary!.evidenceCount, 2);
    });
  });
}
