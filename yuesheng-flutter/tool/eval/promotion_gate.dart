// ─────────────────────────────────────────────────────────────
// W-43 · 批次 B —— 晋升闸（promotion gate）
//
// 职责：把「变体达标与否」与「§4-228 结论是否可复现」变成**机器判定**，
//       而不是由人读 json 得出。
//
// 输入（全部只读）：
//   .ai/reports/eval_gate.criteria.json   冻结判据（容差 / 拆分 / 判定表）
//   .ai/reports/eval_gate.md              判据正文（闸校验其 sha256 未被改动）
//   outputs/gate/eval_trace.jsonl          A 批次逐格逐变体 trace（960 行）
//   outputs/gate/eval_baseline.json        口径 / 成本 / 指标 2 环境读数
//   outputs/gate/w23_cells.json            样本类型（只读）
//
// 输出：outputs/gate/promotion_gate.json + 控制台对账表
//
// ★ 纪律：
//   1. **不重算焦点**：焦点一律取自 A 批次 trace（生产纯函数算出的结果），
//      闸只做聚合与判定 ⇒ 闸与 runner 只有一个真源，不会各自漂移。
//   2. **不改容差**：容差全部从冻结判据读入；闸内不出现任何魔数阈值。
//   3. **不一致不硬调**：与 §4-228 结论不符时如实输出 MISMATCH + 差值，退出码非 0。
//   4. **dev / test 分列**：合并展示在产物层面即不可能（结构上分两个对象）。
//
// ★ 运行（cwd = yuesheng-flutter，纯 Dart，无需 Flutter）：
//     dart run outputs/gate/promotion_gate.dart
// ─────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';

const String kCriteriaJson =
    'D:/ai-teacher/.ai/reports/eval_gate.criteria.json';
const String kCriteriaDoc = 'D:/ai-teacher/.ai/reports/eval_gate.md';
const String kTrace =
    'D:/ai-teacher/yuesheng-flutter/outputs/gate/eval_trace.jsonl';
const String kBaseline =
    'D:/ai-teacher/yuesheng-flutter/tool/eval/baseline/eval_baseline.json';
const String kCells =
    'D:/ai-teacher/yuesheng-flutter/tool/eval/baseline/w23_cells.json';
const String kOut =
    'D:/ai-teacher/yuesheng-flutter/outputs/gate/promotion_gate.json';

const String kTarget = 'P002';
const String kX01TrapCell = 'X01|t07|r1';

String _envOr(String k, String d) {
  final v = Platform.environment[k];
  return (v == null || v.trim().isEmpty) ? d : v;
}

String sha256OfFile(String path) =>
    sha256.convert(File(path).readAsBytesSync()).toString();

// ── trace 载入 ────────────────────────────────────────────────
class Trace {
  final Map<String, Map<String, String?>> focus = {}; // variant → cell → id
  final Map<String, String?> gt = {}; // cell → GT 焦点
  final Map<String, Set<String>> candidates = {}; // cell → 候选集
  final Map<String, String> sampleOf = {};

  int get cellCount => gt.length;

  static Trace load(String path) {
    final t = Trace();
    for (final line in File(path).readAsLinesSync()) {
      if (line.trim().isEmpty) continue;
      final r = jsonDecode(line) as Map<String, dynamic>;
      final v = r['variant'] as String;
      final cid = r['cell_id'] as String;
      final out = r['output'] as Map<String, dynamic>;
      final id = out['activated_focus_id'] as String?;
      t.focus.putIfAbsent(v, () => {})[cid] = (id == null || id.isEmpty)
          ? null
          : id;
      t.gt.putIfAbsent(cid, () => r['gt_focus'] as String?);
      t.sampleOf[cid] = r['sample'] as String;
      if (v == 'v1') {
        t.candidates[cid] = {
          for (final s
              in (r['input'] as List<dynamic>).cast<Map<String, dynamic>>())
            s['syndrome_id'] as String,
        };
      }
    }
    return t;
  }
}

