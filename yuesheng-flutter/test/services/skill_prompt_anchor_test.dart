// ignore_for_file: avoid_print
// ─────────────────────────────────────────────────────────────
// Phase 3 行为锚点（字节级）— 大块索引化重构前冻结现状
//
// 方案：docs/designs/2026-08-28-skill-orthogonal-refactor-plan.md §5
// ADR：docs/ADR-skill-orthogonal-model.md
//
// 目的：把 buildSystemPromptV2 的完整输出（L1 + 态度 + L2 + 语境头 +
//      位置引导）、六个大块 skill 的原文内容、L3 检索注入输出，冻结为
//      字节级基线（长度 + FNV-1a 64 位指纹）。Phase 3 的「纯搬移」步骤
//      （内容迁移至 *_kb_content.dart）不得改变任何锚点；有意的行为
//      变更（大块 → 索引版）须经舰长确认后重生成基线并复查 diff。
//
// 用法：
//   flutter test test/services/skill_prompt_anchor_test.dart
//   UPDATE_SNAPSHOTS=true flutter test test/services/skill_prompt_anchor_test.dart
// ─────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/contracts/teaching_capability.dart';
import 'package:writingcoach/services/skill_dispatcher.dart';
import 'package:writingcoach/services/skill_registry.dart';
import 'package:writingcoach/types/teaching_types.dart';

const String kAnchorPath = 'test/snapshots/skill_prompt_anchor.json';

/// Phase 3 索引化对象（六个大块；方案 §5，teaching-strategy 单列决策不在此列）
const List<String> kPhase3Skills = [
  'narrative-design',
  'plot-design',
  'coaching-rhythm',
  'advanced-phases',
  'outline-diagnosis',
  'genre-guide',
];

/// 锚点用例：上下文均 const，保证可复现；选取与 skill_registry_l2_test
/// 的组装断言同源（beginner/diagnosis/training/advanced/outline 五模式），
/// beginner 额外覆盖三个态度档位。
class _PromptCase {
  final String name;
  final SkillLoadContext ctx;
  const _PromptCase(this.name, this.ctx);
}

const List<_PromptCase> kPromptCases = [
  _PromptCase(
    'beginner_doubao',
    SkillLoadContext(
      phase: TeachingPhase.p0Engage,
      attitude: AttitudeLevel.doubao,
      isBeginner: true,
    ),
  ),
  _PromptCase(
    'beginner_yuesheng',
    SkillLoadContext(
      phase: TeachingPhase.p0Engage,
      attitude: AttitudeLevel.yuesheng,
      isBeginner: true,
    ),
  ),
  _PromptCase(
    'beginner_sensei',
    SkillLoadContext(
      phase: TeachingPhase.p0Engage,
      attitude: AttitudeLevel.sensei,
      isBeginner: true,
    ),
  ),
  _PromptCase(
    'diagnosis_yuesheng',
    SkillLoadContext(
      phase: TeachingPhase.p2PracticeLoop,
      attitude: AttitudeLevel.yuesheng,
      subphase: TeachingSubphase.diagnosis,
    ),
  ),
  _PromptCase(
    'training_yuesheng',
    SkillLoadContext(
      phase: TeachingPhase.p2PracticeLoop,
      attitude: AttitudeLevel.yuesheng,
      subphase: TeachingSubphase.practice,
    ),
  ),
  _PromptCase(
    'advanced_sensei',
    SkillLoadContext(
      phase: TeachingPhase.p3Training,
      attitude: AttitudeLevel.sensei,
    ),
  ),
  _PromptCase(
    'outline_yuesheng',
    SkillLoadContext(
      phase: TeachingPhase.p2PracticeLoop,
      attitude: AttitudeLevel.yuesheng,
      isOutlineContext: true,
    ),
  ),
];

/// L3 注入用例（injectL3 不依赖 L2 模式，统一取 diagnosis 结果调用）
class _L3Case {
  final String name;
  final L3RetrievalContext ctx;
  const _L3Case(this.name, this.ctx);
}

const List<_L3Case> kL3Cases = [
  _L3Case('syndrome_P003', L3RetrievalContext(activeSyndromeIds: ['P003'])),
  _L3Case(
    'technique_T001_T008',
    L3RetrievalContext(focusedTechniqueIds: ['T001', 'T008']),
  ),
  _L3Case(
    'both_P003_P007_T001',
    L3RetrievalContext(
      activeSyndromeIds: ['P003', 'P007'],
      focusedTechniqueIds: ['T001'],
    ),
  ),
  _L3Case('empty', L3RetrievalContext()),
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

/// 汇总当前全部锚点（prompt / 大块原文 / L3 注入）
Map<String, Object> _buildCurrent() {
  final promptAnchors = <String, Object>{};
  for (final c in kPromptCases) {
    promptAnchors[c.name] = _promptAnchor(buildSystemPromptV2(c.ctx));
  }

  final skillAnchors = <String, Object>{};
  for (final id in kPhase3Skills) {
    final skill = skillRegistry[id];
    if (skill == null) {
      throw StateError('Phase 3 大块 skill 未注册: $id');
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
      'phase3Skills': kPhase3Skills.join(','),
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

void main() {
  test('Phase 3 锚点：prompt / 大块原文 / L3 注入字节级不变', () {
    final updating = (Platform.environment['UPDATE_SNAPSHOTS'] ?? '') == 'true';

    // 组装确定性自检：同一上下文连跑两遍，输出必须完全一致
    final first = buildSystemPromptV2(kPromptCases[0].ctx);
    final second = buildSystemPromptV2(kPromptCases[0].ctx);
    expect(first.systemPrompt, second.systemPrompt, reason: '组装非确定性');

    final current = _buildCurrent();
    final file = File(kAnchorPath);

    // 首次生成 / 显式重生成
    if (updating || !file.existsSync()) {
      file
        ..createSync(recursive: true)
        ..writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert(current) + '\n',
        );
      print('[anchor] 基线已生成: $kAnchorPath');
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

    print('[anchor] 比对通过：prompt / 大块原文 / L3 注入与基线字节级一致 ✓');
    expect(diffs, isEmpty);
  });
}
