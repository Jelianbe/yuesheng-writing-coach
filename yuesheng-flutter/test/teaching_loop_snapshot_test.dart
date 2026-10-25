// ignore_for_file: avoid_print
// 批次96-18：教学闭环「快照回归护栏」
// ─────────────────────────────────────────────────────────────
// 目的：把教学闭环当前的结构化决策行为冻结为基线（snapshot），未来任何改动
//      （知识库 / 提示词 / 解析器 / 校验器 / 冲突裁决）若导致结构化决策漂移，
//      本测试立即报出具体差异，由人工判定「有意为之→重生成快照」还是「回归 bug」。
//
// 与 corpus_teacher_acceptance_test 的区别：
//  - acceptance 断言「我手写 ground truth」（与我的预期耦合）
//  - 本测试冻结「当前真实行为」（与现状耦合），任何静默漂移都可见
//
// 与 96-17 原则一致：只快照结构化决策 + 合规约束，**自然语言文案绝不进快照**
//      （话术由 AI 现场生成，质量归人工审阅，不进自动比对）。
//
// 用法：
//  flutter test test/teaching_loop_snapshot_test.dart            # 比对基线（护栏）
//  UPDATE_SNAPSHOTS=true flutter test test/teaching_loop_snapshot_test.dart  # 重生成基线
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/diagnosis_parser.dart';
import 'package:writingcoach/services/teacher_parser.dart';
import 'package:writingcoach/services/teacher_validator.dart';
import 'package:writingcoach/services/syndrome_id_pattern.dart';
import 'package:writingcoach/types/teaching_types.dart';

import 'helpers/anchor_content_floor.dart';

const String kSnapshotPath = 'test/snapshots/teaching_loop_snapshot.json';

// 与 corpus_teacher_acceptance_test 同源的 47 例清单（单一可信源）
const List<Map<String, String>> _corpus = [
  {'id': 'A1', 'file': 'corpus_A1_p001.txt'},
  {'id': 'A2', 'file': 'corpus_A2_p005.txt'},
  {'id': 'A3', 'file': 'corpus_A3_p007.txt'},
  {'id': 'A4', 'file': 'corpus_A4_p009.txt'},
  {'id': 'A5', 'file': 'corpus_A5_p010.txt'},
  {'id': 'A6', 'file': 'corpus_A6_p011.txt'},
  {'id': 'A7', 'file': 'corpus_A7_p017.txt'},
  {'id': 'A8', 'file': 'corpus_A8_p021.txt'},
  {'id': 'A9', 'file': 'corpus_A9_p018.txt'},
  {'id': 'A10', 'file': 'corpus_A10_p002.txt'},
  {'id': 'A11', 'file': 'corpus_A11_p003.txt'},
  {'id': 'A_p004', 'file': 'corpus_A_p004.txt'},
  {'id': 'A12', 'file': 'corpus_A12_p006.txt'},
  {'id': 'A13', 'file': 'corpus_A13_p008.txt'},
  {'id': 'A14', 'file': 'corpus_A14_p012.txt'},
  {'id': 'A15', 'file': 'corpus_A15_p013.txt'},
  {'id': 'A16', 'file': 'corpus_A16_p014.txt'},
  {'id': 'A17', 'file': 'corpus_A17_p012.txt'},
  {'id': 'A18', 'file': 'corpus_A18_p015.txt'},
  {'id': 'A19', 'file': 'corpus_A19_p001.txt'},
  {'id': 'A20', 'file': 'corpus_A20_p016.txt'},
  {'id': 'A21', 'file': 'corpus_A21_p013.txt'},
  {'id': 'A22', 'file': 'corpus_A22_p019.txt'},
  {'id': 'A23', 'file': 'corpus_A23_p011.txt'},
  {'id': 'A24', 'file': 'corpus_A24_p019.txt'},
  {'id': 'A25', 'file': 'corpus_A25_p020.txt'},
  {'id': 'A26', 'file': 'corpus_A26_p005.txt'},
  {'id': 'A27', 'file': 'corpus_A27_p022.txt'},
  {'id': 'A28', 'file': 'corpus_A28_p023.txt'},
  {'id': 'A29', 'file': 'corpus_A29_p024.txt'},
  {'id': 'A30', 'file': 'corpus_A30_p024.txt'},
  {'id': 'A31', 'file': 'corpus_A31_p025.txt'},
  {'id': 'A32', 'file': 'corpus_A32_p009.txt'},
  {'id': 'A33', 'file': 'corpus_A33_p004.txt'},
  {'id': 'A34', 'file': 'corpus_A34_p026.txt'},
  {'id': 'A35', 'file': 'corpus_A35_p027.txt'},
  {'id': 'A36', 'file': 'corpus_A36_p007.txt'},
  {'id': 'A37', 'file': 'corpus_A37_p028.txt'},
  {'id': 'A38', 'file': 'corpus_A38_p029.txt'},
  {'id': 'B1', 'file': 'corpus_B1_p010_p004.txt'},
  {'id': 'B2', 'file': 'corpus_B2_p021_p001.txt'},
  {'id': 'B3', 'file': 'corpus_B3_p003_p001.txt'},
  {'id': 'B4', 'file': 'corpus_B4_p010_p013.txt'},
  {'id': 'B5', 'file': 'corpus_B5_p022_p004.txt'},
  {'id': 'B6', 'file': 'corpus_B6_p029_p010.txt'},
  {'id': 'C1', 'file': 'corpus_C1_good.txt'},
  {'id': 'C2', 'file': 'corpus_C2_short.txt'},
];

