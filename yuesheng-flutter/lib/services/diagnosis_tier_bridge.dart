// ─────────────────────────────────────────────────────────────
// diagnosis_tier_bridge — 「写作阶段」偏好 → 学员技能层级的桥
//
// ★ B6-N（2026-10-06）：把原本零消费的 `DiagnosisPrefs.tier` 接进**已有的**
//   分级诊断库链路，使 UI 上的三个选项真正生效。
//
// ── 为什么不是「新增一套分级」 ──
//   实测（`syndrome_skill_levels.dart`）：**分级诊断库已存在且完整**——
//     · 五层技能层级 L1 基础表达 / L2 叙事节奏 / L3 角色塑造 / L4 情节结构 / L5 风格声线
//       （由 `kSyndromeSkillLevelsDerived` 从注册表派生，非手写）
//     · 学员层级映射 `skillLevelForBeginner`（N0/N1→L1 · N2→L2 · N3→L3 · N4→L4）
//     · 已接两处生效点：`message_injector._injectStudentSkillLevelGuidance`
//       （注入「优先给当前层级+1 以内的问题做重点反馈」）
//       + `focus_resolver._preferLevelAppropriate`（focus fallback 排序降级）
//   但它的真源是 `teaching_state.beginner_level`（冷启动「写作水平」采集），
//   而 UI 上让用户选的是**另一套** `DiagnosisPrefs.tier`（写作阶段）——
//   ⇒ 影子开关：tier 此前**零消费**，只驱动那行后缀词。
//   本文件只做**桥接**（tier → SkillLevel），不新增注入块、不改正文prompt。
//
// ── ★ 与 2026-09-26「方案 A」决策的关系（必须说清，否则等于翻案）──
//   `DiagnosisPrefs` 类注释记着：旧版 ADR §三曾把 tier/genre **硬映射成禁用维度**
//   （beginner 禁 L2–L5 等），2026-09-26 已**撤销**，理由是「硬编码档位过滤会把
//   编辑部裁决与 tier×genre 分类学提前焊死」。
//   ⇒ 本桥接**不违反**该决策：它**不生成任何禁用集**
//   （`effectiveDisabledIds` 仍只并用户手动关闭的 `disabledIds`），
//   而是走既有的「软引导」通道 —— 与 `skillLevelForBeginner` 的输出同形，
//   且同样遵守 `syndrome_skill_levels.dart` 头注的成文红线：
//   **「层级是软引导，不是硬拦截——AI 建议不受限，仅 fallback 排序优先
//     当前层级+1 以内的症候」**。
//
// ── 优先级规则（显式选择 > 系统采集）──
//   `resolveSkillLevelFromTier(tier, beginnerLevel)`：
//     · tier 已设 ⇒ 用 tier 映射的层级（**用户显式选择优先**）
//     · tier 未设（null）⇒ 回退 beginnerLevel（冷启动采集的真链路，保持原行为）
//   理由：tier 是用户当下的**主动**表达，beginner_level 是**一次性的**入门自评；
//   用户能随时改前者、却不会去改后者 ⇒ 前者应优先。
//   ⚠️ 但**不写库**：tier 覆盖只在内存中生效（见`chat_service._prepareTeachingState`
//   的注释），因为写 `teaching_state.beginner_level` 会污染冷启动采集的语义
//   （那列有CHECK 约束与「入门自评」含义）。零 schema 改动 ⇒ 不触 R-027。
// ─────────────────────────────────────────────────────────────

import '../types/teaching_types.dart';
// skillLevelForBeginner + SkillLevel（后者由本文件 re-export，保持对外 API 不变）
import 'syndrome_skill_levels.dart';

/// 写作阶段偏好 → 学员等级（`BeginnerLevel`）的唯一映射表。
///
/// ★ 为什么映射到 `BeginnerLevel` 而不是直接给 `SkillLevel`：
///   接入点 `_prepareTeachingState`（`chat_service.dart:735`）手上只有
///   `BeginnerLevel`，而 `message_injector` / `focus_resolver` 才在**各自内部**
///   调 `skillLevelForBeginner` 转成层级。⇒ 桥接到 `BeginnerLevel` 就能
///   **一处接入、全链生效**，且让 `isBeginner`（同处派生）自动跟着变——
///   若绕开它直接给层级，`isBeginner` 会与实际层级**不一致**（用户选了
///   「想被挑刺」却仍被当新手门控），那才是新的错位。
///
/// 取值依据（两处真实文本，不臆造）：
///   · tier 三档文案见 `growth_diagnosis_prefs_card.dart` `_tiers`：
///       '先写顺'（把基础语病讲透，结构与节奏先不急）
///       '完整故事'（文字、角色、结构都管）
///       '想被挑刺'（全开，连细微毛病也点出来）
///   · `BeginnerLevel` 语义见 `onboarding_flow.dart` `kProficiencyExamples`：
///       N1「写过一些片段」/ N3「有完整作品」/ N4（独立·最高档）
///   逐档对照取「覆盖面与该档文案相符」的那一级（见每行注释）。
///     先写顺   → N1（≈L1 基础表达：只扫字句层，与「结构与节奏先不急」一致）
///     完整故事 → N3（≈L3 角色塑造：文字/角色/结构都管，取覆盖中位）
///     想被挑刺 → N4（≈L4 情节结构：能覆盖结构层与更高层级，与「全开」一致）
///
/// ⚠️ **为什么不用 N0/N2**：N0「刚开始写作」比 N1 更低，与「先写顺」的
///   实际语义（已能写、只是不求全）不符；N2「能写完整场景」与 N3「有完整作品」
///   语义重叠，硬塞会让「完整故事」低于N3 自评用户的实际水平⇒ 反而**收紧**
///   了本该放开的层级。若将来 tier 要四档，宁可加第四个选项，也不要在
///   映射表里做隐式插值。
const Map<String, BeginnerLevel> kTierToBeginnerLevel = {
  'beginner': BeginnerLevel.n1Elements, // 先写顺 ≈ L1 基础表达
  'story': BeginnerLevel.n3Diagnose, // 完整故事 ≈ L3 角色塑造
  'full': BeginnerLevel.n4Independent, // 想被挑刺 ≈ L4 情节结构
};

/// 该 tier 映射到的技能层级（供 UI 展示「这一档大致管到哪一层」用）。
///
/// 走既有真链路换算（`skillLevelForBeginner`）⇒ **不重复维护第二张层级表**，
/// 避免「tier 表与层级表各改一处」的那种漂移。
SkillLevel? skillLevelFromTier(String? tier) {
  if (tier == null || tier.isEmpty) return null;
  final lv = kTierToBeginnerLevel[tier];
  return lv == null ? null : skillLevelForBeginner(lv);
}

/// 统一入口：**tier 优先，beginner_level 兜底**。
///
/// 返回 null 表示「两者都无信号」⇒ 调用方按原行为处理（不限制层级）。
BeginnerLevel? resolveBeginnerLevelFromTier({
  required String? tier,
  required BeginnerLevel? beginnerLevel,
}) {
  // 显式选择优先
  if (tier != null && tier.isNotEmpty) {
    final fromTier = kTierToBeginnerLevel[tier];
    if (fromTier != null) return fromTier;
  }
  // 兜底：走既有真链路（冷启动采集的写作水平）
  return beginnerLevel;
}

/// 该 tier 值是否是已登记的映射键（供 UI 校验存量数据是否合法）。
bool isKnownTier(String? tier) =>
    tier != null && kTierToBeginnerLevel.containsKey(tier);
