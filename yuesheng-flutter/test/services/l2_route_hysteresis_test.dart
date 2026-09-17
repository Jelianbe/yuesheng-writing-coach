// U2 批（2026-09-15）：L2 路由迟滞器单元测试。
//
// 覆盖：基础不干预 / 核心迟滞（训练组→诊断组）/ 显式解锁穿透 /
//       会话隔离 / 容量上限。
//
// 归因：docs/audits/U1批-共享前置落地与缓存偏移实证-2026-09-15.md §5

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/contracts/teaching_capability.dart';
import 'package:writingcoach/services/l2_route_hysteresis.dart';

void main() {
  group('L2RouteHysteresis · 基础决议（不干预路径）', () {
    test('首轮无历史 ⇒ 返回 null（不干预）并建立状态', () {
      final h = L2RouteHysteresis();
      expect(h.overrideFor('s1', L2Mode.diagnosis), isNull);
      expect(h.trackedSessions, 1);
    });

    test('同组连续多轮 ⇒ 恒不干预', () {
      final h = L2RouteHysteresis();
      h.overrideFor('s1', L2Mode.diagnosis);
      for (var i = 0; i < 5; i++) {
        expect(h.overrideFor('s1', L2Mode.diagnosis), isNull, reason: '第 $i 轮');
      }
    });

    test('非 training 起点 → diagnosis 切换不受迟滞影响', () {
      final h = L2RouteHysteresis();
      h.overrideFor('s1', L2Mode.advanced);
      expect(h.overrideFor('s1', L2Mode.diagnosis), isNull);
    });
  });

  group('L2RouteHysteresis · 训练组→诊断组迟滞（核心）', () {
    test('d→t→d：第 3 轮被抑制，第 4 轮放行（M=1 默认）', () {
      final h = L2RouteHysteresis();
      expect(h.overrideFor('s1', L2Mode.diagnosis), isNull); // r1 诊断
      expect(h.overrideFor('s1', L2Mode.training), isNull); // r2 交作业（切1 保留）
      expect(
        h.overrideFor('s1', L2Mode.diagnosis),
        L2Mode.training,
        reason: '练习后自动回切应被抑制',
      ); // r3
      expect(h.overrideFor('s1', L2Mode.diagnosis), isNull); // r4 正常回落
    });

    test('holdRounds=2 ⇒ 连抑制两轮后放行', () {
      final h = L2RouteHysteresis(holdRounds: 2);
      h.overrideFor('s1', L2Mode.diagnosis);
      h.overrideFor('s1', L2Mode.training);
      expect(h.overrideFor('s1', L2Mode.diagnosis), L2Mode.training);
      expect(h.overrideFor('s1', L2Mode.diagnosis), L2Mode.training);
      expect(h.overrideFor('s1', L2Mode.diagnosis), isNull);
    });

    test('holdRounds=0 ⇒ 关闭迟滞（可开关）', () {
      final h = L2RouteHysteresis(holdRounds: 0);
      h.overrideFor('s1', L2Mode.diagnosis);
      h.overrideFor('s1', L2Mode.training);
      expect(h.overrideFor('s1', L2Mode.diagnosis), isNull);
    });

    test('抑制期内 raw 回到 training ⇒ 计数归零（不跨段累积）', () {
      final h = L2RouteHysteresis(holdRounds: 2);
      h.overrideFor('s1', L2Mode.diagnosis);
      h.overrideFor('s1', L2Mode.training);
      expect(h.overrideFor('s1', L2Mode.diagnosis), L2Mode.training); // 抑制 1
      expect(h.overrideFor('s1', L2Mode.training), isNull); // 回训练 ⇒ 归零
      expect(h.overrideFor('s1', L2Mode.diagnosis), L2Mode.training); // 重新计 1
    });

    test('training → advanced/outline/beginner/none 立即生效（阶段推进不迟滞）', () {
      for (final target in <L2Mode>[
        L2Mode.advanced,
        L2Mode.outline,
        L2Mode.beginner,
        L2Mode.none,
      ]) {
        final h = L2RouteHysteresis();
        h.overrideFor('s1', L2Mode.diagnosis);
        h.overrideFor('s1', L2Mode.training);
        expect(h.overrideFor('s1', target), isNull, reason: '$target 不应被迟滞');
      }
    });

    test('advanced → diagnosis 亦不迟滞（仅 training 起点受限）', () {
      final h = L2RouteHysteresis();
      h.overrideFor('s1', L2Mode.training);
      h.overrideFor('s1', L2Mode.advanced);
      expect(h.overrideFor('s1', L2Mode.diagnosis), isNull);
    });
  });

  group('L2RouteHysteresis · 显式解锁穿透', () {
    test('reset 后下一轮立即生效（跳过练习场景）', () {
      final h = L2RouteHysteresis();
      h.overrideFor('s1', L2Mode.diagnosis);
      h.overrideFor('s1', L2Mode.training);
      h.reset('s1'); // 对应 handleSkipPractice → ChatService.setSubphase
      expect(h.overrideFor('s1', L2Mode.diagnosis), isNull, reason: '显式解锁必须穿透');
    });

    test('reset 只影响指定会话', () {
      final h = L2RouteHysteresis();
      h.overrideFor('s1', L2Mode.training);
      h.overrideFor('s2', L2Mode.training);
      h.reset('s1');
      expect(h.trackedSessions, 1);
    });

    test('reset 未跟踪的会话不报错', () {
      final h = L2RouteHysteresis();
      expect(() => h.reset('never-seen'), returnsNormally);
    });
  });

  group('L2RouteHysteresis · 会话隔离与容量', () {
    test('会话之间互不影响', () {
      final h = L2RouteHysteresis();
      h.overrideFor('s1', L2Mode.diagnosis);
      h.overrideFor('s1', L2Mode.training);
      h.overrideFor('s2', L2Mode.diagnosis);
      expect(h.overrideFor('s2', L2Mode.training), isNull, reason: 's2 独立');
      expect(
        h.overrideFor('s1', L2Mode.diagnosis),
        L2Mode.training,
        reason: 's1 仍抑制',
      );
    });

    test('超出 maxSessions ⇒ 按插入序清最陈旧的会话', () {
      final h = L2RouteHysteresis(maxSessions: 3);
      for (var i = 1; i <= 4; i++) {
        h.overrideFor('s$i', L2Mode.training);
      }
      expect(h.trackedSessions, 3);
      expect(
        h.overrideFor('s1', L2Mode.diagnosis),
        isNull,
        reason: 's1 已被清 ⇒ 视作首轮，不干预',
      );
    });
  });
}
