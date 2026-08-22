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
import 'package:writingcoach/types/teaching_types.dart';

const String kSnapshotPath = 'test/snapshots/teaching_loop_snapshot.json';

// 与 corpus_teacher_acceptance_test 同源的 47 例清单（单一可信源）
const List<Map<String, String>> _corpus = [
  {'id': 'A1', 'file': 'corpus_A1_p003.txt'},
  {'id': 'A2', 'file': 'corpus_A2_p007.txt'},
  {'id': 'A3', 'file': 'corpus_A3_p009.txt'},
  {'id': 'A4', 'file': 'corpus_A4_p011.txt'},
  {'id': 'A5', 'file': 'corpus_A5_p012.txt'},
  {'id': 'A6', 'file': 'corpus_A6_p013.txt'},
  {'id': 'A7', 'file': 'corpus_A7_p021.txt'},
  {'id': 'A8', 'file': 'corpus_A8_p028.txt'},
  {'id': 'A9', 'file': 'corpus_A9_p022.txt'},
  {'id': 'A10', 'file': 'corpus_A10_p004.txt'},
  {'id': 'A11', 'file': 'corpus_A11_p005.txt'},
  {'id': 'A_p006', 'file': 'corpus_A_p006.txt'},
  {'id': 'A12', 'file': 'corpus_A12_p008.txt'},
  {'id': 'A13', 'file': 'corpus_A13_p010.txt'},
  {'id': 'A14', 'file': 'corpus_A14_p014.txt'},
  {'id': 'A15', 'file': 'corpus_A15_p015.txt'},
  {'id': 'A16', 'file': 'corpus_A16_p016.txt'},
  {'id': 'A17', 'file': 'corpus_A17_p017.txt'},
  {'id': 'A18', 'file': 'corpus_A18_p018.txt'},
  {'id': 'A19', 'file': 'corpus_A19_p019.txt'},
  {'id': 'A20', 'file': 'corpus_A20_p020.txt'},
  {'id': 'A21', 'file': 'corpus_A21_p023.txt'},
  {'id': 'A22', 'file': 'corpus_A22_p024.txt'},
  {'id': 'A23', 'file': 'corpus_A23_p025.txt'},
  {'id': 'A24', 'file': 'corpus_A24_p026.txt'},
  {'id': 'A25', 'file': 'corpus_A25_p027.txt'},
  {'id': 'A26', 'file': 'corpus_A26_p029.txt'},
  {'id': 'A27', 'file': 'corpus_A27_p030.txt'},
  {'id': 'A28', 'file': 'corpus_A28_p031.txt'},
  {'id': 'A29', 'file': 'corpus_A29_p032.txt'},
  {'id': 'A30', 'file': 'corpus_A30_p033.txt'},
  {'id': 'A31', 'file': 'corpus_A31_p034.txt'},
  {'id': 'A32', 'file': 'corpus_A32_p035.txt'},
  {'id': 'A33', 'file': 'corpus_A33_p036.txt'},
  {'id': 'A34', 'file': 'corpus_A34_p037.txt'},
  {'id': 'A35', 'file': 'corpus_A35_p038.txt'},
  {'id': 'A36', 'file': 'corpus_A36_p039.txt'},
  {'id': 'A37', 'file': 'corpus_A37_p040.txt'},
  {'id': 'A38', 'file': 'corpus_A38_p041.txt'},
  {'id': 'B1', 'file': 'corpus_B1_p012_p006.txt'},
  {'id': 'B2', 'file': 'corpus_B2_p028_p003.txt'},
  {'id': 'B3', 'file': 'corpus_B3_p005_p003.txt'},
  {'id': 'B4', 'file': 'corpus_B4_p012_p015.txt'},
  {'id': 'B5', 'file': 'corpus_B5_p030_p006.txt'},
  {'id': 'B6', 'file': 'corpus_B6_p041_p012.txt'},
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
  final leak = t != null
      ? RegExp(r'P0\d{2}').hasMatch(t.naturalLanguage)
      : false;

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

void main() {
  test('教学闭环结构化决策快照回归', () {
    final updating = (Platform.environment['UPDATE_SNAPSHOTS'] ?? '') == 'true';

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

    final file = File(kSnapshotPath);

    // 首次生成 / 显式重生成
    if (updating || !file.existsSync()) {
      file
        ..createSync(recursive: true)
        ..writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert(current),
        );
      print(
        '[snapshot] ${updating ? "已重生成" : "已生成"}基线 → $kSnapshotPath '
        '(${_corpus.length} 例)',
      );
      expect(currentCases, isNotEmpty, reason: '基线不应为空（生成模式）');
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