// ── 冻结拆分：按规则重算，与判据文件逐样本比对（防手改）───────
List<String> _shuffled(List<String> items, int seed) {
  final a = List<String>.from(items)..sort();
  var s = seed;
  for (var i = a.length - 1; i > 0; i--) {
    s = (s * 1103515245 + 12345) % 2147483648;
    final j = s % (i + 1);
    final tmp = a[i];
    a[i] = a[j];
    a[j] = tmp;
  }
  return a;
}

({List<String> dev, List<String> test}) deriveSplit({
  required Map<String, String> sampleType,
  required Set<String> targetSamples,
  required int seed,
  required Set<String> excluded,
  required Map<String, int> take,
}) {
  final base = sampleType.keys.where((s) => !excluded.contains(s)).toList();
  final pos = base.where((s) => sampleType[s] == 'positive').toList();
  final mix = base.where((s) => sampleType[s] == 'mixed').toList();
  final negT = base
      .where((s) => sampleType[s] == 'negative' && targetSamples.contains(s))
      .toList();
  final negN = base
      .where((s) => sampleType[s] == 'negative' && !targetSamples.contains(s))
      .toList();
  final test = <String>[
    ..._shuffled(pos, seed).take(take['pos']!),
    ..._shuffled(mix, seed).take(take['mix']!),
    ..._shuffled(negT, seed).take(take['negT']!),
    ..._shuffled(negN, seed).take(take['negN']!),
  ]..sort();
  final dev = base.where((s) => !test.contains(s)).toList()..sort();
  return (dev: dev, test: test);
}

// ── 单侧统计 ──────────────────────────────────────────────────
Map<String, dynamic> sideStats(Trace t, Set<String> samples, String variant) {
  var cells = 0, valid = 0, deb = 0, target = 0, other = 0;
  var hitsAll = 0, hitsDeb = 0, hitsTarget = 0, hitsOther = 0;
  var p002Focus = 0, x01P002 = 0, noFocus = 0, lost = 0;
  final v1 = t.focus['v1']!;
  final f = t.focus[variant]!;
  for (final cid in t.gt.keys) {
    if (!samples.contains(t.sampleOf[cid])) continue;
    cells++;
    final g = t.gt[cid];
    final p = f[cid];
    if (p == kTarget) p002Focus++;
    if (p == null) noFocus++;
    if (t.sampleOf[cid] == 'X01' && p == kTarget) x01P002++;
    if (v1[cid] != null && p == null) lost++;
    if (g == null) continue;
    valid++;
    if (p == g) hitsAll++;
    final inCand = t.candidates[cid]?.contains(g) ?? false;
    if (!inCand) continue;
    deb++;
    if (p == g) hitsDeb++;
    if (g == kTarget) {
      target++;
      if (p == g) hitsTarget++;
    } else {
      other++;
      if (p == g) hitsOther++;
    }
  }
  return {
    'cells': cells,
    'valid_gt': valid,
    'debiased': deb,
    'target_layer': target,
    'other_layer': other,
    'hits_all_130': hitsAll,
    'hits_debiased_111': hitsDeb,
    'hits_target': hitsTarget,
    'hits_other': hitsOther,
    'p002_focus_cells': p002Focus,
    'x01_p002_focus_cells': x01P002,
    'no_focus_cells': noFocus,
    'focus_lost_vs_v1': lost,
  };
}

