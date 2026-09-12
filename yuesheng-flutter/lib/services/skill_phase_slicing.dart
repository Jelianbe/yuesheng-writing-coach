// ─────────────────────────────────────────────────────────────
// skill_phase_slicing — 技能内容的「按教学阶段裁剪」纯逻辑
//
// 来源：原 `skill_registry.dart` 的两个 A 类 part 分片
//   `skills_beginner_p9.dart`（coaching-rhythm 裁剪）
//   `skills_advanced_outline_p7.dart`（advanced-phases 裁剪）
//   于 P3-R3 迁出为**真 library**——R-019 A 类豁免的前提之一是
//   「分片无逻辑耦合」，而这两处承载的是算法而非常量数据。
//
// ★ 迁移时的关键约束（Dart 库可见性，务必先读）：
//   part 的 `_` 私有性以 **library** 为单位（分片共享宿主 library），
//   而真 library 之间只能通过 public 符号 + import 交互。两个入口原本
//   直接读取**家族私有数据常量**
//     `_coachingRhythmBody1/2`（位于 skills_beginner_p3/p4.dart）
//     `_advancedPhasesBody1/2`（位于 skills_advanced_outline_p4/p5.dart）
//   迁出后不可见 ⇒ 改为**经参数 [raw] 传入原文**，由宿主在挂载点处提供
//   （`contentForPhase: (phase) => coachingRhythmContentFor(phase, ...)`）。
//   ⇒ 本库是**纯逻辑**：不做任何数据引用，输入 (phase, raw) → 输出裁剪串。
//
// 依据 ADR-knowledge-injection-driver-model.md §2.2 裁剪准入三问：
//   1. 信号来源：ctx.phase（教学状态机，确定性来源，非文本猜测）✅
//   2. 信号缺失时退化：非目标阶段返回完整原文；dispatcher 另有
//      `?? skill.content` 兜底 ✅
//   3. 裁掉的段落在当前信号下确定不会被使用（各入口 dartdoc 内详述）✅
//
// 与索引化的区别：不依赖检索、不会因检索不触发而丢失知识；原文一字未改，
// 切片均为原文子串。
// ─────────────────────────────────────────────────────────────

import 'package:writingcoach/types/teaching_types.dart';

// ══════════════════════════════════════════════════════════════
// 一、coaching-rhythm（原 skills_beginner_p9.dart）
// ══════════════════════════════════════════════════════════════

/// 原文 `## ` 级标题（切片锚点，与 skills_beginner_p3/p4.dart 逐字对应）
const String _crHead2 = '## 二、阶段一：建立投入（P0_ENGAGE）';
const String _crHead3 = '## 三、阶段二：暴露问题（P1_WORLD）';
const String _crHead4 = '## 四、从零构建模式（Build-from-Zero）';

/// 取 [start] 到 [end] 之间的原文片段（[end] 未命中则取到文末）
String _crSlice(String raw, String start, String end) {
  final s = raw.indexOf(start);
  if (s < 0) return '';
  final e = raw.indexOf(end, s + start.length);
  return raw.substring(s, e < 0 ? raw.length : e).trim();
}

/// coaching-rhythm 阶段裁剪入口（dispatcher 经 `Skill.contentForPhase` 调用）。
///
/// [raw] = 完整原文，由宿主在挂载点传入
/// （`_coachingRhythmBody1 + _coachingRhythmBody2`，见 skills_beginner_p1.dart）。
///
/// 非 P0/P1 阶段返回完整原文（字节一致）；切片全部为原文子串，故不存在
/// 编辑漂移（由 test/services/coaching_rhythm_phase_slice_test.dart 断言）。
///
/// 裁剪策略：
///   P0_ENGAGE → 头部(含§一总览) + §二(P0 段)   + §四~§七
///   P1_WORLD  → 头部(含§一总览) + §三(P1 段)   + §四~§七
///   其它阶段   → 完整原文（P2 的 beginner / diagnosis 档逐字节不变）
///
/// 裁掉的理由：
///   - §二 P0_ENGAGE 描述「建立投入」阶段的行为，其入口是 phase == p0Engage；
///     P1 档下该入口不存在 → 不可达
///   - §三 P1_WORLD 同理，P0 档下不可达
///   - §一 总览保留：它是 P0→P1→P2 的旅程地图。裁掉非当前阶段的细节段后，
///     AI 仍知道其他阶段存在，只是没有那一段的操作手册
///   - §四~§七 与 phase 无关（从零构建 / Layer 2 认知桥接 / 分工边界 /
///     贯穿 P0-P2 的三层认知模型），全部保留
///
/// 注：skill 头部自述 `loadWhen: P0-P4 全程加载`，与实际不符——
/// resolveL2Mode 仅在 beginner(P0/P1/P2) 与 diagnosis(P2) 组加载它，
/// P3/P4 不加载。该自述不影响本实现（裁剪只在 P0/P1 生效）。
String coachingRhythmContentFor(TeachingPhase phase, String raw) {
  final isP0 = phase == TeachingPhase.p0Engage;
  final isP1 = phase == TeachingPhase.p1World;
  if (!isP0 && !isP1) return raw;

  final headEnd = raw.indexOf(_crHead2);
  final tailStart = raw.indexOf(_crHead4);
  if (headEnd < 0 || tailStart < 0) return raw; // 防御性兜底（R-028）
  final head = raw.substring(0, headEnd).trim();
  final section = isP0
      ? _crSlice(raw, _crHead2, _crHead3)
      : _crSlice(raw, _crHead3, _crHead4);
  final tail = raw.substring(tailStart).trim(); // §四~§七，与阶段无关

  return [head, section, tail].join('\n\n');
}

// ══════════════════════════════════════════════════════════════
// 二、advanced-phases（原 skills_advanced_outline_p7.dart）
// ══════════════════════════════════════════════════════════════

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

/// advanced-phases 阶段裁剪入口（dispatcher 经 `Skill.contentForPhase` 调用）。
///
/// [raw] = 完整原文，由宿主在挂载点传入
/// （`_advancedPhasesBody1 + _advancedPhasesBody2`，
/// 见 skills_advanced_outline_p1.dart）。
///
/// 非 P3/P4 阶段返回完整原文（字节一致）；切片全部为原文子串，故不存在
/// 编辑漂移（由 test/services/advanced_phases_phase_slice_test.dart 断言）。
///
/// 裁剪策略：
///   P3_TRAINING → 前言 + P3 段 + P3 态度 + (P3→P4 + 迁移约束)
///   P4_REVIEW   → 前言 + P4 段 + P4 态度 + (P4→P2 + 迁移约束)
///   其它阶段     → 完整原文（行为与现状完全相同）
///
/// P5 段已删除（C56 幽灵阶段：TeachingPhase 无 P5 枚举值，原切片只裁掉了
/// 「段」却注入了「通往 P5 的指令」，见 ADR-C54 §9 方案 D）；
/// 已发生的迁移（P2→P3、P3→P4 在 P4 档）同样不注入。
String advancedPhasesContentFor(TeachingPhase phase, String raw) {
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
