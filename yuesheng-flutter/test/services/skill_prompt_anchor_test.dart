// ignore_for_file: avoid_print
// ─────────────────────────────────────────────────────────────
// Phase 3 行为锚点（字节级）— 大块索引化重构前冻结现状
//
// 方案：docs/designs/2026-08-28-skill-orthogonal-refactor-plan.md §5
// ADR：docs/ADR-skill-orthogonal-model.md
//
// 目的：把 buildSystemPromptV2 的完整输出（L1 + 态度 + L2 + 语境头 +
//      位置引导）、全部注册 skill 的原文内容、L3 检索注入输出，冻结为
//      字节级基线（长度 + FNV-1a 64 位指纹）。Phase 3 的「纯搬移」步骤
//      （内容迁移至 *_kb_content.dart）不得改变任何锚点；有意的行为
//      变更（大块 → 索引版）须经舰长确认后重生成基线并复查 diff。
//
// E.11（台账 §E.11）两处加强：
//   ① diff 粒度：逐 Skill 指纹由原 6 个 Phase 3 大块扩到注册表**全部**
//      skill。改一个 skill 后，diff 会直接指名是哪个 skill 变了，而不是
//      只能在 9→13 个 prompt 指纹里看到「全变」却无法确认是否只改了预期处。
//   ② 用例覆盖：补齐 4 个原本缺位的可达组合——
//      P0+零基础=false（L2Mode.none）/ P1+零基础=false（diagnosis 组）/
//      P3+零基础（beginner 组）/ P4+零基础（beginner 组）。
//      原 9 个用例里 L2Mode.none 组**一个都没有**，等于该组从未被锚定。
//
// 用法：
//   flutter test test/services/skill_prompt_anchor_test.dart
//   UPDATE_SNAPSHOTS=true flutter test test/services/skill_prompt_anchor_test.dart
// ─────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/skill_dispatcher.dart';
import 'package:writingcoach/services/skill_layers.dart';
import 'package:writingcoach/services/skill_registry.dart';
import 'package:writingcoach/types/teaching_types.dart';

import '../helpers/anchor_content_floor.dart';

const String kAnchorPath = 'test/snapshots/skill_prompt_anchor.json';

/// 逐 Skill 指纹覆盖的全部 skill（E.11 ①）
///
/// 原为 Phase 3 六个大块（narrative-design / plot-design / coaching-rhythm /
/// advanced-phases / outline-diagnosis / genre-guide）；扩到注册表全部后，
/// 任何一个 skill 的正文被改动都会在 diff 里被指名。
/// 排序取 registry key，保证快照键序稳定、可复现。
List<String> get kAnchoredSkillIds => skillRegistry.keys.toList()..sort();

/// 锚点用例：上下文均 const，保证可复现；选取与 skill_registry_l2_test
/// 的组装断言同源（beginner/diagnosis/training/advanced/outline 五模式），
/// beginner 额外覆盖三个态度档位，并补 P1 档（coaching-rhythm 阶段裁剪生效档）。
///
/// E.11 ②：补齐四个可达组合，使六个 L2Mode 全部至少有一个锚点。
class PromptCase {
  final String name;
  final SkillLoadContext ctx;
  const PromptCase(this.name, this.ctx);
}

