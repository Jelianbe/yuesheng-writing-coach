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

import '../types/coach_persona.dart';
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
  final TeachingMode teachingMode;
  final TeachingSubphase? subphase;
  final bool isBeginner;
  final bool isOutlineContext;

  /// 诊断编辑器：用户永久关闭（「不适用于我」）的症候 ID 集合。
  /// 空集 = 全启用（历史行为）。非空时 L2 索引表剔除对应行。
  final Set<String> disabledSyndromeIds;

  /// D1/D2 Phase 2：当前激活教练人格。
  ///
  /// - null / 系统预设：走原态度档位注入（attitude-*，快照锁守护，逐字节不变）。
  /// - 用户自定义人格（isSystem == false）：注入其 [CoachPersona.systemPromptFragment]
  ///   替代默认态度档位内容（用户人格 = 用户选择的固定语气）。
  final CoachPersona? activePersona;

  /// P1-4：当前消息措辞触发了诊断协议注入，但 l2Mode 并非 diagnosis 阶段时，
  /// 强制注入「先建现场再归类」护栏（否则 P3 阶段裸奔诊断：协议要求 JSON 输出，
  /// 却拿不到症候字典和现场引导）。
  final bool forceDiagnosisSceneFirst;

  /// W-45 窄改①（2026-10-20 舰长批准，触 R-027）：**被诊断文本在全书中的真实位置**。
  ///
  /// 背景（实测见 `.ai/reports/2026-10-20-W45-抽核回执与位置维度调查.md`）：
  /// 「位置敏感」四层实现早已在场，但位置是**猜**的 —— 位置块明写
  /// 「内容过短（< 1000 字）难以判断 ⇒ 判【全局】」。240 格实测 P002 命中率
  /// `<1000` 字组 **39.2%** vs `≥1000` 字组 **93.6%**，差 54pp **全部来自这条猜测规则**
  /// 而非文本质量 ⇒ P002 在长文组失去区分力（恒报）。
  ///
  /// [chapterOrder] = 该章在全书中的**位次（1 基，含本章）**，不是 DB 的
  /// `Chapters.sortOrder` —— 实测该列**0 基且 0/1 混用**
  /// （`outputs/ev3.db` 中 `233efaae` 的「第一章 风起」存的是 `sort_order=1`），
  /// 直接透传会把第一章说成第二章。调用方须先归一化。
  ///
  /// [totalChapters] = 全书总章数。用于让「开头/中段/结尾」可由位次直接判定。
  ///
  /// **两者皆 null ⇒ 位置块逐字节不变**（锚点零漂移的依据）；非 null 时
  /// 在 [kPositionGuidanceConstSection] 之后追加一段「已知位置」，并**覆盖**
  /// 原「过短 ⇒ 判全局」的兜底（真实位次是比字数更强的证据）。
  final int? chapterOrder;
  final int? totalChapters;

  const SkillLoadContext({
    required this.phase,
    required this.attitude,
    this.teachingMode = TeachingMode.socratic,
    this.subphase,
    this.isBeginner = false,
    this.isOutlineContext = false,
    this.disabledSyndromeIds = const {},
    this.activePersona,
    this.forceDiagnosisSceneFirst = false,
    this.chapterOrder,
    this.totalChapters,
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
  ///
  /// ★ 当前生产未接线：`focusedTechniqueIds` 无生产构造点，本函数仅由
  /// `skill_prompt_anchor_test.dart` 锚定；生产技法注入真源 =
  /// `chat_context_builder.dart` → `getTechniquesBySyndrome`。勿删该真路径。
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
  ///
  /// [modeOverride]（U2 · 2026-09-15）：非 null 时**强制**使用该 L2 组，
  /// 跳过 [resolveL2Mode] 的决议结果 —— 用于 L2 路由迟滞
  ///（见 lib/services/l2_route_hysteresis.dart），消掉训练轮结束后的自动回切。
  /// 默认 null ⇒ 行为与改造前**逐字节等价**（两处锚点零漂移的依据）。
  /// 覆盖时返回值 [SystemPromptResult.l2Mode] 与实际装配的 skill 组**必然一致**
  ///（由 buildSystemPromptV2 内「一处决议、向下传递」保证）。
  SystemPromptResult buildSystemPrompt(
    SkillLoadContext ctx, {
    L2Mode? modeOverride,
  });

  /// 根据教学语境决议应加载的 L2 模式。
  L2Mode resolveL2Mode(SkillLoadContext ctx);
}