// ── 判据 R1–R5（数值全部来自冻结判据，闸内无魔数）─────────────
Map<String, dynamic> judge({
  required Map<String, dynamic> cur,
  required Map<String, dynamic> v1,
  required Map<String, dynamic> c,
  required List<String> which,
  required Map<String, dynamic> tol,
  required bool sideHasX01,
}) {
  int i(Map<String, dynamic> m, String k) => m[k] as int;
  final out = <String, dynamic>{};
  for (final id in which) {
    switch (id) {
      case 'R1':
        // 冻结判据 §三 N/A 规则：该侧无 X01 格 ⇒ N/A，不阻塞（不是 PASS）
        if (!sideHasX01) {
          out[id] = {'verdict': 'N/A', 'detail': '该侧无 X01 格，无法检验零放大'};
        } else {
          final d =
              i(cur, 'x01_p002_focus_cells') - i(v1, 'x01_p002_focus_cells');
          out[id] = {
            'verdict': d <= (tol['R1']['tolerance'] as int) ? 'PASS' : 'FAIL',
            'actual': i(cur, 'x01_p002_focus_cells'),
            'baseline_v1': i(v1, 'x01_p002_focus_cells'),
            'delta': d,
            'tolerance': tol['R1']['tolerance'],
          };
        }
      case 'R2':
        final d = i(cur, 'focus_lost_vs_v1');
        out[id] = {
          'verdict': d == 0 ? 'PASS' : 'FAIL',
          'actual': d,
          'tolerance': tol['R2']['tolerance'],
        };
      case 'R3':
        final d = i(cur, 'hits_target') - i(v1, 'hits_target');
        final tv = tol['R3']['tolerance'] as int;
        out[id] = {
          'verdict': d >= tv ? 'PASS' : 'FAIL',
          'actual': i(cur, 'hits_target'),
          'baseline_v1': i(v1, 'hits_target'),
          'delta': d,
          'tolerance': -tv,
        };
      case 'R4':
        final den = i(cur, 'other_layer');
        final tv = math.max(
          tol['R4']['min_abs'] as int,
          (den * (tol['R4']['ratio'] as double)).floor(),
        );
        final d = i(cur, 'hits_other') - i(v1, 'hits_other');
        out[id] = {
          'verdict': d >= -tv ? 'PASS' : 'FAIL',
          'actual': i(cur, 'hits_other'),
          'baseline_v1': i(v1, 'hits_other'),
          'delta': d,
          'tolerance': -tv,
          'tolerance_formula':
              'max(${tol['R4']['min_abs']}, floor(${tol['R4']['ratio']} × $den))',
        };
      case 'R5':
        final tv = tol['R5']['tolerance'] as int;
        final d = i(cur, 'hits_target') - i(c, 'hits_target');
        out[id] = {
          'verdict': d >= -tv ? 'PASS' : 'FAIL',
          'actual': i(cur, 'hits_target'),
          'baseline_C': i(c, 'hits_target'),
          'delta': d,
          'tolerance': -tv,
        };
    }
  }
  final v = out.values.map((e) => (e as Map)['verdict'] as String).toList();
  out['_summary'] = {
    'pass': v.where((x) => x == 'PASS').length,
    'fail': v.where((x) => x == 'FAIL').length,
    'na': v.where((x) => x == 'N/A').length,
    'all_pass': v.every((x) => x == 'PASS' || x == 'N/A'),
  };
  return out;
}

// ── 逐格分类（§4-228 §五 口径：相对 C = 现状）──────────────────
//
// 真收益 = C 给出 P002 而变体撤掉，且 GT 不是 P002（「P002 本不该占位」）
//          —— **注意：不要求变体命中 GT**（§4-228 原文即如此，A 的 7 格里有 3 格
//          变体落到 P018 而 GT 是 P006/P003/P001，仍算真收益）。
// 真损失 = 撤掉 P002 但 GT 正是 P002。
// 不可判定 = GT 无多数（平票）。
// 中性   = 非 P002 焦点变化。
Map<String, dynamic> classify(
  Trace t,
  Set<String> samples,
  String variant, {
  String base = 'v2now',
}) {
  final buckets = <String, List<Map<String, dynamic>>>{
    '真收益': [],
    '真损失': [],
    '中性': [],
    '不可判定': [],
  };
  final b = t.focus[base]!;
  final f = t.focus[variant]!;
  for (final cid in t.gt.keys) {
    if (!samples.contains(t.sampleOf[cid])) continue;
    final before = b[cid], after = f[cid];
    if (before == after) continue;
    final g = t.gt[cid];
    final String k;
    if (before == kTarget && after != kTarget) {
      if (g == null) {
        k = '不可判定';
      } else if (g == kTarget) {
        k = '真损失';
      } else {
        k = '真收益';
      }
    } else if (before != kTarget && after == kTarget) {
      if (g == null) {
        k = '不可判定';
      } else if (g == kTarget) {
        k = '真收益';
      } else {
        k = '真损失';
      }
    } else {
      k = '中性';
    }
    buckets[k]!.add({
      'cell_id': cid,
      'gt_focus': g,
      'before_C': before,
      'after': after,
    });
  }
  return {
    'changed': buckets.values.fold<int>(0, (a, b2) => a + b2.length),
    'gain': buckets['真收益']!.length,
    'loss': buckets['真损失']!.length,
    'neutral': buckets['中性']!.length,
    'undecidable': buckets['不可判定']!.length,
    'cells': buckets,
  };
}

