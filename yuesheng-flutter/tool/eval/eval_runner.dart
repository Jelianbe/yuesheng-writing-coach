// ─────────────────────────────────────────────────────────────
// W-42 · 批次 A —— 常设 eval runner（确定性重算，不跑真 LLM）
//
// 来源：`w23_option_probe_test.dart`（一次性探针）升级为**可重复 / 可比较**的
//       eval runner：入参 = 变体定义 + 数据路径；出参 = 三指标 + 逐格 trace + 成本字段。
//
// ★ 口径纪律（DECISIONS §4-228，本 runner **不复刻、不改口径**）：
//   · 焦点一律由**生产纯函数** `resolveTeachingFocus` 算出（禁 Python 复刻）；
//   · 变体 = **喂给生产函数的形态字段组合**，`lib/` 一个字节都不改：
//       第三通道 `_formEvidenceBulk` 只由 `FocusProblem.formFactCount` /
//       `formStructure` 两个字段决定 ⇒ 改喂入值即等价换判据。
//   · 四变体（直接复用 §4-228 定义，不自创）：
//       v1     两字段全 null        （v1 忠实代理：闸无第三通道）
//       v2now  当前实现              （bulk = {expository, interruption}）
//       v2a    interruption 置 null  （≡ bulk 收窄为 {expository}）
//       v2bLow interruption 需 fact≥5
//
// ★ 三指标：
//   1 焦点命中率 —— 两个口径**同时**给：全 130 格 + 去偏置 111 格分层（目标层 27 / 其他层 84）。
//   2 稳定性 Jaccard —— 同一样本同温度 r1–r5 五 round 的症候集合两两 Jaccard（10 对）取均值；
//      按样本列出，并统计「样本级均值 < 0.8」的样本数。**不需重跑**，cells 里已有 5 round。
//   3 教学针对性 —— **本批不实现**，留桩（需人评 10 格抽样子集，见 W-47）。
//
// ★ 数据源（重要，见报告 §三「输入错位」）：
//   变体所需的两个形态字段 `form_fact_count` / `form_structure` **不在**
//   `w23_cells.json` 里（实测该文件 syndromes 只有 6 个键，无形态字段），
//   而在 `w23_sim/answers/*.json`。§4-228 的全部读数即由 answers 算出。
//   ⇒ 本 runner 的变体输入 = answers；`w23_cells.json` 作 **GT 侧元数据 / Jaccard /
//     样本清单** 的交叉源（只读），两者并列登记、不混算。
//   （若强行只用 w23_cells.json：形态字段恒 null ⇒ 四变体全部退化为 v1 ⇒
//     P002 焦点格恒 41，无法复现 §4-228 的 77/68/72。）
//
// ★ 运行（cwd = yuesheng-flutter，一条命令）：
//     flutter test outputs/gate/eval_runner.dart
//   路径可用环境变量覆盖（默认值即本仓现状）：
//     EVAL_CELLS / EVAL_ANSWERS / EVAL_GT / EVAL_OUT / EVAL_TRACE
//
// ★ 产物：
//   outputs/gate/eval_baseline.json   —— 指标 + 门禁 + 成本 + 与 §4-228 的对账（可 diff）
//   outputs/gate/eval_trace.jsonl     —— 逐格逐变体 trace（每行可回放：输入 + 输出）
// ─────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/focus_resolver.dart';
import 'package:writingcoach/types/teaching_types.dart';

// ── 默认路径（本仓现状；均可用环境变量覆盖）──────────────────
const String kDefaultCells =
    'D:/ai-teacher/yuesheng-flutter/tool/eval/baseline/w23_cells.json';
const String kDefaultAnswers =
    'D:/ai-teacher/.ai/research/cross-validation/data/w23_sim/answers';
const String kDefaultGtDir =
    'D:/ai-teacher/.ai/research/cross-validation/data/w23';
const String kDefaultOut =
    'D:/ai-teacher/yuesheng-flutter/tool/eval/baseline/eval_baseline.json';
const String kDefaultTrace =
    'D:/ai-teacher/yuesheng-flutter/outputs/gate/eval_trace.jsonl';

/// GT 标注方（顺序固定；ai1 的 part1/part2 是分片草稿，**不得**读入——会重复计票）。
const List<String> kGtAnnotators = ['a2', 'ai1', 'blind_a', 'blind_b'];

/// 去偏置分层用的目标症候（v2 第三通道的目标）。
const String kTarget = 'P002';

