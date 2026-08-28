// ─────────────────────────────────────────────────────────────
// 能力契约层 — 教学能力接口
//
// 架构评审（2026-08-18）选项 A：能力契约层骨架。
// 选项 B（依赖倒置）：TeachingCapability 自持教学 DTO（L2Mode /
// SkillLoadContext / L3RetrievalContext / SystemPromptResult），
// 不 import 任何实现文件，避免契约↔实现的循环依赖（门禁 3）。
//
// 实现映射（Dependency Inversion）：
//   class TeachingCapabilityImpl (lib/services/skill_dispatcher.dart)
//   implements TeachingCapability，委托到既有纯函数
//   buildSystemPromptV2 / resolveL2Mode。
//
// ADR: docs/ADR-capability-contracts.md
// ─────────────────────────────────────────────────────────────

import '../types/teaching_types.dart';

/// L2 加载模式：决定注入哪组 skill（DTO 上移至契约层，原定义于 skill_layers.dart）
enum L2Mode {
  beginner,
  diagnosis,
  training,
  advanced,
  outline,
  none;

  static L2Mode fromString(String? s) {
    if (s == null) return L2Mode.none;
    for (final v in L2Mode.values) {
      if (v.name == s) return v;
    }
    return L2Mode.none;
  }
}

/// Skill 加载上下文（DTO 上移至契约层，原定义于 skill_layers.dart）
class SkillLoadContext {
  final TeachingPhase phase;
  final AttitudeLevel attitude;
  final TeachingSubphase? subphase;
  final bool isBeginner;
  final bool isOutlineContext;

  const SkillLoadContext({
    required this.phase,
    required this.attitude,
    this.subphase,
    this.isBeginner = false,
    this.isOutlineContext = false,
  });
}

/// L3 检索上下文：驱动按需检索特定症候/技法详细内容
///（DTO 上移至契约层，原定义于 skill_layers.dart）
class L3RetrievalContext {
  final List<String>? activeSyndromeIds;
  final List<String>? focusedTechniqueIds;

  const L3RetrievalContext({this.activeSyndromeIds, this.focusedTechniqueIds});
}

/// L2 组内挂载引用（ADR-skill-orthogonal-model.md Phase 2 方案 A）。
///
/// 共享本体只存一份 content；各组挂载时通过 [contextHint] 附加「语境适配指令」
/// （50-150 tokens），描述该组场景下如何使用该 skill，避免为每组复制整块内容。
/// [contextHint] 为 null 时退化为纯 skillId 语义（与旧 `List<String>` 等价）。
class SkillRef {
  final String skillId;
  final String? contextHint;

  const SkillRef(this.skillId, [this.contextHint]);
}

/// buildSystemPromptV2 返回的结构化结果
///（DTO 上移至契约层，原定义于 skill_dispatcher.dart）
class SystemPromptResult {
  /// L1 + L2 拼接后的完整 system prompt（可直接传给 LLM）
  final String systemPrompt;

  /// 当前生效的 L2 模式（供调用方了解加载了哪些技能组）
  final L2Mode l2Mode;

  /// 已加载的 skill ID 列表（含 L1 + L2，用于调试和 token 核算）
  final List<String> loadedSkillIds;

  /// 估算的 token 数（基于字符数 × 中文 token 比例）
  final int estimatedTokens;

  /// L3 检索注入函数。
  ///
  /// 调用方在确定了活跃症候/聚焦技法后调用此函数，
  /// 返回应追加到 system prompt 末尾的详细内容。
  final String Function(L3RetrievalContext ctx) injectL3;

  const SystemPromptResult({
    required this.systemPrompt,
    required this.l2Mode,
    required this.loadedSkillIds,
    required this.estimatedTokens,
    required this.injectL3,
  });
}

/// 教学能力契约
///
/// 覆盖「教学语境 → skill 三级加载 → system prompt 拼装」链路。
/// UI/编排层经此契约获取当前教学场景的 prompt，不直接依赖 skill 注册表。
abstract class TeachingCapability {
  /// 根据教学语境（阶段/态度/子阶段/零基础标志）构建三级分层 system prompt。
  /// 返回完整 prompt + L2 模式 + 已加载 skill 列表 + token 估算 + L3 注入函数。
  SystemPromptResult buildSystemPrompt(SkillLoadContext ctx);

  /// 根据教学语境决议应加载的 L2 模式。
  L2Mode resolveL2Mode(SkillLoadContext ctx);
}