const List<PromptCase> kPromptCases = [
  // ── L2Mode.none（P0 + 非零基础：无任何 L2 组注入）── E.11 ② 新增
  PromptCase(
    'none_p0_yuesheng',
    SkillLoadContext(
      phase: TeachingPhase.p0Engage,
      attitude: AttitudeLevel.yuesheng,
    ),
  ),
  // ── L2Mode.beginner ──
  PromptCase(
    'beginner_gentle',
    SkillLoadContext(
      phase: TeachingPhase.p0Engage,
      attitude: AttitudeLevel.gentle,
      isBeginner: true,
    ),
  ),
  PromptCase(
    'beginner_yuesheng',
    SkillLoadContext(
      phase: TeachingPhase.p0Engage,
      attitude: AttitudeLevel.yuesheng,
      isBeginner: true,
    ),
  ),
  PromptCase(
    'beginner_sensei',
    SkillLoadContext(
      phase: TeachingPhase.p0Engage,
      attitude: AttitudeLevel.sensei,
      isBeginner: true,
    ),
  ),
  PromptCase(
    'beginner_p1_yuesheng',
    SkillLoadContext(
      phase: TeachingPhase.p1World,
      attitude: AttitudeLevel.yuesheng,
      isBeginner: true,
    ),
  ),
  // P3/P4 + 零基础 → resolveL2Mode 规则 4 走 beginner 组；
  // 原用例集里这两档只覆盖了非零基础分支。E.11 ② 新增
  PromptCase(
    'beginner_p3_yuesheng',
    SkillLoadContext(
      phase: TeachingPhase.p3Training,
      attitude: AttitudeLevel.yuesheng,
      isBeginner: true,
    ),
  ),
  PromptCase(
    'beginner_p4_yuesheng',
    SkillLoadContext(
      phase: TeachingPhase.p4Review,
      attitude: AttitudeLevel.yuesheng,
      isBeginner: true,
    ),
  ),
  // ── L2Mode.diagnosis ──
  // P1 + 非零基础（无子阶段）也会落到 diagnosis 组；原用例只有 P2+diagnosis
  // 子阶段一种，P1 这条独立分支从未被锚定。E.11 ② 新增
  PromptCase(
    'diagnosis_p1_yuesheng',
    SkillLoadContext(
      phase: TeachingPhase.p1World,
      attitude: AttitudeLevel.yuesheng,
    ),
  ),
  PromptCase(
    'diagnosis_yuesheng',
    SkillLoadContext(
      phase: TeachingPhase.p2PracticeLoop,
      attitude: AttitudeLevel.yuesheng,
      subphase: TeachingSubphase.diagnosis,
    ),
  ),
  // ── L2Mode.training ──
  PromptCase(
    'training_yuesheng',
    SkillLoadContext(
      phase: TeachingPhase.p2PracticeLoop,
      attitude: AttitudeLevel.yuesheng,
      subphase: TeachingSubphase.practice,
    ),
  ),
  // ── L2Mode.advanced ──
  PromptCase(
    'advanced_sensei',
    SkillLoadContext(
      phase: TeachingPhase.p3Training,
      attitude: AttitudeLevel.sensei,
    ),
  ),
  PromptCase(
    'advanced_p4_yuesheng',
    SkillLoadContext(
      phase: TeachingPhase.p4Review,
      attitude: AttitudeLevel.yuesheng,
    ),
  ),
  // ── L2Mode.outline ──
  PromptCase(
    'outline_yuesheng',
    SkillLoadContext(
      phase: TeachingPhase.p2PracticeLoop,
      attitude: AttitudeLevel.yuesheng,
      isOutlineContext: true,
    ),
  ),
  // ★★ A2 批新增（2026-10-05）：`forceDiagnosisSceneFirst=true` 的覆盖缺口。
  //
  // 缺口成因（实测）：`_kDiagnosisSceneFirst` 的注入条件是
  //   `l2Mode == L2Mode.diagnosis || ctx.forceDiagnosisSceneFirst`
  // （`skill_dispatcher.dart:170`），而该 flag 由「**用户消息措辞是否触发诊断
  // 协议**」决定（`chat_service.dart:1255`），**与 l2Mode 无关** ⇒ 非 diagnosis
  // 组（beginner / training / outline / advanced）也会注入这块。
  // 原 13 个用例**全部**不带该 flag（`grep forceDiagnosisSceneFirst` 在本文件
  // 零命中）⇒ 这条路径曾**完全没有体积基线覆盖**，扩写该块时对照组红线会
  // 「凭 13 个用例全绿」而漏掉真实增长。
  //
  // 本例选 P3+零基础（resolveL2Mode 走 beginner 组）+ force=true：
  // 这是线上最易命中的组合（学员在训练阶段说「帮我看看这段」）。
  PromptCase(
    'beginner_p3_yuesheng_forceSceneFirst',
    SkillLoadContext(
      phase: TeachingPhase.p3Training,
      attitude: AttitudeLevel.yuesheng,
      isBeginner: true,
      forceDiagnosisSceneFirst: true,
    ),
  ),
];

/// L3 注入用例（injectL3 不依赖 L2 模式，统一取 diagnosis 结果调用）
class L3Case {
  final String name;
  final L3RetrievalContext ctx;
  const L3Case(this.name, this.ctx);
}

