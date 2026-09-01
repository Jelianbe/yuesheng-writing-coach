// ─────────────────────────────────────────────────────────────
// skill_registry 数据分片：advanced-phases 阶段裁剪（Phase 3 A 组）
// ─────────────────────────────────────────────────────────────
// 背景：方案 Phase 3 原定「L2 索引 + L3 按需检索」，但复查生产链路后
// 确认检索无触发源——dispatcher 的 injectL3 在生产代码零调用点，生产
// 侧 L3 注入仅由 focusSyndromeId 驱动（症候/技法/训练模板），而六块
// 没有对应 focus 信号；X-043 已评估并否决主题词扫描（架构 §4.7）。
// 故改为**状态驱动裁剪**：按 ctx.phase 只注入当前阶段所需分段。
//
// 与索引化的区别：不依赖检索、不会因检索不触发而丢失知识；原文一字
// 未改，切片均为原文子串（非 P3/P4 阶段返回完整原文，字节一致）。
//
// 裁剪策略：
//   P3_TRAINING → 前言 + P3 段 + P3 态度 + (P3→P4 + 迁移约束)
//   P4_REVIEW   → 前言 + P4 段 + P4 态度 + (P4→P2 + 迁移约束)
//   其它阶段     → 完整原文（行为与现状完全相同）
// P5 段已删除（C56 幽灵阶段：TeachingPhase 无 P5 枚举值，原切片只裁掉了
// 「段」却注入了「通往 P5 的指令」，见 ADR-C54 §9 方案 D）；
// 已发生的迁移（P2→P3、P3→P4 在 P4 档）同样不注入。
// ─────────────────────────────────────────────────────────────
part of 'skill_registry.dart';

/// 原文 `## ` 级标题（切片锚点，与 skills_advanced_outline_p4/p5.dart 逐字对应）
const String _apHead3 = '## P3_TRAINING（深度训练阶段）';
const String _apHead4 = '## P4_REVIEW（复盘阶段）';
const String _apHeadAttitude = '## 进阶阶段态度调整';
const String _apHeadTransition = '## 阶段迁移规则';

/// 原文 `### ` 级子段锚点
const String _apAttitude3 = '### P3 态度策略';
const String _apAttitude4 = '### P4 态度策略';
const String _apMoveP3toP4 = '### P3 → P4';
const String _apMoveP4Out = '### P4 → P2（重新开始）';
const String _apMoveConstraint = '### 迁移约束';

/// 取 [start] 到 [end] 之间的原文片段（[end] 未命中则取到文末）
String _apSlice(String raw, String start, String end) {
  final s = raw.indexOf(start);
  if (s < 0) return '';
  final e = raw.indexOf(end, s + start.length);
  return raw.substring(s, e < 0 ? raw.length : e).trim();
}

/// 取 [start] 至文末的原文片段
String _apSliceToEnd(String raw, String start) {
  final s = raw.indexOf(start);
  if (s < 0) return '';
  return raw.substring(s).trim();
}

/// advanced-phases 阶段裁剪入口（dispatcher 经 Skill.contentForPhase 调用）。
///
/// 非 P3/P4 阶段返回完整原文（字节一致）；切片全部为原文子串，故不存在
/// 编辑漂移（由 test/services/advanced_phases_phase_slice_test.dart 断言）。
String advancedPhasesContentFor(TeachingPhase phase) {
  const raw = _advancedPhasesBody1 + _advancedPhasesBody2;

  // 非进阶阶段（或阶段未知）→ 完整原文，与现状逐字节一致
  if (phase != TeachingPhase.p3Training && phase != TeachingPhase.p4Review) {
    return raw;
  }

  final headEnd = raw.indexOf(_apHead3);
  if (headEnd < 0) return raw; // 防御性兜底（R-028）：结构不符则原样返回
  final head = raw.substring(0, headEnd).trim();

  final isP3 = phase == TeachingPhase.p3Training;
  final main = isP3
      ? _apSlice(raw, _apHead3, _apHead4)
      : _apSlice(raw, _apHead4, _apHeadAttitude);
  final attitude = isP3
      ? _apSlice(raw, _apAttitude3, _apAttitude4)
      : _apSlice(raw, _apAttitude4, _apHeadTransition);
  final moveNext = isP3
      ? _apSlice(raw, _apMoveP3toP4, _apMoveP4Out)
      : _apSlice(raw, _apMoveP4Out, _apMoveConstraint);
  final moveConstraint = _apSliceToEnd(raw, _apMoveConstraint);

  return [
    head,
    main,
    '$_apHeadAttitude\n\n$attitude',
    if (moveNext.isNotEmpty) '$_apHeadTransition\n\n$moveNext',
    if (moveConstraint.isNotEmpty) moveConstraint,
  ].join('\n\n');
}
