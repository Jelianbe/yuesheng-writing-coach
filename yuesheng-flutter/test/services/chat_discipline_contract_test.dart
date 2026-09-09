// ─────────────────────────────────────────────────────────────
// ChatService 诊断协议一致性契约测试（ADR-C82）
//
// 背景：2026-09-07 全流程实测发现结构化诊断卡不触发。
// 根因双叠加：①「回复纪律」第 6 条要求 ```diagnosis``` 包裹，
//   与解析器（只认 [YS_DIAGNOSIS]）和协议真源冲突——模型按纪律
//   输出 markdown 包裹 → 诊断块永不解析；
//   ② 诊断协议被长 system prompt 中 P0 指引淹没（API 对照实验
//   B/C/D 已证：user 侧注入可恢复遵循）。
// 修复：纪律第 6 条对齐协议 + 诊断意图时 user 消息侧注入协议。
// 本文件用源码契约护栏防回归（与 reference_picker_test 同模式）。
// ─────────────────────────────────────────────────────────────

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ADR-C82 诊断协议一致性契约', () {
    test('纪律第 6 条不得再要求 ```diagnosis``` 包裹（与解析器冲突）', () {
      final src = File('lib/services/chat_service.dart').readAsStringSync();
      expect(
        src.contains('```diagnosis```'),
        isFalse,
        reason:
            '旧纪律要求 markdown 包裹，与 diagnosis_parser 的 '
            '[YS_DIAGNOSIS] 标记冲突——模型按纪律输出会导致诊断块永不解析',
      );
    });

    test('纪律第 6 条必须指向 [YS_DIAGNOSIS] 协议标记', () {
      final src = File('lib/services/chat_service.dart').readAsStringSync();
      final i = src.indexOf('诊断块按');
      expect(i, greaterThan(0), reason: '纪律第 6 条应改为协议对齐表述');
      final line = src.substring(i, i + 120);
      expect(line, contains('[YS_DIAGNOSIS]'));
    });

    test('存在 user 侧诊断协议注入 helper 与后缀常量', () {
      final src = File('lib/services/chat_service.dart').readAsStringSync();
      expect(src, contains('kDiagnosisProtocolSuffix'));
      expect(src, contains('_maybeInjectDiagnosisProtocol'));
      expect(src, contains('[YS_DIAGNOSIS]'));
      expect(src, contains('[/YS_DIAGNOSIS]'));
    });

    test('注入 helper 必须在流式调用前被调用', () {
      final src = File('lib/services/chat_service.dart').readAsStringSync();
      final callIdx = src.indexOf('_injectDiagnosisFor(');
      expect(
        callIdx,
        greaterThan(0),
        reason: 'sendMessage 主链必须调用注入（R-019 拆出后为聚合入口）',
      );
      final streamIdx = src.indexOf('_streamLlm(', callIdx);
      expect(streamIdx, greaterThan(0), reason: '注入应发生在流式调用之前');
    });

    test('诊断意图检测纯函数存在且信号词对齐 ADR', () {
      final src = File(
        'lib/services/intent_classifier.dart',
      ).readAsStringSync();
      expect(src, contains('bool isDiagnosisRequest(String text)'));
      expect(src, contains('诊断'));
      expect(src, contains('diagnose'));
    });
  });
}
