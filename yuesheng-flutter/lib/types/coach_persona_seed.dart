// ─────────────────────────────────────────────────────────────
// 系统预设教练人格 seed（D1 地基）
//
// 系统预设只承载「选人卡展示 + 兼容壳映射」所需的最小信息；
// 系统预设的真实态度注入仍由 skill_prompt_anchor 快照锁守护
// （见 skills_attitude.dart + chat_context_builder），Phase 2 才评估是否迁移到
// [CoachPersona.systemPromptFragment] 直注。
//
// [systemPromptFragment] 取各态度档「角色定位」首句（skills_attitude.dart:31/94/157），
// 作为声音锚点，不重复搬运完整 skill 正文（避免与快照源漂移）。
// ─────────────────────────────────────────────────────────────

import 'teaching_types.dart';

import 'coach_persona.dart';

/// 内置教练人格（顺序即展示顺序，与 coach_selector_card._coaches 一致）。
const List<CoachPersona> builtInCoachPersonas = [
  CoachPersona(
    id: 'doubao',
    name: '豆包',
    label: '温和，先肯定再给建议，适合刚起步',
    isSystem: true,
    attitudeLevel: AttitudeLevel.doubao,
    systemPromptFragment: '你是用户的写作陪练伙伴，氛围轻松友好，语气温和包容。',
  ),
  CoachPersona(
    id: 'yuesheng',
    name: '月笙如歌',
    label: '有主张但不冷硬，平衡鼓励与指正',
    isSystem: true,
    attitudeLevel: AttitudeLevel.yuesheng,
    systemPromptFragment: '你是用户的写作陪练教练，温柔但有锋芒。',
  ),
  CoachPersona(
    id: 'sensei',
    name: 'sensei',
    label: '严格，直指问题、不留情面',
    isSystem: true,
    attitudeLevel: AttitudeLevel.sensei,
    systemPromptFragment: '你是用户的严格技术教练，专注于写作工艺本身的提升。',
  ),
];

/// 按 id 取系统预设（无 = null）。
CoachPersona? builtInCoachPersonaById(String id) {
  for (final p in builtInCoachPersonas) {
    if (p.id == id) return p;
  }
  return null;
}