String _envOr(String key, String fallback) {
  final v = Platform.environment[key];
  return (v == null || v.trim().isEmpty) ? fallback : v;
}

// ── 变体定义（§4-228 原样复用）────────────────────────────────
enum Variant { v1, v2now, v2a, v2bLow }

const Map<Variant, String> kVariantNote = {
  Variant.v1: '形态两字段全 null（v1 忠实代理：闸无第三通道）',
  Variant.v2now: '当前实现（bulk = {expository, interruption}）',
  Variant.v2a: 'interruption 置 null（≡ bulk 收窄为 {expository}）',
  Variant.v2bLow: 'interruption 需 fact≥5（门槛提高）',
};

/// 该变体下该症候实际喂给生产函数的形态字段（null = 无形态证据）。
({int? fact, String? structure}) formFor(Map<String, dynamic> s, Variant v) {
  final fc = normalizeFormFactCount(s['form_fact_count']);
  final fs = normalizeFormStructure(s['form_structure']);
  switch (v) {
    case Variant.v1:
      return (fact: null, structure: null);
    case Variant.v2now:
      return (fact: fc, structure: fs);
    case Variant.v2a:
      return (fact: fc, structure: fs == 'interruption' ? null : fs);
    case Variant.v2bLow:
      if (fs == 'interruption') {
        return (fact: fc, structure: (fc != null && fc >= 5) ? fs : null);
      }
      return (fact: fc, structure: fs);
  }
}

// ── 数据模型 ──────────────────────────────────────────────────
class RawCell {
  final String cellId;
  final String sample;
  final String tempToken; // 't03' / 't07'
  final int round;
  final List<Map<String, dynamic>> syndromes;

  RawCell({
    required this.cellId,
    required this.sample,
    required this.tempToken,
    required this.round,
    required this.syndromes,
  });

  /// 链键：同一样本 + 同一温度的 5 个 round 构成一条链。
  String get chainKey => '$sample|$tempToken';
}

List<RawCell> _parseCell(String cellId, List<dynamic> rawSyndromes) {
  final parts = cellId.split('|');
  final roundToken = parts.length > 2 ? parts[2] : 'r1';
  return [
    RawCell(
      cellId: cellId,
      sample: parts.isNotEmpty ? parts[0] : '',
      tempToken: parts.length > 1 ? parts[1] : '',
      round: int.tryParse(roundToken.replaceAll('r', '')) ?? 0,
      syndromes: rawSyndromes
          .cast<Map<String, dynamic>>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList(),
    ),
  ];
}

/// 读 sim answers 目录（24 个样本分片，每片 10 格）。
List<RawCell> loadAnswers(String dir) {
  final d = Directory(dir);
  if (!d.existsSync()) {
    throw StateError('answers 目录不存在：$dir');
  }
  final files =
      d
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  final cells = <RawCell>[];
  for (final f in files) {
    final doc = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    for (final c
        in (doc['cells'] as List<dynamic>).cast<Map<String, dynamic>>()) {
      cells.addAll(
        _parseCell(c['cell_id'] as String, c['syndromes'] as List<dynamic>),
      );
    }
  }
  cells.sort((a, b) => a.cellId.compareTo(b.cellId));
  return cells;
}

/// 读 w23_cells.json（只读：GT 侧元数据 + Jaccard 交叉源）。
Map<String, Map<String, dynamic>> loadCells(String path) {
  final doc = jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
  final out = <String, Map<String, dynamic>>{};
  for (final c
      in (doc['cells'] as List<dynamic>).cast<Map<String, dynamic>>()) {
    out[c['cell_id'] as String] = c;
  }
  return out;
}

/// GT 标注：cellId → 标注方 → (症候 → 状态)。`skipped` 的判读不计票。
Map<String, Map<String, Map<String, String>>> loadGt(String dir) {
  final out = <String, Map<String, Map<String, String>>>{};
  for (final who in kGtAnnotators) {
    final f = File('$dir/w23_decisions_$who.json');
    if (!f.existsSync()) {
      throw StateError('GT 标注缺失：${f.path}');
    }
    final doc = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    for (final dec
        in (doc['decisions'] as List<dynamic>).cast<Map<String, dynamic>>()) {
      if (dec['skipped'] == true) continue;
      final states = (dec['states'] as Map<String, dynamic>?) ?? const {};
      out.putIfAbsent(dec['cell_id'] as String, () => {})[who] = {
        for (final e in states.entries) e.key: '${e.value}',
      };
    }
  }
  return out;
}

