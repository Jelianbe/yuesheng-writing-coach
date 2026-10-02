// ─────────────────────────────────────────────────────────────
// persona_structured_constraints — 自定义人格结构化约束组装（ADR-C132 批2）
//
// 定位：把 CoachPersona 的 A 方向结构化字段（表达密度档 / 提问直给偏好 /
// 缓冲词偏好 / emoji 许可）组装成**自然语言约束段**，由 skill_dispatcher
// 在用户预设激活时随 fragment 注入（persona 层组装，ADR §5）。
//
// 契约：
//  - 全部字段为空 → 返回空串（不产生任何注入块，系统预设路径不受影响）
//  - 字段值非法（如 'loud' 不在枚举内）→ 静默忽略该字段（防御性，不报错）
//  - 边界句（kPersonaRedLine）与全局 R-009 红线**同源不重复**：
//    核心语义 = chat_service 已注入的「不替用户写句子、不替用户做决定」，
//    此处只做人格上下文适配，不另立新红线。
//
// R-009 适配：提问直给偏好是**注入层倾向声明**，不改全局教学方式开关
// 裁决权（ADR §5 用户已批准）——约束文本明确写出「遵守教学方式开关裁决」。
// ─────────────────────────────────────────────────────────────

import '../types/coach_persona.dart';

/// 表达密度档合法值。
const List<String> kExpressionDensityValues = ['low', 'medium', 'high'];

/// 提问直给偏好合法值。
const List<String> kQuestionPreferenceValues = ['question', 'direct'];

/// 缓冲词偏好合法值。
const List<String> kBufferWordValues = ['none', 'light', 'warm'];

/// 人格红线（R-009 边界句，用户预设路径自动附加；同源见文件头注释）。
///
/// F-1 口径（ADR-C134 批1，用户已裁定）：红线 = 禁替写成稿 / 成品段落；
/// 教学示范单句受限（为说明改法可给单句示范，不改全段、不替写成品段落）。
/// 示范 ≠ 替写：示范是教学动作（指向根因），替写是代产成品，二者边界在此句写死。
const String kPersonaRedLine =
    '【人格红线】以上语气设定不改变 R-009 边界：不替学员写句子、'
    '不替学员做决定、不给处方；直给判断只指根因与方向；'
    '教学示范单句受限：为说明改法可给单句示范，不改全段、不替写成品段落；'
    '禁成段成品与打分。';

/// 把结构化字段组装为约束段（全空 = ''，不产生注入块）。
///
/// 非法值静默忽略（防御性）：字段是用户自由文本映射而来，不因脏数据
/// 让整个注入链失败。
String buildStructuredConstraints(CoachPersona p) {
  final parts = <String>[];
  switch (p.expressionDensity) {
    case 'low':
      parts.add('表达密度：简洁克制，少堆砌修饰语。');
    case 'medium':
      parts.add('表达密度：适中，点到为止。');
    case 'high':
      parts.add('表达密度：可以铺陈充分，把话说明白。');
  }
  switch (p.questionPreference) {
    case 'question':
      parts.add('提问直给偏好：倾向用提问引导学员思考（遵守教学方式开关的裁决）。');
    case 'direct':
      parts.add('提问直给偏好：倾向直接指出问题与方向（遵守教学方式开关的裁决）。');
  }
  switch (p.bufferWordPreference) {
    case 'none':
      parts.add('缓冲词偏好：避免使用「也许 / 可能 / 不妨」类缓冲词。');
    case 'light':
      parts.add('缓冲词偏好：克制使用，仅在必要时出现。');
    case 'warm':
      parts.add('缓冲词偏好：可以多用温和缓冲词，让语气更软。');
  }
  if (p.emojiAllowed == true) {
    parts.add('emoji：可以少量使用，辅助表达语气。');
  } else if (p.emojiAllowed == false) {
    parts.add('emoji：不使用。');
  }
  return parts.join('\n');
}