/// 从单例 fixture 计算结构化决策快照（不含任何自然语言文案）
Map<String, dynamic> _snapshotCase(String id, String file) {
  final raw = File('test/fixtures/$file').readAsStringSync();

  // ── 诊断层 ──
  final diag = parseDiagnosis(raw);
  final d = diag.diagnosis;
  final allIds = d?.syndromes.map((s) => s.syndromeId).toList() ?? <String>[];
  final l2Ids =
      d?.syndromes
          .where((s) => s.severity == Severity.l2)
          .map((s) => s.syndromeId)
          .toList() ??
      <String>[];
  final primaryId = allIds.isNotEmpty ? allIds.first : '';

  // ── 教学层 ──
  final tp = parseTeacherDecision(raw);
  final t = tp.teacher;
  final task = t?.trainingTask;
  final cons = t != null ? checkTeacherConsistency(t) : null;
  final leak = t != null && kAnySyndromeIdRe.hasMatch(t.naturalLanguage);

  return {
    'id': id,
    'file': file,
    'diagnosis': {
      'parsed': d != null,
      'syndromeIds': allIds, // 保留数组顺序（主症锁定即 syndromes[0]）
      'l2SyndromeIds': l2Ids,
      'primarySyndromeId': primaryId,
      'confidence': d?.confidence,
    },
    'teacher': {
      'teachingDecision': t?.teachingDecision ?? '',
      'hasTask': task != null,
      'taskTargetSyndromeId': task?.targetSyndromeId,
      'taskType': task?.taskType,
    },
    'consistency': {
      'passed': cons?.passed ?? false,
      'violationCount': cons?.violations.length ?? 0,
    },
    'compliance': {'naturalLanguageLeakP0xx': leak},
  };
}

/// 递归 diff，返回 ['path: before → after', ...]
List<String> _diff(String path, dynamic a, dynamic b) {
  final out = <String>[];
  if (a is Map && b is Map) {
    final keys = <String>{...a.keys.cast<String>(), ...b.keys.cast<String>()};
    for (final k in keys) {
      out.addAll(_diff('$path.$k', a[k], b[k]));
    }
  } else if (a is List && b is List) {
    final n = a.length > b.length ? a.length : b.length;
    for (var i = 0; i < n; i++) {
      out.addAll(
        _diff(
          '$path[$i]',
          i < a.length ? a[i] : null,
          i < b.length ? b[i] : null,
        ),
      );
    }
  } else if (a != b) {
    out.add('$path: ${a ?? '∅'} → ${b ?? '∅'}');
  }
  return out;
}