/// GT 焦点口径（**必须与 §4-228 读数逐位一致**）：
/// 该格被 `confirmed` 票数**唯一最高**的症候；平票 / 无 confirmed ⇒ 无有效 GT 焦点。
///
/// ⚠️ 口径发现（不在本批修正，交舰长判）：§4-228 正文写作「多数标注方 confirmed」，
/// 但机器实现必须是**唯一最高票**（不设 >50% 门槛）才能复现其 130 格 / 69 命中；
/// 若按严格多数（票数 > 标注方数 / 2）实现，有效格只有 93 格，读数全不成立。
String? gtFocusOf(
  String cellId,
  Map<String, Map<String, Map<String, String>>> gt,
) {
  final byAnn = gt[cellId];
  if (byAnn == null || byAnn.isEmpty) return null;
  final counts = <String, int>{};
  for (final states in byAnn.values) {
    states.forEach((sid, st) {
      if (st == 'confirmed') counts[sid] = (counts[sid] ?? 0) + 1;
    });
  }
  if (counts.isEmpty) return null;
  var best = 0;
  String? bestId;
  var tie = false;
  counts.forEach((sid, c) {
    if (c > best) {
      best = c;
      bestId = sid;
      tie = false;
    } else if (c == best) {
      tie = true;
    }
  });
  return tie ? null : bestId;
}

// ── 生产纯函数调用（唯一焦点来源）──────────────────────────────
FocusProblem problemFor(Map<String, dynamic> s, Variant v) {
  final f = formFor(s, v);
  return FocusProblem(
    syndromeId: s['syndrome_id'] as String? ?? '',
    syndromeName: (s['name'] as String?) ?? '',
    severity: Severity.fromString(s['severity'] as String?) ?? Severity.l2,
    confirmationStatus: ConfirmationStatus.suspected,
    status: 'active',
    confirmedAt: null,
    formFactCount: f.fact,
    formStructure: f.structure,
  );
}

// 保留为「单格重算」的最小可复用入口：批量路径已内联，本函数供后续 [prod] 逐格
// 比对（见 .ai/reports/eval_prod_sample.json）直接调用，故不删。
// ignore: unreachable_from_main
ResolveFocusOutput resolveFor(RawCell cell, Variant v) {
  return resolveTeachingFocus(
    ResolveFocusInput(
      problems: cell.syndromes.map((s) => problemFor(s, v)).toList(),
      aiSuggestedFocusId: null,
      userFocusOverride: null,
      subphase: null,
      focusHistory: const [],
      studentSkillLevel: null,
    ),
  );
}

Map<String, dynamic> _problemEcho(FocusProblem p) => {
  'syndrome_id': p.syndromeId,
  'severity': p.severity.value,
  'confirmation_status': p.confirmationStatus.value,
  'status': p.status,
  'form_fact_count': p.formFactCount,
  'form_structure': p.formStructure,
};

/// 逐格逐变体执行，返回 trace 行（每行自带完整输入 + 输出 ⇒ 可回放）。
List<Map<String, dynamic>> runTrace(
  List<RawCell> cells,
  Map<String, String?> gtFocus,
) {
  final rows = <Map<String, dynamic>>[];
  for (final c in cells) {
    for (final v in Variant.values) {
      final problems = c.syndromes.map((s) => problemFor(s, v)).toList();
      final out = resolveTeachingFocus(
        ResolveFocusInput(
          problems: problems,
          aiSuggestedFocusId: null,
          userFocusOverride: null,
          subphase: null,
          focusHistory: const [],
          studentSkillLevel: null,
        ),
      );
      rows.add({
        'cell_id': c.cellId,
        'sample': c.sample,
        'temp': c.tempToken,
        'round': c.round,
        'variant': v.name,
        'gt_focus': gtFocus[c.cellId],
        'input': problems.map(_problemEcho).toList(),
        'output': {
          'activated_focus_id': out.activatedFocusId,
          'source': out.source.value,
          'reason': out.reason,
          'reject_reason': out.rejectReason,
        },
      });
    }
  }
  return rows;
}

// ── 指标 1：焦点命中率（两个口径并列）──────────────────────────
double _rate(int hit, int den) => den == 0 ? 0.0 : hit / den;

