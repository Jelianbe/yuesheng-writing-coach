// P0-a 锚定探针（接线层）的验收测试
//
// 对应规格：`.ai/reports/2026-10-20-语文知识体系研究/05-P0规格-断言粒度与锚定.md` §2.6
//
// ⚠️ 本文件只证明「探针把三态分对了」，**不产生能力读数**。
//    `fail` 的比例高不高、是不是模型在编，要靠 06-P002标注语料 与真实诊断日志。

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/p0_verify/anchor.dart';
import 'package:writingcoach/services/p0_verify/anchor_probe.dart';

/// 一段干净的原文（与测试用例里的引文逐字一致）。
const String _src = '他握紧了青玉牌，指节发白。窗外的雪落了一夜，没有人说话。';

void main() {
  group('未测 ≠ 0 命中', () {
    test('原文为 null ⇒ skipped，不给比率', () {
      final r = probeAnchors(
        sourceText: null,
        evidenceBySyndrome: {
          'P001': ['他握紧了青玉牌，指节发白'],
        },
      );
      expect(r.measured, isFalse);
      expect(r.skippedReason, kAnchorSkipNoSource);
      expect(r.aer, isNull);
      expect(r.evidenceCount, 0);
      // 关键：症候条数仍要报出来，否则「跳过一次 3 条病的诊断」看起来像 0 条病。
      expect(r.syndromeCount, 1);
    });

    test('原文为空串 ⇒ 与 null 同待遇（不许判成「0 命中」）', () {
      final r = probeAnchors(sourceText: '', evidenceBySyndrome: const {});
      expect(r.measured, isFalse);
      expect(r.skippedReason, kAnchorSkipNoSource);
    });

    test('未测的 summary 不含任何比率数字', () {
      final r = probeAnchors(sourceText: null, evidenceBySyndrome: const {});
      final s = r.summary;
      expect(s.contains('skipped(no_source_text)'), isTrue);
      // 打印 0.000 会让「没测」被读成「全错」。
      expect(s.contains('0.000'), isFalse);
      expect(s.contains('n/a'), isFalse);
    });

    test('已测但一条 evidence 都没有 ⇒ measured 且 AER 为 null', () {
      final r = probeAnchors(
        sourceText: _src,
        evidenceBySyndrome: {'P001': const []},
      );
      expect(r.measured, isTrue);
      expect(r.evidenceCount, 0);
      expect(r.syndromeCount, 1);
      // 分母为 0 ⇒ aer 为 null（不是 0，也不是 1）。
      expect(r.aer, isNull);
      expect(r.summary.contains('anchor total=0'), isTrue);
    });
  });

  group('锚定结果透传', () {
    test('一真一编 ⇒ ok=1 fail=1，AER=0.5', () {
      final r = probeAnchors(
        sourceText: _src,
        evidenceBySyndrome: {
          'P001': ['他握紧了青玉牌，指节发白', '他曾把青玉牌摔在地上，碎了'],
        },
      );
      expect(r.evidenceCount, 2);
      expect(r.aggregate.okCount, 1);
      expect(r.aggregate.failCount, 1);
      expect(r.aer, 0.5);
    });

    test('bySyndrome 按症候归档，不参与汇总', () {
      final r = probeAnchors(
        sourceText: _src,
        evidenceBySyndrome: {
          'P001': ['他握紧了青玉牌，指节发白'],
          'P002': ['窗外的雪落了一夜'],
        },
      );
      expect(r.bySyndrome.keys.toSet(), {'P001', 'P002'});
      expect(r.bySyndrome['P001']!.single.status, AnchorStatus.okExact);
      expect(r.bySyndrome['P002']!.single.status, AnchorStatus.okExact);
      // 汇总等于两条都算
      expect(r.evidenceCount, 2);
      expect(r.aer, 1.0);
    });

    test('同一条引文在同症候内出现两次 ⇒ 计两次（不去重）', () {
      final r = probeAnchors(
        sourceText: _src,
        evidenceBySyndrome: {
          'P001': ['他握紧了青玉牌，指节发白', '他握紧了青玉牌，指节发白'],
        },
      );
      expect(r.evidenceCount, 2);
      expect(r.aer, 1.0);
    });
  });

  group('空白 evidence 单列', () {
    test('空白串计数但不进分母', () {
      final r = probeAnchors(
        sourceText: _src,
        evidenceBySyndrome: {
          'P001': ['', '   ', '他握紧了青玉牌，指节发白'],
        },
      );
      expect(r.emptyEvidenceCount, 2);
      // 分母只有 1 条真引文
      expect(r.evidenceCount, 1);
      expect(r.aer, 1.0);
    });

    test('整条症的 evidence 全是空白 ⇒ 不进 bySyndrome，但仍计症候数', () {
      final r = probeAnchors(
        sourceText: _src,
        evidenceBySyndrome: {
          'P002': ['', ''],
        },
      );
      expect(r.syndromeCount, 1);
      expect(r.bySyndrome.containsKey('P002'), isFalse);
      expect(r.evidenceCount, 0);
      expect(r.emptyEvidenceCount, 2);
    });

    test('空白不伪装成 too_short（否则整份 AER 会被误判为未测）', () {
      // 6 条空白 + 1 条真引文：若空白算 too_short，tooShortRate=6/7>0.15 ⇒ AER=null。
      final r = probeAnchors(
        sourceText: _src,
        evidenceBySyndrome: {
          'P001': ['', '', '', '', '', '', '他握紧了青玉牌，指节发白'],
        },
      );
      expect(r.aggregate.tooShortCount, 0);
      expect(r.aer, 1.0);
    });
  });

  group('太短率超限 ⇒ AER 未测', () {
    test('3 短 + 1 真 ⇒ shortRate=0.750、AER=null', () {
      final r = probeAnchors(
        sourceText: _src,
        evidenceBySyndrome: {
          'P001': ['他', '他握', '他握着', '他握紧了青玉牌，指节发白'],
        },
      );
      expect(r.aggregate.tooShortCount, 3);
      expect(r.aggregate.tooShortRate, 0.75);
      expect(r.aer, isNull);
      // 但 shortRate 必须打出来 —— 未测的是 AER，不是太短率。
      expect(r.summary.contains('shortRate=0.750'), isTrue);
      expect(r.summary.contains('aer=n/a'), isTrue);
    });

    test('1 短 + 9 真 ⇒ shortRate=0.100 未超限，AER=0.9', () {
      final items = <String>['他'];
      for (var i = 0; i < 9; i++) {
        items.add('他握紧了青玉牌，指节发白');
      }
      final r = probeAnchors(
        sourceText: _src,
        evidenceBySyndrome: {'P001': items},
      );
      expect(r.aggregate.tooShortRate, closeTo(0.1, 1e-9));
      expect(r.aer, closeTo(0.9, 1e-9));
    });
  });

  group('ambiguous 归入锚定成功，但不进 ELA', () {
    test('同一句出现 4 次 ⇒ ambiguous（阈值 3）', () {
      // 引文须长于 tooShortChars=6，否则会先被判 too_short（判据顺序问题）。
      const seg = '窗外的雪落了一夜，没有人说话。';
      final r = probeAnchors(
        sourceText: '$seg$seg$seg$seg',
        evidenceBySyndrome: {
          'P001': [seg],
        },
      );
      final one = r.bySyndrome['P001']!.single;
      expect(one.status, AnchorStatus.ambiguous);
      expect(one.occurrences, 4);
      expect(r.aggregate.okCount, 0);
      expect(r.aggregate.ambiguousCount, 1);
      // ambiguous 计进 AER 分子（§2.4），但不进 ELA 可用集。
      expect(r.aer, 1.0);
      expect(r.aggregate.elaEligible, isEmpty);
    });

    test('出现 3 次仍判 ok（阈值是「超过」，不是「达到」）', () {
      const seg = '窗外的雪落了一夜，没有人说话。';
      final r = probeAnchors(
        sourceText: '$seg$seg$seg',
        evidenceBySyndrome: {
          'P001': [seg],
        },
      );
      expect(r.bySyndrome['P001']!.single.status, AnchorStatus.okExact);
      expect(r.aggregate.ambiguousCount, 0);
    });
  });

  group('环形缓冲', () {
    setUp(() => AnchorProbeLog.instance.clear());

    test('record 后 latest 可取回同一份报告', () {
      final r = probeAnchors(sourceText: _src, evidenceBySyndrome: const {});
      AnchorProbeLog.instance.record('S1', r);
      expect(AnchorProbeLog.instance.recent.length, 1);
      expect(AnchorProbeLog.instance.latest, same(r));
      expect(AnchorProbeLog.instance.recent.single.sessionId, 'S1');
    });

    test('超过容量挤掉最早的（不报错、不无限增长）', () {
      final r = probeAnchors(sourceText: _src, evidenceBySyndrome: const {});
      for (var i = 0; i < AnchorProbeLog.capacity + 1; i++) {
        AnchorProbeLog.instance.record('S$i', r);
      }
      final recent = AnchorProbeLog.instance.recent;
      expect(recent.length, AnchorProbeLog.capacity);
      // 最早那条 S0 已被挤出
      expect(recent.first.sessionId, 'S1');
      expect(recent.last.sessionId, 'S${AnchorProbeLog.capacity}');
    });

    test('recent 是只读视图（外部改不动内部队列）', () {
      final r = probeAnchors(sourceText: _src, evidenceBySyndrome: const {});
      AnchorProbeLog.instance.record('S1', r);
      expect(
        () => AnchorProbeLog.instance.recent.add(
          AnchorProbeRecord(sessionId: 'X', report: r, atSec: 0),
        ),
        throwsUnsupportedError,
      );
    });

    test('空队列 latest 为 null（不是抛异常）', () {
      expect(AnchorProbeLog.instance.latest, isNull);
    });
  });
}
