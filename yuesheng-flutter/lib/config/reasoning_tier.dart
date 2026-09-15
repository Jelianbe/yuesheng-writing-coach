// ─────────────────────────────────────────────────────────────
// reasoning_tier — 推理强度档位（「思考开关」的用户可调真源）
//
// 背景（TH 批实测 2026-09-15，详见 docs/audits/TH批-thinking开关评估*.md）：
//   `deepseek-flash` 默认思考开启（llm_model_profile.dart:54-57 不命中
//   disableThinking）⇒ 输出侧是成本与首字延迟的唯一大头（生产稳态下
//   输出占整请求 93.4%）。实测：`thinking:{"type":"disabled"}` ⇒
//   输出 −82.9%、延迟 −78.9%；`reasoning_effort` 亦生效（max 3.8×、
//   low −31%）。**但关思考的效果随场景翻转**（诊断零退化，教学场景
//   6/6 任务失败）⇒ 故不做全局硬编码，改为**用户可调档位**。
//
// 本文件是「档位 → 请求体补丁」的**唯一真源**：
//   UI（设置页）只引用 [reasoningTierPresets]；请求体构建只调用
//   [reasoningBodyPatchFor]。默认档 [reasoningTierStandard] 返回空 map
//   ⇒ 请求体逐字节不变（既有请求体锚点测试零影响）。
//
// 与 [LlmModelProfile.disableThinking] 的关系（合并顺序 = 模型画像先、
// 档位后）：模型画像是最小安全兜底（GLM thinking 系防退化乱码），
// 档位是用户显式意图。二者同键时**档位值覆盖画像值**（用户显式优先），
// 但 [reasoningTierStandard] 不产键 ⇒ 画像行为保持。
//
// 「开关」与「档位」的关系（两种 UI 入口共用本文件判定，避免双真源）：
//   输入框上方的二值开关 = 当前档位是否 [reasoningTierOff]。关闭时先把
//   开启态档位记入 [kReasoningTierLastOnKey]，再开时经 [restoredOnTier]
//   恢复 ⇒ 用户设的「深度」不会因一次关/开被静默重置为「标准」。
// ─────────────────────────────────────────────────────────────

/// 档位 key：标准（不干预，生产现状）。
const String reasoningTierStandard = 'standard';

/// 档位 key：轻量（降低推理强度，保留思考）。
const String reasoningTierLow = 'low';

/// 档位 key：深度（提高推理强度）。
const String reasoningTierDeep = 'deep';

/// 档位 key：关闭思考（最快最省；教学类场景有任务失败实测风险）。
const String reasoningTierOff = 'off';

/// app_state 存储键（AppStateRepository.getValue / setValue）。
const String kReasoningTierKey = 'reasoning_tier';

/// app_state 存储键：开关「关」之前的最后开启态档位（供开关恢复）。
const String kReasoningTierLastOnKey = 'reasoning_tier_last_on';

/// 推理档位预设（key 为存储值，bodyPatch 为请求体补丁）。
class ReasoningTierPreset {
  final String key;

  /// 界面展示名。
  final String label;

  /// 界面副文案（说明代价与适用场景）。
  final String hint;

  /// 请求体补丁；空 map = 不干预请求体。
  final Map<String, dynamic> bodyPatch;

  const ReasoningTierPreset({
    required this.key,
    required this.label,
    required this.hint,
    required this.bodyPatch,
  });
}

/// 档位预设列表（顺序即界面顺序；首个为默认档）。
const List<ReasoningTierPreset> reasoningTierPresets = [
  ReasoningTierPreset(
    key: reasoningTierStandard,
    label: '标准',
    hint: '默认，不干预模型推理行为',
    bodyPatch: {},
  ),
  ReasoningTierPreset(
    key: reasoningTierLow,
    label: '轻量',
    hint: '降低推理强度：回复更快，深度思考减弱',
    bodyPatch: {'reasoning_effort': 'low'},
  ),
  ReasoningTierPreset(
    key: reasoningTierDeep,
    label: '深度',
    hint: '提高推理强度：思考更充分，耗时与消耗明显增加',
    bodyPatch: {'reasoning_effort': 'max'},
  ),
  ReasoningTierPreset(
    key: reasoningTierOff,
    label: '关闭思考',
    hint: '最快最省，但教学回复可能过于简短',
    bodyPatch: {
      'thinking': {'type': 'disabled'},
    },
  ),
];

/// key → 预设（未命中 / null 回退标准档，保证旧数据与前向兼容）。
ReasoningTierPreset reasoningTierOf(String? key) {
  for (final preset in reasoningTierPresets) {
    if (preset.key == key) return preset;
  }
  return reasoningTierPresets.first;
}

/// 档位 → 请求体补丁（标准档返回**空 map**，调用方据此跳过合并）。
Map<String, dynamic> reasoningBodyPatchFor(String? key) =>
    reasoningTierOf(key).bodyPatch;

/// 思考是否开启（档位 ≠ [reasoningTierOff] 即开启；null / 未知 key ⇒ 标准档 ⇒ 开启）。
bool isThinkingEnabled(String? tierKey) =>
    reasoningTierOf(tierKey).key != reasoningTierOff;

/// 开关由「关」切回「开」时恢复的档位（上次开启态档位；null / off / 未知 → 标准档）。
String restoredOnTier(String? lastOnKey) {
  final preset = reasoningTierOf(lastOnKey);
  return preset.key == reasoningTierOff ? reasoningTierStandard : preset.key;
}
