// ─────────────────────────────────────────────────────────────
// llm_model_profile_glm_fallback_test — GLM 系空流兜底守卫
//
// ★ 本批改动的判据（2026-10-06）：`fallbackDisableThinking` 此前只含
//   deepseek，而同文件上方的 `disableThinking` 却**已含 GLM**
//   ⇒ 同一模型族「主动关思考」却「不兜底空流」的判据不一致。
//
// ★ 为什么必须补测试（本条判据的来源是**实测**，不是推理）：
//   glm-4.7-flash 是思考型模型 —— 实测 `max_tokens=16` 时全部被
//   `reasoning_content` 吃掉、`content` 返回**空串**（finish_reason=length）；
//   流式探查也确认 `delta` 先吐 reasoning_content、content 在其后。而
//   `llm_client._handleSseData` **只认 delta.content** ⇒ 这类模型必然命中
//   「零 content token 且流干净结束」的判空条件。
//
// ★ 既有约束不能破：AC-3 要求「非 deepseek 模型请求体逐字节不变」——
//   本兜底**仅在运行时判空成立时**注入，成功路径零行为变更。
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/llm_model_profile.dart';

void main() {
  group('GLM 系纳入空流兜底（2026-10-06 修正）', () {
    test('M1 GLM thinking 系应同时命中 disableThinking 与 fallback', () {
      for (final m in [
        'glm-4.7-flash',
        'glm-4.5-flash',
        'glm-5',
        'glm-4.6v-flash',
      ]) {
        final p = classifyLlmModel(m);
        expect(p.disableThinking, isTrue, reason: '$m 应主动关思考');
        expect(
          p.fallbackDisableThinking,
          isTrue,
          reason: '$m 思考 token 会吃空 content ⇒ 必须能兜底空流',
        );
      }
    });

    test('M2 ★两判据对 GLM 族必须一致（防再次分叉）', () {
      // 本次缺陷的本质就是「disableThinking 含 GLM 而 fallback 不含」。
      // 用同一族模型同时断言两者，避免只改一半。
      for (final m in ['glm-4.7-flash', 'glm-4.5-flash', 'glm-5']) {
        final p = classifyLlmModel(m);
        expect(
          p.disableThinking,
          p.fallbackDisableThinking,
          reason: '$m 的两个判据不一致 ⇒ 会出现「主动关思考却不兜底空流」',
        );
      }
    });

    test('M3 doubao-seed 系也纳入兜底（与既有 disableThinking 对齐）', () {
      final p = classifyLlmModel('doubao-seed-2.1-turbo');
      expect(p.disableThinking, isTrue);
      expect(
        p.fallbackDisableThinking,
        isTrue,
        reason: 'doubao-seed 深度思考默认开启 ⇒ 同样会吃空 content',
      );
    });

    test('M4 deepseek 系行为不变（AC-3：既有兜底不得回退）', () {
      for (final m in [
        'deepseek-chat',
        'deepseek-reasoner',
        'deepseek-v4-flash',
      ]) {
        expect(
          classifyLlmModel(m).fallbackDisableThinking,
          isTrue,
          reason: '$m 本就在兜底名单内，不得被本次改动破坏',
        );
      }
    });

    test('M5 ★非思考型模型仍不进兜底（不得过度扩大）', () {
      // 「把 GLM 加进名单」不等于「把所有模型加进名单」——
      // 过宽会让普通模型也走降级重试，掩盖真实问题。
      for (final m in [
        'gpt-4.1',
        'kimi-k3',
        'qwen-plus',
        'glm-unknown-suffix',
      ]) {
        expect(
          classifyLlmModel(m).fallbackDisableThinking,
          isFalse,
          reason: '$m 不应被纳入空流兜底（避免无谓的降级重试）',
        );
      }
    });

    test('M6 大小写与空白不敏感（与既有实现同源）', () {
      expect(classifyLlmModel('GLM-4.7-FLASH').fallbackDisableThinking, isTrue);
      expect(
        classifyLlmModel('  glm-4.7-flash  ').fallbackDisableThinking,
        isTrue,
      );
    });
  });
}
