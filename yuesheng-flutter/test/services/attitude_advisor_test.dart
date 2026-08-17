// ─────────────────────────────────────────────────────────────
// AttitudeAdvisor 服务测试 — 复刻 RN attitude-advisor.test.ts
//
// 覆盖：边界 null（消息数/冷却/条件不足/无诊断）、升级路径、
// 降级路径、reason 文案、升级优先于降级、getAttitudeLabel。
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/config/shared_constants.dart';
import 'package:writingcoach/services/attitude_advisor.dart';
import 'package:writingcoach/types/teaching_types.dart';

void main() {
  group('suggestAttitudeAdjustment', () {
    group('边界条件返回 null', () {
      test('消息数不足 5', () {
        final result = suggestAttitudeAdjustment(
          currentAttitude: AttitudeLevel.doubao,
          currentPhase: TeachingPhase.p0Engage,
          messageCount: 4,
        );
        expect(result, isNull);
      });

      test('冷却期内不触发', () {
        final now = DateTime.now().millisecondsSinceEpoch;
        final result = suggestAttitudeAdjustment(
          currentAttitude: AttitudeLevel.doubao,
          currentPhase: TeachingPhase.p0Engage,
          messageCount: 10,
          lastSuggestionTime: now - 5 * 60 * 1000, // 5 分钟前
          now: now,
        );
        expect(result, isNull);
      });

      test('冷却期过后可触发（condition 3: ≥15 消息 + 高阶段 + avg≥1.8）', () {
        final now = DateTime.now().millisecondsSinceEpoch;
        final result = suggestAttitudeAdjustment(
          currentAttitude: AttitudeLevel.doubao,
          currentPhase: TeachingPhase.p2PracticeLoop,
          syndromes: const [Severity.l2], // 1 个症候不满足 condition1，avg=2.0≥1.8
          messageCount: 15,
          lastSuggestionTime: now - 11 * 60 * 1000, // 11 分钟前，超出冷却期
          now: now,
        );
        expect(result, isNotNull);
        expect(result!.direction, 'upgrade');
      });

      test('冷却期刚过但条件不足时返回 null', () {
        final now = DateTime.now().millisecondsSinceEpoch;
        final result = suggestAttitudeAdjustment(
          currentAttitude: AttitudeLevel.doubao,
          currentPhase: TeachingPhase.p0Engage,
          messageCount: 8,
          lastSuggestionTime: now - 11 * 60 * 1000,
          now: now,
        );
        expect(result, isNull);
      });

      test('无诊断数据可返回 null', () {
        final result = suggestAttitudeAdjustment(
          currentAttitude: AttitudeLevel.doubao,
          currentPhase: TeachingPhase.p0Engage,
          messageCount: 20,
        );
        expect(result, isNull);
      });
    });

    group('升级建议', () {
      test('高阶段 + 高严重度 + ≥2症候 → upgrade（doubao→yuesheng）', () {
        final result = suggestAttitudeAdjustment(
          currentAttitude: AttitudeLevel.doubao,
          currentPhase: TeachingPhase.p2PracticeLoop,
          syndromes: const [Severity.l3, Severity.l2], // avg=(3+2)/2=2.5≥2.2
          messageCount: 10,
        );
        expect(result, isNotNull);
        expect(result!.direction, 'upgrade');
        expect(result.targetLevel, AttitudeLevel.yuesheng);
      });

      test('连续正反馈 4 次 → upgrade（doubao→yuesheng）', () {
        final result = suggestAttitudeAdjustment(
          currentAttitude: AttitudeLevel.doubao,
          currentPhase: TeachingPhase.p0Engage,
          messageCount: 10,
          consecutivePositiveFeedback: 4,
        );
        expect(result!.direction, 'upgrade');
        expect(result.targetLevel, AttitudeLevel.yuesheng);
      });

      test('≥15 消息 + 高阶段 + avg≥1.8 → upgrade', () {
        final result = suggestAttitudeAdjustment(
          currentAttitude: AttitudeLevel.doubao,
          currentPhase: TeachingPhase.p3Training,
          syndromes: const [Severity.l2, Severity.l2], // avg=2.0≥1.8
          messageCount: 20,
        );
        expect(result!.direction, 'upgrade');
      });

      test('从 yuesheng 升级到 sensei', () {
        final result = suggestAttitudeAdjustment(
          currentAttitude: AttitudeLevel.yuesheng,
          currentPhase: TeachingPhase.p2PracticeLoop,
          syndromes: const [Severity.l3, Severity.l2],
          messageCount: 10,
        );
        expect(result!.targetLevel, AttitudeLevel.sensei);
      });

      test('sensei 不再升级', () {
        final result = suggestAttitudeAdjustment(
          currentAttitude: AttitudeLevel.sensei,
          currentPhase: TeachingPhase.p2PracticeLoop,
          syndromes: const [Severity.l3, Severity.l3],
          messageCount: 10,
        );
        expect(result, isNull);
      });
    });

    group('降级建议', () {
      test('连续负反馈 3 次 → downgrade（yuesheng→doubao）', () {
        final result = suggestAttitudeAdjustment(
          currentAttitude: AttitudeLevel.yuesheng,
          currentPhase: TeachingPhase.p0Engage,
          messageCount: 10,
          consecutiveNegativeFeedback: 3,
        );
        expect(result!.direction, 'downgrade');
        expect(result.targetLevel, AttitudeLevel.doubao);
      });

      test('低严重度 + ≤1症候 + ≥10消息 → downgrade（sensei→yuesheng）', () {
        final result = suggestAttitudeAdjustment(
          currentAttitude: AttitudeLevel.sensei,
          currentPhase: TeachingPhase.p0Engage,
          syndromes: const [Severity.l1], // avg=1≤1.2, 1症候≤1
          messageCount: 12,
        );
        expect(result!.direction, 'downgrade');
        expect(result.targetLevel, AttitudeLevel.yuesheng);
      });

      test('doubao 不再降级', () {
        final result = suggestAttitudeAdjustment(
          currentAttitude: AttitudeLevel.doubao,
          currentPhase: TeachingPhase.p0Engage,
          messageCount: 10,
          consecutiveNegativeFeedback: 5,
        );
        expect(result, isNull);
      });
    });

    group('reason 文本', () {
      test('升级 reason 包含信息', () {
        final result = suggestAttitudeAdjustment(
          currentAttitude: AttitudeLevel.doubao,
          currentPhase: TeachingPhase.p2PracticeLoop,
          syndromes: const [Severity.l3, Severity.l3],
          messageCount: 10,
        );
        expect(result!.reason, contains('写作问题'));
        expect(result.reason, contains('月笙'));
      });

      test('降级 reason 包含信息', () {
        final result = suggestAttitudeAdjustment(
          currentAttitude: AttitudeLevel.yuesheng,
          currentPhase: TeachingPhase.p0Engage,
          syndromes: const [Severity.l1],
          messageCount: 10,
          consecutiveNegativeFeedback: 3,
        );
        expect(result!.reason, contains('豆包'));
        expect(result.reason, contains('轻松'));
      });
    });

    test('同时满足升降条件时优先升级', () {
      final result = suggestAttitudeAdjustment(
        currentAttitude: AttitudeLevel.doubao,
        currentPhase: TeachingPhase.p2PracticeLoop,
        syndromes: const [Severity.l3, Severity.l2],
        messageCount: 10,
        consecutivePositiveFeedback: 4, // 升级条件（正反馈跟上）
        consecutiveNegativeFeedback: 3, // 降级条件（挫败降档）
      );
      expect(result!.direction, 'upgrade');
    });
  });

  group('getAttitudeLabel', () {
    test('doubao → 豆包', () {
      expect(getAttitudeLabel(AttitudeLevel.doubao), '豆包');
    });

    test('yuesheng → 月笙', () {
      expect(getAttitudeLabel(AttitudeLevel.yuesheng), '月笙');
    });

    test('sensei → 老师', () {
      expect(getAttitudeLabel(AttitudeLevel.sensei), '老师');
    });
  });

  // ── 批次4（4.4）：负反馈关键词 + 安全词上下文判断 ──

  group('containsNegativeFeedback（批次4 4.4）', () {
    test('自嘲样本命中负反馈关键词', () {
      expect(containsNegativeFeedback('我是不是太笨了，完全听不懂'), isTrue);
      expect(containsNegativeFeedback('你讲太快了，我跟不上'), isTrue);
    });

    test('反讽样本命中负反馈关键词', () {
      // "太深奥了"反讽式表达仍是挫败信号
      expect(containsNegativeFeedback('太深奥了，可真是通俗易懂呢'), isTrue);
    });

    test('夸 AI 样本不命中', () {
      expect(containsNegativeFeedback('你讲得真好，特别清楚'), isFalse);
      expect(containsNegativeFeedback('老师你太棒了，我明白了'), isFalse);
    });
  });

  group('isSafetyWordRequest（批次4 4.4 安全词上下文判断）', () {
    test('裸"轻一点" → 降档请求', () {
      expect(isSafetyWordRequest('老师你说话轻一点'), isTrue);
      expect(isSafetyWordRequest('轻一点，别太严厉'), isTrue);
    });

    test('引号内引用（转述）不触发', () {
      expect(isSafetyWordRequest('她说了"轻一点"'), isFalse);
      expect(isSafetyWordRequest('他写道「轻一点」'), isFalse);
    });

    test('写作示例不触发', () {
      expect(isSafetyWordRequest('这句改成"轻一点"更合适'), isFalse);
    });

    test('含"语气措辞"术语不触发', () {
      expect(isSafetyWordRequest('用"轻一点"这个语气措辞怎么样'), isFalse);
      expect(isSafetyWordRequest('"轻一点"这个措辞更温柔'), isFalse);
    });
  });

  // ── B4 接线：chat_attitude 调用 computeAttitudeDowngradeSignal 的回归锁 ──
  group('computeAttitudeDowngradeSignal（B4 降档信号）', () {
    ({String role, String content}) msg(String role, String content) =>
        (role: role, content: content);

    test('最近 3 条用户负反馈 → 返回 3', () {
      final messages = [
        msg('user', '我明白了'),
        msg('user', '太深奥了，我完全听不懂'),
        msg('user', '你讲太快了'),
        msg('user', '我真的跟不上了'),
      ];
      expect(computeAttitudeDowngradeSignal(messages), 3);
    });

    test('非负反馈用户消息打断连续计数', () {
      final messages = [
        msg('user', '太深奥了听不懂'),
        msg('user', '我明白了'),
        msg('user', '还是听不懂'),
      ];
      // 从最新向前：听不懂→1，我明白了(非负反馈)→打断，停止
      expect(computeAttitudeDowngradeSignal(messages), 1);
    });

    test('中间夹 assistant 消息不阻断连续计数', () {
      final messages = [
        msg('user', '太深奥了听不懂'),
        msg('assistant', '我换个说法'),
        msg('user', '你讲太快了'),
      ];
      // assistant 跳过不 break，用户负反馈仍连续 → 2
      expect(computeAttitudeDowngradeSignal(messages), 2);
    });

    test('最新用户消息是安全词「轻一点」→ 强制达到降档阈值', () {
      final messages = [
        msg('user', '老师你说话轻一点'),
        msg('assistant', '好的'),
      ];
      expect(
        computeAttitudeDowngradeSignal(messages),
        AttitudeThresholds.negativeFeedbackDowngradeCount,
      );
    });

    test('转述的"轻一点"不触发降档信号', () {
      final messages = [msg('user', '她说了"轻一点"')];
      expect(computeAttitudeDowngradeSignal(messages), 0);
    });
  });
}
