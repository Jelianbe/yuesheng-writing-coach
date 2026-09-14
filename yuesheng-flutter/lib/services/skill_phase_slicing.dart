// ─────────────────────────────────────────────────────────────
// skill_phase_slicing — 技能内容的「按教学阶段选择段资源」纯逻辑
//
// 来源：原 `skill_registry.dart` 的两个 A 类 part 分片
//   `skills_beginner_p9.dart`（coaching-rhythm 裁剪）
//   `skills_advanced_outline_p7.dart`（advanced-phases 裁剪）
//   于 P3-R3 迁出为**真 library**——R-019 A 类豁免的前提之一是
//   「分片无逻辑耦合」，而这两处承载的是算法而非常量数据。
//
// 【Step 2 模型变更（2026-09-14）：字面标题锚点切片 → 具名段 + 目录导航】
//
//   旧模型：把「整篇原文」交给本库，用 `indexOf('## 三、…')` 这类**字面标题**
//   现场切片。四类失配全部「静默不抛错」，其中「结束锚缺失 → 取到文末」与
//   「头部锚缺失 → 静默返回全量」最危险（见 docs/research/
//   2026-09-14-lib-anchor-scan.md §5）。
//
//   新模型：段资源（segment）是**具名常量**，由宿主在挂载点按名字传入；本库
//   只做「按教学阶段选段 + 以 '\n\n' 装配」。**不再持有任何字面标题，不再
//   indexOf**。失配后果因此从「静默」变为「编译期可见」：
//     · 段缺失 ⇒ 编译错误（具名参数 required）
//     · 段错位 ⇒ 分区不变量测试变红（Σ段体积 + 2×(段数−1) == content 长度）
//     · 父标题（如「进阶阶段态度调整」）由**段本身**携带，不再由代码重拼副本
//
// 依据 ADR-knowledge-injection-driver-model.md §2.2 裁剪准入三问：
//   1. 信号来源：ctx.phase（教学状态机，确定性来源，非文本猜测）✅
//   2. 信号缺失时退化：非目标阶段装配全部段（= 完整原文）✅
//   3. 裁掉的段落在当前信号下确定不会被使用（各入口 dartdoc 内详述）✅
//
// 字节不变性：段资源迁移自原正文，装配结果与迁移前逐字节一致
// （由 test/snapshots/skill_prompt_anchor.json 锚点快照 +
//   test/services/*_phase_slice_test.dart 共同守护）。
//
// 与索引化的区别：不依赖检索、不会因检索不触发而丢失知识；原文一字未改，
// 装配产物是段资源原文的拼接。
// ─────────────────────────────────────────────────────────────

import 'package:writingcoach/types/teaching_types.dart';

/// 段装配式：以 `'\n\n'` 连接（与迁移前 `.trim()` + `join('\n\n')` 逐字节等价）。
///
/// **公开导出**：挂载点的 `Skill.content`（完整原文）与本库的阶段装配必须共用
/// 同一分隔符定义——分隔符若在两处各写一份字面量，会出现「全文与相位输出不成
/// 同一装配式」的隐性漂移。收敛到此处后，两者结构上同源。
String joinSegments(List<String> segments) => segments.join('\n\n');

// ══════════════════════════════════════════════════════════════
// 一、coaching-rhythm（段资源见 skills_beginner_p3.dart / skills_beginner_p4.dart）
// ══════════════════════════════════════════════════════════════

/// coaching-rhythm 阶段装配入口（dispatcher 经 `Skill.contentForPhase` 调用）。
///
/// 段清单（目录）：
///   `head` 前言 + §一 总览             —— 全相位恒注入（P0→P1→P2 旅程地图）
///   `p0`   §二 阶段一：建立投入         —— 仅 P0 档
///   `p1`   §三 阶段二：暴露问题         —— 仅 P1 档（段尾自带 `---` 分隔线）
///   `tail` §四~§七                     —— 与相位无关，恒注入
///
/// 裁掉的理由：
///   - `p0` 描述 phase == p0Engage 的行为，P1 档下该入口不存在 → 不可达
///   - `p1` 同理，P0 档下不可达
///   - `head` 保留：裁掉非当前阶段的细节段后，AI 仍知道其他阶段存在
///   - `tail` 保留：从零构建 / Layer 2 认知桥接 / 分工边界 / 贯穿 P0-P2 的
///     三层认知模型，均与 phase 无关
///
/// 注：skill 头部自述 `loadWhen: P0-P4 全程加载`，与实际不符——
/// resolveL2Mode 仅在 beginner(P0/P1/P2) 与 diagnosis(P2) 组加载它，
/// P3/P4 不加载。该自述不影响本实现（装配只在 P0/P1 生效）。
String coachingRhythmSelect(
  TeachingPhase phase, {
  required String head,
  required String p0,
  required String p1,
  required String tail,
}) {
  if (phase != TeachingPhase.p0Engage && phase != TeachingPhase.p1World) {
    return joinSegments([head, p0, p1, tail]);
  }
  final current = phase == TeachingPhase.p0Engage ? p0 : p1;
  return joinSegments([head, current, tail]);
}

// ══════════════════════════════════════════════════════════════
// 二、advanced-phases（段资源见 skills_advanced_outline_p4.dart / _p5.dart）
// ══════════════════════════════════════════════════════════════

/// advanced-phases 阶段装配入口（dispatcher 经 `Skill.contentForPhase` 调用）。
///
/// 段清单（目录）：共 11 段，逐段职责见各段常量的 `///` 注释。
///
/// 关键取舍：
///   - `attHead` / `transHead` 两个**父标题段**自身即注入内容。旧实现是把
///     标题以常量副本重拼（`'## 进阶阶段态度调整\n\n' + attitude`），原文标题
///     改动时副本不跟、**无任何告警**；现在标题取自段本身。
///   - `p2toP3`（已发生的迁移）两档均不注入，只有完整原文才含它。
///   - P5 幽灵阶段（C56：TeachingPhase 无 P5 枚举值）已不存在对应段。
///   - `constraint`（迁移约束）是通用规则，P3/P4 两档都保留。
String advancedPhasesSelect(
  TeachingPhase phase, {
  required String head,
  required String p3Main,
  required String p4Main,
  required String attHead,
  required String p3Att,
  required String p4Att,
  required String transHead,
  required String p2toP3,
  required String p3toP4,
  required String p4toP2,
  required String constraint,
}) {
  if (phase != TeachingPhase.p3Training && phase != TeachingPhase.p4Review) {
    return joinSegments([
      head,
      p3Main,
      p4Main,
      attHead,
      p3Att,
      p4Att,
      transHead,
      p2toP3,
      p3toP4,
      p4toP2,
      constraint,
    ]);
  }
  final isP3 = phase == TeachingPhase.p3Training;
  return joinSegments([
    head,
    isP3 ? p3Main : p4Main,
    attHead,
    isP3 ? p3Att : p4Att,
    transHead,
    isP3 ? p3toP4 : p4toP2,
    constraint,
  ]);
}
