// ─────────────────────────────────────────────────────────────
// book_library_diagnosis_isolation_test — 书籍资料库诊断隔离线锚点（ADR-C143 批D）
//
// 写死隔离线（ADR-C142 §5.6.1 / ADR-C143 §1.6）：
//   **未确认记录/资料 ≠ 教学诊断依据**。诊断上下文数据源白名单 =
//   学员作文文本 + 教学状态机最小元数据；资料库（record_entry / material_entry）
//   **默认不进诊断 prompt**。
//
// 已确认定稿设定（character_fact / world_fact）维持既有冲突/偏离检测注入
// （setting_library_service.buildConflictComparisonPrompt）——本批**不推翻**，
// 故该文件不在「禁引」名单内（它只消费 character/world，本测试不碰它的行为）。
//
// 本测试 = 注入链静态锚点：诊断链源文件**不得** import 新资料库仓库/服务。
// record_entry / material_entry 是 v44 全新表，此刻本就无任何诊断消费方；
// 本测试把「默认不进」从注释升格为可执行断言，防未来自动接回注入链。
//
// 阳性对照（堵「扫描器静默失效 ⇒ 零命中假绿」，honest_affordance_guard 同款教训）：
//   仓库源文件自身必须真能被扫出 recordEntries / materialEntries。
// ─────────────────────────────────────────────────────────────

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 诊断注入链源文件（prompt / 上下文装配层）。
/// 这些文件**不得**引用书籍资料库新表/仓库/服务。
const List<String> _diagnosisChainFiles = [
  'lib/services/diagnosis_service.dart',
  'lib/services/diagnosis_committer.dart',
  'lib/services/diagnosis_flow_handler.dart',
  'lib/services/progressive_diagnosis.dart',
  'lib/services/skills_diagnosis.dart',
  'lib/services/skills_diagnosis_p1.dart',
  'lib/services/skills_diagnosis_p2.dart',
  'lib/services/skills_diagnosis_p3.dart',
  'lib/services/setting_library_service.dart',
  'lib/services/conflict_detector.dart',
  'lib/services/setting_assertion_extractor.dart',
];

/// 书籍资料库新表/仓库/服务的标识（出现即 = 被诊断链引用）。
const List<String> _forbiddenNeedles = [
  'record_entry_repository',
  'material_entry_repository',
  'material_entry_service',
  'recordEntries',
  'materialEntries',
];

String _read(String rel) => File(rel).readAsStringSync();

void main() {
  test('阳性对照：资料库仓库源文件自身真能被扫出表访问器', () {
    // 证明扫描针有效（否则下面「零命中」是假绿）
    expect(
      _read('lib/data/repositories/record_entry_repository.dart'),
      contains('recordEntries'),
    );
    expect(
      _read('lib/data/repositories/material_entry_repository.dart'),
      contains('materialEntries'),
    );
  });

  test('诊断注入链零引用书籍资料库（记录/资料默认不进诊断 prompt）', () {
    final hits = <String>[];
    for (final rel in _diagnosisChainFiles) {
      final f = File(rel);
      if (!f.existsSync()) continue; // 个别文件可能尚未存在，跳过（不放行引用）
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final s = lines[i].trim();
        if (s.startsWith('//')) continue; // 注释行豁免
        for (final needle in _forbiddenNeedles) {
          if (s.contains(needle)) {
            hits.add('$rel:${i + 1} [$needle]: $s');
          }
        }
      }
    }
    expect(
      hits,
      isEmpty,
      reason: '诊断注入链不得引用书籍资料库（隔离线被破坏）：\n${hits.join('\n')}',
    );
  });
}
