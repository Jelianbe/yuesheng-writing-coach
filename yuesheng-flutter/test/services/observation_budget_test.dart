// ─────────────────────────────────────────────────────────────
// observation_budget_test — S2（R3/R4）观察段两级预算纯函数
//
// 覆盖：
//   1. 未超限：kept == 输入（逐条相等）、dropped == 0（零行为变更面）
//   2. 条数上限：> N 砍尾到 N，保序、不重排（Q3 甲）
//   3. 字符预算：逐行累计超限即停；恰好等于预算不裁（判据是 >）
//   4. 叠加态（R4-AC3）：先条数、后字符，dropped 为两级合计
//   5. 防御：单行超预算 → kept 空（构建器侧降级为 null）
//   6. truncationNotice：提示计数与丢弃数一致（R3-AC2）
//   7. 留痕（R7-AC1/AC2）：触发 → 恰一条含段名+丢弃数；未触发 → 零日志
// ─────────────────────────────────────────────────────────────

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/config/shared_constants.dart';
import 'package:writingcoach/services/observation_budget.dart';

/// 构造 n 条长度为 len 的行（内容含序号，便于断言保序砍尾）
List<String> lines(int n, int len) => List.generate(
  n,
  (i) => '${(i + 1).toString().padLeft(2, '0')}${'字' * (len - 2)}',
);

void main() {
  late DebugPrintCallback originalDebugPrint;
  final logs = <String>[];

  setUp(() {
    originalDebugPrint = debugPrint;
    logs.clear();
    debugPrint = (String? message, {int? wrapWidth}) {
      logs.add(message ?? '');
    };
  });

  tearDown(() {
    debugPrint = originalDebugPrint;
  });

  group('未超限（零行为变更面，R3-AC3）', () {
    test('条数与字符均在预算内 → kept 逐条相等、dropped == 0', () {
      final input = lines(5, 100);
      final r = ObservationBudget.apply(input, section: '测试段');
      expect(r.kept, input, reason: '未超限必须原样保留（逐条相等）');
      expect(r.dropped, 0);
    });

    test('恰好 12 条（== 上限）→ 全保留', () {
      final input = lines(ContextBudget.observationMaxItems, 60);
      final r = ObservationBudget.apply(input, section: '测试段');
      expect(r.kept, input);
      expect(r.dropped, 0);
    });

    test('累计字符恰好等于预算（used == budget）→ 不裁（判据是 >）', () {
      final input = lines(9, 100); // 9 × 100 = 900 == 预算
      final r = ObservationBudget.apply(input, section: '测试段');
      expect(r.kept, input);
      expect(r.dropped, 0);
    });
  });

  group('条数上限（R3，Q3 甲砍尾不重排）', () {
    test('15 条 → 砍尾到 12 条，kept == 输入前 12 条（保序）', () {
      final input = lines(15, 60);
      final r = ObservationBudget.apply(input, section: '测试段');
      expect(r.kept, input.sublist(0, ContextBudget.observationMaxItems));
      expect(r.dropped, input.length - ContextBudget.observationMaxItems);
      // 砍尾语义：被丢弃的是尾部，首条必在
      expect(r.kept.first, input.first);
      expect(r.kept.last, input[ContextBudget.observationMaxItems - 1]);
    });
  });

  group('字符预算（R4，X-043「只计可变行」口径）', () {
    test('10 条 × 100 chars（合计 1000 > 900）→ 前 9 条保留、第 10 条起丢弃', () {
      final input = lines(10, 100);
      final r = ObservationBudget.apply(input, section: '测试段');
      expect(r.kept, input.sublist(0, 9));
      expect(r.dropped, 1);
    });

    test('防御：单行即超预算 → kept 为空、dropped == 1（构建器侧降级 null）', () {
      final input = ['长' * 1000];
      final r = ObservationBudget.apply(input, section: '测试段');
      expect(r.kept, isEmpty);
      expect(r.dropped, 1);
    });
  });

  group('叠加态（R4-AC3：先条数后字符，确定性）', () {
    test('25 条 × 120 chars → 条数砍 13、字符再砍 5，dropped 合计 18', () {
      final input = lines(25, 120);
      final r = ObservationBudget.apply(input, section: '测试段');
      // ① 条数：25 → 12（dropped 13）；② 字符：12×120=1440 > 900，
      // 7×120=840 ≤ 900，第 8 条 960 > 900 → 再丢 5 条
      final expectedKeptByChars =
          ContextBudget.observationSectionBudgetChars ~/ 120; // 7
      expect(r.kept, input.sublist(0, expectedKeptByChars));
      expect(
        r.dropped,
        input.length -
            ContextBudget.observationMaxItems +
            (ContextBudget.observationMaxItems - expectedKeptByChars),
      );
      expect(r.dropped, 18);
    });

    test('同输入两次运行字节级一致（R3-AC5 稳定性）', () {
      final input = lines(25, 120);
      final a = ObservationBudget.apply(input, section: '测试段');
      final b = ObservationBudget.apply(input, section: '测试段');
      expect(a.kept.join('\n'), b.kept.join('\n'));
      expect(a.dropped, b.dropped);
    });
  });

  group('truncationNotice（R3-AC2 提示计数一致）', () {
    test('文案含丢弃数与两个常量值', () {
      final notice = ObservationBudget.truncationNotice(8);
      expect(notice, startsWith('### 观察截断提示\n'));
      expect(notice, contains('另有 8 条观察未列出'));
      expect(
        notice,
        contains('预算 ${ContextBudget.observationSectionBudgetChars} chars'),
      );
      expect(notice, contains('条数上限 ${ContextBudget.observationMaxItems} 条'));
      expect(notice, contains('不要把已列出的部分当作全部线索'));
    });
  });

  group('留痕（R7-AC1/AC2）', () {
    test('触发裁剪 → 恰一条日志，含段名与丢弃数', () {
      ObservationBudget.apply(lines(15, 60), section: '时序矛盾观察');
      expect(logs, hasLength(1));
      expect(logs.single, contains('[ObservationBudget]'));
      expect(logs.single, contains('时序矛盾观察'));
      expect(logs.single, contains('截断 3 条'));
    });

    test('未触发 → 零日志（不刷屏）', () {
      ObservationBudget.apply(lines(5, 60), section: '测试段');
      expect(logs, isEmpty);
    });
  });
}
