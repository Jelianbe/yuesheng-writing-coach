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
      // ★ ADR-0004 步 5 批 2（2026-10-07）：纪律第 6 条文本随
      //   _appendDisciplineReminder 迁至 prompt_assembly_service.dart ⇒
      //   **两个文件都扫**（扫两文件内容再定位，不是放宽判据）。
      final src =
          File('lib/services/chat_service.dart').readAsStringSync() +
          File('lib/services/prompt_assembly_service.dart').readAsStringSync();
      final i = src.indexOf('诊断块按');
      expect(i, greaterThan(0), reason: '纪律第 6 条应改为协议对齐表述');
      // ⚠️ 用 clamp 而非 `substring(i, i + 120)`：纪律第 6 条文本随批2
      //   迁到 prompt_assembly_service.dart 的**文件末尾**，原写法会
      //   RangeError(end) —— 实测「命中位置 + 120 超出总长」即崩。
      final end = (i + 120) < src.length ? (i + 120) : src.length;
      final line = src.substring(i, end);
      expect(line, contains('[YS_DIAGNOSIS]'));
    });

    test('存在 user 侧诊断协议注入 helper 与后缀常量', () {
      final src = File('lib/services/chat_service.dart').readAsStringSync();
      // ★ ADR-0004 步 5 批 1（2026-10-07）：诊断簇已抽为独立类
      //   （DiagnosisInjectionService）⇒ 协议注入 helper 与后缀常量分居两个
      //   文件。**两文件都扫**（不是放宽：断言意图「协议注入通路存在且单一真源」
      //   仍然成立，且现在额外验证了常量未被复制进新文件）。
      final dis = File(
        'lib/services/diagnosis_injection_service.dart',
      ).readAsStringSync();
      expect(src, contains('kDiagnosisProtocolSuffix'));
      expect(dis, contains('_maybeInjectDiagnosisProtocol'));
      // ★ 单一真源：协议文本只允许在 chat_service.dart 一处**定义**，
      //   新文件经构造注入接收、不得复制一份。
      //   判据用「输出要求」块首行（协议正文的唯一指纹）——不能用 YS_DIAGNOSIS：
      //   新文件**注释里**合法提到它（格式约束说明），实测 :141/:184 两处。
      expect(dis, isNot(contains('输出要求·最高优先级')));
      //   但构造参数名必须存在（证明是「注入接收」而非「各写一份」）。
      expect(dis, contains('diagnosisProtocolSuffix'));
      expect(src, contains('[YS_DIAGNOSIS]'));
      expect(src, contains('[/YS_DIAGNOSIS]'));
    });

    test('注入 helper 必须在流式调用前被调用', () {
      final src = File('lib/services/chat_service.dart').readAsStringSync();
      // TH 五批：注入聚合入口改为 _applyDiagnosisInjection（R-019 减负）
      // ADR-C134 批 2：签名带 sessionId（fading 块运行时条件注入）
      final callIdx = src.indexOf(
        '_applyDiagnosisInjection(ctx, content, options, sessionId);',
      );
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
      // TH 五批：签名并入「诊断上下文」确定性信号（弱信号措辞需佐证）
      expect(
        src,
        contains(
          'bool isDiagnosisRequest(String text, '
          '{bool hasDiagnosisContext = false})',
        ),
      );
      expect(src, contains('诊断'));
      expect(src, contains('diagnose'));
    });
  });
}