Map<String, dynamic> metricFocusHit(
  List<Map<String, dynamic>> trace,
  Map<String, String?> gtFocus,
  Map<String, Set<String>> candidateSet,
) {
  // 口径 A：全 130 格（有有效 GT 焦点的格）。
  final valid = gtFocus.entries.where((e) => e.value != null).toList();
  // 口径 B：去偏置 111 格（GT 焦点 ∈ 该格新模拟候选集）。
  final debiased = valid
      .where((e) => candidateSet[e.key]?.contains(e.value) ?? false)
      .toList();
  // 焦点结果索引：variant → cellId → focusId
  final focus = <String, Map<String, String>>{};
  for (final r in trace) {
    focus.putIfAbsent(r['variant'] as String, () => {})[r['cell_id']
            as String] =
        (r['output'] as Map<String, dynamic>)['activated_focus_id']
            as String? ??
        '';
  }

  int hitsIn(List<MapEntry<String, String?>> set, Map<String, String> f) =>
      set.where((e) => f[e.key] == e.value).length;

  final all130 = <String, dynamic>{};
  final deb = <String, dynamic>{};
  final v1Target = hitsIn(
    debiased.where((e) => e.value == kTarget).toList(),
    focus['v1'] ?? const {},
  );
  final v1Other = hitsIn(
    debiased.where((e) => e.value != kTarget).toList(),
    focus['v1'] ?? const {},
  );
  for (final v in Variant.values) {
    final f = focus[v.name] ?? const <String, String>{};
    final h = hitsIn(valid, f);
    final targetSet = debiased.where((e) => e.value == kTarget).toList();
    final otherSet = debiased.where((e) => e.value != kTarget).toList();
    final tHit = hitsIn(targetSet, f);
    final oHit = hitsIn(otherSet, f);
    all130[v.name] = {
      'hits': h,
      'denominator': valid.length,
      'rate': _rate(h, valid.length),
    };
    final dh = hitsIn(debiased, f);
    deb[v.name] = {
      'hits': dh,
      'denominator': debiased.length,
      'rate': _rate(dh, debiased.length),
      'target_layer': {
        'hits': tHit,
        'denominator': targetSet.length,
        'rate': _rate(tHit, targetSet.length),
      },
      'other_layer': {
        'hits': oHit,
        'denominator': otherSet.length,
        'rate': _rate(oHit, otherSet.length),
      },
      'net_vs_v1': {
        'target_delta': tHit - v1Target,
        'other_delta': oHit - v1Other,
        'net': (tHit - v1Target) + (oHit - v1Other),
      },
    };
  }
  return {
    'all_130': {
      'caliber': 'GT 焦点存在（唯一最高 confirmed 票）的全部格；含 P018 结构性偏置',
      'by_variant': all130,
    },
    'debiased_111': {
      'caliber': '限定「GT 焦点 ∈ 该格新模拟候选集」子集；另 19 格为候选集差异伪影',
      'denominator': debiased.length,
      'excluded_as_artifact': valid.length - debiased.length,
      'by_variant': deb,
    },
    'gt_distribution_top': _gtDistribution(valid),
  };
}

List<Map<String, dynamic>> _gtDistribution(
  List<MapEntry<String, String?>> valid,
) {
  final counts = <String, int>{};
  for (final e in valid) {
    counts[e.value!] = (counts[e.value] ?? 0) + 1;
  }
  final list = counts.entries.toList()
    ..sort(
      (a, b) => b.value != a.value
          ? b.value.compareTo(a.value)
          : a.key.compareTo(b.key),
    );
  return [
    for (final e in list)
      {
        'gt_focus': e.key,
        'cells': e.value,
        'rate': _rate(e.value, valid.length),
      },
  ];
}

// ── 指标 2：稳定性 Jaccard ────────────────────────────────────
double jaccard(Set<String> a, Set<String> b) {
  if (a.isEmpty && b.isEmpty) return 1.0;
  final uni = a.union(b).length;
  return uni == 0 ? 1.0 : a.intersection(b).length / uni;
}

