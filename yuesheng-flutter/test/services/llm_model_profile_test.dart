// ─────────────────────────────────────────────────────────────
// llm_model_profile_test — OpenAI 兼容模型参数画像（ADR-C83）
//
// 覆盖 classifyLlmModel 的推理模型识别：
//   - OpenAI o 系列（o1/o3/o4/gpt-5 及 -mini/-preview 变体）→ reasoningOnly
//   - DeepSeek 系与其他 OpenAI 兼容模型 → 通用行为（非 reasoningOnly）
//   - 大小写不敏感
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/llm_client.dart';

void main() {
  group('classifyLlmModel（ADR-C83）', () {
    test('OpenAI o 系列推理模型 → reasoningOnly=true', () {
      expect(classifyLlmModel('o1').reasoningOnly, isTrue);
      expect(classifyLlmModel('o1-mini').reasoningOnly, isTrue);
      expect(classifyLlmModel('o1-preview').reasoningOnly, isTrue);
      expect(classifyLlmModel('o3-mini').reasoningOnly, isTrue);
      expect(classifyLlmModel('o4-mini').reasoningOnly, isTrue);
      expect(classifyLlmModel('gpt-5').reasoningOnly, isTrue);
      expect(classifyLlmModel('gpt-5-mini').reasoningOnly, isTrue);
    });

    test('DeepSeek 系保持通用行为（非 reasoningOnly）', () {
      expect(classifyLlmModel('deepseek-v4-flash').reasoningOnly, isFalse);
      expect(classifyLlmModel('deepseek-chat').reasoningOnly, isFalse);
      expect(classifyLlmModel('deepseek-reasoner').reasoningOnly, isFalse);
    });

    test('其他 OpenAI 兼容模型保持通用行为', () {
      expect(classifyLlmModel('gpt-4o').reasoningOnly, isFalse);
      expect(classifyLlmModel('gpt-4.1').reasoningOnly, isFalse);
      expect(classifyLlmModel('qwen-plus').reasoningOnly, isFalse);
      expect(classifyLlmModel('moonshot-v1-8k').reasoningOnly, isFalse);
      expect(classifyLlmModel('glm-4').reasoningOnly, isFalse);
      expect(classifyLlmModel('doubao-pro-32k').reasoningOnly, isFalse);
    });

    test('大小写不敏感', () {
      expect(classifyLlmModel('O1-MINI').reasoningOnly, isTrue);
      expect(classifyLlmModel('O3').reasoningOnly, isTrue);
      expect(classifyLlmModel('GPT-4O').reasoningOnly, isFalse);
      expect(classifyLlmModel('DeepSeek-V4-Flash').reasoningOnly, isFalse);
    });

    test('空串/前后空白不误判', () {
      expect(classifyLlmModel('').reasoningOnly, isFalse);
      expect(classifyLlmModel('  deepseek-v4-flash  ').reasoningOnly, isFalse);
      expect(classifyLlmModel('  o1-mini  ').reasoningOnly, isTrue);
    });

    test('GLM thinking 系 → disableThinking=true（防思考退化乱码）', () {
      expect(
        classifyLlmModel('glm-4.1v-thinking-flash').disableThinking,
        isTrue,
      );
      expect(classifyLlmModel('glm-4.5').disableThinking, isTrue);
      expect(classifyLlmModel('glm-4.6').disableThinking, isTrue);
      expect(classifyLlmModel('glm-4.7-flash').disableThinking, isTrue);
      expect(classifyLlmModel('glm-5').disableThinking, isTrue);
      expect(
        classifyLlmModel('glm-4.1v-thinking-flash').reasoningOnly,
        isFalse,
      );
    });

    test('GLM 旧系 / DeepSeek 不受 disableThinking 影响', () {
      expect(classifyLlmModel('glm-4').disableThinking, isFalse);
      expect(classifyLlmModel('glm-4-flash').disableThinking, isFalse);
      expect(classifyLlmModel('deepseek-chat').disableThinking, isFalse);
      expect(classifyLlmModel('deepseek-reasoner').disableThinking, isFalse);
      expect(classifyLlmModel('gpt-4o').disableThinking, isFalse);
      expect(classifyLlmModel('qwen-plus').disableThinking, isFalse);
    });

    test('doubao-seed 深度思考系 → disableThinking=true（默认思考控延迟）', () {
      expect(
        classifyLlmModel('doubao-seed-2.1-turbo').disableThinking,
        isTrue,
      );
      expect(classifyLlmModel('doubao-seed-2.1-pro').disableThinking, isTrue);
      expect(classifyLlmModel('doubao-seed-1.6-flash').disableThinking, isTrue);
      expect(classifyLlmModel('doubao-seed-2.1-turbo').reasoningOnly, isFalse);
    });

    test('doubao 无思考能力变体 / kimi-k3 不受 disableThinking 影响', () {
      // doubao-seed-character 无版本号（不带深度思考能力标签），不命中
      expect(
        classifyLlmModel('doubao-seed-character-251128').disableThinking,
        isFalse,
      );
      expect(classifyLlmModel('doubao-pro-32k').disableThinking, isFalse);
      // kimi-k3 始终思考且不应传 thinking 参数；reasoning_content 由解析层忽略
      expect(classifyLlmModel('kimi-k3').disableThinking, isFalse);
      expect(classifyLlmModel('kimi-k3').reasoningOnly, isFalse);
    });
  });
}