// ★ 2026-10-30（T-20261030-07）用例名对齐实测切片：
//   `syndrome_P003` → `syndrome_P001`（`activeSyndromeIds: ['P001']`，旧名误称）；
//   `both_P003_P007_T001` → `both_P001_P005_T001`（实际 P001+P005+T001，旧名误称）。
//   `technique_T001_T008` 与实测一致，未动。改名 = 快照键名改 ⇒ 随重冻更新，
//   len/fnv 钉值不变（批 B 实测两键零漂移是切片本就含 P003 面、未受三行改字影响，
//   非切片排除）。
const List<L3Case> kL3Cases = [
  L3Case('syndrome_P001', L3RetrievalContext(activeSyndromeIds: ['P001'])),
  L3Case(
    'technique_T001_T008',
    L3RetrievalContext(focusedTechniqueIds: ['T001', 'T008']),
  ),
  L3Case(
    'both_P001_P005_T001',
    L3RetrievalContext(
      activeSyndromeIds: ['P001', 'P005'],
      focusedTechniqueIds: ['T001'],
    ),
  ),
  L3Case('empty', L3RetrievalContext()),
];

/// FNV-1a 64 位指纹（VM 原生 int 乘法回绕，输出恒为正；任一字节变化
/// 都会改变指纹，与长度断言共同构成字节级判定）
int _fnv1a64(String s) {
  // FNV-1a 64 位偏移基数（14695981039346656037）。项目仅发布 Android、不编译 JS，
  // VM 上 int 即 64 位；改用 BigInt 会改变哈希值 ⇒ 锚点快照全量失配，故保留字面量。
  // ignore: avoid_js_rounded_ints
  var h = 0xcbf29ce484222325;
  for (final cu in s.codeUnits) {
    h ^= cu;
    h *= 0x100000001b3;
  }
  return h & 0x7fffffffffffffff;
}

Map<String, Object> _textAnchor(String s) => {
  'len': s.length,
  'fnv': _fnv1a64(s).toRadixString(16),
};

Map<String, Object> _promptAnchor(SystemPromptResult r) => {
  'len': r.systemPrompt.length,
  'fnv': _fnv1a64(r.systemPrompt).toRadixString(16),
  'tokens': r.estimatedTokens,
  'skills': r.loadedSkillIds.join(','),
};

/// 汇总当前全部锚点（prompt / 全部 skill 原文 / L3 注入）
Map<String, Object> _buildCurrent() {
  final promptAnchors = <String, Object>{};
  for (final c in kPromptCases) {
    promptAnchors[c.name] = _promptAnchor(buildSystemPromptV2(c.ctx));
  }

  // E.11 ①：由 6 个大块扩到注册表全部 skill
  final skillAnchors = <String, Object>{};
  for (final id in kAnchoredSkillIds) {
    final skill = skillRegistry[id];
    if (skill == null) {
      throw StateError('注册表中的 skill 消失: $id');
    }
    skillAnchors[id] = _textAnchor(skill.content);
  }

  // injectL3 与 L2 模式无关，统一用 diagnosis 上下文的构建结果
  final diagnosisCase = kPromptCases.firstWhere(
    (c) => c.name == 'diagnosis_yuesheng',
  );
  final injectL3 = buildSystemPromptV2(diagnosisCase.ctx).injectL3;
  final l3Anchors = <String, Object>{};
  for (final c in kL3Cases) {
    l3Anchors[c.name] = _textAnchor(injectL3(c.ctx));
  }

  // P1-9：三块非注册 prompt const 的独立分节指纹（promptBoundary /
  // positionGuidance / diagnosisSceneFirst）——改其中一块能在 driftSummary 里
  // 直接点名是哪块漂移，而不是只看到整条 system prompt 全变。
  final constSections = <String, Object>{};
  for (final entry in getDiagnosisConstSections().entries) {
    constSections[entry.key] = _textAnchor(entry.value);
  }

  return {
    'meta': {
      'note': 'Phase 3 行为锚点基线（字节级：长度 + FNV-1a 指纹）',
      'promptCases': kPromptCases.map((c) => c.name).join(','),
      'anchoredSkillCount': kAnchoredSkillIds.length,
    },
    'prompt': promptAnchors,
    'skillContent': skillAnchors,
    'l3Inject': l3Anchors,
    'constSections': constSections,
  };
}

/// 递归 diff，返回 ['path: before → after', ...]（与快照护栏同款）
List<String> _diff(String path, dynamic a, dynamic b) {
  final out = <String>[];
  if (a is Map && b is Map) {
    final keys = <String>{...a.keys.cast<String>(), ...b.keys.cast<String>()};
    for (final k in keys) {
      out.addAll(_diff('$path.$k', a[k], b[k]));
    }
  } else if (a != b) {
    out.add('$path: ${a ?? '∅'} → ${b ?? '∅'}');
  }
  return out;
}

