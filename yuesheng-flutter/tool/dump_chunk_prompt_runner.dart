// 导出**当前生产的分块层 system prompt**（离线采样器的「同构」依据）。
//
// 为什么是 `flutter test` 而不是 `dart run`（实测，勿改回去）
// ------------------------------------------------------------
// `progressive_diagnosis.dart` 依赖 Flutter（`package:flutter/...`）⇒
// `dart run` 会在编译期报 `Not a constant expression`（flutter 的
// `Offset.zero` 等）而**导不出任何东西**（2026-10-27 实测）。
// `flutter test` 带 Flutter 引擎，可以正常构造该常量。
//
// 为什么不在 `test/` 下、也不叫 `*_test.dart`
// -------------------------------------------
// 它不是测试，是导出工具。放进 `test/` 或加 `_test` 后缀会被全量
// `flutter test` 收集 ⇒ 用例基线 +1（会触发例数基线告警），且每次收尾多跑一次
// 无用导出。**判据是显式路径调用**：
//
//     flutter test tool/dump_chunk_prompt_runner.dart
//     # 可选：DUMP_OUT=<路径> 指定输出
//
// 退出码语义：测试失败 ⇒ flutter test rc≠0（采样器据此 fail-fast，不静默用旧文件）。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/progressive_diagnosis.dart';

const String _defaultOut = 'outputs/gate/chunk_system_prompt_prod.txt';

void main() {
  test('dump chunk system prompt → 文件', () {
    final outPath = Platform.environment['DUMP_OUT'] ?? _defaultOut;
    final content = kChunkSystemPrompt;

    final f = File(outPath);
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(content, flush: true);

    // 三条结构探针：不是判据，只用于「导出的是不是那一份」的肉眼对账。
    stdout.writeln('[dump-chunk] 字符数=${content.length} → $outPath');
    stdout.writeln(
      '[dump-chunk] 含「症候判定要点」=${content.contains('症候判定要点')} '
      '含「片段窗口边界」=${content.contains('片段窗口边界')} '
      '含「跨章依赖判据」=${content.contains('跨章依赖判据')}',
    );

    expect(content.isNotEmpty, isTrue, reason: '生产分块 prompt 不得为空');
    expect(File(outPath).existsSync(), isTrue, reason: '导出文件必须落盘（rc=0 ≠ 落盘）');
    expect(
      File(outPath).readAsStringSync().length,
      content.length,
      reason: '回读长度必须与内存一致（防半截写入）',
    );
  });
}