/// 同一样本同温度 r1–r5 的症候集合两两 Jaccard（C(5,2)=10 对）取均值。
Map<String, dynamic> metricStability(
  List<RawCell> cells, {
  required String sourceLabel,
}) {
  final chains = <String, Map<int, Set<String>>>{};
  for (final c in cells) {
    chains.putIfAbsent(c.chainKey, () => {})[c.round] = {
      for (final s in c.syndromes) '${s['syndrome_id']}',
    };
  }
  final chainStats = <String, Map<String, dynamic>>{};
  final perSamplePairs = <String, List<double>>{};
  final chainKeys = chains.keys.toList()..sort();
  for (final key in chainKeys) {
    final rounds = chains[key]!;
    final sorted = rounds.keys.toList()..sort();
    final pairs = <Map<String, dynamic>>[];
    final vals = <double>[];
    for (var i = 0; i < sorted.length; i++) {
      for (var j = i + 1; j < sorted.length; j++) {
        final a = rounds[sorted[i]]!;
        final b = rounds[sorted[j]]!;
        final jv = jaccard(a, b);
        vals.add(jv);
        pairs.add({
          'r_a': sorted[i],
          'r_b': sorted[j],
          'jaccard': jv,
          'union': a.union(b).toList()..sort(),
          'intersection': a.intersection(b).toList()..sort(),
        });
      }
    }
    final mean = vals.isEmpty
        ? null
        : vals.reduce((x, y) => x + y) / vals.length;
    final sample = key.split('|').first;
    perSamplePairs.putIfAbsent(sample, () => []).addAll(vals);
    chainStats[key] = {
      'rounds': sorted.length,
      'pair_count': vals.length,
      'mean_jaccard': mean,
      'pairs': pairs,
    };
  }
  final perSample = <String, dynamic>{};
  final samples = perSamplePairs.keys.toList()..sort();
  final below = <String>[];
  for (final s in samples) {
    final vals = perSamplePairs[s]!;
    final mean = vals.isEmpty
        ? null
        : vals.reduce((x, y) => x + y) / vals.length;
    perSample[s] = {
      'pair_count': vals.length,
      'mean_jaccard': mean,
      'min_jaccard': vals.isEmpty ? null : vals.reduce((x, y) => x < y ? x : y),
      'below_threshold': mean != null && mean < 0.8,
    };
    if (mean != null && mean < 0.8) below.add(s);
  }
  return {
    'source': sourceLabel,
    'definition':
        '同一样本同温度 r1–r5 的症候集合两两 Jaccard（10 对）取均值；样本级 = 该样本 2 条温度链共 20 对合并取均值',
    'threshold': 0.8,
    'sample_count': samples.length,
    'below_threshold_count': below.length,
    'below_threshold_samples': below,
    'per_sample': perSample,
    'per_chain': chainStats,
    'variant_invariant': true,
    'note': '四变体只改形态字段、不改症候集合 ⇒ Jaccard 与变体无关，只算一次',
  };
}

// ── 指标 3：教学针对性（本批留桩）─────────────────────────────
Map<String, dynamic> metricTeachingTargetingStub() => {
  'status': 'stub',
  'implemented': false,
  'value': null,
  'reason': '需人评 10 格抽样子集，见 W-47',
  'planned_inputs': ['人评盲评表（10 格）', '逐格 trace（本文件已产出）'],
};

// ── 焦点格读数（§4-228 已登记值的对账面）──────────────────────
Map<String, dynamic> guardStats(
  List<Map<String, dynamic>> trace,
  List<RawCell> cells,
) {
  final focus = <String, Map<String, String>>{};
  final reasons = <String, Map<String, String>>{};
  for (final r in trace) {
    final v = r['variant'] as String;
    final id = r['cell_id'] as String;
    focus.putIfAbsent(v, () => {})[id] =
        (r['output'] as Map<String, dynamic>)['activated_focus_id']
            as String? ??
        '';
    reasons.putIfAbsent(v, () => {})[id] =
        '${(r['output'] as Map<String, dynamic>)['reason']}';
  }
  final out = <String, dynamic>{};
  for (final v in Variant.values) {
    final f = focus[v.name]!;
    final v1 = focus['v1']!;
    final bulk = cells.where((c) {
      final p = c.syndromes.where((s) => s['syndrome_id'] == kTarget);
      if (p.isEmpty) return false;
      final ff = formFor(p.first, v);
      return ff.fact != null && ff.fact! >= 3 && ff.structure != null;
    }).length;
    out[v.name] = {
      'p002_focus_cells': f.values.where((x) => x == kTarget).length,
      'x01_p002_focus_cells': f.entries
          .where((e) => e.key.startsWith('X01|') && e.value == kTarget)
          .length,
      'x22_p002_focus_cells': f.entries
          .where((e) => e.key.startsWith('X22|') && e.value == kTarget)
          .length,
      'no_focus_cells': f.values.where((x) => x.isEmpty).length,
      // 「焦点丢失」= v1 有焦点、该变体变成空（只加正向性质的直接判据）
      'focus_lost_vs_v1': f.entries
          .where((e) => v1[e.key]!.isNotEmpty && e.value.isEmpty)
          .length,
      'changed_vs_v1': f.entries.where((e) => v1[e.key] != e.value).length,
      'p002_bulk_cells': bulk,
      '_reason_sample': reasons[v.name]![cells.first.cellId],
    };
  }
  return out;
}