/// 按顶层分节统计漂移条数（E.11 ① 配套：先看清是哪一节在动）
///
/// 输出形如 `prompt 3 / skillContent 2`；对 skillContent 还会进一步点名
/// 具体是哪几个 skill（这正是本次加强的目的）。
String _driftSummary(List<String> diffs) {
  final sections = <String, int>{};
  final touchedSkills = <String>[];
  for (final d in diffs) {
    final parts = d.split('.');
    final sec = parts.first;
    sections[sec] = (sections[sec] ?? 0) + 1;
    if (sec == 'skillContent' && parts.length >= 2) {
      final id = parts[1];
      if (!touchedSkills.contains(id)) touchedSkills.add(id);
    }
  }
  final head = sections.entries.map((e) => '${e.key} ${e.value}').join(' / ');
  if (touchedSkills.isEmpty) return head;
  final shown = touchedSkills.take(12).join(', ');
  final rest = touchedSkills.length > 12 ? ' 等 ${touchedSkills.length} 个' : '';
  return '$head\n  skillContent 命中: $shown$rest';
}

// ─────────────────────────────────────────────────────────────
// 重建下限判据（T-20261024-15 · L4 支撑层）
//
// 由来：本文件的**重建分支此前连回读都没有**（只有 `expect(file.existsSync())`），
//   而比对分支的双向键集合判据在重建时完全不生效 —— 「装配塌成空壳」写出的
//   基线与正常基线外观相同（键齐、指纹合法），此后长期绿。
//
// 口径（`DECISIONS §4-260⑤` 舰长 2026-10-24 23:31 已裁，不得改）：
//   ① 每例**非空** + 总数 ≥ 旧基线 **50%**；② 越限 = **fail**。
//
// 落点只在**重建分支**：比对分支的判据面是「与基线逐字节一致」，塌陷基线在那里
//   表现为「当前 ≠ 基线」⇒ 本来就会红。
// ★ 判据在**写盘之前**：失败必须**不写**。
// ─────────────────────────────────────────────────────────────

/// 本快照的四个判据面（分节）。
const List<String> _kSections = [
  'prompt',
  'skillContent',
  'l3Inject',
  'constSections',
];

/// `len == 0` 属**设计允许**的唯一一处：`l3Inject.empty`
/// （`L3RetrievalContext()` 不带任何 ID ⇒ L3 检索结果本就是空串）。
/// 实测基线 `test/snapshots/skill_prompt_anchor.json:260-261` 即
/// `"empty": { "len": 0, ... }`。
/// ★ 这是**点名豁免**，不是放宽阈值：其余任何条目 `len == 0` 一律红。
const Set<String> _kLegitEmptyLen = {'l3Inject.empty'};

/// F1 + F2：每例非空。不过即 `fail`（**不写盘**）。
///
/// F1 = 每个分节至少 1 条（条数下限）；
/// F2 = 每条目的 `fnv` 不得为空、`len` 不得为 0（除 `_kLegitEmptyLen` 点名者）。
void _assertPerCaseNonEmpty(Map<String, Object> current) {
  final emptySections = <String>[];
  final emptyEntries = <String>[];
  final emptyFnv = <String>[];
  for (final section in _kSections) {
    final got = current[section]! as Map<String, Object>;
    if (got.isEmpty) {
      emptySections.add(section);
      continue;
    }
    for (final e in got.entries) {
      final anchor = e.value as Map<String, Object>;
      final id = '$section.${e.key}';
      final len = anchor['len']! as int;
      if ((anchor['fnv']! as String).isEmpty) emptyFnv.add(id);
      if (len < 1 && !_kLegitEmptyLen.contains(id)) {
        emptyEntries.add('$id(len=$len)');
      }
    }
  }
  if (emptySections.isEmpty && emptyEntries.isEmpty && emptyFnv.isEmpty) return;
  fail(
    '[anchor] 重建下限不过（F1 分节条数 / F2 叶值非空），**已拒绝写盘**：\n'
    '  F1 空分节 ${emptySections.length} 个：$emptySections\n'
    '  F2 空条目 ${emptyEntries.length} 条：${emptyEntries.take(12).toList()}'
    '${emptyEntries.length > 12 ? ' …' : ''}\n'
    '  F2 空指纹 ${emptyFnv.length} 条：${emptyFnv.take(12).toList()}'
    '${emptyFnv.length > 12 ? ' …' : ''}\n'
    '  ★ 这多半是装配塌陷（skill 注册表读空 / `buildSystemPromptV2` 返回空串），'
    '**不是**「prompt 变短了」。空壳基线一旦落盘，此后长期绿。\n'
    '  排查真因后确需重写基线：UPDATE_SNAPSHOTS=true。',
  );
}