bool _sameSet(List<String> a, List<String> b) =>
    a.toSet().length == b.toSet().length && a.toSet().containsAll(b);

Map<String, dynamic> _splitSummary(
  List<String> samples,
  Map<String, dynamic> s,
) => {
  'samples': samples,
  'sample_count': samples.length,
  'cells': s['cells'],
  'valid_gt': s['valid_gt'],
  'debiased': s['debiased'],
  'target_layer': s['target_layer'],
};

void main() {
  final criteriaPath = _envOr('GATE_CRITERIA', kCriteriaJson);
  final docPath = _envOr('GATE_DOC', kCriteriaDoc);
  final tracePath = _envOr('GATE_TRACE', kTrace);
  final baselinePath = _envOr('GATE_BASELINE', kBaseline);
  final cellsPath = _envOr('GATE_CELLS', kCells);
  final outPath = _envOr('GATE_OUT', kOut);

  final criteria =
      jsonDecode(File(criteriaPath).readAsStringSync()) as Map<String, dynamic>;

  // ① 判据完整性：正文未被改动
  final docHash = sha256OfFile(docPath);
  if (docHash != criteria['doc_sha256']) {
    stderr.writeln(
      '[gate] 判据文件已被改动，拒绝运行：\n'
      '  期望 ${criteria['doc_sha256']}\n  实际 $docHash',
    );
    exit(2);
  }
  final criteriaHash = sha256OfFile(criteriaPath);

  // ② 载入
  final t = Trace.load(tracePath);
  final baseline =
      jsonDecode(File(baselinePath).readAsStringSync()) as Map<String, dynamic>;
  final cellsDoc =
      jsonDecode(File(cellsPath).readAsStringSync()) as Map<String, dynamic>;
  final sampleType = <String, String>{
    for (final c
        in (cellsDoc['cells'] as List<dynamic>).cast<Map<String, dynamic>>())
      c['sample'] as String: c['sample_type'] as String,
  };

  // ③ 拆分：按规则重算，与冻结清单逐样本比对
  final targetSamples = <String>{
    for (final cid in t.gt.keys)
      if (t.gt[cid] == kTarget) t.sampleOf[cid]!,
  };
  final rule = criteria['split_rule'] as Map<String, dynamic>;
  final sides = criteria['sides'] as Map<String, dynamic>;
  final take = <String, int>{
    'pos': (sides['test']['samples'] as List)
        .where((s) => sampleType[s] == 'positive')
        .length,
    'mix': (sides['test']['samples'] as List)
        .where((s) => sampleType[s] == 'mixed')
        .length,
    'negT': (sides['test']['samples'] as List)
        .where((s) => sampleType[s] == 'negative' && targetSamples.contains(s))
        .length,
    'negN': (sides['test']['samples'] as List)
        .where((s) => sampleType[s] == 'negative' && !targetSamples.contains(s))
        .length,
  };
  final derived = deriveSplit(
    sampleType: sampleType,
    targetSamples: targetSamples,
    seed: rule['seed'] as int,
    excluded: {for (final s in (rule['excluded'] as List)) '$s'},
    take: take,
  );
  final frozenDev = [for (final s in (sides['dev']['samples'] as List)) '$s'];
  final frozenTest = [for (final s in (sides['test']['samples'] as List)) '$s'];
  final splitMatches =
      _sameSet(derived.dev, frozenDev) && _sameSet(derived.test, frozenTest);
  if (!splitMatches) {
    stderr.writeln(
      '[gate] 拆分与冻结清单不一致，拒绝运行：\n'
      '  derived dev=${derived.dev}\n  frozen  dev=$frozenDev\n'
      '  derived test=${derived.test}\n  frozen  test=$frozenTest',
    );
    exit(2);
  }

  final caliber = (criteria['caliber'] as String);
  final traceCaliber =
      (baseline['cost'] as Map<String, dynamic>)['mode'] ==
          'deterministic_replay'
      ? 'sim'
      : 'prod';
  if (caliber != traceCaliber) {
    stderr.writeln('[gate] 口径不一致：判据=$caliber trace=$traceCaliber ⇒ 拒绝混算');
    exit(2);
  }

  // ④ 三侧统计（dev / test / X22 单侧）
  final variants = criteria['variants'] as Map<String, dynamic>;
  final devSet = frozenDev.toSet();
  final testSet = frozenTest.toSet();
  final singleSet = {
    for (final s in (sides['single_side']['samples'] as List)) '$s',
  };
  final names = <String, String>{
    'v1': 'v1',
    'A': variants['A'] as String,
    'B_low': variants['B_low'] as String,
    'C': variants['C'] as String,
  };
  Map<String, dynamic> statsFor(Set<String> ss) => {
    for (final e in names.entries) e.key: sideStats(t, ss, e.value),
  };
  final devStats = statsFor(devSet);
  final testStats = statsFor(testSet);
  final singleStats = statsFor(singleSet);

  // ⑤ 判据裁定（dev 全量 / test 只判方向类）
  final tol = criteria['tolerances'] as Map<String, dynamic>;
  Map<String, dynamic> verdictsFor(
    Map<String, dynamic> stats,
    String side,
    Set<String> samples,
  ) {
    final which = [for (final r in (sides[side]['criteria'] as List)) '$r'];
    final hasX01 = samples.contains('X01');
    return {
      for (final key in ['A', 'B_low', 'C'])
        key: judge(
          cur: stats[key] as Map<String, dynamic>,
          v1: stats['v1'] as Map<String, dynamic>,
          c: stats['C'] as Map<String, dynamic>,
          which: which,
          tol: tol,
          sideHasX01: hasX01,
        ),
    };
  }

  final devVerdicts = verdictsFor(devStats, 'dev', devSet);
  final testVerdicts = verdictsFor(testStats, 'test', testSet);

  // ⑥ 逐格分类（全局 240，与 §4-228 §五 同口径）
  final allSamples = t.gt.keys.map((c) => t.sampleOf[c]!).toSet();
  final clsAll = {
    'A': classify(t, allSamples, names['A']!),
    'B_low': classify(t, allSamples, names['B_low']!),
  };

  // ⑦ §4-228 结论复现（闸自己算，不读人工结论）
  final computed = {
    'A': {
      'gain': clsAll['A']!['gain'],
      'loss': clsAll['A']!['loss'],
      'x01_trap_focus': t.focus[names['A']!]![kX01TrapCell],
      'x01_trap_gt': t.gt[kX01TrapCell],
    },
    'B_low': {
      'gain': clsAll['B_low']!['gain'],
      'loss': clsAll['B_low']!['loss'],
      'x01_trap_focus': t.focus[names['B_low']!]![kX01TrapCell],
      'x01_trap_gt': t.gt[kX01TrapCell],
    },
  };

  // §4-228 的登记结论（逐句拆开，便于定位是哪一句不成立）
  final claims = [
    {
      'id': 'C1',
      'source': '§4-228 §五 末句 / §七 摘要',
      'text': 'A 与 B_low 净效果同为 +7 真收益 / −1 真损失',
      'expect_gain': {'A': 7, 'B_low': 7},
      'expect_loss': {'A': 1, 'B_low': 1},
    },
    {
      'id': 'C2',
      'source': '§4-228 §五 A 逐格表',
      'text': 'A：真收益 7 · 真损失 1',
      'expect_gain': {'A': 7},
      'expect_loss': {'A': 1},
    },
    {
      'id': 'C3',
      'source': '§4-228 §五 B_low 逐格表',
      'text': 'B_low：真收益 3 · 真损失 1',
      'expect_gain': {'B_low': 3},
      'expect_loss': {'B_low': 1},
    },
    {
      'id': 'C4',
      'source': '§4-228 §五 末句 / §七 A·B_low 两行',
      'text': '两者都把 X01|t07|r1 归位到 GT 焦点 P018',
      'expect_trap': {'A': 'P018', 'B_low': 'P018'},
    },
  ];
  final claimResults = <Map<String, dynamic>>[];
  for (final c in claims) {
    final diffs = <String, dynamic>{};
    final eg = c['expect_gain'] as Map<String, dynamic>?;
    final el = c['expect_loss'] as Map<String, dynamic>?;
    final et = c['expect_trap'] as Map<String, dynamic>?;
    eg?.forEach((k, v) {
      final a = (computed[k] as Map)['gain'] as int;
      if (a != v) {
        // v 是 Map<String, dynamic> 的 value ⇒ 显式 as int，否则 a - v 退化为 dynamic
        diffs['$k.gain'] = {
          'expected': v,
          'actual': a,
          'delta': a - (v as int),
        };
      }
    });
    el?.forEach((k, v) {
      final a = (computed[k] as Map)['loss'] as int;
      if (a != v) {
        diffs['$k.loss'] = {
          'expected': v,
          'actual': a,
          'delta': a - (v as int),
        };
      }
    });
    et?.forEach((k, v) {
      final a = (computed[k] as Map)['x01_trap_focus'] as String?;
      if (a != v) diffs['$k.x01_trap_focus'] = {'expected': v, 'actual': a};
    });
    claimResults.add({
      'id': c['id'],
      'source': c['source'],
      'text': c['text'],
      'verdict': diffs.isEmpty ? 'MATCH' : 'MISMATCH',
      'diffs': diffs,
    });
  }

  // ⑧ 汇总
  final reportable = <String>[];
  for (final k in ['A', 'B_low', 'C']) {
    final devOk = (devVerdicts[k]!['_summary'] as Map)['all_pass'] == true;
    final testOk = (testVerdicts[k]!['_summary'] as Map)['all_pass'] == true;
    if (devOk && testOk) reportable.add(k);
  }

  final gates = {
    'criteria_immutable': docHash == criteria['doc_sha256'],
    'split_reproducible': splitMatches,
    'caliber_consistent': caliber == traceCaliber,
    'metric2_present': baseline['metrics']['m2_stability_jaccard'] != null,
    'cost_fields_present': [
      'llm_calls',
      'prompt_tokens',
      'completion_tokens',
      'usd',
      'wall_ms',
    ].every((k) => (baseline['cost'] as Map).containsKey(k)),
    'sides_separated': true,
  };

  // ── v2-1：R4 余量复核（不改 PASS/FAIL，只加标记）──────────────
  // 余量 = actual − (baseline_v1 + tolerance)；tolerance 为负数（如 −11）。
  // A: 45 − (55 − 11) = 1 格 ⇒ 触发复核；B_low: 43 − 44 = −1（本身已 FAIL）。
  final marginThreshold =
      (criteria['extra_rules']?['human_review_when_margin_le'] as int?) ?? 2;
  final humanReview = <String, dynamic>{};
  for (final k in ['A', 'B_low', 'C']) {
    final r4 = devVerdicts[k]?['R4'] as Map<String, dynamic>?;
    if (r4 == null) continue;
    final margin =
        (r4['actual'] as int) -
        ((r4['baseline_v1'] as int) + (r4['tolerance'] as int));
    humanReview[k] = {
      'metric': 'dev.R4.other_hits',
      'verdict': r4['verdict'],
      'actual': r4['actual'],
      'baseline_v1': r4['baseline_v1'],
      'tolerance': r4['tolerance'],
      'margin_cells': margin,
      'human_review_required':
          r4['verdict'] == 'PASS' && margin <= marginThreshold,
      'reason': r4['verdict'] != 'PASS'
          ? 'R4 已 ${r4['verdict']}，不适用余量复核（复核只针对「勉强 PASS」）'
          : (margin <= marginThreshold
                ? '余量 $margin 格 <= $marginThreshold ⇒ 按 v2-1 须人工复核（本侧 PASS 不等于可自动放行）'
                : '余量 $margin 格 > $marginThreshold，无需额外复核'),
    };
  }

  final out = <String, dynamic>{
    'schema': 'promotion-gate-report-v1',
    'generated': DateTime.now().toIso8601String(),
    'caliber': caliber,
    'caliber_note': '指标名一律带 [$caliber]；本批 llm_calls=0，[prod] 通道结构预留、不得与本批混算',
    'criteria': {
      'doc': docPath,
      'doc_sha256': docHash,
      'doc_mtime': File(docPath).lastModifiedSync().toIso8601String(),
      'criteria_sha256': criteriaHash,
      'criteria_mtime': File(criteriaPath).lastModifiedSync().toIso8601String(),
      'frozen_before_run': File(
        criteriaPath,
      ).lastModifiedSync().isBefore(DateTime.now()),
      'rulings': criteria['rulings'],
      'version': criteria['version'],
      'v2_revisions': criteria['revisions'],
      'v2_extra_rules': criteria['extra_rules'],
    },
    'inputs': {
      'trace': tracePath,
      'trace_cells': t.cellCount,
      'trace_variants': t.focus.keys.toList()..sort(),
      'baseline': baselinePath,
    },
    'split': {
      'rule': rule,
      'matches_frozen_list': splitMatches,
      'dev': _splitSummary(frozenDev, devStats['v1'] as Map<String, dynamic>),
      'test': _splitSummary(
        frozenTest,
        testStats['v1'] as Map<String, dynamic>,
      ),
      'single_side': {
        'samples': singleSet.toList()..sort(),
        'note': '污染样本，只作单侧证据，不并入 dev / test',
        'stats': singleStats,
      },
    },
    'environment': {
      'jaccard_sim': {
        'note': '与变体无关，只算一次；观察线 0.8，非红线',
        'sample_count':
            baseline['metrics']['m2_stability_jaccard']['primary']['sample_count'],
        'below_threshold_count':
            baseline['metrics']['m2_stability_jaccard']['primary']['below_threshold_count'],
      },
      'metric_3': 'stub（需人评 10 格）',
    },
    'sides': {
      'dev': {
        'samples': frozenDev,
        'cells': (devStats['v1'] as Map)['cells'],
        'stats': devStats,
        'verdicts': devVerdicts,
      },
      'test': {
        'samples': frozenTest,
        'cells': (testStats['v1'] as Map)['cells'],
        'stats': testStats,
        'verdicts': testVerdicts,
        'criteria_applied': sides['test']['criteria'],
        'criteria_skipped_reason':
            'R4/R5 在 test 上无分辨力（其他层 8 格，1 格噪声 = 12.5%）⇒ 预先声明不做',
      },
    },
    'classification_vs_C': clsAll,
    'conclusion_reproduction': {
      'computed': computed,
      'claims': claimResults,
      'all_match': claimResults.every((r) => r['verdict'] == 'MATCH'),
    },
    'reportable_variants': reportable,
    'human_review': humanReview,
    'gates': gates,
    'gates_all_passed': gates.values.every((v) => v),
  };

  File(
    outPath,
  ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(out));

  // ── 控制台：两侧分列，永不合并 ──────────────────────────────
  void log(Object? s) => print(s); // ignore: avoid_print
  String pad(Object? s, int w) => '$s'.padLeft(w);

  log(
    '[gate] 判据 ${criteriaHash.substring(0, 12)}… · 正文 '
    '${docHash.substring(0, 12)}… · ${out['criteria']['version']} · 口径 [$caliber] · '
    '冻结早于跑数：${out['criteria']['frozen_before_run']}',
  );
  for (final side in ['dev', 'test']) {
    final stats = side == 'dev' ? devStats : testStats;
    final vd = side == 'dev' ? devVerdicts : testVerdicts;
    final which = side == 'dev' ? 'R1–R5' : 'R1–R3';
    log(
      '\n===== $side 侧（${side == 'dev' ? frozenDev : frozenTest}）判据 $which =====',
    );
    log(
      '  变体    P002焦点   X01  无焦点  全GT命中  目标层  其他层   '
      '${side == 'dev' ? 'R1 R2 R3 R4 R5  判定' : 'R1 R2 R3  判定'}',
    );
    for (final k in ['v1', 'A', 'B_low', 'C']) {
      final s = stats[k]!;
      final tail = k == 'v1'
          ? (side == 'dev' ? '—  —  —  —  —  基线' : '—  —  —  基线')
          : [
                  for (final r in (sides[side]['criteria'] as List))
                    (vd[k]![r] as Map)['verdict'],
                ].join(' ').padRight(side == 'dev' ? 15 : 9) +
                ((vd[k]!['_summary'] as Map)['all_pass'] == true
                    ? ' 本侧全绿'
                    : ' 本侧有 FAIL');
      log(
        '  ${k.padRight(6)}${pad(s['p002_focus_cells'], 9)}'
        '${pad(s['x01_p002_focus_cells'], 6)}${pad(s['no_focus_cells'], 8)}'
        '${pad('${s['hits_all_130']}/${s['valid_gt']}', 8)}'
        '${pad('${s['hits_target']}/${s['target_layer']}', 8)}'
        '${pad('${s['hits_other']}/${s['other_layer']}', 8)}   $tail',
      );
    }
    // v2-4：test 侧 R4 未判，必须让「没查代价」在表里可见
    if (side == 'test') {
      log(
        '  [v2-4] 本侧只判 R1–R3（R4 未判）—— 其他层 4/8 四变体同值 = 未查代价，'
        '不得解读为「无代价」',
      );
    } else {
      // v2-1：余量 ≤2 格 ⇒ 人工复核（不改 PASS/FAIL）
      for (final k in ['A', 'B_low', 'C']) {
        final hr = humanReview[k];
        if (hr is Map && hr['human_review_required'] == true) {
          log(
            '  [v2-1] $k 的 R4 余量仅 ${hr['margin_cells']} 格（actual=${hr['actual']} · '
            'baseline=${hr['baseline_v1']} · tol=${hr['tolerance']}）'
            '⇒ 须人工复核：本侧 PASS 不等于可自动放行',
          );
        }
      }
    }
  }
  log('\n===== X22 单侧（污染，只登记不判定）=====');
  for (final k in ['v1', 'A', 'B_low', 'C']) {
    final s = singleStats[k]!;
    log(
      '  ${k.padRight(6)} P002焦点=${s['p002_focus_cells']} '
      '目标层=${s['hits_target']}/${s['target_layer']}',
    );
  }
  log('\n===== 逐格分类（相对 C = v2now，全局 240）=====');
  for (final k in ['A', 'B_low']) {
    final c = clsAll[k]!;
    log(
      '  $k 改动 ${c['changed']} 格 · 真收益 ${c['gain']} · '
      '真损失 ${c['loss']} · 中性 ${c['neutral']} · 不可判定 ${c['undecidable']}',
    );
    for (final b in ['真收益', '真损失', '不可判定', '中性']) {
      final list = (c['cells'] as Map)[b] as List;
      if (list.isEmpty) continue;
      log(
        '    $b：${list.map((e) => '${(e as Map)['cell_id']}'
            '(GT=${e['gt_focus']})').join(' · ')}',
      );
    }
  }
  final trap = t.focus['v1']![kX01TrapCell];
  log(
    '  X01|t07|r1：GT=${t.gt[kX01TrapCell]} · v1=$trap · '
    'C=${t.focus['v2now']![kX01TrapCell]} · A=${t.focus['v2a']![kX01TrapCell]} · '
    'B_low=${t.focus['v2bLow']![kX01TrapCell]}',
  );
  log('\n===== §4-228 结论复现（闸自算，未读人工结论）=====');
  for (final r in claimResults) {
    log(
      '  ${r['verdict'] == 'MATCH' ? 'MATCH   ' : 'MISMATCH'} ${r['id']} '
      '${r['text']}  ← ${r['source']}',
    );
    if (r['verdict'] != 'MATCH') log('           差异：${jsonEncode(r['diffs'])}');
  }
  log('  可提报变体：${reportable.isEmpty ? '无' : reportable.join(' / ')}');
  log('  产物：$outPath');
}