// ─────────────────────────────────────────────────────────────
// 重建下限判据（T-20261024-15 · L4 支撑层）
//
// 由来：`T-20261024-14` 在重建分支只保证「写完整没有」（`cases` 是对象 +
//   47 个 id 键齐）——**没有下限**。47 例全部解析成空结构化决策同样「键齐」，
//   于是写出的基线与「解析器全塌」的产物一致，此后长期绿。
//
// 口径（`DECISIONS §4-260⑤` 舰长 2026-10-24 23:31 已裁，不得改）：
//   ① 每例**非空** + 总数 ≥ 旧基线 **50%**；② 越限 = **fail**。
//
// 落点只在**重建分支**：比对分支的判据面是「与基线递归 diff」，塌陷基线在那里
//   表现为「当前 ≠ 基线」⇒ 本来就会红。
// ★ 判据在**写盘之前**：失败必须**不写**。
// ─────────────────────────────────────────────────────────────

/// 每例必需的结构块（缺一块 = 装配塌陷，不是「决策变简单了」）。
const List<String> _kCaseBlocks = [
  'diagnosis',
  'teacher',
  'consistency',
  'compliance',
];

/// F1 + F2：每例非空。不过即 `fail`（**不写盘**）。
///
/// F1 = 该例 `id` / `file` 非空且四个结构块齐备（核心条数 ≥ 1 的对应量）；
/// F2 = 该例内 **ID 型叶值**不得为空串（`syndromeIds` / `l2SyndromeIds` 的元素）。
/// ★ 豁免（有实测依据，不是放宽）：`primarySyndromeId` 在「无症候」时按设计写
///   空串 —— 实测 `test/snapshots/teaching_loop_snapshot.json` 的 `cases.C1` /
///   `cases.C2`（good / short 语料）即为 `""`；`taskTargetSyndromeId` /
///   `taskType` 在无训练任务时为 `null`。三者都不参与 F2。
/// ★ 空**数组**同样是良性的（C1/C2 无症候）：F2 查的是**元素**非空，不是数组非空。
void _assertPerCaseNonEmpty(Map<String, dynamic> cases) {
  final emptyCases = <String>[];
  final emptyIds = <String>[];
  for (final e in cases.entries) {
    final id = e.key;
    final c = e.value as Map<String, dynamic>;
    final missingBlocks = <String>[
      for (final b in _kCaseBlocks)
        if (c[b] is! Map) b,
    ];
    final idField = c['id'] as String? ?? '';
    final fileField = c['file'] as String? ?? '';
    if (idField.isEmpty || fileField.isEmpty || missingBlocks.isNotEmpty) {
      emptyCases.add(
        missingBlocks.isEmpty
            ? '$id(id=${idField.isEmpty ? '∅' : idField},'
                  'file=${fileField.isEmpty ? '∅' : fileField})'
            : '$id(缺块 $missingBlocks)',
      );
      continue;
    }
    final diagnosis = c['diagnosis'] as Map<String, dynamic>;
    for (final k in const ['syndromeIds', 'l2SyndromeIds']) {
      final list = diagnosis[k] as List<dynamic>? ?? const <dynamic>[];
      for (final v in list) {
        if (v is String && v.isEmpty) emptyIds.add('$id.diagnosis.$k[]');
      }
    }
  }
  if (emptyCases.isEmpty && emptyIds.isEmpty) return;
  fail(
    '[snapshot] 重建下限不过（F1 每例结构 / F2 叶值非空），**已拒绝写盘**：\n'
    '  F1 结构缺失 ${emptyCases.length} 例：${emptyCases.take(12).toList()}'
    '${emptyCases.length > 12 ? ' …' : ''}\n'
    '  F2 空 ID 叶值 ${emptyIds.length} 处：${emptyIds.take(12).toList()}'
    '${emptyIds.length > 12 ? ' …' : ''}\n'
    '  ★ 这多半是装配塌陷（fixture 读不到 / 解析器全返回空 / 校验器异常被吞），'
    '**不是**「决策变简单了」。空壳基线一旦落盘，此后长期绿。\n'
    '  排查真因后确需重写基线：UPDATE_SNAPSHOTS=true。',
  );
}