// ── 轻门禁 4 条 ────────────────────────────────────────────────
List<Map<String, dynamic>> buildGates({
  required int sampleCount,
  required int cellCount,
  required int traceRows,
  required List<String> exceptions,
  required Map<String, dynamic> cost,
}) {
  final traceComplete =
      traceRows == cellCount * Variant.values.length &&
      traceRows > 0; // 每格 × 每变体各一行 = 输入输出齐备
  final costOk = [
    'llm_calls',
    'prompt_tokens',
    'completion_tokens',
    'usd',
    'wall_ms',
  ].every((k) => cost.containsKey(k) && cost[k] != null);
  return [
    {
      'id': 'G1',
      'name': '至少 1 样本跑通',
      'passed': sampleCount >= 1 && cellCount > 0,
      'detail': 'samples=$sampleCount cells=$cellCount（阈值 ≥1 样本）',
    },
    {
      'id': 'G2',
      'name': '无未捕获异常',
      'passed': exceptions.isEmpty,
      'detail': exceptions.isEmpty ? 'exceptions=0' : 'exceptions=$exceptions',
    },
    {
      'id': 'G3',
      'name': '有完整 trace（每格输入输出可回放）',
      'passed': traceComplete,
      'detail': 'trace 行数 $traceRows / 期望 ${cellCount * Variant.values.length}',
    },
    {
      'id': 'G4',
      'name': '有成本字段（结构留存）',
      'passed': costOk,
      'detail':
          'llm_calls / prompt_tokens / completion_tokens / usd / wall_ms 均存在',
    },
  ];
}

// ── 与 §4-228 登记值对账（**不一致即失败，不修正读数**）────────
const Map<String, Map<String, int>> kExpectedFocus = {
  'v1': {'p002_focus_cells': 41, 'x01': 0, 'x22': 8},
  'v2now': {'p002_focus_cells': 77, 'x01': 1, 'x22': 9},
  'v2a': {'p002_focus_cells': 68, 'x01': 0, 'x22': 9},
  'v2bLow': {'p002_focus_cells': 72, 'x01': 0, 'x22': 9},
};

/// §4-228 §四 的两口径命中读数（作为二级对账，误差容忍 0）。
const Map<String, Map<String, int>> kExpectedHits = {
  'v1': {'all': 69, 'deb': 69, 'target': 10, 'other': 59},
  'v2now': {'all': 62, 'deb': 62, 'target': 17, 'other': 45},
  'v2a': {'all': 65, 'deb': 65, 'target': 16, 'other': 49},
  'v2bLow': {'all': 63, 'deb': 63, 'target': 16, 'other': 47},
};

List<Map<String, dynamic>> compareWith4228({
  required Map<String, dynamic> stats,
  required Map<String, dynamic> hit,
}) {
  final rows = <Map<String, dynamic>>[];
  final deb = hit['debiased_111']['by_variant'] as Map<String, dynamic>;
  final all = hit['all_130']['by_variant'] as Map<String, dynamic>;
  for (final v in Variant.values) {
    final s = stats[v.name] as Map<String, dynamic>;
    final e = kExpectedFocus[v.name]!;
    final eh = kExpectedHits[v.name]!;
    final dv = deb[v.name] as Map<String, dynamic>;
    final checks = <String, List<int>>{
      'p002_focus_cells': [
        s['p002_focus_cells'] as int,
        e['p002_focus_cells']!,
      ],
      'x01_p002': [s['x01_p002_focus_cells'] as int, e['x01']!],
      'x22_p002': [s['x22_p002_focus_cells'] as int, e['x22']!],
      'hit_all_130': [(all[v.name] as Map)['hits'] as int, eh['all']!],
      'hit_debiased_111': [dv['hits'] as int, eh['deb']!],
      'hit_target_layer': [
        (dv['target_layer'] as Map)['hits'] as int,
        eh['target']!,
      ],
      'hit_other_layer': [
        (dv['other_layer'] as Map)['hits'] as int,
        eh['other']!,
      ],
    };
    final mismatch = checks.entries.where((e2) => e2.value[0] != e2.value[1]);
    rows.add({
      'variant': v.name,
      'checks': {
        for (final en in checks.entries)
          en.key: {
            'actual': en.value[0],
            'expected': en.value[1],
            'match': en.value[0] == en.value[1],
            'delta': en.value[0] - en.value[1],
          },
      },
      'all_match': mismatch.isEmpty,
      'mismatch_fields': mismatch.map((e2) => e2.key).toList(),
    });
  }
  return rows;
}

