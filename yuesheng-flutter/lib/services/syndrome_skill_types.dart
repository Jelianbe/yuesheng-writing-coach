// ─────────────────────────────────────────────────────────────
// 症候技能层级类型（ADR-C70：解 `syndrome_registry ↔ syndrome_skill_levels` 环）
//
// 为什么单独成文件：
//   syndrome_registry.dart 只需要 SkillLevel 这个**类型**，
//   syndrome_skill_levels.dart 需要 registry 的**派生数据**
//   （kSyndromeSkillLevelsDerived）。两者互相需要，形成循环。
//   把类型这一层抽出来后依赖变为单向：
//     registry      → syndrome_skill_types   （只要类型）
//     skill_levels  → registry + types       （要数据 + 类型）
//
// 对外 API 不变：syndrome_skill_levels.dart 用 `export` 透传本文件，
// 既有的 `import 'syndrome_skill_levels.dart'` 一行都不用改。
//
// 为何只搬 SkillLevel、不连 InterventionLevel 一起搬（R-010 最小化范围）：
//   本环只由 SkillLevel 引起，InterventionLevel 暂留 syndrome_skill_levels.dart。
//   待它也被 registry 侧需要时再一并迁出，避免现在做无依据的推测性改动。
// ─────────────────────────────────────────────────────────────

/// 技能层级（V2.0 §2.1：基础表达 → 叙事节奏 → 角色塑造 → 情节结构 → 风格声线）
enum SkillLevel {
  l1('L1', '基础表达'),
  l2('L2', '叙事节奏'),
  l3('L3', '角色塑造'),
  l4('L4', '情节结构'),
  l5('L5', '风格声线');

  final String value;
  final String label;

  const SkillLevel(this.value, this.label);
}
