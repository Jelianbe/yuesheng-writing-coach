/// T-20261024-11 §B · 语料重生成 harness（**新增文件**，理由见下）。
///
/// 为什么需要它（卡内 §B-2 授权项）：
///   `chunks_para.json` 是 2026-10-22 的**旧产物**，其生成器**不在仓内**（全仓 grep
///   `chunks_para|splitContent` 只命中消费方 `tool/build_chunk_sim_tasks.py` 与
///   `.ai/research/.../check_metrics*.py`，无产出方）。而卡要求「用**修复后的**
///   `splitContent` 重新生成」⇒ 必须直接调**生产函数**，不得用 Python 近似实现
///   （近似 = 语料与生产代码不同源，读数失去意义）。
///
/// 同源取证（本 harness 之外的独立复核，见 `_repro_check_c1553.py`）：
///   用**旧版**合并语义逐行复算 ⇒ 与既有 `chunks_para.json` **18 块逐块逐字全等**；
///   换成修复版语义 ⇒ 只有 1 块变化（L03c2 3458 → 3187，Δ = 重叠段 180+87+4）。
///   ⇒ 输入变换（`\n` → `\n\n`「段间空行形态」）与算法参数已被旧文件反向确认。
///
/// 运行方式：
///   `flutter test tool/build_chunks_c1553.dart`
///   不能 `dart run` —— `lib/services/progressive_diagnosis.dart` import
///   `package:flutter/foundation.dart`（⇒ dart:ui），Dart VM 不提供。
///
/// 边界：
///   · 只写 `.ai/research/cross-validation/data/chunk_sim/chunks_para_c1553.json`；
///   · **不覆盖** `chunks_para.json` / `chunks.json` / `chunks_raw.json`（前批证据只读）；
///   · `lib/` 零改动（只 import 生产符号，不修改）。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/progressive_diagnosis.dart';

const String kSimBase =
    'D:/ai-teacher/.ai/research/cross-validation/data/chunk_sim';
const String kCorpus = 'D:/ai-teacher/.ai/reports/2026-10-21-长文语料/corpus.jsonl';
const String kOut = '$kSimBase/chunks_para_c1553.json';

/// 段间空行形态：App 排版开关设计态（`reports/2026-10-23-分块链读数.md:19`）。
/// 旧 `chunks_para.json` 的 `chapter_chars` 已反向验证此变换（5911+71=5982 等 7/7 命中）。
String toParagraphForm(String text) => text.replaceAll('\n', '\n\n');

List<Map<String, dynamic>> buildChunks() {
  final lines = File(
    kCorpus,
  ).readAsLinesSync().where((l) => l.trim().isNotEmpty).toList();
  final out = <Map<String, dynamic>>[];
  for (final line in lines) {
    final row = jsonDecode(line) as Map<String, dynamic>;
    final text = toParagraphForm(row['text'] as String);
    final chunks = splitContent(text);
    for (var i = 0; i < chunks.length; i++) {
      out.add({
        'corpus_id': row['corpus_id'],
        'chapter_chars': text.length,
        'chunk_index': i,
        'chunk_count': chunks.length,
        'chunk_chars': chunks[i].length,
        'text': chunks[i],
      });
    }
  }
  return out;
}

void main() {
  test('build chunks_para_c1553.json via production splitContent', () {
    final chunks = buildChunks();
    final totalChars = chunks.fold<int>(
      0,
      (a, c) => a + (c['chunk_chars'] as int),
    );
    final payload = <String, dynamic>{
      'meta': {
        'generator': 'yuesheng-flutter/tool/build_chunks_c1553.dart',
        'prod_symbol': 'splitContent (lib/services/progressive_diagnosis.dart)',
        'source': '.ai/reports/2026-10-21-长文语料/corpus.jsonl',
        'transform': r"text.replaceAll('\n', '\n\n') # 段间空行形态",
        'chunk_size': kDiagnosisChunkSize,
        'chunk_overlap': kDiagnosisChunkOverlap,
        'min_last_chunk': kDiagnosisMinLastChunk,
        'n_chunks': chunks.length,
        'total_chars': totalChars,
      },
      'chunks': chunks,
    };
    File(kOut).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(payload),
      encoding: utf8,
      flush: true,
    );
    // ignore: avoid_print
    print('[build] ${chunks.length} 块 → $kOut （总字符 $totalChars）');
    expect(chunks.length, greaterThan(0));
    expect(File(kOut).existsSync(), isTrue);
  });
}