void main() {
  test('W-42 批次A · 常设 eval runner（确定性重算，四变体 × 240 格）', () {
    final sw = Stopwatch()..start();
    final cellsPath = _envOr('EVAL_CELLS', kDefaultCells);
    final answersPath = _envOr('EVAL_ANSWERS', kDefaultAnswers);
    final gtDir = _envOr('EVAL_GT', kDefaultGtDir);
    final outPath = _envOr('EVAL_OUT', kDefaultOut);
    final tracePath = _envOr('EVAL_TRACE', kDefaultTrace);

    final exceptions = <String>[];
    final answers = loadAnswers(answersPath);
    final cellsMeta = loadCells(cellsPath);
    final gt = loadGt(gtDir);
    expect(answers.length, 240, reason: '24 样本 × 10 格（S×2温度×5round）');

    final gtFocus = <String, String?>{
      for (final c in answers) c.cellId: gtFocusOf(c.cellId, gt),
    };
    final candidateSet = <String, Set<String>>{
      for (final c in answers)
        c.cellId: {for (final s in c.syndromes) '${s['syndrome_id']}'},
    };

    final trace = runTrace(answers, gtFocus);
    final stats = guardStats(trace, answers);
    final hit = metricFocusHit(trace, gtFocus, candidateSet);
    final stabAnswers = metricStability(answers, sourceLabel: 'answers（变体输入源）');
    // w23_cells.json 的 Jaccard 作交叉源（只读，不与变体口径混算）
    final stabCells = metricStability([
      for (final e in cellsMeta.values)
        RawCell(
          cellId: e['cell_id'] as String,
          sample: e['sample'] as String,
          // 交叉源用 temp 数值编码成独立 token，避免两个温度的同号 round 互相覆盖
          tempToken: 't${((e['temp'] as num) * 10).round()}',
          round: e['round'] as int? ?? 0,
          syndromes: (e['syndromes'] as List<dynamic>)
              .cast<Map<String, dynamic>>(),
        ),
    ], sourceLabel: 'w23_cells.json（交叉源）');

    sw.stop();
    final cost = <String, dynamic>{
      'mode': 'deterministic_replay',
      'llm_calls': 0,
      'prompt_tokens': 0,
      'completion_tokens': 0,
      'total_tokens': 0,
      'usd': 0.0,
      'wall_ms': sw.elapsedMilliseconds,
      'cells_computed': trace.length,
      'note': '本批不跑真 LLM（成本恒 0）；字段结构预留，B 批次接生产口径时复用同名字段',
    };

    final samples = answers.map((c) => c.sample).toSet().length;
    final gates = buildGates(
      sampleCount: samples,
      cellCount: answers.length,
      traceRows: trace.length,
      exceptions: exceptions,
      cost: cost,
    );
    final cmp = compareWith4228(stats: stats, hit: hit);
    final coreOk =
        cmp.every((r) => r['all_match'] == true) &&
        stats.entries
            .where((e) => e.key != 'v1')
            .every((e) => (e.value as Map)['focus_lost_vs_v1'] == 0);

    final baseline = <String, dynamic>{
      'schema': 'w23-eval-baseline-v1',
      'generated': DateTime.now().toIso8601String(),
      'batch': 'W-42 · A（确定性重算；无 LLM）',
      'inputs': {
        'cells': cellsPath,
        'answers': answersPath,
        'gt_dir': gtDir,
        'gt_annotators': kGtAnnotators,
        'answer_files': Directory(answersPath)
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.json'))
            .length,
        'cell_count': answers.length,
        'sample_count': samples,
      },
      'provenance_note':
          '变体所需的 form_fact_count/form_structure 只存在于 answers；'
          'w23_cells.json 无这两个字段（见报告 §三）。强行只用 cells ⇒ 四变体退化为 v1。',
      'variant_definitions': {
        for (final v in Variant.values) v.name: kVariantNote[v],
      },
      'variant_count': Variant.values.length,
      'metrics': {
        'm1_focus_hit_rate': hit,
        'm2_stability_jaccard': {
          'primary': stabAnswers,
          'cross_check_cells': {
            'source': stabCells['source'],
            'sample_count': stabCells['sample_count'],
            'below_threshold_count': stabCells['below_threshold_count'],
            'below_threshold_samples': stabCells['below_threshold_samples'],
            'per_sample': {
              for (final e
                  in (stabCells['per_sample'] as Map<String, dynamic>).entries)
                e.key: {
                  'mean_jaccard': (e.value as Map)['mean_jaccard'],
                  'below_threshold': (e.value as Map)['below_threshold'],
                },
            },
          },
        },
        'm3_teaching_targeting': metricTeachingTargetingStub(),
      },
      'focus_stats': stats,
      'gates': gates,
      'gates_all_passed': gates.every((g) => g['passed'] == true),
      'cost': cost,
      'comparison_vs_4_228': {
        'expected_focus': kExpectedFocus,
        'expected_hits': kExpectedHits,
        'rows': cmp,
        'all_match': coreOk,
      },
      'trace': {
        'path': tracePath,
        'rows': trace.length,
        'format': 'jsonl（每行 = 一格 × 一变体，含完整输入 + 输出，可回放）',
      },
    };

    File(
      outPath,
    ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(baseline));
    File(
      tracePath,
    ).writeAsStringSync('${trace.map((r) => jsonEncode(r)).join('\n')}\n');

    // ── 控制台摘要 + 对账表 ──────────────────────────────────
    void log(String s) => print(s); // ignore: avoid_print
    log(
      '[eval-runner] cells=${answers.length} samples=$samples '
      'variants=${Variant.values.length} trace=${trace.length} '
      'wall=${cost['wall_ms']}ms',
    );
    log('  变体        P002焦点  X01  X22  无焦点  丢失(vs v1)  变动');
    for (final v in Variant.values) {
      final s = stats[v.name] as Map<String, dynamic>;
      log(
        '  ${v.name.padRight(10)} ${'${s['p002_focus_cells']}'.padLeft(8)}'
        '${'${s['x01_p002_focus_cells']}'.padLeft(5)}'
        '${'${s['x22_p002_focus_cells']}'.padLeft(5)}'
        '${'${s['no_focus_cells']}'.padLeft(8)}'
        '${'${s['focus_lost_vs_v1']}'.padLeft(13)}'
        '${'${s['changed_vs_v1']}'.padLeft(6)}',
      );
    }
    final all = hit['all_130']['by_variant'] as Map<String, dynamic>;
    final deb = hit['debiased_111']['by_variant'] as Map<String, dynamic>;
    log('  变体        全130     去偏置111   目标层27    其他层84   净(vs v1)');
    for (final v in Variant.values) {
      final a = all[v.name] as Map<String, dynamic>;
      final d = deb[v.name] as Map<String, dynamic>;
      final t = d['target_layer'] as Map<String, dynamic>;
      final o = d['other_layer'] as Map<String, dynamic>;
      final n = d['net_vs_v1'] as Map<String, dynamic>;
      log(
        '  ${v.name.padRight(10)} ${a['hits']}/130  ${d['hits']}/111  '
        '${t['hits']}/27  ${o['hits']}/84  ${n['net']}',
      );
    }
    log(
      '[eval-runner] Jaccard（answers）样本级 <0.8：'
      '${stabAnswers['below_threshold_count']} / ${stabAnswers['sample_count']}'
      ' ${stabAnswers['below_threshold_samples']}',
    );
    log(
      '[eval-runner] 门禁：'
      '${gates.map((g) => '${g['id']}=${g['passed'] == true ? 'PASS' : 'FAIL'}').join(' ')}',
    );
    final mism = cmp
        .where((r) => r['all_match'] != true)
        .map((r) => '${r['variant']}:${r['mismatch_fields']}')
        .toList();
    log(
      '[eval-runner] 与 §4-228 对账：${mism.isEmpty ? 'ALL MATCH' : 'MISMATCH $mism'}',
    );
    log('[eval-runner] 产出：$outPath · $tracePath');

    // ── 失败即报（不修正读数：不一致本身是发现）───────────────
    expect(
      gates.every((g) => g['passed'] == true),
      isTrue,
      reason:
          '轻门禁未全绿：${gates.where((g) => g['passed'] != true).map((g) => g['id']).toList()}',
    );
    expect(coreOk, isTrue, reason: '读数与 §4-228 登记值不一致（口径漂移，须交舰长判）：$mism');
  });
}
