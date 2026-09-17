// ignore_for_file: avoid_print
// ─────────────────────────────────────────────────────────────
// L3 知识库「词条级」行为锚点（字节级）— 补 P3 覆盖缺口
//
// 背景（docs/research/2026-09-13-injection-refinement-guardrail-gaps.md §G-2）：
//   test/snapshots/skill_prompt_anchor.json 的 l3Inject 只覆盖 4 个注入组合
//   （P003 / T001+T008 / P003+P007+T001 / 空），L3 **逐词条正文**无字节级保护。
//   本测试为三类 L3 检索源建立**逐词条**指纹快照（len + FNV-1a 64），
//   任一词条被删/改都会在 diff 里被指名。
//
// 覆盖（检索口径 = 单条 ID 的注入输出，与生产 L3 注入同函数）：
//   syndrome  → getSyndromeContent([id])   （症候词条；kSyndromeIds）
//   technique → getTechniqueContent([id])  （技法词条；kTechniqueShortNames.keys）
//   training  → getTrainingContent([id])   （训练词条；kTrainingSyndromeIds）
//   * 空内容词条（如索引/无对应段）以 len=0 记录，内容新增亦会被捕获。
//
// 快照：test/snapshots/l3_entry_anchor.json（**独立文件**，
//       绝不动 skill_prompt_anchor.json 的现有值）。
// 算法：与 test/services/skill_prompt_anchor_test.dart:196-203 同款
//       （UTF-16 code units 的 FNV-1a 64 位）。
//
// 用法：
//   flutter test test/services/l3_entry_anchor_test.dart
//   UPDATE_SNAPSHOTS=true flutter test test/services/l3_entry_anchor_test.dart
// ─────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/syndrome_knowledge_base.dart';
import 'package:writingcoach/services/syndrome_registry.dart';
import 'package:writingcoach/services/technique_knowledge_base.dart';
import 'package:writingcoach/services/training_knowledge_base.dart';

const String kL3AnchorPath = 'test/snapshots/l3_entry_anchor.json';

/// FNV-1a 64 位指纹（与 skill_prompt_anchor_test.dart 同款）。
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

/// 症候词条 ID（活跃，注册表派生）。
List<String> get _syndromeEntryIds => kSyndromeIds;

/// 技法词条 ID（技法名真源 31 条，排序保证键序稳定）。
List<String> get _techniqueEntryIds =>
    kTechniqueShortNames.keys.toList()..sort();

/// 训练词条 ID（与症候真源同源）。
List<String> get _trainingEntryIds => kTrainingSyndromeIds;

/// 汇总当前全部 L3 词条锚点。
Map<String, Object> _buildCurrent() {
  final syndrome = <String, Object>{};
  for (final id in _syndromeEntryIds) {
    syndrome[id] = _textAnchor(getSyndromeContent([id]));
  }
  final technique = <String, Object>{};
  for (final id in _techniqueEntryIds) {
    technique[id] = _textAnchor(getTechniqueContent([id]));
  }
  final training = <String, Object>{};
  for (final id in _trainingEntryIds) {
    training[id] = _textAnchor(getTrainingContent([id]));
  }
  return {
    'meta': {
      'note': 'L3 知识库词条级行为锚点（字节级：长度 + FNV-1a 指纹）',
      'syndromeCount': syndrome.length,
      'techniqueCount': technique.length,
      'trainingCount': training.length,
    },
    'syndrome': syndrome,
    'technique': technique,
    'training': training,
  };
}

/// 递归 diff（与既有锚点护栏同款）。
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
  test('L3 词条级锚点：syndrome / technique / training 逐条字节级不变', () {
    final updating = (Platform.environment['UPDATE_SNAPSHOTS'] ?? '') == 'true';

    // 组装确定性自检：同一词条连跑两遍，输出必须一致。
    final probeId = _syndromeEntryIds.first;
    final first = getSyndromeContent([probeId]);
    final second = getSyndromeContent([probeId]);
    expect(first, second, reason: 'L3 检索非确定性');

    final current = _buildCurrent();
    final file = File(kL3AnchorPath);

    if (updating || !file.existsSync()) {
      file
        ..createSync(recursive: true)
        ..writeAsStringSync(
          '${const JsonEncoder.withIndent('  ').convert(current)}\n',
        );
      print('[l3-anchor] 基线已生成: $kL3AnchorPath');
      print(
        '[l3-anchor] syndrome ${_syndromeEntryIds.length} / '
        'technique ${_techniqueEntryIds.length} / '
        'training ${_trainingEntryIds.length} 条',
      );
      expect(file.existsSync(), isTrue);
      return;
    }

    final stored = jsonDecode(file.readAsStringSync());
    final diffs = <String>[
      ..._diff('syndrome', stored['syndrome'], current['syndrome']),
      ..._diff('technique', stored['technique'], current['technique']),
      ..._diff('training', stored['training'], current['training']),
    ];

    if (diffs.isNotEmpty) {
      print('[l3-anchor] 检测到 ${diffs.length} 处 L3 词条字节级漂移：');
      for (final d in diffs.take(40)) {
        print('  - $d');
      }
      if (diffs.length > 40) {
        print('  ... 其余 ${diffs.length - 40} 处省略');
      }
      fail('L3 词条级锚点发生字节级漂移（${diffs.length} 处），见上方 diff。');
    }

    print('[l3-anchor] 比对通过：L3 全部词条与基线字节级一致 ✓');
    expect(diffs, isEmpty);
  });
}
