import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/p0_verify/arm_parity.dart';

void main() {
  group('judgeArmParity · 可比', () {
    test('#I-1 两臂都未降级 ⇒ 可比', () {
      final r = judgeArmParity(
        pair: 'A2,A3',
        x: const ArmRun(armId: 'A2', sampleId: 's1'),
        y: const ArmRun(armId: 'A3', sampleId: 's1'),
      );
      expect(r.isComparable, isTrue);
      expect(r.verdict, ArmParityVerdict.comparable);
      expect(r.degradedArms, isEmpty);
    });

    test('#I-2 降级级名顺序不同但集合相同 ⇒ 仍可比（逐级降级序是确定的，但纯函数不该依赖入参顺序）', () {
      final r = judgeArmParity(
        pair: 'A2,A3',
        x: const ArmRun(
          armId: 'A2',
          sampleId: 's1',
          droppedStages: ['merge_chunk_notes_top3'],
        ),
        y: const ArmRun(
          armId: 'A3',
          sampleId: 's1',
          droppedStages: ['merge_chunk_notes_top3'],
        ),
      );
      // 齐降 ⇒ 不可比（见#I-5）。此处只验 verdict 与 reason 指向同一原因。
      expect(r.verdict, ArmParityVerdict.incomparableBudgetDegraded);
      expect(r.reason, contains('齐降'));
    });
  });

  group('judgeArmParity · 剔除', () {
    test('#I-3 只有一臂降级 ⇒ 剔除并指名是哪一臂', () {
      final r = judgeArmParity(
        pair: 'A2,A3',
        x: const ArmRun(armId: 'A2', sampleId: 's1'),
        y: const ArmRun(
          armId: 'A3',
          sampleId: 's1',
          droppedStages: ['merge_structure_profile'],
        ),
      );
      expect(r.isComparable, isFalse);
      expect(r.verdict, ArmParityVerdict.incomparableBudgetDegraded);
      // ★ 剔除必须能回答「剔的是哪一臂」—— 否则报告只能写「剔了 N 个」。
      expect(r.degradedArms, ['A3:merge_structure_profile']);
      expect(r.reason, contains('不等'));
    });

    test('#I-4 两臂降级级名不同 ⇒ 剔除（哪怕降级次数相同）', () {
      final r = judgeArmParity(
        pair: 'A2,A3',
        x: const ArmRun(
          armId: 'A2',
          sampleId: 's1',
          droppedStages: ['merge_structure_profile'],
        ),
        y: const ArmRun(
          armId: 'A3',
          sampleId: 's1',
          droppedStages: ['merge_inactive_context'],
        ),
      );
      expect(r.isComparable, isFalse);
      expect(r.degradedArms, hasLength(2));
    });

    test('#I-5 ★ 两臂齐降 ⇒ 仍不可比（本闸最易漏的一格）', () {
      // 判据若写成「须相等」而不写「须相等**且都为空**」，
      // 两臂齐降会静默通过 —— 而「相等」在这里恰恰是坏消息：
      // 两臂输入同样被削，对比依然不成立。
      final r = judgeArmParity(
        pair: 'A2,A3',
        x: const ArmRun(
          armId: 'A2',
          sampleId: 's1',
          droppedStages: ['merge_structure_profile'],
        ),
        y: const ArmRun(
          armId: 'A3',
          sampleId: 's1',
          droppedStages: ['merge_structure_profile'],
        ),
      );
      expect(r.isComparable, isFalse);
      expect(r.verdict, ArmParityVerdict.incomparableBudgetDegraded);
      expect(r.degradedArms, ['A2', 'A3']);
      expect(r.reason, contains('齐降'));
    });

    test('#I-6 任一侧拒发 ⇒ 不可比·拒发（优先级高于降级）', () {
      final r = judgeArmParity(
        pair: 'A2,A3',
        x: const ArmRun(armId: 'A2', sampleId: 's1'),
        y: const ArmRun(
          armId: 'A3',
          sampleId: 's1',
          droppedStages: ['merge_structure_profile'],
          rejectedOverBudget: true,
        ),
      );
      expect(r.verdict, ArmParityVerdict.incomparableRejected);
      expect(r.degradedArms, ['A3']);
      expect(r.reason, contains('拒发'));
    });
  });

  group('summarizeArmParity', () {
    test('#I-7 n_excluded 必须与 n 并列，且剔除分类计数正确', () {
      final s = summarizeArmParity(
        pair: 'A2,A3',
        runs: [
          // s1 可比
          const ArmRun(armId: 'A2', sampleId: 's1'),
          const ArmRun(armId: 'A3', sampleId: 's1'),
          // s2 单臂降级
          const ArmRun(armId: 'A2', sampleId: 's2'),
          const ArmRun(
            armId: 'A3',
            sampleId: 's2',
            droppedStages: ['merge_structure_profile'],
          ),
          // s3 齐降
          const ArmRun(
            armId: 'A2',
            sampleId: 's3',
            droppedStages: ['merge_chunk_notes_top3'],
          ),
          const ArmRun(
            armId: 'A3',
            sampleId: 's3',
            droppedStages: ['merge_chunk_notes_top3'],
          ),
          // s4 拒发
          const ArmRun(armId: 'A2', sampleId: 's4'),
          const ArmRun(armId: 'A3', sampleId: 's4', rejectedOverBudget: true),
        ],
      );
      expect(s.totalRuns, 4);
      expect(s.comparable, 1);
      expect(s.excludedBudget, 2, reason: 's2 单臂降级 + s3 齐降');
      expect(s.excludedRejected, 1);
      expect(s.excludedRate, closeTo(0.75, 1e-9));
      // > 5% ⇒ 主对比结论须标「受限」
      expect(s.conclusionConstrained, isTrue);
      // 被剔除样本须留明细（写「剔掉的是哪一类章」的唯一依据）
      expect(
        s.excluded.map((e) => e.sampleId),
        containsAll(['s2', 's3', 's4']),
      );
    });

    test('#I-8 剔除占比 <= 5% ⇒ 不标受限（阈值带方向，不是「越少越好」）', () {
      // 20 个样本剔1个 = 5%，恰好在边界（判据写的是 > 5%）。
      final runs = <ArmRun>[];
      for (var i = 0; i < 19; i++) {
        runs
          ..add(ArmRun(armId: 'A2', sampleId: 's$i'))
          ..add(ArmRun(armId: 'A3', sampleId: 's$i'));
      }
      runs
        ..add(const ArmRun(armId: 'A2', sampleId: 'sBad'))
        ..add(
          const ArmRun(
            armId: 'A3',
            sampleId: 'sBad',
            droppedStages: ['merge_structure_profile'],
          ),
        );
      final s = summarizeArmParity(pair: 'A2,A3', runs: runs);
      expect(s.totalRuns, 20);
      expect(s.excludedRate, closeTo(0.05, 1e-9));
      expect(s.conclusionConstrained, isFalse, reason: '5% 不触发 >5%');
    });

    test('#I-9 配对缺失 ⇒ 抛错而不是静默配错', () {
      // 「配错对」与「预算降级」是两个不同的病。静默配错会让剔除理由失真，
      // 而剔除理由是报告里「剔掉的是哪一类章」的唯一来源。
      expect(
        () => summarizeArmParity(
          pair: 'A2,A3',
          runs: const [ArmRun(armId: 'A2', sampleId: 's1')],
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => summarizeArmParity(
          pair: 'A2,A3',
          runs: const [
            ArmRun(armId: 'A2', sampleId: 's1'),
            ArmRun(armId: 'A3', sampleId: 's1'),
            ArmRun(armId: 'A4', sampleId: 's1'),
          ],
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('#I-10 空输入 ⇒ 比率 0、不标受限（未测 ≠ 全不合格）', () {
      final s = summarizeArmParity(pair: 'A2,A3', runs: const []);
      expect(s.totalRuns, 0);
      expect(s.excludedRate, 0);
      expect(s.conclusionConstrained, isFalse);
    });
  });

  group('armRunFromSnapshot', () {
    test('#I-11 levels 为空 ⇒ 未降级', () {
      final r = armRunFromSnapshot(
        armId: 'A3',
        sampleId: 's1',
        snapshotPayload: const {
          'budget_report': {'levels': <Object?>[]},
        },
      );
      expect(r.droppedStages, isEmpty);
      expect(r.rejectedOverBudget, isFalse);
    });

    test('#I-12 levels 含 stage ⇒ 还原级名', () {
      final r = armRunFromSnapshot(
        armId: 'A3',
        sampleId: 's1',
        snapshotPayload: const {
          'budget_report': {
            'levels': [
              {'stage': 'merge_structure_profile', 'total_before': 100},
              {'stage': 'merge_inactive_context', 'total_before': 90},
            ],
          },
        },
      );
      expect(r.droppedStages, [
        'merge_structure_profile',
        'merge_inactive_context',
      ]);
    });

    test('#I-13 载荷缺 budget_report ⇒ 缺省未降级（不抛）', () {
      final r = armRunFromSnapshot(
        armId: 'A2',
        sampleId: 's1',
        snapshotPayload: const {'event': 'llm_prompt_snapshot'},
      );
      expect(r.droppedStages, isEmpty);
    });

    test('#I-14 拒发须由调用方传入（本函数不推断）', () {
      // 拒发时**不发送** ⇒ 不产生快照 ⇒ 本函数无从推断。
      // 这条测试锁住「不猜」：漏传就会把拒发样本当未降级混进主对比。
      final r = armRunFromSnapshot(
        armId: 'A3',
        sampleId: 's1',
        snapshotPayload: const {
          'budget_report': {'levels': <Object?>[]},
        },
      );
      expect(r.rejectedOverBudget, isFalse);
      final r2 = armRunFromSnapshot(
        armId: 'A3',
        sampleId: 's1',
        snapshotPayload: const {
          'budget_report': {'levels': <Object?>[]},
        },
        rejectedOverBudget: true,
      );
      expect(r2.rejectedOverBudget, isTrue);
    });
  });

  group('判据按对比对写（防写死对象）', () {
    test('#I-15 A4 排期时 (A0,A4) 自动适用，无需改判据', () {
      // 判据的对象是「关系」不是「具体的那两个东西」。
      // 若有人把 pair 写死成 'A2,A3'，本条会红。
      final r = judgeArmParity(
        pair: 'A0,A4',
        x: const ArmRun(armId: 'A0', sampleId: 's1'),
        y: const ArmRun(armId: 'A4', sampleId: 's1'),
      );
      expect(r.pair, '(A0,A4)');
      expect(r.isComparable, isTrue);
    });

    test('#I-16 不同对比对的剔除互不影响', () {
      final runs = <ArmRun>[
        const ArmRun(armId: 'A2', sampleId: 's1'),
        const ArmRun(
          armId: 'A3',
          sampleId: 's1',
          droppedStages: ['merge_structure_profile'],
        ),
      ];
      final s = summarizeArmParity(pair: 'A2,A3', runs: runs);
      expect(s.pair, '(A2,A3)');
      expect(s.excludedBudget, 1);
    });
  });
}