/// 读旧基线的四个分节；返回 `null` = 无可比基线。
///
/// 「不可解析」（非 JSON / 顶层非对象 / 缺分节）一律**默认 fail**（除非显式豁免）：
/// `旧快照损坏 + UPDATE_SNAPSHOTS=true` 是**洗白基线最省力的入口**。
Map<String, dynamic>? _loadBaselineSections(File file, {required bool exists}) {
  if (!exists) return null; // 首次生成：F3 不生效（调用处打告警）
  final raw = file.readAsStringSync();
  String? why;
  // ★ 失败形态标签：多种「基线不可用」共用同一出口，靠它区分。
  var kind = '不可解析';
  Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException catch (e) {
    why = '${e.message}（偏移 ${e.offset}）';
  }
  if (why == null) {
    if (decoded is! Map<String, dynamic>) {
      why = '顶层应为 JSON 对象，实际为 ${decoded.runtimeType}';
    } else {
      final missing = <String>[
        for (final s in _kSections)
          if (decoded[s] is! Map) s,
      ];
      if (missing.isNotEmpty) {
        kind = decoded.keys.where((k) => k != 'meta').isEmpty
            ? '顶层只有 meta、缺全部分节'
            : '缺分节';
        why = '缺分节 $missing';
      } else {
        final sections = <String, dynamic>{
          for (final s in _kSections) s: decoded[s],
        };
        if (anchorMeasureVolume(sections).content == 0) {
          // ★ 最隐蔽的一种：分节齐备、但所有 `len` 都是 0 且无叶字符串。
          //   体积 0 ⇒ 下限 `ceil(0/2) == 0` ⇒ 任何内容都 `≥ 0` ⇒ F3 恒绿（fail-open）。
          //   与「不可解析」同类失效，必须走同一条 fail 通路，**不另造出口**。
          kind = '分节齐备但全零长度';
          why =
              '分节齐备，但内容体积（单调代理）为 0'
              '（所有 `len` 均为 0，且无叶字符串）';
        } else {
          final hollows = findHollowLenFnvFamilies(sections);
          if (hollows.isNotEmpty) {
            kind = '族内全零长度但 fnv 非空';
            why =
                '${hollows.length} 个 len+fnv 节点族族内 len 全 0、fnv 非空'
                '（空壳基线，与「体积为 0」同罪）：${hollows.take(3).join(' / ')}';
          } else {
            return sections;
          }
        }
      }
    }
  }
  final waived =
      (Platform.environment['ALLOW_FLOORLESS_REBUILD'] ?? '') == 'true';
  if (!waived) {
    fail(
      '[anchor] 旧基线不可解析 ⇒ 比率下限无法生效（或：可解析但不可用）：'
      '$kAnchorPath\n'
      '  本次形态：$kind\n'
      '  判定依据：$why\n'
      '  ★ 可解析但不可用 = ① 缺分节 ② 顶层只有 `meta` ③ **分节齐备但所有 `len` 均为 0**'
      ' ④ **族内 len 全 0 但 fnv 非空**。\n'
      '    前三者让下限退化为 0、④ 让下限来自非内容量 ⇒ F3 对任何内容恒绿（fail-open），与「文件损坏」同罪。\n'
      '  两条出口：\n'
      '    ① 恢复基线：git checkout -- $kAnchorPath\n'
      '    ② 确认要丢弃旧基线：ALLOW_FLOORLESS_REBUILD=true'
      '（会打双重告警，且本次不设任何下限）',
    );
  }
  print(
    '[anchor][告警] 已放弃比率下限：旧基线不可解析或不可用（$kind：$why）'
    '⇒ 本次未做任何比对，这不是校验通过。',
  );
  print('[anchor][告警] 路径：$kAnchorPath；本次为「无下限重建」，须人工复核体量。');
  return null;
}

