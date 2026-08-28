// ─────────────────────────────────────────────────────────────
// skill_registry 数据分片：coaching-rhythm 阶段裁剪（Phase 3 A 组）
// ─────────────────────────────────────────────────────────────
// 依据 ADR-knowledge-injection-driver-model.md §2.2 裁剪准入三问：
//
//   1. 信号来源：ctx.phase（教学状态机，确定性来源，非文本猜测）✅
//   2. 信号缺失时退化：非 P0/P1 阶段返回完整原文；dispatcher 另有
//      `?? skill.content` 兜底 ✅
//   3. 裁掉的段落在当前信号下确定不会被使用：
//      - §二 P0_ENGAGE 描述「建立投入」阶段的行为，其入口是
//        phase == p0Engage；P1 档下该入口不存在 → 不可达
//      - §三 P1_WORLD 同理，P0 档下不可达
//      - §一 总览保留：它是 P0→P1→P2 的旅程地图。裁掉非当前阶段的
//        细节段后，AI 仍知道其他阶段存在，只是没有那一段的操作手册
//      - §四~§七 与 phase 无关（从零构建 / Layer 2 认知桥接 / 分工
//        边界 / 贯穿 P0-P2 的三层认知模型），全部保留
//
// 与索引化的区别：不依赖检索、不会因检索不触发而丢失知识；原文一字
// 未改，切片均为原文子串。
//
// 裁剪策略：
//   P0_ENGAGE → 头部(含§一总览) + §二(P0 段)   + §四~§七
//   P1_WORLD  → 头部(含§一总览) + §三(P1 段)   + §四~§七
//   其它阶段   → 完整原文（P2 的 beginner / diagnosis 档逐字节不变）
//
// 注：skill 头部自述 `loadWhen: P0-P4 全程加载`，与实际不符——
// resolveL2Mode 仅在 beginner(P0/P1/P2) 与 diagnosis(P2) 组加载它，
// P3/P4 不加载。该自述不影响本实现（裁剪只在 P0/P1 生效）。
// ─────────────────────────────────────────────────────────────
part of 'skill_registry.dart';

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

/// coaching-rhythm 阶段裁剪入口（dispatcher 经 Skill.contentForPhase 调用）。
///
/// 非 P0/P1 阶段返回完整原文（字节一致）；切片全部为原文子串，故不存在
/// 编辑漂移（由 test/services/coaching_rhythm_phase_slice_test.dart 断言）。
String coachingRhythmContentFor(TeachingPhase phase) {
  const raw = _coachingRhythmBody1 + _coachingRhythmBody2;

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
