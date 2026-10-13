// ─────────────────────────────────────────────────────────────
// teaching_labels — L-UI 层教学话术单一真源（R-027 Task A · L-UI 落地批）
//
// 收敛 D7 话术溯源批坐实的全库手抄漂移，三组用户可见标签一处定义：
//   1. kSeverityLabels       严重度 L1-L3 中文标签
//   2. kTeachingStateLabels  教学状态机四态中文标签
//   3. kConfirmationBarText    诊断确认栏五态文案表（治 §4-194 病灶）
//
// 纪律：只允许在本文件一处改文案；其他位置经本表 / 函数读取，
//       不得自写 Map / switch。本文件为纯 UI 展示层常量，不依赖 services/，
//       仅依赖 types/teaching_types.dart（依赖方向单向向上）。
// ─────────────────────────────────────────────────────────────

import '../types/teaching_types.dart';

/// 严重度 L1-L3 → 用户可见标签（唯一真源）。
///
/// 历史漂移：diagnosis_card / growth_detail_widgets / syndrome_history_list /
/// syndrome_detail_modal / partial_agreement_card 五处手抄同一份 switch，
/// task_panel 更曾用「建议/注意/严重」另一套词。统一为「轻微/中等/严重」。
const Map<String, String> kSeverityLabels = {
  'L1': '轻微',
  'L2': '中等',
  'L3': '严重',
};

/// 严重度中文标签（未知档统一兜底「轻微」，对齐各调用方原 `_ => '轻微'`）。
String severityLabel(String? level) => kSeverityLabels[level] ?? '轻微';

/// 教学状态机 → 用户可见标签（唯一真源）。
///
/// 历史漂移（≥3 份手抄）：teaching_state_badge（刚识别/训练中/趋稳中/已掌握）、
/// growth_detail_syndrome_groups（待诊断/练习中/巩固中）、
/// focus_card_builder（已识别/教学中/巩固中）。统一为：
/// identified→刚识别 / inProgress→训练中 / consolidating→趋稳中 / mastered→已掌握。
const Map<TeachingState, String> kTeachingStateLabels = {
  TeachingState.identified: '刚识别',
  TeachingState.inProgress: '训练中',
  TeachingState.consolidating: '趋稳中',
  TeachingState.mastered: '已掌握',
};

/// 教学状态中文标签（兜底退回枚举名，不暴露英文枚举给用户时调用方应自行判空）。
String teachingStateLabel(TeachingState state) =>
    kTeachingStateLabels[state] ?? state.name;

/// 诊断确认栏五态文案表（唯一真源；治 §4-194 不认同/不适用绑定病灶）。
///
/// 每态 = [状态行主文案, 副提示文案]；副提示中 `{name}` 由调用方运行时替换为症候名。
///
/// ★ §4-194 边界（两态必须分治）：
///   - disputed（不认同 / 提出异议）= 仅「记下了你的反对意见」，
///     绝不出现「不适用」字样，副提示指向「继续补充沟通」。
///   - dismissed（永久静音 / 写作类型声明）= 「不适用」语义的唯一合法归属
///     （落库 disabledIds，成长页 → 教学设置可恢复）。
const Map<String, List<String>> kConfirmationBarText = {
  // 提问态：问题句；副提示留空（认同/部分认同/不认同按钮行另行渲染）。
  'pending': ['这个诊断符合你的实际情况吗？', ''],
  'confirmed': ['已认同', '可以开始针对「{name}」的练习'],
  'partial': ['部分认同', '建议继续沟通确认'],
  // 异议：只是「已记录异议」，不是「这条诊断作废 / 不适用」。
  'disputed': ['已记录异议', '可在对话中补充哪里不对'],
  // 永久静音：「不适用」语义的唯一合法归属（成长页可恢复）。
  'dismissed': ['已关闭', '以后不再提示（成长页可恢复）'],
};