/// 读旧基线的 `cases` 子树；返回 `null` = 无可比基线。
///
/// 「不可解析」（非 JSON / 顶层非对象 / 缺 `cases` 对象）一律**默认 fail**
/// （除非显式豁免）：`旧快照损坏 + UPDATE_SNAPSHOTS=true` 是**洗白基线最省力的
/// 入口**。留开关是为了快照真坏时还能修。
Map<String, dynamic>? _loadBaselineCases(File file, {required bool exists}) {
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
      final cases = decoded['cases'];
      if (cases is! Map<String, dynamic>) {
        kind = decoded.keys.where((k) => k != 'meta' && k != 'version').isEmpty
            ? '顶层只有 meta/version、缺 cases'
            : '结构不符（缺 cases）';
        why = '`cases` 应为 JSON 对象，实际为 ${cases.runtimeType}';
      } else if (cases.isEmpty) {
        kind = '空 cases';
        why = '`cases` 是空对象，没有任何用例键';
      } else if (anchorMeasureVolume(cases).content == 0) {
        // ★ 最隐蔽的一种：键齐、但内容体积为 0。体积 0 ⇒ 下限 `ceil(0/2) == 0`
        //   ⇒ 任何内容都 `≥ 0` ⇒ F3 恒绿（fail-open）。与「不可解析」同类失效，
        //   必须走同一条 fail 通路，**不另造出口**。
        kind = '键齐但全零长度';
        why =
            '用例键齐备，但内容体积（单调代理）为 0'
            '（所有 `len` / `length` 均为 0、且无叶字符串）';
      } else {
        return cases;
      }
    }
  }
  final waived =
      (Platform.environment['ALLOW_FLOORLESS_REBUILD'] ?? '') == 'true';
  if (!waived) {
    fail(
      '[snapshot] 旧基线不可解析 ⇒ 比率下限无法生效（或：可解析但不可用）：'
      '$kSnapshotPath\n'
      '  本次形态：$kind\n'
      '  判定依据：$why\n'
      '  ★ 可解析但不可用 = ① 空 `cases` ② 顶层只有 `meta` / `version`'
      ' ③ **键齐但所有长度均为 0**。\n'
      '    三者都让下限退化为 0 ⇒ F3 对任何内容恒绿（fail-open），与「文件损坏」同罪。\n'
      '  两条出口：\n'
      '    ① 恢复基线：git checkout -- $kSnapshotPath\n'
      '    ② 确认要丢弃旧基线：ALLOW_FLOORLESS_REBUILD=true'
      '（会打双重告警，且本次不设任何下限）',
    );
  }
  print(
    '[snapshot][告警] 已放弃比率下限：旧基线不可解析或不可用（$kind：$why）'
    '⇒ 本次未做任何比对，这不是校验通过。',
  );
  print('[snapshot][告警] 路径：$kSnapshotPath；本次为「无下限重建」，须人工复核体量。');
  return null;
}

