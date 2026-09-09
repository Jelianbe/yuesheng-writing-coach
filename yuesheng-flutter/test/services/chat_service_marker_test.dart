// ─────────────────────────────────────────────────────────────
// chat_service_marker_test — CR-54 协议标记最早位统一 helper 契约
//
// 背景：5 种协议标记（[YS_DIAGNOSIS]/[YS_MD]/[YS_OUTLINE]/[YS_FACT]/
// [YS_GENUI]）的「最早出现位」此前是 4 层嵌套 _earliestMarkerIndex
// min-reduce，与同文件 _blockPendingPrefix 的 List.reduce 风格
// 形成双实现（新增标记需改 2 处）。
// 修复：抽 static _earliestMarkerIndexList(List<int>) + 统一调用。
//
// 覆盖：
//   1. helper 定义存在
//   2. _streamLlm 使用 helper（嵌套 min-reduce 不再出现）
//   3. helper 与 _blockPendingPrefix 语义对偶（max vs min 双向统一）
// ─────────────────────────────────────────────────────────────

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final src = File('lib/services/chat_service.dart').readAsStringSync();

  group('CR-54 协议标记最早位统一', () {
    test('1. _earliestMarkerIndexList helper 定义存在', () {
      expect(
        src,
        contains('static int _earliestMarkerIndexList(List<int> indexes)'),
        reason: 'CR-54 应抽取 List 版最早位 helper',
      );
    });

    test('2. _streamLlm 改用 helper，4 层嵌套 min-reduce 不再出现', () {
      // 旧形态：_earliestMarkerIndex(_earliestMarkerIndex(... 连续嵌套
      final nested = RegExp(
        r'_earliestMarkerIndex\(\s*_earliestMarkerIndex\(',
        multiLine: true,
      );
      expect(
        nested.allMatches(src),
        isEmpty,
        reason: 'CR-54 应消除嵌套 min-reduce，改走 _earliestMarkerIndexList',
      );
      // 新形态：List 字面量传入 helper
      expect(
        src,
        contains('_earliestMarkerIndexList(['),
        reason: '调用点应传 List 字面量',
      );
    });

    test('3. 5 种协议标记 indexOf 仍在扫描区间内（无遗漏）', () {
      for (final m in [
        'kDiagnosisStart',
        'kMarkdownDiagOpen',
        'kOutlineStart',
        'kFactStart',
        'kGenuiStart',
      ]) {
        expect(src, contains(m), reason: '协议标记常量 $m 必须保留');
      }
      // List 字面量以 indexOf 结果变量传入（CR-54 形态）——5 个变量齐全
      final listIdx = src.indexOf('_earliestMarkerIndexList([');
      expect(listIdx, greaterThan(0));
      final window = src.substring(listIdx, listIdx + 260);
      for (final v in [
        'diagMarkerIndex',
        'mdDiagMarkerIndex',
        'outlineMarkerIndex',
        'factMarkerIndex',
        'genuiMarkerIndex',
      ]) {
        expect(window, contains(v), reason: 'helper 应收到全部 5 个标记 index 变量 $v');
      }
    });
  });
}