/// F3：总数（**内容体积（单调代理）**）≥ 旧基线 50%。不过即 `fail`（**不写盘**）。
///
/// 口径见 `test/helpers/anchor_content_floor.dart`：叶字符串长度 + 仅 `len` /
/// `length` 键的整数值；`tokens` 与其余整数单列 `nonContentInt`，**不计体积**。
/// ⚠️ 该指标**不得当作字节数 / token 成本引用**：本文件的 `len` 与 `tokens`
///    14/14 恒等（`estimatedTokens => content.length`），同一段 prompt 会被算两遍，
///    所以只计 `len` 一次；要看成本请用 `tool/check_prompt_volume.py`。
void _assertVolumeFloor(
  Map<String, Object> current, {
  required File file,
  required bool exists,
}) {
  final body = <String, Object>{for (final s in _kSections) s: current[s]!};
  final newMeasure = anchorMeasureVolume(body);
  final newVolume = newMeasure.content;
  final baseline = _loadBaselineSections(file, exists: exists);
  if (baseline == null) {
    if (!exists) {
      print(
        '[anchor][告警] 本次为首次生成，比率下限未生效：$kAnchorPath\n'
        '  ★ 首次生成是合法通路，故不拦；但**不静默** —— 否则「删掉旧快照再重冻」'
        '就成了绕过下限的最短路径。\n'
        '  提交前请人工复核该基线的体量是否合理'
        '（本次内容体积（单调代理）$newVolume；'
        '非长度整数（不计体积，含 tokens）${newMeasure.nonContentInt}）。',
      );
    }
    return;
  }
  final baselineMeasure = anchorMeasureVolume(baseline);
  final baselineVolume = baselineMeasure.content;
  final floor = (baselineVolume / 2).ceil();
  if (newVolume < floor) {
    fail(
      '[anchor] 重建内容体积（单调代理）低于比率下限，**已拒绝写盘**：\n'
      '  实际：$newVolume\n'
      '  下限：$floor（旧基线 $baselineVolume 的 50%）\n'
      '  非长度整数（不计体积，含 tokens）：${newMeasure.nonContentInt}'
      '（旧基线 ${baselineMeasure.nonContentInt}）\n'
      '  ★ 键齐但内容腰斩 = 装配塌陷的典型形态（注册表读空 / 装配异常被吞）。\n'
      '  ★ 该指标是「内容体积（单调代理）」，**不得当作字节数 / token 成本引用**。\n'
      '  确为有意的语料缩减须经评审并在 .ai/DECISIONS.md 登记；'
      '确认不设下限时：ALLOW_FLOORLESS_REBUILD=true。',
    );
  }
  print(
    '[anchor] 重建下限通过：内容体积（单调代理）$newVolume ≥ 下限 $floor'
    '（旧基线 $baselineVolume 的 50%）；'
    '非长度整数（不计体积，含 tokens）${newMeasure.nonContentInt}。',
  );
}

/// ③「`len` 与 `tokens` 恒等」自检（主理人 2026-10-25 要求）。
///
/// 依据：`estimatedTokens => content.length`（`DECISIONS §4-265⑦`）⇒ 本文件 14 个
/// prompt 节点两者 **14/14 相等**（实测 `test/snapshots/skill_prompt_anchor.json`）。
///
/// 体积口径**只计 `len`、不计 `tokens`**，而这条恒等正是那个决定的前提：
/// 一旦 `tokens` 改成真实 token 估算，`len` 与 `tokens` 就分家，「不计 `tokens`」
/// 会变成**静默漏计**（只量到字符数，丢掉真实成本口径）⇒ 判据面悄悄变窄。
/// ⇒ 把断言打在这个**前提**上，让口径漂移变成响亮红灯。
void _assertLenTokensIdentity(Map<String, Object> current) {
  final prompt = current['prompt']! as Map<String, Object>;
  final drift = <String>[];
  for (final e in prompt.entries) {
    final anchor = e.value as Map<String, Object>;
    final len = anchor['len'] as int?;
    final tokens = anchor['tokens'] as int?;
    if (len == null || tokens == null) continue; // 只要求「同时存在时相等」
    if (len != tokens) drift.add('prompt.${e.key}(len=$len, tokens=$tokens)');
  }
  if (drift.isEmpty) return;
  fail(
    '[anchor] `estimatedTokens` 不再是 `content.length`，本文件的体积口径需重审：\n'
    '  ${drift.length} 个节点 len ≠ tokens：${drift.take(12).toList()}'
    '${drift.length > 12 ? ' …' : ''}\n'
    '  ★ 体积口径只计 `len`、**不计 `tokens`**（两者恒等，计了就是双计）。'
    '若 `tokens` 已改为真实 token 估算，「不计 tokens」就变成静默漏计 ⇒ '
    '须重审 `test/helpers/anchor_content_floor.dart` 的口径并在本卡片登记新口径。\n'
    '  ★ 该指标是「内容体积（单调代理）」，不得当作字节数 / token 成本引用。',
  );
}

