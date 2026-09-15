// ─────────────────────────────────────────────────────────────
// reasoning_tier_test — 推理档位真源（用户可调思考开关）
// 断言「档位 → 请求体补丁」映射。重点锁死**标准档不产键**：
// 它保证未设置档位（含旧库）时请求体与改造前逐字节相同，
// 既有请求体锚点测试（llm_client_stream_fallback_test）零影响。
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/config/reasoning_tier.dart';

void main() {
  group('推理档位 → 请求体补丁', () {
    test('标准档 / null / 未知 key ⇒ 空补丁（请求体零变更护栏）', () {
      expect(reasoningBodyPatchFor(reasoningTierStandard), isEmpty);
      expect(reasoningBodyPatchFor(null), isEmpty);
      expect(reasoningBodyPatchFor('不存在的档位'), isEmpty);
    });

    test('轻量档 ⇒ reasoning_effort: low（保留思考、降强度）', () {
      expect(reasoningBodyPatchFor(reasoningTierLow), {
        'reasoning_effort': 'low',
      });
    });

    test('深度档 ⇒ reasoning_effort: max', () {
      expect(reasoningBodyPatchFor(reasoningTierDeep), {
        'reasoning_effort': 'max',
      });
    });

    test('关闭档 ⇒ thinking: disabled', () {
      expect(reasoningBodyPatchFor(reasoningTierOff), {
        'thinking': {'type': 'disabled'},
      });
    });
  });

  group('推理档位列表约束', () {
    test('兜底档 = 列表首项（界面默认与逻辑默认同源）', () {
      expect(reasoningTierOf(null).key, reasoningTierPresets.first.key);
      expect(reasoningTierPresets.first.key, reasoningTierStandard);
    });

    test('key 唯一、非空，且不与存储键同名', () {
      final keys = reasoningTierPresets.map((p) => p.key).toList();
      expect(keys.toSet().length, keys.length);
      expect(keys.every((k) => k.isNotEmpty), isTrue);
      expect(keys.contains(kReasoningTierKey), isFalse);
      expect(kReasoningTierKey, 'reasoning_tier');
    });

    test('每个档位都有面向用户的 label / hint', () {
      for (final p in reasoningTierPresets) {
        expect(p.label, isNotEmpty);
        expect(p.hint, isNotEmpty);
      }
    });
  });

  // 「开关」（输入框上方二值）与「档位」（设置/更多菜单四档）是同一状态
  // 的两种视图；这组用例锁死二者换算，防两处入口各写一套判定而漂移。
  group('思考开关 ⇄ 档位换算', () {
    test('开关开 = 档位非「关闭思考」（含 null 默认档）', () {
      expect(isThinkingEnabled(reasoningTierStandard), isTrue);
      expect(isThinkingEnabled(reasoningTierLow), isTrue);
      expect(isThinkingEnabled(reasoningTierDeep), isTrue);
      expect(isThinkingEnabled(null), isTrue);
      expect(isThinkingEnabled('未知档位'), isTrue);
    });

    test('开关关 = 关闭思考档', () {
      expect(isThinkingEnabled(reasoningTierOff), isFalse);
    });

    test('重开恢复「上次开启态档位」（用户设的深度不被静默重置）', () {
      expect(restoredOnTier(reasoningTierDeep), reasoningTierDeep);
      expect(restoredOnTier(reasoningTierLow), reasoningTierLow);
      expect(restoredOnTier(reasoningTierStandard), reasoningTierStandard);
    });

    test('无记忆 / 记忆为关闭档 / 未知 ⇒ 回退标准档', () {
      expect(restoredOnTier(null), reasoningTierStandard);
      expect(restoredOnTier(reasoningTierOff), reasoningTierStandard);
      expect(restoredOnTier('未知档位'), reasoningTierStandard);
    });

    test('开关记忆键与档位键不同名（两个 key 互不覆盖）', () {
      expect(kReasoningTierLastOnKey, isNot(kReasoningTierKey));
      expect(kReasoningTierLastOnKey, 'reasoning_tier_last_on');
    });
  });
}