/// F3：总数（**内容体积（单调代理）**）≥ 旧基线 50%。不过即 `fail`（**不写盘**）。
///
/// 口径见 `test/helpers/anchor_content_floor.dart`：叶字符串长度 + 仅 `len` /
/// `length` 键的整数值；其余整数（本文件的 `violationCount`）单列
/// `nonContentInt`，**不计体积**。
/// ⚠️ 该指标**不得当作字节数 / token 成本引用**。
void _assertVolumeFloor(
  Map<String, dynamic> cases, {
  required File file,
  required bool exists,
}) {
  final newMeasure = anchorMeasureVolume(cases);
  final newVolume = newMeasure.content;
  final baseline = _loadBaselineCases(file, exists: exists);
  if (baseline == null) {
    if (!exists) {
      print(
        '[snapshot][告警] 本次为首次生成，比率下限未生效：$kSnapshotPath\n'
        '  ★ 首次生成是合法通路，故不拦；但**不静默** —— 否则「删掉旧快照再重冻」'
        '就成了绕过下限的最短路径。\n'
        '  提交前请人工复核该基线的体量是否合理'
        '（本次内容体积（单调代理）$newVolume；'
        '非长度整数（不计体积）${newMeasure.nonContentInt}）。',
      );
    }
    return;
  }
  final baselineMeasure = anchorMeasureVolume(baseline);
  final baselineVolume = baselineMeasure.content;
  final floor = (baselineVolume / 2).ceil();
  if (newVolume < floor) {
    fail(
      '[snapshot] 重建内容体积（单调代理）低于比率下限，**已拒绝写盘**：\n'
      '  实际：$newVolume\n'
      '  下限：$floor（旧基线 $baselineVolume 的 50%）\n'
      '  非长度整数（不计体积）：${newMeasure.nonContentInt}'
      '（旧基线 ${baselineMeasure.nonContentInt}）\n'
      '  ★ 键齐但内容腰斩 = 装配塌陷的典型形态（fixture 失效 / 解析器异常被吞）。\n'
      '  ★ 该指标是「内容体积（单调代理）」，**不得当作字节数 / token 成本引用**。\n'
      '  确为有意的语料缩减须经评审并在 .ai/DECISIONS.md 登记；'
      '确认不设下限时：ALLOW_FLOORLESS_REBUILD=true。',
    );
  }
  print(
    '[snapshot] 重建下限通过：内容体积（单调代理）$newVolume ≥ 下限 $floor'
    '（旧基线 $baselineVolume 的 50%）；'
    '非长度整数（不计体积）${newMeasure.nonContentInt}。',
  );
}

