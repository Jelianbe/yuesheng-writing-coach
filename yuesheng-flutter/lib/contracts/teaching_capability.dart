// ─────────────────────────────────────────────────────────────
// 能力契约层 — 教学能力接口
//
// 架构评审（2026-08-18）选项 A：能力契约层骨架。
// 纯接口定义，不改任何现有实现。
//
// 当前实现映射：
//   buildSystemPrompt → lib/services/skill_dispatcher.dart buildSystemPromptV2
//   resolveL2Mode     → lib/services/skill_layers.dart resolveL2Mode
//
// ADR: docs/ADR-capability-contracts.md
// ─────────────────────────────────────────────────────────────

import '../services/skill_dispatcher.dart';
import '../services/skill_layers.dart';

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
