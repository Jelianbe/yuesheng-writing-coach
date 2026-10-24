// U5 裁定用探针：user 侧注入面的**真实体积读数**（零 API 调用、零模型调用）
//
// 用途：`check_prompt_volume.py:131` 自陈「user 侧注入面没有红线上限」。
// 要裁「要不要设上限」，先得知道现在多大、把 39 条判据全注进去会多大。
//
// 运行： dart run tool/probe_user_face_volume.dart
// 输出： JSON（stdout），字段口径见 README 段。
//
// ⚠️ 本脚本只读常量，不写任何文件、不改任何状态。

// ignore_for_file: avoid_print

import 'dart:convert';

import 'package:writingcoach/services/syndrome_knowledge_base.dart';
import 'package:writingcoach/services/syndrome_registry.dart';

void main() {
  final ids = kSyndromeRegistry.map((s) => s.id).toList();

  // 每症候的判据段长度（getSyndromeCriteriaSections 的单条形态，
  // 用单元素列表取，避免 join 分隔符干扰）
  final perId = <String, int>{};
  final missing = <String>[];
  for (final id in ids) {
    final len = getSyndromeCriteriaSections([id]).length;
    perId[id] = len;
    if (len == 0) missing.add(id);
  }

  final block4 = buildFirstRoundCriteriaBlock();
  final sections4 = getSyndromeCriteriaSections(kFirstRoundCriteriaIds);

  // 假设臂：按「手册段长度」升序取前 N 条（不是最终方案，只是给上限一个量纲感）
  final sorted = ids.where((id) => perId[id]! > 0).toList()
    ..sort((a, b) => perId[a]!.compareTo(perId[b]!));
  int sizedN(int n) =>
      getSyndromeCriteriaSections(sorted.take(n).toList()).length;
  // 反向臂：按长度降序取前 N（最坏情况）
  final sortedDesc = [...sorted]
    ..sort((a, b) => perId[b]!.compareTo(perId[a]!));
  int sizedNDesc(int n) =>
      getSyndromeCriteriaSections(sortedDesc.take(n).toList()).length;

  final out = <String, Object?>{
    'registry_count': ids.length,
    'per_criterion_len': perId,
    'per_criterion_missing': missing,
    'per_criterion_total_len': perId.values.fold<int>(0, (a, b) => a + b),
    'per_criterion_max': perId.values.reduce((a, b) => a > b ? a : b),
    'per_criterion_min': perId.values
        .where((v) => v > 0)
        .reduce((a, b) => a < b ? a : b),
    'per_criterion_median': _median(perId.values.where((v) => v > 0).toList()),
    'index_content_len': kSyndromeIndexContent.length,
    'manual_content_len': kSyndromeManualContent.length,
    'first_round_ids': kFirstRoundCriteriaIds,
    'first_round_block_len': block4.length,
    'first_round_sections_len': sections4.length,
    'first_round_header_len': block4.length - sections4.length,
    'sizing_asc': {
      for (final n in [4, 8, 12, 18, 24, 39]) 'first_$n': sizedN(n),
    },
    'sizing_desc': {
      for (final n in [4, 8, 12, 18, 24, 39]) 'first_$n': sizedNDesc(n),
    },
  };
  print(const JsonEncoder.withIndent('  ').convert(out));
}

double _median(List<int> xs) {
  if (xs.isEmpty) return 0;
  final s = [...xs]..sort();
  final m = s.length ~/ 2;
  return s.length.isOdd ? s[m].toDouble() : (s[m - 1] + s[m]) / 2;
}
