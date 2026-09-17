// ─────────────────────────────────────────────────────────────
// llm_usage_test — M 批：用量值对象解析与派生量
//
// 覆盖：完整解析（DeepSeek 实测形态）/ 缓存命中两种口径 / 推理 token /
// 字段缺失与类型不符的容错 / 不可用块返回 null / hitRate 边界不除零。
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/llm_usage.dart';

/// 2026-09-14 实测抓包得到的 DeepSeek 非流式 usage 原样形态。
const Map<String, Object> _kRealDeepSeekUsage = {
  'prompt_tokens': 37,
  'completion_tokens': 20,
  'total_tokens': 57,
  'prompt_tokens_details': {'cached_tokens': 0},
  'completion_tokens_details': {'reasoning_tokens': 17},
  'prompt_cache_hit_tokens': 0,
  'prompt_cache_miss_tokens': 37,
};

void main() {
  group('LlmUsage.fromJson 解析', () {
    test('实测形态逐字段解析', () {
      final u = LlmUsage.fromJson(_kRealDeepSeekUsage, model: 'deepseek-flash');
      expect(u, isNotNull);
      expect(u!.promptTokens, 37);
      expect(u.completionTokens, 20);
      expect(u.cachedTokens, 0);
      expect(u.reasoningTokens, 17);
      expect(u.model, 'deepseek-flash');
    });

    test('缓存命中优先取顶层 prompt_cache_hit_tokens', () {
      final u = LlmUsage.fromJson({
        'prompt_tokens': 100,
        'completion_tokens': 10,
        'prompt_cache_hit_tokens': 80,
        'prompt_cache_miss_tokens': 20,
      });
      expect(u!.cachedTokens, 80);
      expect(u.missTokens, 20);
      expect(u.hitRate, closeTo(0.8, 1e-9));
    });

    test('无顶层键时回退 OpenAI 嵌套 cached_tokens', () {
      final u = LlmUsage.fromJson({
        'prompt_tokens': 100,
        'completion_tokens': 10,
        'prompt_tokens_details': {'cached_tokens': 25},
      });
      expect(u!.cachedTokens, 25);
    });

    test('顶层键存在时不与嵌套键混用（单一口径）', () {
      final u = LlmUsage.fromJson({
        'prompt_tokens': 100,
        'completion_tokens': 10,
        'prompt_cache_hit_tokens': 10,
        'prompt_tokens_details': {'cached_tokens': 90},
      });
      expect(u!.cachedTokens, 10);
    });

    test('reasoning_tokens 缺省为 0', () {
      final u = LlmUsage.fromJson({'prompt_tokens': 1, 'completion_tokens': 2});
      expect(u!.reasoningTokens, 0);
    });

    test('字段缺失按 0 计，不整体作废', () {
      final u = LlmUsage.fromJson({'prompt_tokens': 5});
      expect(u, isNotNull);
      expect(u!.promptTokens, 5);
      expect(u.completionTokens, 0);
    });

    test('类型不符按 0 计', () {
      final u = LlmUsage.fromJson({
        'prompt_tokens': 5,
        'completion_tokens': true,
        'prompt_cache_hit_tokens': {'x': 1},
        'completion_tokens_details': 'oops',
      });
      expect(u!.completionTokens, 0);
      expect(u.cachedTokens, 0);
      expect(u.reasoningTokens, 0);
    });

    test('数字字符串与浮点可解析', () {
      final u = LlmUsage.fromJson({
        'prompt_tokens': '42',
        'completion_tokens': 7.9,
      });
      expect(u!.promptTokens, 42);
      expect(u.completionTokens, 7);
    });

    test('两个 token 都取不到 ⇒ null（不构成读数）', () {
      expect(LlmUsage.fromJson({}), isNull);
      expect(LlmUsage.fromJson({'total_tokens': 57}), isNull);
    });

    test('非 Map 入参 ⇒ null（含 null / String / List / num）', () {
      expect(LlmUsage.fromJson(null), isNull);
      expect(LlmUsage.fromJson('usage'), isNull);
      expect(LlmUsage.fromJson(<dynamic>[1, 2]), isNull);
      expect(LlmUsage.fromJson(3), isNull);
    });

    test('model 缺省为 null', () {
      final u = LlmUsage.fromJson({'prompt_tokens': 1});
      expect(u!.model, isNull);
    });
  });

  group('派生量', () {
    test('totalTokens = prompt + completion', () {
      const u = LlmUsage(promptTokens: 30, completionTokens: 12);
      expect(u.totalTokens, 42);
    });

    test('promptTokens == 0 ⇒ hitRate 0.0（不除零）', () {
      const u = LlmUsage(promptTokens: 0, completionTokens: 5);
      expect(u.hitRate, 0.0);
      expect(u.missTokens, 0);
    });

    test('cached 超过 prompt 时 missTokens 不为负（脏数据防御）', () {
      const u = LlmUsage(
        promptTokens: 10,
        completionTokens: 1,
        cachedTokens: 99,
      );
      expect(u.missTokens, 0);
    });

    test('toString 含关键读数（供 debug 留痕）', () {
      const u = LlmUsage(promptTokens: 100, completionTokens: 20);
      expect(u.toString(), contains('prompt: 100'));
      expect(u.toString(), contains('completion: 20'));
    });
  });
}
