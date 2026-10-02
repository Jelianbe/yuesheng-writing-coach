// revisit_guardrail_test — 复刷护栏指标对（ADR-C138 §4.1）
//
// 验收判据（ADR §5.4）：
//   - 复刷 + 无伴随信号 → shouldAlert=true；
//   - 复刷 + 有伴随信号（anchor_ack / completion）→ shouldAlert=false；
//   - 纯函数无副作用（同输入同输出、不突变入参列表、不读全局状态）。
// 四硬隔离：判定结果仅供留痕，本测试不触任何教学状态 / prompt。
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/revisit_guardrail.dart';

void main() {
  group('evaluateRevisitGuardrail · 报警判定', () {
    test('复刷 + 窗口内无伴随信号 → 报警（companionCount=0）', () {
      final v = evaluateRevisitGuardrail(
        isRevisit: true,
        windowEvents: const [],
      );
      expect(v.shouldAlert, isTrue);
      expect(v.companionCount, 0);
    });

    test('复刷 + 窗口内仅 diff（非伴随）→ 视同无伴随 → 报警', () {
      final v = evaluateRevisitGuardrail(
        isRevisit: true,
        windowEvents: const [
          GuardrailWindowEvent(type: GuardrailEventType.other),
        ],
      );
      expect(v.shouldAlert, isTrue);
      expect(v.companionCount, 0);
    });

    test('复刷 + 窗口内有 anchor_ack（自主指认）→ 不报警', () {
      final v = evaluateRevisitGuardrail(
        isRevisit: true,
        windowEvents: const [
          GuardrailWindowEvent(type: GuardrailEventType.anchorAck),
          GuardrailWindowEvent(type: GuardrailEventType.other),
        ],
      );
      expect(v.shouldAlert, isFalse);
      expect(v.companionCount, 1);
    });

    test('复刷 + 窗口内有 completion（训练完成）→ 不报警', () {
      final v = evaluateRevisitGuardrail(
        isRevisit: true,
        windowEvents: const [
          GuardrailWindowEvent(type: GuardrailEventType.completion),
        ],
      );
      expect(v.shouldAlert, isFalse);
      expect(v.companionCount, 1);
    });

    test('复刷 + 既有 anchor_ack 又有 completion → 不报警（计数累加）', () {
      final v = evaluateRevisitGuardrail(
        isRevisit: true,
        windowEvents: const [
          GuardrailWindowEvent(type: GuardrailEventType.anchorAck),
          GuardrailWindowEvent(type: GuardrailEventType.other),
          GuardrailWindowEvent(type: GuardrailEventType.completion),
        ],
      );
      expect(v.shouldAlert, isFalse);
      expect(v.companionCount, 2);
    });

    test('非复刷 → 一律不报警（即使窗口为空，首刷/留存不在口径内）', () {
      final v0 = evaluateRevisitGuardrail(
        isRevisit: false,
        windowEvents: const [],
      );
      expect(v0.shouldAlert, isFalse);
      expect(v0.companionCount, 0);
      // 非复刷即便窗口里堆了事件，护栏也不报警（口径外）。
      final v = evaluateRevisitGuardrail(
        isRevisit: false,
        windowEvents: const [
          GuardrailWindowEvent(type: GuardrailEventType.other),
        ],
      );
      expect(v.shouldAlert, isFalse);
    });
  });

  group('纯函数无副作用', () {
    test('同输入 → 同输出（引用透明）', () {
      const evs = [GuardrailWindowEvent(type: GuardrailEventType.other)];
      final a = evaluateRevisitGuardrail(isRevisit: true, windowEvents: evs);
      final b = evaluateRevisitGuardrail(isRevisit: true, windowEvents: evs);
      expect(a.shouldAlert, b.shouldAlert);
      expect(a.companionCount, b.companionCount);
    });

    test('不突变传入的事件列表', () {
      final evs = [
        const GuardrailWindowEvent(type: GuardrailEventType.completion),
      ];
      final before = evs.length;
      evaluateRevisitGuardrail(isRevisit: true, windowEvents: evs);
      expect(evs.length, before); // 调用后列表原样
    });

    test('不依赖外部可变状态：多次调用互不影响', () {
      const withAck = [
        GuardrailWindowEvent(type: GuardrailEventType.anchorAck),
      ];
      const empty = <GuardrailWindowEvent>[];
      // 先算一次有伴随（不报警），再算一次空窗口（报警）——互不污染。
      expect(
        evaluateRevisitGuardrail(
          isRevisit: true,
          windowEvents: withAck,
        ).shouldAlert,
        isFalse,
      );
      expect(
        evaluateRevisitGuardrail(
          isRevisit: true,
          windowEvents: empty,
        ).shouldAlert,
        isTrue,
      );
    });
  });

  group('GuardrailEventType.fromEventType · 字面值映射', () {
    test("'anchor_ack' / 'completion' 正确映射；其余/空 → other", () {
      expect(
        GuardrailEventType.fromEventType('anchor_ack'),
        GuardrailEventType.anchorAck,
      );
      expect(
        GuardrailEventType.fromEventType('completion'),
        GuardrailEventType.completion,
      );
      expect(
        GuardrailEventType.fromEventType('diff'),
        GuardrailEventType.other,
      );
      expect(GuardrailEventType.fromEventType(null), GuardrailEventType.other);
      expect(GuardrailEventType.fromEventType(''), GuardrailEventType.other);
    });

    test('伴随信号判定：anchor_ack / completion 为 true，other 为 false', () {
      expect(isGuardrailCompanion(GuardrailEventType.anchorAck), isTrue);
      expect(isGuardrailCompanion(GuardrailEventType.completion), isTrue);
      expect(isGuardrailCompanion(GuardrailEventType.other), isFalse);
    });
  });
}
