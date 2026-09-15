// ─────────────────────────────────────────────────────────────
// LLM 模型参数画像（ADR-C83 引入；ADR-C94 从 llm_client.dart 拆出独立文件，
// 承 ADR-C74「新逻辑独立类」纪律：画像分类逻辑自成一体，便于测试与扩充）
// ─────────────────────────────────────────────────────────────

/// OpenAI 兼容模型的参数画像（ADR-C83：扩展多供应商）。
///
/// 差异点：
/// - OpenAI o 系列推理模型（o1/o3/o4/gpt-5）：不支持 `temperature`，
///   `max_tokens` 需改用 `max_completion_tokens`，否则请求 400；
/// - GLM thinking 系（glm-4.5+ / 含 thinking 的 glm 变体，如
///   glm-4.1v-thinking-flash）：思考模式在复杂长 prompt 下易退化输出
///   （[gMASK] 复读 / 乱码，sglang + z.ai 实证），请求体显式关闭
///   thinking（`{"type":"disabled"}`）规避；temperature/max_tokens 照常。
/// - DeepSeek 系与其他 OpenAI 兼容端点：`max_tokens` + `temperature`
///   均支持（现状保持不变）；deepseek 系另挂空流兜底名单标记
///   （[fallbackDisableThinking]，ADR-C94）。
class LlmModelProfile {
  /// true = 推理优先模型：禁 temperature，用 max_completion_tokens
  final bool reasoningOnly;

  /// true = GLM thinking 系：请求体注入 `thinking: {type: disabled}`
  ///（防思考退化乱码；DeepSeek/OpenAI 保持 false 不受影响）
  final bool disableThinking;

  /// true = deepseek 系：流式「空流」（零 content token 且流干净结束，
  /// ADR-C94 §3.4 判据；不要求达成 [DONE]）时允许注入
  /// `thinking: {type: disabled}` 兜底
  /// 重试（§3.3 分级降级）。**仅降级时生效**——尝试 1 请求体保持原参数，
  /// 成功路径零行为变更（C80 §3.1 价值承袭）。
  final bool fallbackDisableThinking;

  const LlmModelProfile({
    required this.reasoningOnly,
    this.disableThinking = false,
    this.fallbackDisableThinking = false,
  });
}

/// 按模型名识别参数画像（纯函数，前缀匹配、大小写不敏感）。
/// 仅识别 OpenAI o 系列推理模型、GLM thinking 系与 deepseek 空流兜底名单；
/// 其余走通用 OpenAI 行为。
LlmModelProfile classifyLlmModel(String model) {
  final m = model.toLowerCase().trim();
  final reasoningOnly =
      RegExp(r'^(o1|o3|o4|gpt-5)([-.]|$)').hasMatch(m) ||
      m.startsWith('o1-') ||
      m.startsWith('o3-') ||
      m.startsWith('o4-');
  // disableThinking：GLM thinking 系（防复杂 prompt 下退化乱码）+ doubao-seed
  // 系（火山方舟深度思考默认开启，简单诊断任务显式关闭以控延迟/成本）。
  // 两者均用 OpenAI 兼容字段 thinking: {"type": "disabled"}。
  // doubao-seed-character 等无深度思考能力的变体不带版本号，不命中。
  final disableThinking =
      RegExp(r'^glm[-_.]?(4\.[5-9]|5|5\.\d|4\.1v)').hasMatch(m) ||
      RegExp(r'^doubao-seed-\d').hasMatch(m) ||
      m.contains('thinking');
  // fallbackDisableThinking（ADR-C94 §3.1）：deepseek 系纳入空流兜底名单
  //（deepseek-chat / deepseek-reasoner / deepseek-v4-flash 等前缀全命中）。
  // 运行时判空成立才注入兜底参数，非 deepseek 模型请求体逐字节不变（AC-3）。
  final fallbackDisableThinking = m.startsWith('deepseek');
  return LlmModelProfile(
    reasoningOnly: reasoningOnly,
    disableThinking: disableThinking,
    fallbackDisableThinking: fallbackDisableThinking,
  );
}
