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
    'beginner_doubao',
    SkillLoadContext(
      phase: TeachingPhase.p0Engage,
      attitude: AttitudeLevel.doubao,
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
];

/// L3 注入用例（injectL3 不依赖 L2 模式，统一取 diagnosis 结果调用）
class L3Case {
  final String name;
  final L3RetrievalContext ctx;
  const L3Case(this.name, this.ctx);
}

const List<L3Case> kL3Cases = [
  L3Case('syndrome_P003', L3RetrievalContext(activeSyndromeIds: ['P003'])),
  L3Case(
    'technique_T001_T008',
    L3RetrievalContext(focusedTechniqueIds: ['T001', 'T008']),
  ),
  L3Case(
    'both_P003_P007_T001',
    L3RetrievalContext(
      activeSyndromeIds: ['P003', 'P007'],
      focusedTechniqueIds: ['T001'],
    ),
  ),
  L3Case('empty', L3RetrievalContext()),
];

/// FNV-1a 64 位指纹（VM 原生 int 乘法回绕，输出恒为正；任一字节变化
/// 都会改变指纹，与长度断言共同构成字节级判定）
int _fnv1a64(String s) {
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

  return {
    'meta': {
      'note': 'Phase 3 行为锚点基线（字节级：长度 + FNV-1a 指纹）',
      'promptCases': kPromptCases.map((c) => c.name).join(','),
      'anchoredSkillCount': kAnchoredSkillIds.length,
    },
    'prompt': promptAnchors,
    'skillContent': skillAnchors,
    'l3Inject': l3Anchors,
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

    final current = _buildCurrent();
    final file = File(kAnchorPath);

    // 首次生成 / 显式重生成
    if (updating || !file.existsSync()) {
      file
        ..createSync(recursive: true)
        ..writeAsStringSync(
          '${const JsonEncoder.withIndent('  ').convert(current)}\n',
        );
      print('[anchor] 基线已生成: $kAnchorPath');
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