void main() {
  test('Phase 3 锚点：prompt / skill 原文 / L3 注入字节级不变', () {
    final updating = (Platform.environment['UPDATE_SNAPSHOTS'] ?? '') == 'true';

    // 组装确定性自检：同一上下文连跑两遍，输出必须完全一致
    final first = buildSystemPromptV2(kPromptCases[0].ctx);
    final second = buildSystemPromptV2(kPromptCases[0].ctx);
    expect(first.systemPrompt, second.systemPrompt, reason: '组装非确定性');

    // E.11 ② 配套自检：六个 L2Mode 必须全部被锚点覆盖，否则某组改动会漏网
    final coveredModes = kPromptCases.map((c) => resolveL2Mode(c.ctx)).toSet();
    expect(
      coveredModes.length,
      L2Mode.values.length,
      reason:
          '锚点用例未覆盖全部 L2Mode：'
          '已覆盖 ${coveredModes.map((m) => m.name).join(',')}，'
          '共 ${L2Mode.values.length} 组',
    );

    // ★★ A2 批新增（2026-10-05）：`forceDiagnosisSceneFirst` 覆盖缺口的**牙齿**。
    //
    // 为什么必须断言「force=true 时非 diagnosis 组也注入该块」：
    //   若某天注入条件被改成只看 `l2Mode == diagnosis`，本例会静默变成
    //   「beginner 组 + 不含该块」，而**快照照样能生成、门禁照样全绿**——
    //   覆盖缺口复现且无人察觉。断言打在**条件本身**，不是打在快照上。
    const forceCaseName = 'beginner_p3_yuesheng_forceSceneFirst';
    final forceCase = kPromptCases.firstWhere((c) => c.name == forceCaseName);
    expect(
      resolveL2Mode(forceCase.ctx),
      isNot(L2Mode.diagnosis),
      reason: '$forceCaseName 必须走非 diagnosis 组，否则测不到 force 分支',
    );
    final forcePrompt = buildSystemPromptV2(forceCase.ctx).systemPrompt;
    expect(
      forcePrompt.contains('## 诊断前置：先定层级'),
      isTrue,
      reason:
          '$forceCaseName 应注入 _kDiagnosisSceneFirst —— '
          'force=true 且非 diagnosis 组时也必须注入（skill_dispatcher.dart:170）',
    );
    // ★ 2026-10-09：裁定6「新手诊断姿态」的「先认对的地方」块已从
    //   `skill_dispatcher.dart`撤回（该实现删除）。**本断言随之移除** ——
    //   移除它不是「放弃覆盖」，而是它的**被测对象已不存在**；若保留，
    //   它会恒假，并把「实现已撤回」伪装成「门禁红灯」，掩盖真正的漂移面。
    //   撤回依据三条：① 该块属「位置强制」（明写「顺序不可颠倒：先肯定 → 再修技术」），
    //   与「证据驱动」语义冲突；② 三臂代理回放（C 臂 = A 臂 − 该块）证其
    //   **非行为充分因** —— 删掉后 10 篇输出形态逐字不变；③ 裁定 6 本身未废，
    //   仅该实现撤回，替换形态另批立项。
    //   ★ 仍保留上一条断言（`## 诊断前置：先定层级`）—— 它才是 force 分支的
    //   真正覆盖点，删块不影响它；若一并删除，该分支会重新变成零体积基线覆盖
    //   （A2 批补该用例的原因，见本文件上方 force 用例注释）。

    final file = File(kAnchorPath);
    final exists = file.existsSync();

    // ── fail-closed 守卫（`T-20261024-13` 缺口 2 的最后一处收口 · 2026-10-25）──
    // 旧写法 `if (updating || !file.existsSync())` 把两件事并成一个分支：
    //   「显式重生成」与「快照缺失」⇒ 快照被误删 / 误移 / 未检出时本用例**照样绿**，
    //   并把当前装配静默写成新基线（此刻 lib 侧若有漂移，基线即被替换成漂移后的值
    //   ⇒ 之后再不会红）。同族三份（`chat_service_message_sequence_anchor_test`
    //   / `l3_entry_anchor_test` / `student_profile_anchor_test`）已于 2026-10-24
    //   改成 fail-closed，本文件是**最后一个**残留。
    // ★ 守卫**前置于 `_buildCurrent()`**：否则装配侧抛错会先红，
    //   「快照缺失」这个真因会被后者的报错遮住（判据落点须指向缺失本身）。
    // ⚠️ 如实声明本守卫的效力边界：本文件钉的 9 组 prompt 总量在
    //   `tool/check_prompt_volume.py` 的 `REDLINE` 里**另有硬编码常量**，
    //   所以 fail-open **不构成「主红线可被绕过」**；它丢的是**逐 skill 字节级
    //   漂移侦测**与「删 A 加 B、总量不变」这类交换式改动的可见性。
    if (!exists && !updating) {
      fail(
        '[anchor] 锚点快照缺失：$kAnchorPath\n'
        '  ★ 快照文件缺失 = 事故，不是常态（该文件本应随仓库一起检出）。\n'
        '  缺失时**不得**自动生成基线 —— 那等于用「当前行为」重写判据，'
        '任何漂移都会被静默转绿。\n'
        '  先查三因：误删 / 误移 / 未检出'
        '（git status --porcelain、git ls-files test/snapshots/）。\n'
        '  确需重建（基线变更须可对账、须经评审）：\n'
        '    UPDATE_SNAPSHOTS=true flutter test '
        'test/services/skill_prompt_anchor_test.dart',
      );
    }

    final current = _buildCurrent();

    // 显式重生成（`UPDATE_SNAPSHOTS=true`）
    if (updating) {
      // ── 基线非退化判据（T-20261024-15 · 重建分支专属）──────────────
      // 顺序：③ 恒等自检（口径前提）→ F1/F2（纯内存）→ F3（读旧基线，
      // 含 IO 与「不可解析」分支）。全部在 `writeAsStringSync` **之前**。
      _assertLenTokensIdentity(current);
      _assertPerCaseNonEmpty(current);
      _assertVolumeFloor(current, file: file, exists: exists);

      file
        ..createSync(recursive: true)
        ..writeAsStringSync(
          '${const JsonEncoder.withIndent('  ').convert(current)}\n',
        );
      print('[anchor] 基线已生成: $kAnchorPath');
      print(
        '[anchor][告警] UPDATE_SNAPSHOTS=true ⇒ 基线被强制覆盖：本次**未做任何比对**，'
        '这不是校验通过。',
      );
      print(
        '[anchor] prompt 用例 ${kPromptCases.length} 个 / '
        '逐 skill 指纹 ${kAnchoredSkillIds.length} 个 / '
        'L3 用例 ${kL3Cases.length} 个',
      );
      expect(file.existsSync(), isTrue);
      return;
    }

    final stored = jsonDecode(file.readAsStringSync());
    final diffs = <String>[
      ..._diff('prompt', stored['prompt'], current['prompt']),
      ..._diff('skillContent', stored['skillContent'], current['skillContent']),
      ..._diff('l3Inject', stored['l3Inject'], current['l3Inject']),
      ..._diff(
        'constSections',
        stored['constSections'],
        current['constSections'],
      ),
    ];

    if (diffs.isNotEmpty) {
      print('[anchor] 检测到 ${diffs.length} 处字节级漂移：');
      print('[anchor] 分布：${_driftSummary(diffs)}');
      for (final d in diffs.take(40)) {
        print('  - $d');
      }
      if (diffs.length > 40) {
        print('  ... 其余 ${diffs.length - 40} 处省略');
      }
      print('[anchor] 若漂移为预期改动（须舰长确认），请运行：');
      print(
        '  UPDATE_SNAPSHOTS=true flutter test '
        'test/services/skill_prompt_anchor_test.dart',
      );
      fail('Phase 3 行为锚点发生字节级漂移（${diffs.length} 处），见上方 diff。');
    }

    print('[anchor] 比对通过：prompt / skill 原文 / L3 注入与基线字节级一致 ✓');
    print(
      '[anchor] 覆盖：${kPromptCases.length} 个 prompt 用例 / '
      '${kAnchoredSkillIds.length} 个 skill 指纹 / ${kL3Cases.length} 个 L3 用例',
    );
    expect(diffs, isEmpty);
  });
}
