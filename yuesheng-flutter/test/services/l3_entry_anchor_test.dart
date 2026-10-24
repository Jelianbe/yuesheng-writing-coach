// ignore_for_file: avoid_print
// ─────────────────────────────────────────────────────────────
// L3 知识库「词条级」行为锚点（字节级）— 补 P3 覆盖缺口
//
// 背景（docs/research/2026-09-13-injection-refinement-guardrail-gaps.md §G-2）：
//   test/snapshots/skill_prompt_anchor.json 的 l3Inject 只覆盖 4 个注入组合
//   （P001 / T001+T008 / P001+P005+T001 / 空），L3 **逐词条正文**无字节级保护。
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
    final file = File(kL3AnchorPath);
    final exists = file.existsSync();

    // ── fail-closed 守卫（T-20261024-14 B 块；与 -13 B 块同形）────────────
    // 旧写法 `if (updating || !file.existsSync())` 把两件事并成一个分支：
    //   「显式重生成」与「快照缺失」⇒ 快照被误删 / 误移 / 未检出时本用例**照样绿**，
    //   并把当前装配静默写成新基线（此刻 lib 侧若有漂移，基线即被替换成漂移后的值
    //   ⇒ 之后再不会红）。本文件**门禁侧无兜底**（`scripts/` `tool/` `.ai/tools/`
    //   全量 grep 无任何脚本读该快照）⇒ 测试侧是唯一一道。
    // ★ 守卫前置于 _buildCurrent()：否则词条检索里任一环节抛错会先红，
    //   「快照缺失」这个真因会被后者的报错遮住（判据落点须指向缺失本身）。
    if (!exists && !updating) {
      fail(
        '[l3-anchor] 锚点快照缺失：$kL3AnchorPath\n'
        '  ★ 快照文件缺失 = 事故，不是常态（该文件本应随仓库一起检出）。\n'
        '  缺失时**不得**自动生成基线 —— 那等于用「当前行为」重写判据，'
        '任何漂移都会被静默转绿。\n'
        '  先查三因：误删 / 误移 / 未检出'
        '（git status --porcelain、git ls-files test/snapshots/）。\n'
        '  确需重建（基线变更须可对账、须经评审）：\n'
        '    UPDATE_SNAPSHOTS=true flutter test '
        'test/services/l3_entry_anchor_test.dart',
      );
    }

    // 组装确定性自检：同一词条连跑两遍，输出必须一致。
    final probeId = _syndromeEntryIds.first;
    final first = getSyndromeContent([probeId]);
    final second = getSyndromeContent([probeId]);
    expect(first, second, reason: 'L3 检索非确定性');

    final current = _buildCurrent();

    if (updating) {
      // ── 显式重建通路（UPDATE_SNAPSHOTS=true）──────────────────────────
      // 允许写，但**必须打告警**：本分支不做任何比对，写出的就是新判据。
      // 旧措辞「基线已生成」与正常日志无法区分 ⇒ 重建被误读成「校验通过」。
      final hadSnapshot = exists;
      file
        ..createSync(recursive: true)
        ..writeAsStringSync(
          '${const JsonEncoder.withIndent('  ').convert(current)}\n',
        );
      print(
        '[l3-anchor][告警] UPDATE_SNAPSHOTS=true ⇒ 基线被强制覆盖：'
        '$kL3AnchorPath（syndrome ${_syndromeEntryIds.length} / '
        'technique ${_techniqueEntryIds.length} / '
        'training ${_trainingEntryIds.length} 条）',
      );
      print(
        '[l3-anchor][告警] 本次**未做任何比对**，这不是校验通过；'
        '原快照${hadSnapshot ? '已被丢弃' : '本就不存在（本次为新建）'}。',
      );
      print('[l3-anchor][告警] 提交前必须逐条复核 git diff $kL3AnchorPath。');

      // 回读校验：写入成功 ≠ 写出的是完整基线（截断 / 空文件同样「存在」）。
      final reread = jsonDecode(file.readAsStringSync());
      final written = reread is Map<String, dynamic>
          ? reread
          : const <String, dynamic>{};
      for (final section in const ['syndrome', 'technique', 'training']) {
        final got = written[section];
        if (got is! Map || got.isEmpty) {
          fail(
            '[l3-anchor] 基线写入不完整：section `$section` '
            '${got == null ? '缺失' : '为空或类型错误（${got.runtimeType}）'}',
          );
        }
      }
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