void main() {
  test('教学闭环结构化决策快照回归', () {
    final updating = (Platform.environment['UPDATE_SNAPSHOTS'] ?? '') == 'true';
    final file = File(kSnapshotPath);
    final exists = file.existsSync();

    // ── fail-closed 守卫（T-20261024-14 B 块；与 -13 B 块同形）────────────
    // 旧写法 `if (updating || !file.existsSync())` 把「显式重生成」与「快照缺失」
    // 并成一个分支 ⇒ 快照被误删 / 误移 / 未检出时本用例**照样绿**，并静默写新基线。
    // 本文件**门禁侧无兜底**（全量 grep：无任何脚本读该快照）⇒ 测试侧是唯一一道。
    // ★ 守卫前置于 _snapshotCase 装配：本用例要读 47 个 fixture，任一缺失会抛
    //   FileSystemException ⇒ 会把「快照缺失」这个真因遮住。
    if (!exists && !updating) {
      fail(
        '[snapshot] 锚点快照缺失：$kSnapshotPath\n'
        '  ★ 快照文件缺失 = 事故，不是常态（该文件本应随仓库一起检出）。\n'
        '  缺失时**不得**自动生成基线 —— 那等于用「当前行为」重写判据，'
        '任何漂移都会被静默转绿。\n'
        '  先查三因：误删 / 误移 / 未检出'
        '（git status --porcelain、git ls-files test/snapshots/）。\n'
        '  确需重建（基线变更须可对账、须经评审）：\n'
        '    UPDATE_SNAPSHOTS=true flutter test '
        'test/teaching_loop_snapshot_test.dart',
      );
    }

    // 计算当前全部 47 例的结构化快照
    final currentCases = <String, dynamic>{};
    for (final c in _corpus) {
      currentCases[c['id']!] = _snapshotCase(c['id']!, c['file']!);
    }
    final current = {
      'meta': {
        'caseCount': _corpus.length,
        'note': '教学闭环结构化决策基线（话术文案不进快照，详见批次96-17/96-18）',
        'generatedAt': DateTime.now().toIso8601String(),
      },
      'cases': currentCases,
    };

    if (updating) {
      // ── 基线非退化判据（T-20261024-15 · 重建分支专属）──────────────
      // 顺序：F1/F2（纯内存，先拦最明显的塌陷）→ F3（要读旧基线，含 IO 与
      // 「不可解析」分支）。两者都在 `writeAsStringSync` **之前**。
      _assertPerCaseNonEmpty(currentCases);
      _assertVolumeFloor(currentCases, file: file, exists: exists);

      // ── 显式重建通路（UPDATE_SNAPSHOTS=true）──────────────────────────
      // 允许写，但**必须打告警**：本分支不做任何比对，写出的就是新判据。
      // ⚠️ 本快照的 `meta.generatedAt` 取当前时间 ⇒ **重建必然改变文件 md5**，
      //    「重建后 md5 不变」在此文件上结构上不可满足（判据须改为「除
      //    generatedAt 外内容不变」）。
      final hadSnapshot = exists;
      file
        ..createSync(recursive: true)
        ..writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert(current),
        );
      print(
        '[snapshot][告警] UPDATE_SNAPSHOTS=true ⇒ 基线被强制覆盖：'
        '$kSnapshotPath（${_corpus.length} 例）',
      );
      print(
        '[snapshot][告警] 本次**未做任何比对**，这不是校验通过；'
        '原快照${hadSnapshot ? '已被丢弃' : '本就不存在（本次为新建）'}。',
      );
      print('[snapshot][告警] 提交前必须逐条复核 git diff $kSnapshotPath。');
      expect(currentCases, isNotEmpty, reason: '基线不应为空（生成模式）');

      // 回读校验：写入成功 ≠ 写出的是完整基线（截断 / 空文件同样「存在」）。
      final reread = jsonDecode(file.readAsStringSync());
      final written = reread is Map<String, dynamic>
          ? reread
          : const <String, dynamic>{};
      final writtenCases = written['cases'];
      if (writtenCases is! Map) {
        fail('[snapshot] 基线写入结构错误：cases 不是对象（${writtenCases.runtimeType}）');
      }
      final lostIds = <String>[
        for (final c in _corpus)
          if (!writtenCases.containsKey(c['id']!)) c['id']!,
      ];
      if (lostIds.isNotEmpty) {
        fail('[snapshot] 基线写入不完整，缺 ${lostIds.length} 个用例键：$lostIds');
      }
      return;
    }

    // 比对模式：加载基线，递归 diff
    final storedRaw = file.readAsStringSync();
    final stored = jsonDecode(storedRaw) as Map<String, dynamic>;
    final storedCases = stored['cases'] as Map<String, dynamic>;

    expect(
      storedCases.length,
      equals(currentCases.length),
      reason: '案例数量变化（新增/删除 fixture 需同步更新清单与快照）',
    );

    final diffs = <String>[];
    for (final id in currentCases.keys) {
      if (!storedCases.containsKey(id)) {
        diffs.add('cases.$id: 缺失于基线 → 当前存在');
        continue;
      }
      diffs.addAll(_diff('cases.$id', storedCases[id], currentCases[id]));
    }
    for (final id in storedCases.keys) {
      if (!currentCases.containsKey(id)) {
        diffs.add('cases.$id: 基线存在 → 当前缺失');
      }
    }

    if (diffs.isNotEmpty) {
      print('[snapshot] 检测到 ${diffs.length} 处结构化决策漂移：');
      for (final d in diffs.take(40)) {
        print('  - $d');
      }
      if (diffs.length > 40) {
        print('  ... 其余 ${diffs.length - 40} 处省略');
      }
      print('[snapshot] 若漂移为预期改动，请运行：');
      print(
        '  UPDATE_SNAPSHOTS=true flutter test '
        'test/teaching_loop_snapshot_test.dart',
      );
      fail('教学闭环结构化决策发生漂移（${diffs.length} 处），见上方 diff。');
    }

    print('[snapshot] 比对通过：47 例结构化决策与基线一致 ✓');
    expect(diffs, isEmpty);
  });
}
